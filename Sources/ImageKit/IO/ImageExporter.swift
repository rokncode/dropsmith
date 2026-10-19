import CoreImage
import Foundation
import ImageIO

public enum ImageExporter {
    /// Encodes the image. Metadata (EXIF, GPS) is not carried over.
    public static func data(for image: CIImage, format: ImageFormat, quality: Double = 0.9) throws -> Data {
        var image = image
        if !format.supportsAlpha {
            // Formats without alpha would turn transparent pixels black; flatten onto white instead.
            image = image.composited(over: CIImage(color: .white).cropped(to: image.extent))
        }
        let cgImage = try Renderer.cgImage(from: image)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.utType.identifier as CFString, 1, nil) else {
            throw ImageKitError.encodeFailed(format)
        }
        var properties: [CFString: Any] = [:]
        if format.supportsQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ImageKitError.encodeFailed(format) }
        return data as Data
    }

    public static func write(_ image: CIImage, format: ImageFormat, quality: Double = 0.9, to url: URL) throws {
        try data(for: image, format: format, quality: quality).write(to: url, options: .atomic)
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
