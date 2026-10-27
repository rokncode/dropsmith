import AppKit
import SwiftUI

/// Behind-window blur: the frosted base every Dropsmith window sits on. Controls, bars and
/// panels float above it as Liquid Glass.
struct WindowBackdrop: NSViewRepresentable {
    var material = NSVisualEffectView.Material.underWindowBackground

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

@MainActor
enum GlassWindow {
    /// A translucent window: content runs under a transparent title bar, over a behind-window blur.
    static func make(title: String, size: NSSize, minSize: NSSize, content: some View) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.contentMinSize = minSize
        window.contentView = NSHostingView(rootView: content.background {
            WindowBackdrop().ignoresSafeArea()
        })
        window.center()
        return window
    }
}

extension View {
    /// A floating Liquid Glass panel, e.g. the inspector or a toolbar.
    func glassPanel(cornerRadius: CGFloat = 20) -> some View {
        glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// A small capsule of text or icons on glass, e.g. a badge or a summary chip.
    func glassChip() -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(.regular, in: Capsule())
    }
}
