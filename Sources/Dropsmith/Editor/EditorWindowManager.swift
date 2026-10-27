import AppKit
import SwiftUI

/// Opens a window per drop: the full editor for one image, the batch window for several.
@MainActor
final class EditorWindowManager {
    private var windows: [NSWindow] = []

    func open(_ sources: [SourceImage]) {
        if sources.count == 1 {
            openEditor(sources[0])
        } else if !sources.isEmpty {
            openBatch(sources)
        }
    }

    func openEditor(_ source: SourceImage) {
        let session = EditSession(source: source)
        show(GlassWindow.make(
            title: source.name,
            size: NSSize(width: 1040, height: 700),
            minSize: NSSize(width: 820, height: 540),
            content: EditorView(session: session)
        ))
    }

    private func openBatch(_ sources: [SourceImage]) {
        let session = BatchSession(sources: sources)
        session.openInEditor = { [weak self] source in self?.openEditor(source) }
        show(GlassWindow.make(
            title: "\(sources.count) Images",
            size: NSSize(width: 780, height: 580),
            minSize: NSSize(width: 620, height: 440),
            content: BatchView(session: session)
        ))
    }

    private func show(_ window: NSWindow) {
        let windowID = ObjectIdentifier(window)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.windows.removeAll { ObjectIdentifier($0) == windowID }
            }
        }
        windows.append(window)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
