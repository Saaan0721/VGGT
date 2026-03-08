import SwiftUI
import RealityKit
import Observation

@Observable
class AppModel {
    var isImmersiveSpaceOpen = false

    init() {
        loadSettings()
    }
    var loadedFileName: String?
    var pointCloudEntity: Entity?
    var isLoading = false
    var errorMessage: String?
    // 6DoF 포인트클라우드 배치
    var position: SIMD3<Float> = SIMD3<Float>(0, 1.2, 0.2)
    var orientation: simd_quatf = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
    var scale: Float = 1.0
    var showHands: Bool = true
    var gestureEnabled: Bool = false
    var backgroundOpacity: Float = 1.0  // 0=passthrough, 1=black

    func rotatePitch(_ angle: Float) {
        let q = simd_quatf(angle: angle, axis: SIMD3<Float>(1, 0, 0))
        orientation = q * orientation
    }

    func rotateRoll(_ angle: Float) {
        let q = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 0, 1))
        orientation = q * orientation
    }

    func resetView() {
        position = SIMD3<Float>(0, 1.2, 0.2)
        orientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(0, 1, 0))
        scale = 1.0
    }

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set([position.x, position.y, position.z], forKey: "vggt_position")
        defaults.set([orientation.vector.x, orientation.vector.y, orientation.vector.z, orientation.vector.w], forKey: "vggt_orientation")
        defaults.set(scale, forKey: "vggt_scale")
        defaults.set(showHands, forKey: "vggt_showHands")
    }

    func loadSettings() {
        let defaults = UserDefaults.standard
        if let pos = defaults.array(forKey: "vggt_position") as? [Float], pos.count == 3 {
            position = SIMD3<Float>(pos[0], pos[1], pos[2])
        }
        if let ori = defaults.array(forKey: "vggt_orientation") as? [Float], ori.count == 4 {
            orientation = simd_quatf(ix: ori[0], iy: ori[1], iz: ori[2], r: ori[3])
        }
        if let s = defaults.object(forKey: "vggt_scale") as? Float {
            scale = s
        }
        showHands = defaults.object(forKey: "vggt_showHands") as? Bool ?? true
    }
}
