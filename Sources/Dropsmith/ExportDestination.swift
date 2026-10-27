import AppKit

enum ExportDestination: Hashable {
    case besideOriginal, chooseFolder, clipboard

    /// Asks for an output folder; nil when cancelled.
    @MainActor static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

extension SourceImage {
    /// Next to the original when that folder is writable, otherwise (and for dropped data) ~/Downloads.
    var defaultExportFolder: URL {
        let folder = url.deletingLastPathComponent()
        if !isTemporary, FileManager.default.isWritableFile(atPath: folder.path) {
            return folder
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }
}
