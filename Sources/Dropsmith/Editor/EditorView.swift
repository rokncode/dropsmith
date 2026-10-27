import ImageKit
import SwiftUI

struct EditorView: View {
    @Bindable var session: EditSession

    var body: some View {
        HStack(spacing: 0) {
            CanvasView(session: session)
            InspectorView(session: session)
                .frame(width: 300)
                .glassPanel()
                .padding([.vertical, .trailing], 10)
                // The panel runs up beside the traffic lights; the canvas keeps clear of them.
                .ignoresSafeArea(.container, edges: .top)
        }
        .frame(minWidth: 820, minHeight: 540)
        .task { await session.load() }
        .task(id: session.compressionKey) { await session.refreshComparison() }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } }),
            presenting: session.errorMessage
        ) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
    }
}

struct CanvasView: View {
    @Bindable var session: EditSession

    var body: some View {
        ZStack {
            Color.clear
            if session.isComparing, let image = session.current {
                CompareView(session: session, original: image)
            } else if let image = session.current {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .background(Checkerboard())
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
                    .overlay {
                        if session.isCropping {
                            CropOverlay(rect: $session.cropRect, aspect: session.normalizedCropAspect)
                        }
                    }
                    // Don't upscale small images beyond their pixel size.
                    .frame(maxWidth: CGFloat(image.width), maxHeight: CGFloat(image.height))
                    .padding(28)
            }
            if session.isWorking {
                ProgressView()
                    .controlSize(.large)
                    .padding(24)
                    .glassPanel(cornerRadius: 18)
            }
        }
    }
}

struct Thumbnail: View {
    let url: URL
    var maxPixelSize = 160
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            }
        }
        .task(id: url) {
            let size = maxPixelSize
            image = await Task.detached { ImageLoader.thumbnail(contentsOf: url, maxPixelSize: size) }.value
        }
    }
}

/// Transparency backdrop so removed backgrounds are visible.
struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 8
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            var path = Path()
            for row in 0..<Int((size.height / tile).rounded(.up)) {
                for column in 0..<Int((size.width / tile).rounded(.up)) where (row + column).isMultiple(of: 2) {
                    path.addRect(CGRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile, width: tile, height: tile))
                }
            }
            context.fill(path, with: .color(Color(white: 0.87)))
        }
    }
}
