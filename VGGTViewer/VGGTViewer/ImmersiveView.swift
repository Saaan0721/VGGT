import SwiftUI
import RealityKit

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @State private var rootEntity = Entity()
    @State private var pointCloudContainer = Entity()
    @State private var skyEntity: ModelEntity?
    @State private var lastPointCloudId: UInt64 = 0

    @State private var gestureRotation: simd_quatf = .init(ix: 0, iy: 0, iz: 0, r: 1)
    @State private var gestureScale: Float = 1.0

    var body: some View {
        RealityView { content in
            // 배경 구체: 머티리얼 알파로 투명도 제어
            let skyMesh = MeshResource.generateSphere(radius: 5)
            let sky = ModelEntity(mesh: skyMesh, materials: [Self.makeSkyMaterial(opacity: appModel.backgroundOpacity)])
            skyEntity = sky
            rootEntity.addChild(sky)

            pointCloudContainer.position = appModel.position
            rootEntity.addChild(pointCloudContainer)
            content.add(rootEntity)
        } update: { content in
            // 배경 opacity
            if let sky = skyEntity {
                sky.model?.materials = [Self.makeSkyMaterial(opacity: appModel.backgroundOpacity)]
            }

            // 포인트클라우드 로드
            if let source = appModel.pointCloudEntity, source.id != lastPointCloudId {
                lastPointCloudId = source.id
                pointCloudContainer.children.removeAll()
                // 포인트클라우드 교체 시 collision 재생성 필요
                pointCloudContainer.components.remove(CollisionComponent.self)
                pointCloudContainer.components.remove(InputTargetComponent.self)

                let pointCloud = source.clone(recursive: true)
                pointCloudContainer.addChild(pointCloud)
            }

            // 포인트클라우드 컨테이너에 collision 동적 추가/제거
            // 개별 child의 visualBounds 전체를 collision box로 쓰면 영역이 너무 커서
            // 윈도우 버튼의 gaze 입력을 가로챔 → 크기 제한된 sphere를 컨테이너에 적용
            if appModel.gestureEnabled {
                if pointCloudContainer.components[CollisionComponent.self] == nil,
                   !pointCloudContainer.children.isEmpty {
                    let bounds = pointCloudContainer.visualBounds(relativeTo: pointCloudContainer)
                    let shape = ShapeResource.generateSphere(radius: 0.5)
                        .offsetBy(translation: bounds.center)
                    pointCloudContainer.components.set(CollisionComponent(shapes: [shape]))
                    pointCloudContainer.components.set(InputTargetComponent(allowedInputTypes: .indirect))
                }
            } else {
                pointCloudContainer.components.remove(CollisionComponent.self)
                pointCloudContainer.components.remove(InputTargetComponent.self)
            }

            // 6DoF
            pointCloudContainer.orientation = gestureRotation * appModel.orientation
            pointCloudContainer.scale = SIMD3<Float>(repeating: appModel.scale * gestureScale)
            pointCloudContainer.position = appModel.position
        }
        .simultaneousGesture(dragRotateGesture)
        .simultaneousGesture(pinchScaleGesture)
        .onChange(of: appModel.backgroundOpacity) { _, newValue in
            if let sky = skyEntity {
                sky.model?.materials = [Self.makeSkyMaterial(opacity: newValue)]
            }
        }
    }

    private static func makeSkyMaterial(opacity: Float) -> PhysicallyBasedMaterial {
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = .init(tint: .black)
        mat.blending = .transparent(opacity: .init(scale: opacity))
        mat.faceCulling = .front
        return mat
    }

    // MARK: - 한 손 드래그 → 회전

    private var dragRotateGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .targetedToAnyEntity()
            .onChanged { value in
                let t = value.translation3D
                let yaw = simd_quatf(angle: Float(t.x) * -0.005, axis: SIMD3<Float>(0, 1, 0))
                let pitch = simd_quatf(angle: Float(t.y) * -0.005, axis: SIMD3<Float>(1, 0, 0))
                gestureRotation = yaw * pitch
            }
            .onEnded { _ in
                appModel.orientation = gestureRotation * appModel.orientation
                gestureRotation = .init(ix: 0, iy: 0, iz: 0, r: 1)
            }
    }

    // MARK: - 두 손 핀치 → 스케일

    private var pinchScaleGesture: some Gesture {
        MagnifyGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                gestureScale = min(max(Float(value.magnification), 0.5), 3.0)
            }
            .onEnded { value in
                let mag = min(max(Float(value.magnification), 0.5), 3.0)
                let finalScale = min(max(appModel.scale * mag, 0.1), 10.0)
                gestureScale = 1.0
                appModel.scale = finalScale
            }
    }
}
