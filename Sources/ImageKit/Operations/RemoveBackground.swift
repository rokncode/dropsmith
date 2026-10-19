import CoreImage
import Vision

/// Keeps the foreground subject(s) found by Vision and makes everything else transparent.
public struct RemoveBackground: ImageOperation {
    public init() {}

    public var title: String { "Remove Background" }

    public func apply(to image: CIImage) async throws -> CIImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: image)
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else {
            throw ImageKitError.noSubjectFound
        }
        let mask = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
        return image
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: CIImage.empty(),
                kCIInputMaskImageKey: CIImage(cvPixelBuffer: mask),
            ])
            .cropped(to: image.extent)
    }
}
