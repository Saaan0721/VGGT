import SwiftUI

struct CaptureView: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("Scene Capture Guide")
                .font(.title2)

            VStack(alignment: .leading, spacing: 16) {
                guideRow(step: "1", title: "Record Video",
                         desc: "Use the Vision Pro Camera app to record a video of the scene.")

                guideRow(step: "2", title: "Transfer & Process",
                         desc: "AirDrop to Mac, then run:\nscp video.mov user@server:~/vggt/\nssh user@server \"cd ~/vggt && python process_video.py video.mov -o scene.glb\"")

                guideRow(step: "3", title: "Get Result",
                         desc: "scp user@server:~/vggt/scene.glb .\nAirDrop the GLB file back to Vision Pro.")

                guideRow(step: "4", title: "View in AR",
                         desc: "Switch to Task mode and load the GLB file.")
            }
            .padding()

            VStack(alignment: .leading, spacing: 8) {
                Text("Tips for Best Results")
                    .font(.headline)
                Text("- Move slowly and steadily")
                Text("- Capture from multiple angles")
                Text("- Ensure good lighting")
                Text("- 10-30 seconds of video is enough")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding()
        }
    }

    private func guideRow(step: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(step)
                .font(.title2.bold())
                .foregroundStyle(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(desc)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
