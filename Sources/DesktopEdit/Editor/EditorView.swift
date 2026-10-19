import ImageKit
import SwiftUI

struct EditorView: View {
    @Bindable var session: EditSession

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                CanvasView(session: session)
                if session.sources.count > 1 {
                    Divider()
                    ThumbnailStrip(session: session)
                }
            }
            Divider()
            InspectorView(session: session)
                .frame(width: 300)
        }
        .frame(minWidth: 820, minHeight: 540)
        .task { await session.loadSelected() }
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
            Color(nsColor: .underPageBackgroundColor)
            if let image = session.current {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .background(Checkerboard())
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
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}

struct ThumbnailStrip: View {
    let session: EditSession

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(session.sources.enumerated()), id: \.element.id) { index, source in
                    Button { session.select(index) } label: {
                        Thumbnail(url: source.url)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(index == session.selectedIndex ? Color.accentColor : .clear, lineWidth: 2.5)
                            }
                    }
                    .buttonStyle(.plain)
                    .help(source.name)
                }
            }
            .padding(10)
        }
        .background(.bar)
        .disabled(session.isWorking)
    }
}

struct Thumbnail: View {
    let url: URL
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.15)
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            }
        }
        .task(id: url) {
            image = await Task.detached { ImageLoader.thumbnail(contentsOf: url, maxPixelSize: 160) }.value
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
