import CoreGraphics

/// Crop-rect math in normalized (0...1), top-left-origin coordinates, shared by the crop overlay UI.
public enum CropGeometry {
    public static let minimumSize: CGFloat = 0.02

    /// Converts a pixel aspect ratio (width / height) into the matching ratio in normalized space.
    public static func normalizedAspect(_ pixelAspect: CGFloat, imageSize: CGSize) -> CGFloat {
        pixelAspect * imageSize.height / imageSize.width
    }

    /// The largest centered rect with the given normalized aspect, or the full image when `aspect` is nil.
    public static func centeredRect(aspect: CGFloat?) -> CGRect {
        guard let aspect else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let size = aspect >= 1 ? CGSize(width: 1, height: 1 / aspect) : CGSize(width: aspect, height: 1)
        return CGRect(x: (1 - size.width) / 2, y: (1 - size.height) / 2, width: size.width, height: size.height)
    }

    /// The rect spanned by a fixed `anchor` corner and a dragged corner `point`. The dragged corner
    /// stays on its own side of the anchor (`towardRight` / `towardBottom`), and the result is kept
    /// inside the unit square, honoring `aspect` when set.
    public static func rect(anchor: CGPoint, point: CGPoint, towardRight: Bool, towardBottom: Bool, aspect: CGFloat?) -> CGRect {
        let availableWidth = towardRight ? 1 - anchor.x : anchor.x
        let availableHeight = towardBottom ? 1 - anchor.y : anchor.y
        var width = min(availableWidth, max(minimumSize, towardRight ? point.x - anchor.x : anchor.x - point.x))
        var height = min(availableHeight, max(minimumSize, towardBottom ? point.y - anchor.y : anchor.y - point.y))
        if let aspect {
            width = max(width, height * aspect)
            height = width / aspect
            if width > availableWidth { width = availableWidth; height = width / aspect }
            if height > availableHeight { height = availableHeight; width = height * aspect }
        }
        return CGRect(
            x: towardRight ? anchor.x : anchor.x - width,
            y: towardBottom ? anchor.y : anchor.y - height,
            width: width,
            height: height
        )
    }

    /// `rect` moved by `delta` and clamped inside the unit square.
    public static func moved(_ rect: CGRect, by delta: CGSize) -> CGRect {
        var result = rect
        result.origin.x = min(max(0, rect.minX + delta.width), 1 - rect.width)
        result.origin.y = min(max(0, rect.minY + delta.height), 1 - rect.height)
        return result
    }
}
