import CoreImage
import Foundation

/// Renders and encodes one image of a batch. Callers cache `render` results, so changing only
/// the encode settings never reruns Vision.
public enum BatchProcessor {
    public struct Encoded: Sendable {
        public let data: Data
        /// False when `maxBytes` was set and even the lowest quality is bigger.
        public let fitsTarget: Bool
    }

    public static func render(_ url: URL, recipe: BatchRecipe) async throws -> CGImage {
        try Renderer.cgImage(from: await Pipeline.run(recipe.operations, on: ImageLoader.load(contentsOf: url)))
    }

    /// Encodes `image`. With `maxBytes`, uses the highest quality that fits, or quality 0 when none does.
    public static func encode(_ image: CGImage, format: ImageFormat, options: EncodeOptions, maxBytes: Int? = nil) throws -> Encoded {
        let prepared = try ImageExporter.prepare(CIImage(cgImage: image), for: format)
        guard let maxBytes, format.supportsQuality else {
            return Encoded(data: try ImageExporter.encode(prepared, format: format, options: options), fitsTarget: true)
        }
        if let fit = try Compressor.fit(prepared, format: format, options: options, maxBytes: maxBytes) {
            return Encoded(data: fit.data, fitsTarget: true)
        }
        var smallest = options
        smallest.lossless = false
        smallest.quality = 0
        return Encoded(data: try ImageExporter.encode(prepared, format: format, options: smallest), fitsTarget: false)
    }
}
