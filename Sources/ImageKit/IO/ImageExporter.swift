import CoreImage
import Foundation
import ImageIO

public enum ImageExporter {
    /// Encodes the image. Metadata (EXIF, GPS) is not carried over.
    public static func data(for image: CIImage, format: ImageFormat, options: EncodeOptions = .init()) throws -> Data {
        try encode(prepare(image, for: format), format: format, options: options)
    }

    public static func write(_ image: CIImage, format: ImageFormat, options: EncodeOptions = .init(), to url: URL) throws {
        try data(for: image, format: format, options: options).write(to: url, options: .atomic)
    }

    /// Renders once so repeated encodes (live preview, size fitting) skip Core Image.
    public static func prepare(_ image: CIImage, for format: ImageFormat) throws -> CGImage {
        var image = image
        if !format.supportsAlpha {
            // Formats without alpha would turn transparent pixels black; flatten onto white instead.
            image = image.composited(over: CIImage(color: .white).cropped(to: image.extent))
        }
        return try Renderer.cgImage(from: image)
    }

    public static func encode(_ image: CGImage, format: ImageFormat, options: EncodeOptions = .init()) throws -> Data {
        if format == .webp {
            return try WebPEncoder.encode(image, options: options)
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.utType.identifier as CFString, 1, nil) else {
            throw ImageKitError.encodeFailed(format)
        }
        var properties: [CFString: Any] = [:]
        if format.supportsQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = options.quality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageKitError.encodeFailed(format) }
        return data as Data
    }

    /// Decodes encoded bytes back to an image, to preview compression artifacts.
    public static func decode(_ data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw ImageKitError.renderFailed }
        return image
    }
}

public enum OutputNaming {
    /// `photo.png` → `photo-edited.jpg`, then `photo-edited-2.jpg`, ... so existing files are never overwritten.
    public static func uniqueURL(for source: URL, format: ImageFormat, in directory: URL, suffix: String = "-edited") -> URL {
        let base = source.deletingPathExtension().lastPathComponent + suffix
        var candidate = directory.appendingPathComponent(base).appendingPathExtension(format.fileExtension)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(counter)").appendingPathExtension(format.fileExtension)
            counter += 1
        }
        return candidate
    }
}
