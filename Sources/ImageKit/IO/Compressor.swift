import CoreGraphics
import Foundation

public enum Compressor {
    public struct Fit: Sendable {
        public let quality: Double
        public let data: Data
    }

    /// The highest quality whose encoded size is at most `maxBytes`, found by binary search.
    /// Returns nil when even the lowest quality is too big (resize first in that case).
    public static func fit(_ image: CGImage, format: ImageFormat, options: EncodeOptions, maxBytes: Int, steps: Int = 7) throws -> Fit? {
        precondition(format.supportsQuality, "\(format) has no quality setting to search")
        var options = options
        options.lossless = false

        func attempt(_ quality: Double) throws -> Fit? {
            options.quality = quality
            let data = try ImageExporter.encode(image, format: format, options: options)
            return data.count <= maxBytes ? Fit(quality: quality, data: data) : nil
        }

        if let full = try attempt(1) { return full }
        guard var best = try attempt(0) else { return nil }
        var low = 0.0, high = 1.0
        for _ in 0..<steps {
            let middle = (low + high) / 2
            if let fit = try attempt(middle) {
                best = fit
                low = middle
            } else {
                high = middle
            }
        }
        return best
    }
}
