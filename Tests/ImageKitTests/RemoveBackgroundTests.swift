import CoreImage
import Foundation
import Testing
@testable import ImageKit

/// Uses a stock macOS photo, so it only runs where that file exists.
private let samplePhoto = URL(fileURLWithPath: "/Library/User Pictures/Animals/Parrot.heic")

@Suite struct RemoveBackgroundTests {
    @Test(.enabled(if: FileManager.default.fileExists(atPath: samplePhoto.path)))
    func makesBackgroundTransparentAndKeepsSubject() async throws {
        let photo = try ImageLoader.load(contentsOf: samplePhoto)
        let output = try await RemoveBackground().apply(to: photo)
        #expect(output.extent == photo.extent)

        let cgImage = try Renderer.cgImage(from: output)
        let alphas = try alphaValues(of: cgImage)
        #expect(alphas.contains { $0 == 0 }, "expected some fully transparent background pixels")
        #expect(alphas.contains { $0 == 255 }, "expected some opaque subject pixels")
    }

    @Test func throwsWhenThereIsNoSubject() async {
        await #expect(throws: (any Error).self) {
            try await RemoveBackground().apply(to: solid(width: 256, height: 256, color: .gray))
        }
    }

    private func alphaValues(of image: CGImage) throws -> [UInt8] {
        let context = try #require(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        return stride(from: 3, to: image.width * image.height * 4, by: 4).map { pixels[$0] }
    }
}
