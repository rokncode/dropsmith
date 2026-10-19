import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

@main
struct DesktopEditApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Desktop Edit", systemImage: "photo.on.rectangle.angled") {
            MenuContent(appDelegate: appDelegate)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let dropZone = DropZoneController()
    let editors = EditorWindowManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar agent: no Dock icon even when run unbundled via `swift run`.
        NSApp.setActivationPolicy(.accessory)
        dropZone.onDrop = { [weak self] sources in self?.editors.open(sources) }
        dropZone.onOpen = { [weak self] in self?.openImages() }
        dropZone.start()
    }

    func openImages() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let sources = panel.urls.filter(SourceImage.isImage).map { SourceImage(url: $0) }
        if !sources.isEmpty { editors.open(sources) }
    }
}

struct MenuContent: View {
    let appDelegate: AppDelegate
    @AppStorage(DropZoneController.visibleKey) private var showDropZone = true
    @AppStorage(DropZoneController.floatsKey) private var floatAboveWindows = false

    var body: some View {
        Button("Open Images…") { appDelegate.openImages() }
            .keyboardShortcut("o")
        Divider()
        Toggle("Show Drop Zone", isOn: $showDropZone)
        Toggle("Keep Drop Zone Above Windows", isOn: $floatAboveWindows)
        if LoginItem.isAvailable {
            Toggle("Launch at Login", isOn: LoginItem.binding)
        }
        Divider()
        Button("Quit Desktop Edit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

enum LoginItem {
    /// SMAppService only works from a real .app bundle, not `swift run`.
    static var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    @MainActor static var binding: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enabled in
                try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            }
        )
    }
}
