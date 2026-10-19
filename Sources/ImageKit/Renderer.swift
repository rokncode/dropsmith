import CoreImage

public enum Renderer {
    public static let context = CIContext(options: [.cacheIntermediates: false])
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    public static func cgImage(from image: CIImage) throws -> CGImage {
        let extent = image.extent.integral
        guard !extent.isInfinite, !extent.isEmpty else { throw ImageKitError.renderFailed }
        // RGBA8 output needs an RGB color space; grayscale/CMYK sources render into sRGB.
        let colorSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? sRGB
        guard let cgImage = context.createCGImage(image, from: extent, format: .RGBA8, colorSpace: colorSpace) else {
            throw ImageKitError.renderFailed
        }
        return cgImage
    }
}
