import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What a file is, read from its header without decoding the pixels.
public struct ImageInfo: Sendable, Hashable {
    /// With EXIF orientation applied, so it matches `ImageLoader.load`.
    public let pixelSize: CGSize
    public let fileBytes: Int
    public let format: ImageFormat?
    /// Short type name for display, e.g. "HEIC", also for formats we can't write.
    public let typeName: String
    public let hasAlpha: Bool

    public init?(contentsOf url: URL) {
        // Resolve symlinks, or the size is the link's own.
        let url = url.resolvingSymlinksInPath()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }

        // Orientations 5...8 are rotated a quarter turn, so width and height swap.
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        pixelSize = (5...8).contains(orientation)
            ? CGSize(width: height, height: width)
            : CGSize(width: width, height: height)
        fileBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        hasAlpha = properties[kCGImagePropertyHasAlpha] as? Bool ?? false

        let type = (CGImageSourceGetType(source) as String?).flatMap { UTType($0) }
        format = type.flatMap { type in ImageFormat.allCases.first { type.conforms(to: $0.utType) } }
        typeName = format?.displayName
            ?? type?.preferredFilenameExtension?.uppercased()
            ?? url.pathExtension.uppercased()
    }
}
