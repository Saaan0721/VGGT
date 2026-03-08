import SwiftUI
import RealityKit
import UniformTypeIdentifiers

struct TaskView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var showFilePicker = false
    @State private var isOpeningSpace = false

    var body: some View {
        @Bindable var model = appModel

        VStack(spacing: 16) {
            if let fileName = appModel.loadedFileName {
                Text("Loaded: \(fileName)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Button("Load 3D File") {
                showFilePicker = true
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [
                    .usdz,
                    .init(filenameExtension: "glb")!,
                    .init(filenameExtension: "bin")!,
                ],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    loadFile(url: url)
                }
            }

            if appModel.loadedFileName != nil {
                if isOpeningSpace {
                    ProgressView("Opening AR...")
                } else {
                    Button(appModel.isImmersiveSpaceOpen ? "Close AR View" : "Open AR View") {
                        Task {
                            if appModel.isImmersiveSpaceOpen {
                                await dismissImmersiveSpace()
                                appModel.isImmersiveSpaceOpen = false
                            } else {
                                isOpeningSpace = true
                                let result = await openImmersiveSpace(id: "ImmersiveSpace")
                                appModel.isImmersiveSpaceOpen = result == .opened
                                isOpeningSpace = false
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if appModel.isImmersiveSpaceOpen {
                Divider()

                // 위치 컨트롤 (회전/스케일은 제스처로)
                Grid(alignment: .center, horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        positionStepper("L/R", axis: 0, step: 0.02)
                        positionStepper("Height", axis: 1, step: 0.02)
                        positionStepper("Depth", axis: 2, step: 0.02)
                    }
                }

                // Pitch/Roll/Scale 버튼
                Grid(alignment: .center, horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        rotationStepper("Pitch", action: { appModel.rotatePitch($0) })
                        rotationStepper("Roll", action: { appModel.rotateRoll($0) })
                        scaleStepper()
                    }
                }

                HStack(spacing: 12) {
                    Toggle("Gesture", isOn: $model.gestureEnabled)
                    Toggle("Hands", isOn: $model.showHands)
                }
                .frame(maxWidth: 300)

                VStack(spacing: 4) {
                    Text("BG: \(String(format: "%.0f%%", appModel.backgroundOpacity * 100))")
                        .font(.caption)
                        .monospacedDigit()
                    Slider(value: $model.backgroundOpacity, in: 0...1, step: 0.05)
                        .frame(maxWidth: 300)
                }
                .frame(maxWidth: 400)

                HStack(spacing: 12) {
                    Button("Reset") { appModel.resetView() }
                        .buttonStyle(.bordered)
                    Button("Save") { appModel.saveSettings() }
                        .buttonStyle(.bordered)
                }
            }

            if appModel.isLoading {
                ProgressView("Loading...")
            }
            if let error = appModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    /// +/- 버튼으로 position[axis] 조절
    private func positionStepper(_ label: String, axis: Int, step: Float) -> some View {
        VStack(spacing: 4) {
            Text("\(label): \(String(format: "%.2fm", appModel.position[axis]))")
                .font(.caption)
                .monospacedDigit()
            HStack(spacing: 12) {
                Button(action: { appModel.position[axis] -= step }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.largeTitle)
                }
                .buttonStyle(.bordered)
                Button(action: { appModel.position[axis] += step }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.largeTitle)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(minWidth: 100)
    }

    /// Pitch/Roll ±5° 버튼
    private func rotationStepper(_ label: String, action: @escaping (Float) -> Void) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
            HStack(spacing: 12) {
                Button(action: { action(-.pi / 36) }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.largeTitle)
                }
                .buttonStyle(.bordered)
                Button(action: { action(.pi / 36) }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.largeTitle)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(minWidth: 100)
    }

    /// Scale ±0.05x 버튼
    private func scaleStepper() -> some View {
        VStack(spacing: 4) {
            Text("Scale: \(String(format: "%.2fx", appModel.scale))")
                .font(.caption)
                .monospacedDigit()
            HStack(spacing: 12) {
                Button(action: { appModel.scale = max(appModel.scale - 0.05, 0.1) }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.largeTitle)
                }
                .buttonStyle(.bordered)
                Button(action: { appModel.scale = min(appModel.scale + 0.05, 10.0) }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.largeTitle)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(minWidth: 100)
    }

    private func loadFile(url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dest = docs.appendingPathComponent(url.lastPathComponent)

        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            appModel.loadedFileName = url.lastPathComponent

            appModel.isLoading = true
            appModel.errorMessage = nil

            if dest.pathExtension == "bin" {
                Task {
                    do {
                        let pointData = try PointCloudLoader.loadBin(url: dest)
                        let entity = try PointCloudLoader.buildEntity(from: pointData)
                        appModel.pointCloudEntity = entity
                        appModel.isLoading = false
                    } catch {
                        appModel.errorMessage = "Failed to load bin: \(error.localizedDescription)"
                        appModel.isLoading = false
                    }
                }
            } else {
                Task {
                    do {
                        let entity = try await Entity(contentsOf: dest)
                        appModel.pointCloudEntity = entity
                        appModel.isLoading = false
                    } catch {
                        appModel.errorMessage = "Failed to load: \(error.localizedDescription)"
                        appModel.isLoading = false
                    }
                }
            }
        } catch {
            appModel.errorMessage = "Failed to copy file: \(error.localizedDescription)"
        }
    }
}
