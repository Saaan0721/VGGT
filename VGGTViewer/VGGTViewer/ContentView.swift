import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var model = appModel

        VStack(spacing: 24) {
            Text("VGGT 3D Viewer")
                .font(.largeTitle)

            TaskView()
        }
        .padding(40)
    }
}
