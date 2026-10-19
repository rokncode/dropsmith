import CoreImage

public struct Crop: ImageOperation {
    /// Normalized (0...1) rect with a top-left origin, so one crop applies proportionally across a batch.
    public var rect: CGRect

    public init(normalizedRect: CGRect) {
        rect = normalizedRect
    }

    public var title: String { "Crop" }

    public func apply(to image: CIImage) async throws -> CIImage {
        let unit = rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !unit.isNull, unit.width > 0, unit.height > 0 else { throw ImageKitError.invalidCrop }
        let extent = image.extent
        // Core Image uses a bottom-left origin.
        let pixels = CGRect(
            x: extent.minX + unit.minX * extent.width,
            y: extent.minY + (1 - unit.maxY) * extent.height,
            width: unit.width * extent.width,
            height: unit.height * extent.height
        ).integral.intersection(extent)
        guard !pixels.isEmpty else { throw ImageKitError.invalidCrop }
        return image.cropped(to: pixels).normalized
    }
}
