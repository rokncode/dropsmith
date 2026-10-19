import CoreImage
@testable import ImageKit

func solid(width: Int, height: Int, color: CIColor = .red) -> CIImage {
    CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
}

/// RGBA of one pixel, with Core Image's bottom-left origin.
func pixel(_ image: CIImage, x: Int, y: Int) -> [UInt8] {
    var rgba = [UInt8](repeating: 0, count: 4)
    Renderer.context.render(
        image, toBitmap: &rgba, rowBytes: 4,
        bounds: CGRect(x: x, y: y, width: 1, height: 1),
        format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
    )
    return rgba
}
