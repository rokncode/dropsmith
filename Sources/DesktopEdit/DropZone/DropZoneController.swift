import AppKit
import SwiftUI

/// Owns the desktop drop zone: a borderless, non-activating panel that sits just above the
/// desktop icons (WidgetKit widgets can't accept drops, so this stands in for a widget).
@MainActor
final class DropZoneController {
    static let visibleKey = "dropZoneVisible"
    static let floatsKey = "dropZoneFloatsAboveWindows"
    private static let frameName = "DropZone"
    private static let size = NSSize(width: 150, height: 150)

    var onDrop: (([SourceImage]) -> Void)?
    var onOpen: (() -> Void)?

    private var panel: NSPanel?
    private var defaultsObserver: NSObjectProtocol?

    func start() {
        UserDefaults.standard.register(defaults: [Self.visibleKey: true, Self.floatsKey: false])
        // The menu toggles write to UserDefaults via @AppStorage; follow them from here.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySettings() }
        }
        applySettings()
    }

    private func applySettings() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Self.visibleKey) else {
            panel?.orderOut(nil)
            return
        }
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.level = defaults.bool(forKey: Self.floatsKey)
            ? .floating
            : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.contentView = MovableHostingView(rootView: DropZoneView(
            onDrop: { [weak self] sources in self?.onDrop?(sources) },
            onOpen: { [weak self] in self?.onOpen?() },
            onHide: { UserDefaults.standard.set(false, forKey: Self.visibleKey) }
        ))
        if !panel.setFrameUsingName(Self.frameName), let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - Self.size.width - 24, y: screen.minY + 24))
        }
        panel.setFrameAutosaveName(Self.frameName)
        return panel
    }
}

/// Lets a drag anywhere on the SwiftUI content move the borderless panel.
private final class MovableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
}
