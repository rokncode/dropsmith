import ImageIO
import UniformTypeIdentifiers

public enum ImageFormat: String, CaseIterable, Identifiable, Sendable {
    case png, jpeg, webp, avif, heic, tiff, gif, bmp

    public var id: Self { self }

    public var utType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .webp: .webP
        case .avif: UTType("public.avif") ?? UTType(importedAs: "public.avif")
        case .heic: .heic
        case .tiff: .tiff
        case .gif: .gif
        case .bmp: .bmp
        }
    }

    public var displayName: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .webp: "WebP"
        case .avif: "AVIF"
        case .heic: "HEIC"
        case .tiff: "TIFF"
        case .gif: "GIF"
        case .bmp: "BMP"
        }
    }

    public var fileExtension: String { self == .jpeg ? "jpg" : rawValue }

    public var supportsAlpha: Bool { ![.jpeg, .bmp].contains(self) }

    public var supportsQuality: Bool { [.jpeg, .webp, .avif, .heic].contains(self) }

    /// Options only the libwebp encoder exposes.
    public var supportsLossless: Bool { self == .webp }
    public var supportsEffort: Bool { self == .webp }

    /// WebP is always available (bundled libwebp); everything else is encoded by ImageIO,
    /// whose encoders vary by OS version (AVIF needs a recent macOS).
    public static var writable: [ImageFormat] {
        let identifiers = Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])
        return allCases.filter { $0 == .webp || identifiers.contains($0.utType.identifier) }
    }

    public init?(fileExtension: String) {
        guard let type = UTType(filenameExtension: fileExtension),
              let match = Self.allCases.first(where: { type.conforms(to: $0.utType) })
        else { return nil }
        self = match
    }
}

public struct EncodeOptions: Sendable, Hashable {
    /// 0...1, used by lossy formats.
    public var quality: Double
    /// WebP only.
    public var lossless: Bool
    /// WebP only: 0 (fastest) ... 6 (smallest), libwebp's `method`.
    public var effort: Int

    public init(quality: Double = 0.8, lossless: Bool = false, effort: Int = 4) {
        self.quality = quality
        self.lossless = lossless
        self.effort = effort
    }
}
