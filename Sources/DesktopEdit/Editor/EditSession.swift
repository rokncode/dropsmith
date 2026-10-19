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

/// State for one editor window. `operations` is the edit recipe; `history` holds the rendered
/// result after each step for the selected image, so undo is instant and Vision never reruns.
@MainActor @Observable
final class EditSession {
    let sources: [SourceImage]
    private(set) var selectedIndex = 0
    private(set) var operations: [any ImageOperation] = []
    private(set) var history: [CGImage] = []
    private(set) var isWorking = false
    var errorMessage: String?

    var isCropping = false
    var cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    var cropAspect = CropAspect.free { didSet { cropRect = CropGeometry.centeredRect(aspect: normalizedCropAspect) } }

    var exportFormat: ImageFormat
    var exportQuality = 0.85
    var destination = ExportDestination.besideOriginal
    var exportAll = true
    private(set) var exportMessage: String?
    private(set) var exportedURLs: [URL] = []

    init(sources: [SourceImage]) {
        self.sources = sources
        let sourceFormat = sources.first.flatMap { ImageFormat(fileExtension: $0.url.pathExtension) }
        exportFormat = sourceFormat.flatMap { ImageFormat.writable.contains($0) ? $0 : nil } ?? .png
    }

    var current: CGImage? { history.last }
    var selectedSource: SourceImage { sources[selectedIndex] }
    var currentSize: CGSize { current.map { CGSize(width: $0.width, height: $0.height) } ?? .zero }
    var hasTransparencyEdit: Bool { operations.contains { $0 is RemoveBackground } }

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
        cropRect = CropGeometry.centeredRect(aspect: normalizedCropAspect)
        isCropping = true
    }

    func applyCrop() async {
        let crop = Crop(normalizedRect: cropRect)
        isCropping = false
        await apply(crop)
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
        let format = exportFormat, quality = exportQuality, operations = operations
        await run {
            var written: [URL] = []
            for index in indices {
                let source = self.sources[index]
                let url = OutputNaming.uniqueURL(for: source.url, format: format, in: folder ?? Self.defaultFolder(for: source))
                let baked = index == self.selectedIndex ? current : nil
                try await Self.export(source: source.url, baked: baked, operations: operations, format: format, quality: quality, to: url)
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
        format: ImageFormat, quality: Double, to url: URL
    ) async throws {
        let image = if let baked {
            CIImage(cgImage: baked)
        } else {
            try await Pipeline.run(operations, on: ImageLoader.load(contentsOf: source))
        }
        try ImageExporter.write(image, format: format, quality: quality, to: url)
    }
}
