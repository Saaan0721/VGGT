"""PLY point cloud → 간단한 바이너리 포맷 변환 (visionOS용).

출력 포맷:
  - 4 bytes: uint32 point count (N)
  - N * 16 bytes: [float32 x, float32 y, float32 z, uint8 r, uint8 g, uint8 b, uint8 a] per point
"""
import sys
import struct
import numpy as np
import trimesh

def convert(ply_path, out_path, max_points=500000):
    scene = trimesh.load(ply_path)
    # GLB를 Scene으로 로드하는 경우: 모든 메쉬의 정점/색상을 합침
    if isinstance(scene, trimesh.Scene):
        all_verts = []
        all_colors = []
        for name, geom in scene.geometry.items():
            if hasattr(geom, 'vertices'):
                transform = scene.graph.get(name)[0] if scene.graph.get(name) else np.eye(4)
                v = np.array(geom.vertices, dtype=np.float32)
                # 트랜스폼 적용
                v_h = np.hstack([v, np.ones((len(v), 1), dtype=np.float32)])
                v = (v_h @ transform.T)[:, :3].astype(np.float32)
                all_verts.append(v)
                if hasattr(geom, 'visual') and hasattr(geom.visual, 'vertex_colors'):
                    c = np.array(geom.visual.vertex_colors, dtype=np.uint8)
                else:
                    c = np.full((len(v), 4), 128, dtype=np.uint8)
                    c[:, 3] = 255
                all_colors.append(c)
        verts = np.vstack(all_verts).astype(np.float32)
        colors = np.vstack(all_colors).astype(np.uint8)
    else:
        verts = np.array(scene.vertices, dtype=np.float32)
        colors = np.array(scene.colors, dtype=np.uint8)  # RGBA

    # Downsample
    if len(verts) > max_points:
        idx = np.random.choice(len(verts), max_points, replace=False)
        verts = verts[idx]
        colors = colors[idx]

    print(f"Converting {len(verts)} points")

    with open(out_path, 'wb') as f:
        f.write(struct.pack('<I', len(verts)))
        for i in range(len(verts)):
            f.write(struct.pack('<fff', verts[i, 0], verts[i, 1], verts[i, 2]))
            f.write(struct.pack('<BBBB', colors[i, 0], colors[i, 1], colors[i, 2], colors[i, 3]))

    import os
    size_mb = os.path.getsize(out_path) / 1024 / 1024
    print(f"Exported {out_path} ({size_mb:.1f} MB)")

if __name__ == "__main__":
    ply = sys.argv[1] if len(sys.argv) > 1 else "scene_v5.ply"
    out = sys.argv[2] if len(sys.argv) > 2 else "scene.bin"
    max_pts = int(sys.argv[3]) if len(sys.argv) > 3 else 500000
    convert(ply, out, max_pts)
