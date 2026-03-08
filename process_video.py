"""
Vision Pro 촬영 영상 → VGGT 3D Reconstruction → USDZ export

Usage:
    python process_video.py input_video.mp4 --output scene.usdz
    python process_video.py ./images/ --output scene.usdz   # 이미지 폴더도 가능
"""

import argparse
import os
import sys
import glob
import cv2
import torch
import numpy as np

sys.path.append(os.path.dirname(__file__))

from vggt.models.vggt import VGGT
from vggt.utils.load_fn import load_and_preprocess_images
from vggt.utils.pose_enc import pose_encoding_to_extri_intri
from vggt.utils.geometry import unproject_depth_map_to_point_map
from visual_util import predictions_to_glb


def extract_frames(video_path, fps_interval=1.0):
    """영상에서 프레임 추출. fps_interval초 간격."""
    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    frame_interval = max(1, int(fps * fps_interval))

    frames_dir = os.path.join(os.path.dirname(video_path) or ".", "_frames_tmp")
    os.makedirs(frames_dir, exist_ok=True)

    count = 0
    saved = 0
    paths = []
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        if count % frame_interval == 0:
            path = os.path.join(frames_dir, f"{saved:06d}.png")
            cv2.imwrite(path, frame)
            paths.append(path)
            saved += 1
        count += 1
    cap.release()
    print(f"Extracted {saved} frames from video")
    return frames_dir, paths


def run_vggt(image_dir, device="cuda"):
    """VGGT 추론 실행."""
    print("Loading VGGT model...")
    model = VGGT()
    url = "https://huggingface.co/facebook/VGGT-1B/resolve/main/model.pt"
    model.load_state_dict(torch.hub.load_state_dict_from_url(url, map_location="cpu"))
    model = model.to(device)
    model.eval()

    image_names = sorted(glob.glob(os.path.join(image_dir, "*")))
    image_names = [p for p in image_names if p.lower().endswith((".png", ".jpg", ".jpeg"))]
    print(f"Processing {len(image_names)} images...")

    images = load_and_preprocess_images(image_names).to(device)

    with torch.no_grad():
        with torch.cuda.amp.autocast(dtype=torch.bfloat16):
            predictions = model(images)

    extrinsic, intrinsic = pose_encoding_to_extri_intri(predictions["pose_enc"], images.shape[-2:])
    predictions["extrinsic"] = extrinsic
    predictions["intrinsic"] = intrinsic

    # images 텐서 저장 (색상용, float 0-1) - squeeze 전에 처리
    raw_images = images.cpu().numpy()
    if raw_images.ndim == 5:
        raw_images = raw_images[0]  # (1, S, C, H, W) → (S, C, H, W)
    # raw_images is now (S, C, H, W)

    for key in predictions:
        if isinstance(predictions[key], torch.Tensor):
            predictions[key] = predictions[key].cpu().numpy().squeeze(0)

    depth_map = predictions["depth"]
    world_points = unproject_depth_map_to_point_map(depth_map, predictions["extrinsic"], predictions["intrinsic"])
    predictions["world_points_from_depth"] = world_points

    predictions["images"] = raw_images

    torch.cuda.empty_cache()
    return predictions


def predictions_to_pointcloud(predictions, conf_threshold=50.0):
    """predictions에서 point cloud (vertices + colors) 추출. 원본 visual_util.py 방식."""
    # 원본처럼 world_points (direct pointmap) 우선 사용
    if "world_points" in predictions:
        world_points = predictions["world_points"]  # (S, H, W, 3)
        conf = predictions.get("world_points_conf", np.ones_like(world_points[..., 0]))
    else:
        world_points = predictions["world_points_from_depth"]  # (S, H, W, 3)
        conf = predictions.get("depth_conf", np.ones_like(world_points[..., 0]))

    # 원본처럼 predictions["images"] 에서 색상 가져오기 (float 0-1)
    images = predictions["images"]  # (S, C, H, W) or (S, H, W, C)
    if images.ndim == 4 and images.shape[1] == 3:  # NCHW → NHWC
        colors_all = np.transpose(images, (0, 2, 3, 1))
    else:
        colors_all = images
    colors_all = (colors_all.reshape(-1, 3) * 255).astype(np.uint8)

    points = world_points.reshape(-1, 3)

    # confidence 기반 필터링
    conf_flat = conf.reshape(-1)
    if conf_threshold > 0:
        threshold = np.percentile(conf_flat, conf_threshold)
        mask = (conf_flat >= threshold) & (conf_flat > 1e-5)
    else:
        mask = conf_flat > 1e-5
    points = points[mask]
    colors_all = colors_all[mask]

    # NaN/Inf 제거
    valid = np.isfinite(points).all(axis=1)
    points = points[valid]
    colors_all = colors_all[valid]

    print(f"Point cloud: {len(points)} points")
    return points, colors_all


def export_usdz(points, colors, output_path):
    """Point cloud를 USDZ로 export."""
    cloud = trimesh.PointCloud(vertices=points, colors=colors)
    scene = trimesh.Scene(cloud)

    # trimesh는 USDZ 직접 export 불가 → GLB로 먼저 저장
    glb_path = output_path.replace(".usdz", ".glb")
    scene.export(glb_path)
    print(f"Exported GLB: {glb_path}")

    # USDZ 변환 시도 (usdzconvert 있으면 사용)
    if output_path.endswith(".usdz"):
        try:
            import subprocess
            # macOS의 usdzconvert 또는 Apple의 Reality Converter 사용
            result = subprocess.run(
                ["xcrun", "usdz_converter", glb_path, output_path],
                capture_output=True, text=True
            )
            if result.returncode == 0:
                print(f"Exported USDZ: {output_path}")
                return output_path
            else:
                print(f"usdz_converter failed, using GLB instead")
        except FileNotFoundError:
            print("usdz_converter not found, using GLB instead")
            print("Vision Pro can also load GLB files via RealityKit")

    return glb_path


def main():
    parser = argparse.ArgumentParser(description="Video/Images → VGGT → 3D Point Cloud")
    parser.add_argument("input", help="Video file or image directory")
    parser.add_argument("--output", "-o", default="scene.usdz", help="Output file path")
    parser.add_argument("--fps-interval", type=float, default=1.0, help="Frame extraction interval (seconds)")
    parser.add_argument("--conf-threshold", type=float, default=50.0, help="Confidence threshold percentile")
    parser.add_argument("--device", default="cuda", help="Device (cuda/cpu)")
    parser.add_argument("--brightness", type=float, default=1.0, help="Brightness multiplier (e.g. 1.3)")
    parser.add_argument("--saturation", type=float, default=1.0, help="Saturation multiplier (e.g. 1.5)")
    parser.add_argument("--mask-black", action="store_true", help="Mask out black background pixels")
    parser.add_argument("--export-ply", action="store_true", help="Also export PLY file")
    args = parser.parse_args()

    # 입력 처리
    if os.path.isfile(args.input):
        image_dir, _ = extract_frames(args.input, args.fps_interval)
    elif os.path.isdir(args.input):
        image_dir = args.input
    else:
        print(f"Error: {args.input} not found")
        sys.exit(1)

    # VGGT 추론
    predictions = run_vggt(image_dir, device=args.device)

    # 색상 보정 (brightness/saturation)
    if args.brightness != 1.0 or args.saturation != 1.0:
        images = predictions["images"]  # (S, C, H, W), float 0-1
        if images.ndim == 4 and images.shape[1] == 3:
            # NCHW → NHWC for processing
            imgs = np.transpose(images, (0, 2, 3, 1))
        else:
            imgs = images.copy()

        # Brightness
        if args.brightness != 1.0:
            imgs = imgs * args.brightness

        # Saturation (increase distance from grey)
        if args.saturation != 1.0:
            grey = imgs.mean(axis=-1, keepdims=True)
            imgs = grey + (imgs - grey) * args.saturation

        imgs = np.clip(imgs, 0.0, 1.0)

        if images.ndim == 4 and images.shape[1] == 3:
            predictions["images"] = np.transpose(imgs, (0, 3, 1, 2))
        else:
            predictions["images"] = imgs

    # 원본 visual_util.py의 predictions_to_glb 사용
    glb_path = args.output.replace(".usdz", ".glb")
    scene_3d = predictions_to_glb(
        predictions,
        conf_thres=args.conf_threshold,
        mask_black_bg=args.mask_black,
    )
    scene_3d.export(glb_path)
    print(f"Exported GLB: {glb_path}")

    # PLY export
    if args.export_ply:
        import trimesh
        ply_path = glb_path.replace(".glb", ".ply")
        for geom in scene_3d.geometry.values():
            if isinstance(geom, trimesh.PointCloud):
                geom.export(ply_path)
                print(f"Exported PLY: {ply_path}")
                break

    # 임시 프레임 정리
    if os.path.isfile(args.input) and os.path.exists("_frames_tmp"):
        import shutil
        shutil.rmtree("_frames_tmp", ignore_errors=True)

    print("Done!")


if __name__ == "__main__":
    main()
