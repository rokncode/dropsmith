import CoreImage
import Foundation

/// A single edit step. Operations are small value types so a list of them can be
/// replayed on any image (undo, batch export).
public protocol ImageOperation: Sendable {
    var title: String { get }
    func apply(to image: CIImage) async throws -> CIImage
}

public enum ImageKitError: LocalizedError, Equatable {
    case unreadableImage(URL)
    case invalidCrop
    case noSubjectFound
    case renderFailed
    case encodeFailed(ImageFormat)

    public var errorDescription: String? {
        switch self {
        case .unreadableImage(let url): "Couldn't read \(url.lastPathComponent) as an image."
        case .invalidCrop: "The crop area is empty."
        case .noSubjectFound: "No subject was found to keep."
        case .renderFailed: "The image couldn't be rendered."
        case .encodeFailed(let format): "The image couldn't be saved as \(format.displayName)."
        }
    }
}

public enum Pipeline {
    public static func run(_ operations: [any ImageOperation], on image: CIImage) async throws -> CIImage {
        var current = image
        for operation in operations {
            current = try await operation.apply(to: current)
        }
        return current
    }
}

extension CIImage {
    /// Moves the image so its extent starts at (0, 0). Every operation returns a normalized image.
    var normalized: CIImage {
        transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
    }
}
