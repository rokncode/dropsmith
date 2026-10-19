import CoreImage
import Foundation
import Testing
@testable import ImageKit

/// Detailed content so lossy encoders have something to throw away.
private func noise(width: Int = 256, height: Int = 256) throws -> CGImage {
    let random = CIFilter(name: "CIRandomGenerator")!.outputImage!
        .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    return try Renderer.cgImage(from: random.applyingGaussianBlur(sigma: 1.5).cropped(to: random.extent))
}

@Suite struct CompressionTests {
    @Test(arguments: ImageFormat.writable.filter(\.supportsQuality))
    func lowerQualityIsSmaller(format: ImageFormat) throws {
        let image = try noise()
        let high = try ImageExporter.encode(image, format: format, options: EncodeOptions(quality: 0.95))
        let low = try ImageExporter.encode(image, format: format, options: EncodeOptions(quality: 0.2))
        #expect(low.count < high.count)
    }

    @Test func webpLosslessKeepsExactPixelsIncludingAlpha() throws {
        // Semi-transparent orange: checks straight-alpha conversion around libwebp.
        let color = CIColor(red: 1, green: 0.5, blue: 0, alpha: 0.5)
        let source = try Renderer.cgImage(from: solid(width: 16, height: 16, color: color))
        let data = try ImageExporter.encode(source, format: .webp, options: EncodeOptions(lossless: true))
        let decoded = CIImage(cgImage: try ImageExporter.decode(data))
        let original = pixel(CIImage(cgImage: source), x: 8, y: 8)
        let roundTripped = pixel(decoded, x: 8, y: 8)
        #expect(zip(original, roundTripped).allSatisfy { abs(Int($0) - Int($1)) <= 1 }, "\(original) vs \(roundTripped)")
    }

    @Test func avifIsWritableOnRecentMacOS() throws {
        if #available(macOS 15, *) {
            #expect(ImageFormat.writable.contains(.avif))
        }
    }

    @Test(arguments: [ImageFormat.jpeg, .webp])
    func fitStaysUnderTargetSize(format: ImageFormat) throws {
        let image = try noise(width: 512, height: 512)
        // Each encoder has its own size range on the same image (WebP's is narrow on noise),
        // so aim between this format's smallest and largest output.
        let smallest = try ImageExporter.encode(image, format: format, options: EncodeOptions(quality: 0)).count
        let largest = try ImageExporter.encode(image, format: format, options: EncodeOptions(quality: 1)).count
        let target = (smallest + largest) / 2
        let fit = try #require(try Compressor.fit(image, format: format, options: .init(), maxBytes: target))
        #expect(fit.data.count <= target)
        #expect(fit.quality > 0 && fit.quality < 1)
    }

    @Test func fitReturnsNilWhenUnreachable() throws {
        #expect(try Compressor.fit(noise(), format: .jpeg, options: .init(), maxBytes: 100) == nil)
    }
}
