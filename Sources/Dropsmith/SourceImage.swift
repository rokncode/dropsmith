import AppKit
import UniformTypeIdentifiers

/// A dropped or opened image. Raw image data (e.g. dragged from a browser) is written to a
/// temporary file first, so every operation and export works from a file URL.
struct SourceImage: Identifiable, Hashable, Sendable {
    let id = UUID()
    let url: URL
    var isTemporary = false

    var name: String { url.lastPathComponent }

    static func isImage(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
        return type?.conforms(to: .image) ?? false
    }

    static func temporary(data: Data, type: UTType) throws -> SourceImage {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Dropsmith", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Dropped Image")
            .appendingPathExtension(type.preferredFilenameExtension ?? "png")
        try data.write(to: url)
        return SourceImage(url: url, isTemporary: true)
    }
}

@MainActor
enum DropLoader {
    static func sources(from providers: [NSItemProvider]) async -> [SourceImage] {
        var sources: [SourceImage] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                if let url = await fileURL(from: provider), SourceImage.isImage(url) {
                    sources.append(SourceImage(url: url))
                }
            } else if let source = await imageData(from: provider) {
                sources.append(source)
            }
        }
        return sources
    }

    private static func fileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    private static func imageData(from provider: NSItemProvider) async -> SourceImage? {
        guard let type = provider.registeredTypeIdentifiers
            .compactMap(UTType.init)
            .first(where: { $0.conforms(to: .image) })
        else { return nil }
        let data: Data? = await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
        guard let data else { return nil }
        return try? SourceImage.temporary(data: data, type: type)
    }
}
