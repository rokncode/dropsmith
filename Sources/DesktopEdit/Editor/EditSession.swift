import AppKit
import ImageKit
import Observation

enum ExportDestination: Hashable {
    case besideOriginal, chooseFolder, clipboard
}

enum CropAspect: String, CaseIterable, Identifiable {
    case free = "Free", original = "Original", square = "1:1"
    case fourThree = "4:3", threeTwo = "3:2", sixteenNine = "16:9"
    case threeFour = "3:4", nineSixteen = "9:16"

    var id: Self { self }

    /// Width / height in pixels, nil for free-form.
    func pixelAspect(imageSize: CGSize) -> CGFloat? {
        switch self {
        case .free: nil
        case .original: imageSize.width / imageSize.height
        case .square: 1
        case .fourThree: 4 / 3
        case .threeTwo: 3 / 2
        case .sixteenNine: 16 / 9
        case .threeFour: 3 / 4
        case .nineSixteen: 9 / 16
        }
    }
}

/// Live Squoosh-style preview: the current image actually encoded with the export settings.
struct Comparison {
    let image: CGImage
    let bytes: Int
}

/// Everything that should trigger a re-encode of the comparison preview.
struct CompressionKey: Hashable {
    let isComparing: Bool
    let format: ImageFormat
    let options: EncodeOptions
    let revision: Int
}

/// State for one editor window. `operations` is the edit recipe; `history` holds the rendered
/// result after each step for the selected image, so undo is instant and Vision never reruns.
@MainActor @Observable
final class EditSession {
    let sources: [SourceImage]
    private(set) var selectedIndex = 0
    private(set) var operations: [any ImageOperation] = []
    private(set) var history: [CGImage] = [] { didSet { revision += 1 } }
    /// Bumped on every change to `history`, since its count alone repeats after undo + apply.
    private(set) var revision = 0
    private(set) var isWorking = false
    var errorMessage: String?

    var isCropping = false
    var cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    var cropAspect = CropAspect.free { didSet { cropRect = CropGeometry.centeredRect(aspect: normalizedCropAspect) } }

    var exportFormat: ImageFormat
    var encodeOptions = EncodeOptions(quality: 0.8)
    var targetKilobytes: Int?
    var destination = ExportDestination.besideOriginal
    var exportAll = true
    private(set) var exportMessage: String?
    private(set) var exportedURLs: [URL] = []

    var isComparing = false { didSet { if !isComparing { comparison = nil } } }
    private(set) var comparison: Comparison?
    private(set) var isEncoding = false

    init(sources: [SourceImage]) {
        self.sources = sources
        let sourceFormat = sources.first.flatMap { ImageFormat(fileExtension: $0.url.pathExtension) }
        exportFormat = sourceFormat.flatMap { ImageFormat.writable.contains($0) ? $0 : nil } ?? .png
    }

    var current: CGImage? { history.last }
    var selectedSource: SourceImage { sources[selectedIndex] }
    var currentSize: CGSize { current.map { CGSize(width: $0.width, height: $0.height) } ?? .zero }
    var hasTransparencyEdit: Bool { operations.contains { $0 is RemoveBackground } }

    var originalBytes: Int? {
        // Resolve symlinks, or this reports the link's own size.
        (try? selectedSource.url.resolvingSymlinksInPath().resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }

    var compressionKey: CompressionKey {
        CompressionKey(isComparing: isComparing, format: exportFormat, options: encodeOptions, revision: revision)
    }

    /// Short description of the encode settings, e.g. "WebP · 80%" or "WebP · lossless".
    var encodeSummary: String {
        if exportFormat.supportsLossless && encodeOptions.lossless { return "\(exportFormat.displayName) · lossless" }
        if exportFormat.supportsQuality { return "\(exportFormat.displayName) · \(Int((encodeOptions.quality * 100).rounded()))%" }
        return exportFormat.displayName
    }

    var normalizedCropAspect: CGFloat? {
        guard currentSize != .zero, let aspect = cropAspect.pixelAspect(imageSize: currentSize) else { return nil }
        return CropGeometry.normalizedAspect(aspect, imageSize: currentSize)
    }

    var cropPixelSize: CGSize {
        CGSize(width: (cropRect.width * currentSize.width).rounded(), height: (cropRect.height * currentSize.height).rounded())
    }

    // MARK: Editing

    func loadSelected() async {
        await run {
            self.history = try await Self.renderSteps(of: self.selectedSource.url, operations: self.operations)
        }
    }

    func select(_ index: Int) {
        guard index != selectedIndex, sources.indices.contains(index) else { return }
        selectedIndex = index
        isCropping = false
        Task { await loadSelected() }
    }

    func apply(_ operation: any ImageOperation) async {
        guard let current else { return }
        await run {
            let result = try await Self.render(operation, on: current)
            self.operations.append(operation)
            self.history.append(result)
            if operation is RemoveBackground, !self.exportFormat.supportsAlpha {
                self.exportFormat = .png
            }
        }
    }

    func undo() {
        guard !operations.isEmpty else { return }
        operations.removeLast()
        history.removeLast()
    }

    func reset() {
        operations.removeAll()
        history = Array(history.prefix(1))
    }

    func beginCrop() {
        isComparing = false
        cropRect = CropGeometry.centeredRect(aspect: normalizedCropAspect)
        isCropping = true
    }

    func applyCrop() async {
        let crop = Crop(normalizedRect: cropRect)
        isCropping = false
        await apply(crop)
    }

    // MARK: Compression

    /// Re-encodes the comparison preview. Called from `.task(id: compressionKey)`, which cancels
    /// the previous run on every change, so the sleep doubles as a debounce while dragging sliders.
    func refreshComparison() async {
        guard isComparing, let current else {
            comparison = nil
            isEncoding = false
            return
        }
        let format = exportFormat, options = encodeOptions
        isEncoding = true
        do {
            try await Task.sleep(for: .milliseconds(250))
            let result = try await Self.compress(current, format: format, options: options)
            try Task.checkCancellation()
            comparison = result
            isEncoding = false
        } catch is CancellationError {
            // A newer refresh owns `isEncoding` now.
        } catch {
            isEncoding = false
            errorMessage = error.localizedDescription
        }
    }

    /// Sets the quality to the highest value whose file fits `targetKilobytes`.
    func fitToTargetSize() async {
        guard let current, let kilobytes = targetKilobytes, kilobytes > 0, exportFormat.supportsQuality else { return }
        let format = exportFormat, options = encodeOptions
        await run {
            guard let fit = try await Self.fit(current, format: format, options: options, maxBytes: kilobytes * 1000) else {
                self.errorMessage = "\(format.displayName) can't get under \(kilobytes) KB even at the lowest quality. Try resizing the image first."
                return
            }
            self.encodeOptions.lossless = false
            self.encodeOptions.quality = fit.quality
        }
    }

    // MARK: Export

    func export() async {
        guard let current else { return }
        exportMessage = nil
        exportedURLs = []

        if destination == .clipboard {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([NSImage(cgImage: current, size: .zero)])
            exportMessage = "Copied to clipboard"
            return
        }

        var folder: URL?
        if destination == .chooseFolder {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Export Here"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            folder = url
        }

        let indices = exportAll && sources.count > 1 ? Array(sources.indices) : [selectedIndex]
        let format = exportFormat, options = encodeOptions, operations = operations
        await run {
            var written: [URL] = []
            for index in indices {
                let source = self.sources[index]
                let url = OutputNaming.uniqueURL(for: source.url, format: format, in: folder ?? Self.defaultFolder(for: source))
                let baked = index == self.selectedIndex ? current : nil
                try await Self.export(source: source.url, baked: baked, operations: operations, format: format, options: options, to: url)
                written.append(url)
            }
            self.exportedURLs = written
            self.exportMessage = written.count == 1 ? "Saved \(written[0].lastPathComponent)" : "Saved \(written.count) images"
        }
    }

    func revealExports() {
        NSWorkspace.shared.activateFileViewerSelecting(exportedURLs)
    }

    // MARK: Helpers

    private func run(_ work: () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await work()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Next to the original when that folder is writable, otherwise (and for dropped data) ~/Downloads.
    private static func defaultFolder(for source: SourceImage) -> URL {
        let folder = source.url.deletingLastPathComponent()
        if !source.isTemporary, FileManager.default.isWritableFile(atPath: folder.path) {
            return folder
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    @concurrent
    private nonisolated static func renderSteps(of url: URL, operations: [any ImageOperation]) async throws -> [CGImage] {
        var steps = [try Renderer.cgImage(from: ImageLoader.load(contentsOf: url))]
        for operation in operations {
            steps.append(try await render(operation, on: steps[steps.count - 1]))
        }
        return steps
    }

    @concurrent
    private nonisolated static func render(_ operation: any ImageOperation, on image: CGImage) async throws -> CGImage {
        try Renderer.cgImage(from: await operation.apply(to: CIImage(cgImage: image)))
    }

    @concurrent
    private nonisolated static func export(
        source: URL, baked: CGImage?, operations: [any ImageOperation],
        format: ImageFormat, options: EncodeOptions, to url: URL
    ) async throws {
        let image = if let baked {
            CIImage(cgImage: baked)
        } else {
            try await Pipeline.run(operations, on: ImageLoader.load(contentsOf: source))
        }
        try ImageExporter.write(image, format: format, options: options, to: url)
    }

    @concurrent
    private nonisolated static func compress(_ image: CGImage, format: ImageFormat, options: EncodeOptions) async throws -> Comparison {
        let prepared = try ImageExporter.prepare(CIImage(cgImage: image), for: format)
        let data = try ImageExporter.encode(prepared, format: format, options: options)
        return Comparison(image: try ImageExporter.decode(data), bytes: data.count)
    }

    @concurrent
    private nonisolated static func fit(_ image: CGImage, format: ImageFormat, options: EncodeOptions, maxBytes: Int) async throws -> Compressor.Fit? {
        let prepared = try ImageExporter.prepare(CIImage(cgImage: image), for: format)
        return try Compressor.fit(prepared, format: format, options: options, maxBytes: maxBytes)
    }
}
