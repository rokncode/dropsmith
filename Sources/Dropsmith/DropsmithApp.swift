import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

@main
struct DropsmithApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AppDelegate.menuBarIconKey) private var showMenuBarIcon = true

    var body: some Scene {
        MenuBarExtra("Dropsmith", systemImage: "photo.on.rectangle.angled", isInserted: $showMenuBarIcon) {
            AppMenu(appDelegate: appDelegate)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let menuBarIconKey = "menuBarIconVisible"
    private static let hiddenIconTipKey = "suppressHiddenMenuBarIconTip"

    let dropZone = DropZoneController()
    let dragTargets = DragTargetsController()
    let editors = EditorWindowManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar agent: no Dock icon even when run unbundled via `swift run`.
        NSApp.setActivationPolicy(.accessory)
        dropZone.onDrop = { [weak self] sources in self?.editors.open(sources) }
        dropZone.menu = { [unowned self] in AnyView(AppMenu(appDelegate: self)) }
        dropZone.start()
        dragTargets.onDrop = { [weak self] sources in self?.editors.open(sources) }
        dragTargets.start()
    }

    /// Launching the app again while it runs (Finder, Spotlight, `open`) is the way back when
    /// both the menu bar icon and the drop zone are hidden, so bring both back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        UserDefaults.standard.set(true, forKey: Self.menuBarIconKey)
        UserDefaults.standard.set(true, forKey: DropZoneController.visibleKey)
        return false
    }

    var isMenuBarIconVisible: Bool {
        UserDefaults.standard.object(forKey: Self.menuBarIconKey) as? Bool ?? true
    }

    var isDropZoneVisible: Bool {
        UserDefaults.standard.bool(forKey: DropZoneController.visibleKey)
    }

    func setMenuBarIconVisible(_ visible: Bool) {
        UserDefaults.standard.set(visible, forKey: Self.menuBarIconKey)
        if !visible { explainHowToGetBack(force: !isDropZoneVisible) }
    }

    func setDropZoneVisible(_ visible: Bool) {
        UserDefaults.standard.set(visible, forKey: DropZoneController.visibleKey)
        if !visible && !isMenuBarIconVisible { explainHowToGetBack(force: true) }
    }

    /// Shown when the menu bar icon is hidden (suppressible), and always when nothing is left visible.
    private func explainHowToGetBack(force: Bool) {
        let defaults = UserDefaults.standard
        guard force || !defaults.bool(forKey: Self.hiddenIconTipKey) else { return }
        let alert = NSAlert()
        if isDropZoneVisible {
            alert.messageText = "Menu bar icon hidden"
            alert.informativeText = "Right-click the drop zone for settings and Quit. You can also open Dropsmith again from Finder or Spotlight to bring the icon back."
            alert.showsSuppressionButton = true
        } else {
            alert.messageText = "Dropsmith is still running"
            alert.informativeText = "The menu bar icon and the drop zone are both hidden. Open Dropsmith again from Finder or Spotlight to bring them back."
        }
        NSApp.activate()
        alert.runModal()
        if alert.suppressionButton?.state == .on {
            defaults.set(true, forKey: Self.hiddenIconTipKey)
        }
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

/// Shared by the menu bar icon and the drop zone's right-click menu, so every setting (and Quit)
/// stays reachable when either one is hidden.
struct AppMenu: View {
    let appDelegate: AppDelegate
    @AppStorage(AppDelegate.menuBarIconKey) private var showMenuBarIcon = true
    @AppStorage(DropZoneController.visibleKey) private var showDropZone = true
    @AppStorage(DropZoneController.floatsKey) private var floatAboveWindows = false
    @AppStorage(DragTargetsController.dockKey) private var dockTarget = true
    @AppStorage(DragTargetsController.menuBarKey) private var menuBarTarget = true

    var body: some View {
        Button("Open Images…") { appDelegate.openImages() }
            .keyboardShortcut("o")
        Divider()
        Toggle("Show Drop Zone", isOn: Binding(
            get: { showDropZone },
            set: { appDelegate.setDropZoneVisible($0) }
        ))
        Toggle("Keep Drop Zone Above Windows", isOn: $floatAboveWindows)
        Menu("Drop Targets While Dragging") {
            Toggle("Near the Dock", isOn: $dockTarget)
            Toggle("Under the Menu Bar", isOn: $menuBarTarget)
        }
        Toggle("Show Menu Bar Icon", isOn: Binding(
            get: { showMenuBarIcon },
            set: { appDelegate.setMenuBarIconVisible($0) }
        ))
        if LoginItem.isAvailable {
            Toggle("Launch at Login", isOn: LoginItem.binding)
        }
        Divider()
        Button("Quit Dropsmith") { NSApp.terminate(nil) }
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
