import AppKit
import SwiftUI

@MainActor
final class EditorWindowManager {
    private var windows: [NSWindow] = []

    func open(_ sources: [SourceImage]) {
        let session = EditSession(sources: sources)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = sources.count == 1 ? sources[0].name : "\(sources.count) Images"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: EditorView(session: session))
        window.center()

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
