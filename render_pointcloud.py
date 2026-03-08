"""GLB point cloud를 matplotlib로 렌더링하여 PNG로 저장."""
import sys
import numpy as np
import trimesh
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

def render_pointcloud(glb_path, output_prefix="render"):
    scene = trimesh.load(glb_path)

    # Extract point cloud
    if isinstance(scene, trimesh.Scene):
        for geom in scene.geometry.values():
            if isinstance(geom, trimesh.PointCloud):
                pc = geom
                break
        else:
            print("No PointCloud found in scene")
            return
    else:
        pc = scene

    vertices = np.array(pc.vertices)
    colors = np.array(pc.colors)[:, :3] / 255.0  # RGBA → RGB normalized

    print(f"Points: {len(vertices)}, Color range: {colors.min():.3f} - {colors.max():.3f}")

    # Subsample for faster rendering
    if len(vertices) > 200000:
        idx = np.random.choice(len(vertices), 200000, replace=False)
        vertices = vertices[idx]
        colors = colors[idx]

    # Render from 3 angles
    angles = [
        ("front", 0, 0),
        ("side", 90, 0),
        ("top", 0, 90),
    ]

    for name, azim, elev in angles:
        fig = plt.figure(figsize=(12, 9))
        ax = fig.add_subplot(111, projection='3d')
        ax.scatter(vertices[:, 0], vertices[:, 1], vertices[:, 2],
                   c=colors, s=0.1, alpha=0.8)
        ax.view_init(elev=elev, azim=azim)
        ax.set_xlabel('X')
        ax.set_ylabel('Y')
        ax.set_zlabel('Z')
        ax.set_title(f'{name} view ({len(vertices)} points)')
        plt.tight_layout()
        out = f"{output_prefix}_{name}.png"
        plt.savefig(out, dpi=150, bbox_inches='tight')
        plt.close()
        print(f"Saved {out}")

if __name__ == "__main__":
    glb_path = sys.argv[1] if len(sys.argv) > 1 else "scene_v2.glb"
    prefix = sys.argv[2] if len(sys.argv) > 2 else "render"
    render_pointcloud(glb_path, prefix)
