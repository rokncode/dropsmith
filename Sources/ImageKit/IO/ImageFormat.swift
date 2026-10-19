import ImageIO
import UniformTypeIdentifiers

public enum ImageFormat: String, CaseIterable, Identifiable, Sendable {
    case png, jpeg, heic, tiff, gif, bmp, webp

    public var id: Self { self }

    public var utType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        case .tiff: .tiff
        case .gif: .gif
        case .bmp: .bmp
        case .webp: .webP
        }
    }

    public var displayName: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        case .tiff: "TIFF"
        case .gif: "GIF"
        case .bmp: "BMP"
        case .webp: "WebP"
        }
    }

    public var fileExtension: String { self == .jpeg ? "jpg" : rawValue }

    public var supportsAlpha: Bool { ![.jpeg, .bmp].contains(self) }

    public var supportsQuality: Bool { [.jpeg, .heic, .webp].contains(self) }

    /// Formats ImageIO can encode on this machine (WebP encoding depends on the OS version).
    public static var writable: [ImageFormat] {
        let identifiers = Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])
        return allCases.filter { identifiers.contains($0.utType.identifier) }
    }

    public init?(fileExtension: String) {
        guard let type = UTType(filenameExtension: fileExtension),
              let match = Self.allCases.first(where: { type.conforms(to: $0.utType) })
        else { return nil }
        self = match
    }
}
