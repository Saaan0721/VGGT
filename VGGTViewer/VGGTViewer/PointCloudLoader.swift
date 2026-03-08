import Foundation
import RealityKit
import CoreGraphics

/// .bin 파일에서 포인트 클라우드를 읽어 삼각형 메시 ModelEntity로 변환
enum PointCloudLoader {

    struct PointData {
        var positions: [SIMD3<Float>]
        var colors: [SIMD4<Float>] // 0-1 normalized RGBA
    }

    /// .bin 바이너리 파일 파싱 (convert_to_bin.py 포맷)
    /// 4 bytes: uint32 count, then N * 16 bytes: [f32 x, f32 y, f32 z, u8 r, u8 g, u8 b, u8 a]
    static func loadBin(url: URL) throws -> PointData {
        let data = try Data(contentsOf: url)
        guard data.count >= 4 else { throw LoadError.invalidFormat }

        let count = data.withUnsafeBytes { $0.load(as: UInt32.self) }
        let n = Int(count)
        let expectedSize = 4 + n * 16
        guard data.count >= expectedSize else { throw LoadError.invalidFormat }

        var positions = [SIMD3<Float>]()
        var colors = [SIMD4<Float>]()
        positions.reserveCapacity(n)
        colors.reserveCapacity(n)

        data.withUnsafeBytes { ptr in
            var offset = 4
            for _ in 0..<n {
                let x = ptr.load(fromByteOffset: offset, as: Float.self)
                let y = ptr.load(fromByteOffset: offset + 4, as: Float.self)
                let z = ptr.load(fromByteOffset: offset + 8, as: Float.self)
                let r = ptr.load(fromByteOffset: offset + 12, as: UInt8.self)
                let g = ptr.load(fromByteOffset: offset + 13, as: UInt8.self)
                let b = ptr.load(fromByteOffset: offset + 14, as: UInt8.self)
                let a = ptr.load(fromByteOffset: offset + 15, as: UInt8.self)

                positions.append(SIMD3<Float>(-x, -y, z)) // X,Y축 반전 (VGGT→RealityKit)
                colors.append(SIMD4<Float>(
                    Float(r) / 255.0,
                    Float(g) / 255.0,
                    Float(b) / 255.0,
                    Float(a) / 255.0
                ))
                offset += 16
            }
        }

        return PointData(positions: positions, colors: colors)
    }

    /// 포인트 데이터를 작은 삼각형 메시로 변환하여 ModelEntity 생성
    static func buildEntity(from pointData: PointData) throws -> ModelEntity {
        let n = pointData.positions.count
        let triSize: Float = 0.003 // 3mm 삼각형

        // 삼각형 오프셋 (정삼각형)
        let offsets: [SIMD3<Float>] = [
            SIMD3<Float>(-triSize / 2, -triSize * 0.29, 0),
            SIMD3<Float>( triSize / 2, -triSize * 0.29, 0),
            SIMD3<Float>( 0,            triSize * 0.58, 0),
        ]

        var meshPositions = [SIMD3<Float>]()
        var indices = [UInt32]()
        var uvs = [SIMD2<Float>]()

        meshPositions.reserveCapacity(n * 3)
        indices.reserveCapacity(n * 3)
        uvs.reserveCapacity(n * 3)

        // 텍스처 크기 계산
        let texSize = Int(ceil(sqrt(Double(n))))

        for i in 0..<n {
            let pos = pointData.positions[i]
            let baseIdx = UInt32(i * 3)

            // UV: 이 포인트의 텍셀 좌표
            let row = i / texSize
            let col = i % texSize
            let u = (Float(col) + 0.5) / Float(texSize)
            let v = (Float(row) + 0.5) / Float(texSize)
            let uv = SIMD2<Float>(u, v)

            for j in 0..<3 {
                meshPositions.append(pos + offsets[j])
                indices.append(baseIdx + UInt32(j))
                uvs.append(uv)
            }
        }

        // MeshDescriptor
        var descriptor = MeshDescriptor(name: "PointCloudTextured")
        descriptor.positions = MeshBuffer(meshPositions)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)

        let mesh = try MeshResource.generate(from: [descriptor])

        // CGImage로 텍스처 생성
        let texture = try createColorTexture(colors: pointData.colors, size: texSize)

        var material = UnlitMaterial()
        material.color = .init(texture: .init(texture))
        material.faceCulling = .none // 양면 렌더링

        let entity = ModelEntity(mesh: mesh, materials: [material])
        return entity
    }

    /// 색상 배열에서 CGImage를 만들어 TextureResource 생성
    private static func createColorTexture(colors: [SIMD4<Float>], size: Int) throws -> TextureResource {
        let totalPixels = size * size
        var pixelData = [UInt8](repeating: 0, count: totalPixels * 4)

        for i in 0..<colors.count {
            pixelData[i * 4 + 0] = UInt8(min(colors[i].x * 255, 255))
            pixelData[i * 4 + 1] = UInt8(min(colors[i].y * 255, 255))
            pixelData[i * 4 + 2] = UInt8(min(colors[i].z * 255, 255))
            pixelData[i * 4 + 3] = 255
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let provider = CGDataProvider(data: Data(pixelData) as CFData),
              let cgImage = CGImage(
                width: size,
                height: size,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: size * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw LoadError.textureCreationFailed
        }

        let texture = try TextureResource.generate(from: cgImage, options: .init(semantic: .color))
        return texture
    }

    enum LoadError: Error {
        case invalidFormat
        case textureCreationFailed
    }
}
