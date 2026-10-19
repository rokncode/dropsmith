import AppKit
import SwiftUI

struct DropZoneView: View {
    let onDrop: ([SourceImage]) -> Void
    let menu: () -> AnyView

    @State private var isTargeted = false
    @State private var isLoading = false

    private let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)

    var body: some View {
        ZStack {
            VisualEffectBackground()
                .clipShape(shape)
            shape
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.45))
                .padding(10)
            VStack(spacing: 8) {
                if isLoading {
                    ProgressView().controlSize(.regular)
                } else {
                    Image(systemName: isTargeted ? "photo.badge.plus.fill" : "photo.on.rectangle.angled")
                        .font(.system(size: 34, weight: .regular))
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(isTargeted ? "Release to edit" : "Drop images")
                    .font(.callout.weight(.medium))
            }
            .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
        }
        .padding(6)
        .scaleEffect(isTargeted ? 1.05 : 1)
        .animation(.spring(duration: 0.25), value: isTargeted)
        .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { providers in
            isLoading = true
            Task {
                let sources = await DropLoader.sources(from: providers)
                isLoading = false
                if !sources.isEmpty { onDrop(sources) }
            }
            return true
        }
        .contextMenu { menu() }
    }
}

/// Behind-window blur so the zone reads as a translucent widget over the wallpaper.
struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
