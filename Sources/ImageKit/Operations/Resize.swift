import CoreImage
import CoreImage.CIFilterBuiltins

public struct Resize: ImageOperation {
    public enum Mode: Sendable, Hashable {
        /// Multiply both sides, e.g. 0.5 for half size.
        case scale(Double)
        /// Largest size that fits the box while keeping the aspect ratio.
        case fit(width: Int, height: Int)
        /// Exactly this size, stretching if the aspect ratio differs.
        case exact(width: Int, height: Int)
    }

    public var mode: Mode

    public init(_ mode: Mode) {
        self.mode = mode
    }

    public var title: String { "Resize" }

    public func targetSize(for size: CGSize) -> CGSize {
        let raw: CGSize
        switch mode {
        case .scale(let factor):
            raw = CGSize(width: size.width * factor, height: size.height * factor)
        case .fit(let width, let height):
            let factor = min(Double(width) / size.width, Double(height) / size.height)
            raw = CGSize(width: size.width * factor, height: size.height * factor)
        case .exact(let width, let height):
            raw = CGSize(width: width, height: height)
        }
        return CGSize(width: max(1, raw.width.rounded()), height: max(1, raw.height.rounded()))
    }

    public func apply(to image: CIImage) async throws -> CIImage {
        let size = image.extent.size
        let target = targetSize(for: size)
        guard size.width > 0, size.height > 0 else { throw ImageKitError.renderFailed }
        let scaleY = target.height / size.height
        let scaleX = target.width / size.width

        let filter = CIFilter.lanczosScaleTransform()
        // Clamping avoids soft transparent fringes at the edges after Lanczos sampling.
        filter.inputImage = image.normalized.clampedToExtent()
        filter.scale = Float(scaleY)
        filter.aspectRatio = Float(scaleX / scaleY)
        guard let output = filter.outputImage else { throw ImageKitError.renderFailed }
        return output.cropped(to: CGRect(origin: .zero, size: target))
    }
}
