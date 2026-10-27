import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Shows temporary drop targets next to the Dock and under the menu bar while an image is being
/// dragged anywhere, so images don't have to come from the desktop. Each target can be turned off.
///
/// A global mouse-drag monitor (no Accessibility permission needed) notices when the system drag
/// pasteboard changes; if the new drag carries images, the targets appear until the mouse is released.
@MainActor
final class DragTargetsController {
    nonisolated static let dockKey = "dragTargetNearDock"
    nonisolated static let menuBarKey = "dragTargetUnderMenuBar"
    private static let size = NSSize(width: 230, height: 64)
    private static let gap: CGFloat = 8

    private enum Target: CaseIterable {
        case dock, menuBar

        var key: String { self == .dock ? DragTargetsController.dockKey : DragTargetsController.menuBarKey }
    }

    var onDrop: (([SourceImage]) -> Void)?

    private var panels: [Target: NSPanel] = [:]
    private var dragMonitor: Any?
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var releaseTimer: Timer?
    private var hideTask: Task<Void, Never>?

    func start() {
        UserDefaults.standard.register(defaults: [Self.dockKey: true, Self.menuBarKey: true])
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDragged() }
        }
    }

    private var enabledTargets: [Target] {
        Target.allCases.filter { UserDefaults.standard.bool(forKey: $0.key) }
    }

    private func mouseDragged() {
        // A new drag session writes the drag pasteboard once; later events of the same drag are no-ops.
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragChangeCount else { return }
        dragChangeCount = pasteboard.changeCount
        guard !enabledTargets.isEmpty, Self.carriesImages(pasteboard) else { return }
        show()
    }

    private static func carriesImages(_ pasteboard: NSPasteboard) -> Bool {
        let imageFiles = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ])
        return !(imageFiles ?? []).isEmpty
            || pasteboard.canReadItem(withDataConformingToTypes: [UTType.image.identifier])
    }

    private func show() {
        hideTask?.cancel()
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        for target in enabledTargets {
            let panel = panels[target] ?? makePanel()
            panels[target] = panel
            panel.setFrame(frame(for: target, on: screen), display: false)
            if !panel.isVisible {
                panel.alphaValue = 0
                panel.orderFrontRegardless()
            }
            panel.animator().alphaValue = 1
        }
        // The drag runs in the source app, so poll for the release instead of waiting for an event.
        releaseTimer?.invalidate()
        releaseTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
                self?.dragEnded()
            }
        }
    }

    private func dragEnded() {
        releaseTimer?.invalidate()
        releaseTimer = nil
        // Give a drop on a target time to be delivered before the panel goes away.
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func hide() {
        for panel in panels.values where panel.isVisible {
            NSAnimationContext.runAnimationGroup { _ in
                panel.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated {
                    if panel.alphaValue == 0 { panel.orderOut(nil) }
                }
            }
        }
    }

    private func frame(for target: Target, on screen: NSScreen) -> NSRect {
        let full = screen.frame, visible = screen.visibleFrame
        let size = Self.size, gap = Self.gap
        var origin: NSPoint
        switch target {
        case .menuBar:
            // Under the menu bar icon when it's on this screen, otherwise centered.
            let midX = Self.statusItemFrame().flatMap { full.contains($0.origin) ? $0.midX : nil } ?? full.midX
            origin = NSPoint(x: midX - size.width / 2, y: visible.maxY - size.height - gap)
        case .dock:
            // visibleFrame excludes the Dock, so the side it's missing from is where the Dock is.
            if visible.minX > full.minX {
                origin = NSPoint(x: visible.minX + gap, y: visible.midY - size.height / 2)
            } else if visible.maxX < full.maxX {
                origin = NSPoint(x: visible.maxX - size.width - gap, y: visible.midY - size.height / 2)
            } else {
                origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + gap)
            }
        }
        origin.x = min(max(origin.x, full.minX + gap), full.maxX - size.width - gap)
        return NSRect(origin: origin, size: size)
    }

    /// The menu bar icon's window (MenuBarExtra doesn't expose its NSStatusItem).
    private static func statusItemFrame() -> NSRect? {
        NSApp.windows.first { String(describing: type(of: $0)) == "NSStatusBarWindow" && $0.isVisible }?.frame
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Above the Dock and the menu bar.
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: DragTargetView { [weak self] sources in
            self?.hide()
            self?.onDrop?(sources)
        })
        return panel
    }
}

private struct DragTargetView: View {
    let onDrop: ([SourceImage]) -> Void

    @State private var isTargeted = false
    @State private var isLoading = false

    private let shape = Capsule(style: .continuous)

    var body: some View {
        ZStack {
            shape
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.45))
                .padding(6)
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: isTargeted ? "photo.badge.plus.fill" : "photo.on.rectangle.angled")
                        .font(.system(size: 22))
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(isTargeted ? "Release to edit" : "Drop to edit")
                    .font(.callout.weight(.medium))
            }
            .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
        }
        .glassEffect(isTargeted ? .regular.tint(.accentColor.opacity(0.35)) : .regular, in: shape)
        .scaleEffect(isTargeted ? 1.05 : 1)
        .animation(.spring(duration: 0.25), value: isTargeted)
        .onImageDrop(isTargeted: $isTargeted, isLoading: $isLoading, perform: onDrop)
    }
}
