import AppKit
import ImageKit
import Observation

/// One image in a batch window.
struct BatchItem: Identifiable {
    enum Status: Equatable {
        case idle, working, exported(URL), failed(String)
    }

    /// What the export settings would produce, from an actual encode.
    struct Estimate: Equatable {
        let bytes: Int
        let pixelSize: CGSize
        /// False when a target size is set and even the lowest quality is bigger.
        let fitsTarget: Bool
    }

    let source: SourceImage
    let info: ImageInfo?
    var estimate: Estimate?
    var status = Status.idle

    var id: SourceImage.ID { source.id }
}

/// Everything that should trigger re-estimating the output sizes.
struct BatchEstimateKey: Hashable {
    let recipe: BatchRecipe
    let format: ImageFormat
    let options: EncodeOptions
    let maxBytes: Int?
}

/// State for a batch window: one recipe (no crop, that's per image) applied to every dropped image,
/// with a live size estimate per image.
@MainActor @Observable
final class BatchSession {
    /// Images encoded at once while estimating, so Vision and the encoders don't swamp the machine.
    private static let parallelism = 3
    /// Pixels of rendered results kept in memory (about 800 MB of RGBA8).
    private static let cachePixelBudget = 200_000_000

    private(set) var items: [BatchItem]
    var recipe = BatchRecipe() {
        didSet {
            if recipe.removeBackground, !format.supportsAlpha { format = .png }
        }
    }
    var format: ImageFormat
    var encodeOptions = EncodeOptions(quality: 0.8)
    var targetKilobytes: Int?
    var destination = ExportDestination.besideOriginal
    var errorMessage: String?

    private(set) var estimating: Set<SourceImage.ID> = []
    private(set) var isExporting = false
    private(set) var exportMessage: String?
    private(set) var exportedURLs: [URL] = []

    /// Opens one image in the full editor (crop and one-off edits).
    var openInEditor: ((SourceImage) -> Void)?

    private struct RenderKey: Hashable {
        let id: SourceImage.ID
        let recipe: BatchRecipe
    }

    /// Background removal is the slow part, so its results are kept and changing only the encode
    /// settings never reruns Vision. A plain decode + resize is cheap enough to redo.
    @ObservationIgnored private var renders: [RenderKey: CGImage] = [:]

    init(sources: [SourceImage]) {
        let items = sources.map { BatchItem(source: $0, info: ImageInfo(contentsOf: $0.url)) }
        self.items = items
        let sourceFormat = items.first?.info?.format
        format = sourceFormat.flatMap { ImageFormat.writable.contains($0) ? $0 : nil } ?? .png
    }

    /// The format files are written in: PNG when the background is removed and `format` has no alpha.
    var outputFormat: ImageFormat { recipe.effectiveFormat(format) }

    var maxBytes: Int? {
        let lossless = outputFormat.supportsLossless && encodeOptions.lossless
        guard let targetKilobytes, targetKilobytes > 0, outputFormat.supportsQuality, !lossless else { return nil }
        return targetKilobytes * 1000
    }

    var estimateKey: BatchEstimateKey {
        BatchEstimateKey(recipe: recipe, format: outputFormat, options: encodeOptions, maxBytes: maxBytes)
    }

    var originalBytes: Int { items.compactMap(\.info?.fileBytes).reduce(0, +) }

    /// Nil until every image has an estimate.
    var estimatedBytes: Int? {
        let estimates = items.compactMap(\.estimate)
        return estimates.count == items.count ? estimates.map(\.bytes).reduce(0, +) : nil
    }

    var isEstimating: Bool { !estimating.isEmpty }

    /// Short description of the encode settings, e.g. "80%", "Lossless" or "≤ 200 KB".
    var encodeSummary: String {
        if let targetKilobytes, maxBytes != nil { return "≤ \(targetKilobytes) KB" }
        if outputFormat.supportsLossless && encodeOptions.lossless { return "Lossless" }
        if outputFormat.supportsQuality { return "\(Int((encodeOptions.quality * 100).rounded()))%" }
        return "Default"
    }

    func remove(_ item: BatchItem) {
        guard items.count > 1 else { return }
        items.removeAll { $0.id == item.id }
        renders = renders.filter { $0.key.id != item.id }
    }

    // MARK: Estimates

    /// Encodes every image with the current settings to show its real output size. Called from
    /// `.task(id: estimateKey)`, which cancels the previous run on every change, so the sleep
    /// doubles as a debounce while dragging sliders.
    func refreshEstimates() async {
        let recipe = recipe, format = outputFormat, options = encodeOptions, maxBytes = maxBytes
        do {
            try await Task.sleep(for: .milliseconds(300))
        } catch {
            return
        }
        renders = renders.filter { $0.key.recipe == recipe }
        for index in items.indices { items[index].status = .idle }

        var pending = items.map { (id: $0.id, url: $0.source.url, cached: renders[RenderKey(id: $0.id, recipe: recipe)]) }[...]
        estimating = Set(pending.map(\.id))

        await withTaskGroup(of: (SourceImage.ID, Result<(CGImage, BatchProcessor.Encoded), any Error>).self) { group in
            func startNext() {
                guard let job = pending.popFirst() else { return }
                group.addTask {
                    do {
                        let estimate = try await Self.estimate(job.url, cached: job.cached, recipe: recipe, format: format, options: options, maxBytes: maxBytes)
                        return (job.id, .success(estimate))
                    } catch {
                        return (job.id, .failure(error))
                    }
                }
            }
            for _ in 0..<Self.parallelism { startNext() }

            for await (id, result) in group {
                // A newer refresh owns `estimating` and the items now.
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                estimating.remove(id)
                if let index = items.firstIndex(where: { $0.id == id }) {
                    switch result {
                    case .success(let (image, encoded)):
                        items[index].estimate = BatchItem.Estimate(
                            bytes: encoded.data.count,
                            pixelSize: CGSize(width: image.width, height: image.height),
                            fitsTarget: encoded.fitsTarget
                        )
                        cache(image, for: RenderKey(id: id, recipe: recipe))
                    case .failure(let error):
                        items[index].estimate = nil
                        items[index].status = .failed(error.localizedDescription)
                    }
                }
                startNext()
            }
        }
    }

    private func cache(_ image: CGImage, for key: RenderKey) {
        guard key.recipe.removeBackground, renders[key] == nil else { return }
        let used = renders.values.reduce(0) { $0 + $1.width * $1.height }
        if used + image.width * image.height <= Self.cachePixelBudget {
            renders[key] = image
        }
    }

    // MARK: Export

    func export() async {
        exportMessage = nil
        exportedURLs = []
        let recipe = recipe, format = outputFormat, options = encodeOptions, maxBytes = maxBytes

        if destination == .clipboard {
            isExporting = true
            defer { isExporting = false }
            var images: [NSImage] = []
            for item in items {
                do {
                    let image = try await Self.render(item.source.url, cached: renders[RenderKey(id: item.id, recipe: recipe)], recipe: recipe)
                    images.append(NSImage(cgImage: image, size: .zero))
                } catch {
                    setStatus(.failed(error.localizedDescription), for: item.id)
                }
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects(images)
            exportMessage = "Copied \(images.count) \(images.count == 1 ? "image" : "images")"
            return
        }

        var folder: URL?
        if destination == .chooseFolder {
            guard let chosen = ExportDestination.chooseFolder() else { return }
            folder = chosen
        }

        isExporting = true
        defer { isExporting = false }
        var written: [URL] = []
        for item in items {
            setStatus(.working, for: item.id)
            // One at a time, so `uniqueURL` sees the files written before it.
            let url = OutputNaming.uniqueURL(for: item.source.url, format: format, in: folder ?? item.source.defaultExportFolder)
            do {
                let cached = renders[RenderKey(id: item.id, recipe: recipe)]
                try await Self.export(item.source.url, cached: cached, recipe: recipe, format: format, options: options, maxBytes: maxBytes, to: url)
                setStatus(.exported(url), for: item.id)
                written.append(url)
            } catch {
                setStatus(.failed(error.localizedDescription), for: item.id)
            }
        }
        exportedURLs = written
        let failed = items.count - written.count
        exportMessage = "Saved \(written.count) \(written.count == 1 ? "image" : "images")" + (failed > 0 ? ", \(failed) failed" : "")
    }

    func revealExports() {
        NSWorkspace.shared.activateFileViewerSelecting(exportedURLs)
    }

    private func setStatus(_ status: BatchItem.Status, for id: SourceImage.ID) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].status = status
        }
    }

    // MARK: Helpers

    @concurrent
    private nonisolated static func render(_ url: URL, cached: CGImage?, recipe: BatchRecipe) async throws -> CGImage {
        if let cached { return cached }
        return try await BatchProcessor.render(url, recipe: recipe)
    }

    @concurrent
    private nonisolated static func estimate(
        _ url: URL, cached: CGImage?, recipe: BatchRecipe, format: ImageFormat, options: EncodeOptions, maxBytes: Int?
    ) async throws -> (CGImage, BatchProcessor.Encoded) {
        let image = try await render(url, cached: cached, recipe: recipe)
        try Task.checkCancellation()
        return (image, try BatchProcessor.encode(image, format: format, options: options, maxBytes: maxBytes))
    }

    @concurrent
    private nonisolated static func export(
        _ url: URL, cached: CGImage?, recipe: BatchRecipe, format: ImageFormat, options: EncodeOptions, maxBytes: Int?, to output: URL
    ) async throws {
        let image = try await render(url, cached: cached, recipe: recipe)
        try BatchProcessor.encode(image, format: format, options: options, maxBytes: maxBytes).data.write(to: output, options: .atomic)
    }
}
