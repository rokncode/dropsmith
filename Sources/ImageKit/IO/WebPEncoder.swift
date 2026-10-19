import CoreGraphics
import Foundation
import libwebp

/// libwebp's advanced API, for quality, lossless and effort (`method`) control.
enum WebPEncoder {
    static func encode(_ image: CGImage, options: EncodeOptions) throws -> Data {
        let width = image.width, height = image.height
        let stride = width * 4
        let rgba = try straightRGBA(image)

        var config = WebPConfig()
        guard WebPConfigInit(&config) != 0 else { throw ImageKitError.encodeFailed(.webp) }
        config.lossless = options.lossless ? 1 : 0
        config.quality = Float(min(max(options.quality, 0), 1) * 100)
        config.method = Int32(min(max(options.effort, 0), 6))
        guard WebPValidateConfig(&config) != 0 else { throw ImageKitError.encodeFailed(.webp) }

        var picture = WebPPicture()
        guard WebPPictureInit(&picture) != 0 else { throw ImageKitError.encodeFailed(.webp) }
        defer { WebPPictureFree(&picture) }
        picture.use_argb = 1
        picture.width = Int32(width)
        picture.height = Int32(height)
        guard WebPPictureImportRGBA(&picture, rgba, Int32(stride)) != 0 else { throw ImageKitError.encodeFailed(.webp) }

        var writer = WebPMemoryWriter()
        WebPMemoryWriterInit(&writer)
        defer { WebPMemoryWriterClear(&writer) }
        let succeeded = withUnsafeMutablePointer(to: &writer) { writerPointer in
            picture.writer = WebPMemoryWrite
            picture.custom_ptr = UnsafeMutableRawPointer(writerPointer)
            return WebPEncode(&config, &picture) != 0
        }
        guard succeeded, let bytes = writer.mem else { throw ImageKitError.encodeFailed(.webp) }
        return Data(bytes: bytes, count: writer.size)
    }

    /// libwebp wants straight (non-premultiplied) sRGB RGBA. CoreGraphics only draws premultiplied
    /// 8-bit bitmaps, so draw that and divide alpha back out.
    private static func straightRGBA(_ image: CGImage) throws -> [UInt8] {
        let width = image.width, height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: Renderer.sRGB,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw ImageKitError.encodeFailed(.webp) }
        rgba.withUnsafeMutableBufferPointer { pixels in
            for index in Swift.stride(from: 0, to: pixels.count, by: 4) {
                let alpha = Int(pixels[index + 3])
                guard alpha > 0, alpha < 255 else { continue }
                for channel in index..<index + 3 {
                    pixels[channel] = UInt8(min(255, (Int(pixels[channel]) * 255 + alpha / 2) / alpha))
                }
            }
        }
        return rgba
    }
}
