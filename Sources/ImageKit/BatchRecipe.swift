import Foundation

/// The edits a batch applies to every image. Crop isn't here: it only makes sense per image.
public struct BatchRecipe: Sendable, Hashable {
    public var removeBackground: Bool
    /// `.scale` or `.fit`; `.exact` would stretch images with other shapes.
    public var resize: Resize.Mode?

    public init(removeBackground: Bool = false, resize: Resize.Mode? = nil) {
        self.removeBackground = removeBackground
        self.resize = resize
    }

    public var isEmpty: Bool { !removeBackground && resize == nil }

    /// Background removal first, so Vision sees the full-resolution image.
    public var operations: [any ImageOperation] {
        var operations: [any ImageOperation] = []
        if removeBackground { operations.append(RemoveBackground()) }
        if let resize { operations.append(Resize(resize)) }
        return operations
    }

    /// The pixel size after the recipe, for an image of `size`.
    public func outputSize(for size: CGSize) -> CGSize {
        resize.map { Resize($0).targetSize(for: size) } ?? size
    }

    /// A removed background needs alpha, so formats without it switch to PNG.
    public func effectiveFormat(_ format: ImageFormat) -> ImageFormat {
        removeBackground && !format.supportsAlpha ? .png : format
    }
}
