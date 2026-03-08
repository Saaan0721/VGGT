"""GLB 파일을 브라우저에서 3D로 회전/줌하며 볼 수 있는 Gradio 뷰어."""
import argparse
import gradio as gr


def view_glb(glb_path):
    return glb_path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("glb", nargs="?", default="scene_v5.glb", help="GLB file path")
    parser.add_argument("--port", type=int, default=7860)
    args = parser.parse_args()

    with gr.Blocks(title="VGGT 3D Viewer") as demo:
        gr.Markdown("# VGGT 3D Point Cloud Viewer")
        model3d = gr.Model3D(value=args.glb, label="3D Scene", height=600)
        file_input = gr.File(label="Load another GLB", file_types=[".glb", ".ply", ".obj"])
        file_input.change(fn=view_glb, inputs=file_input, outputs=model3d)

    demo.launch(server_port=args.port, share=False)


if __name__ == "__main__":
    main()
