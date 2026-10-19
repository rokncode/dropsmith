import CoreImage
import ImageIO

public enum ImageLoader {
    /// Loads the first frame with EXIF orientation applied, normalized to a (0, 0) origin.
    public static func load(contentsOf url: URL) throws -> CIImage {
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            throw ImageKitError.unreadableImage(url)
        }
        return image.normalized
    }

    public static func thumbnail(contentsOf url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
