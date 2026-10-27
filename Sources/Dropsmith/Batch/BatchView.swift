import ImageKit
import SwiftUI

/// Compact window for several dropped images: one set of edits for all of them, a card per image
/// with its real output size, and "Open in Editor" for anything per image (like crop).
struct BatchView: View {
    @Bindable var session: BatchSession

    var body: some View {
        VStack(spacing: 0) {
            BatchHeader(session: session)
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 240), spacing: 14)], spacing: 14) {
                    ForEach(session.items) { item in
                        BatchCard(session: session, item: item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                // Room to scroll the last row out from under the floating action bar.
                .padding(.bottom, 96)
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
        }
        .overlay(alignment: .bottom) {
            BatchActionBar(session: session)
                .padding(12)
        }
        .frame(minWidth: 620, minHeight: 440)
        .task(id: session.estimateKey) { await session.refreshEstimates() }
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

// MARK: Header

private struct BatchHeader: View {
    let session: BatchSession

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(session.items.count) Images")
                    .font(.title2.weight(.semibold))
                Text(details)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                if session.isEstimating {
                    ProgressView().controlSize(.small)
                }
                Text(formatBytes(session.originalBytes))
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                Text(session.estimatedBytes.map(formatBytes) ?? "…")
                    .fontWeight(.semibold)
            }
            .monospacedDigit()
            .glassChip()
            if let estimated = session.estimatedBytes, let savings = Savings(from: session.originalBytes, to: estimated) {
                Text(savings.text)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(savings.color)
                    .glassChip()
            }
        }
        .animation(.default, value: session.estimatedBytes)
    }

    /// e.g. "HEIC, PNG → WebP · 48 MP".
    private var details: String {
        var types: [String] = []
        for name in session.items.compactMap(\.info?.typeName) where !types.contains(name) {
            types.append(name)
        }
        let megapixels = session.items.compactMap(\.info).reduce(0) { $0 + $1.pixelSize.width * $1.pixelSize.height } / 1_000_000
        return "\(types.joined(separator: ", ")) → \(session.outputFormat.displayName) · \(Int(megapixels.rounded())) MP"
    }
}

// MARK: Card

private struct BatchCard: View {
    let session: BatchSession
    let item: BatchItem

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            preview
            VStack(alignment: .leading, spacing: 4) {
                Text(item.source.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.source.name)
                HStack(spacing: 4) {
                    Text(typeChange)
                    Spacer(minLength: 4)
                    Text(sizeChange)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                bytes
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .glassPanel(cornerRadius: 18)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { session.openInEditor?(item.source) }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }

    private var preview: some View {
        Thumbnail(url: item.source.url, maxPixelSize: 480)
            .background(Checkerboard())
            .frame(height: 130)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topTrailing) { statusBadge.padding(6) }
            .overlay(alignment: .topLeading) {
                if isHovering && !session.isExporting {
                    GlassEffectContainer(spacing: 6) {
                        HStack(spacing: 6) {
                            Button("Open in Editor", systemImage: "slider.horizontal.3") { session.openInEditor?(item.source) }
                                .help("Open in Editor to crop or edit this image on its own")
                            if session.items.count > 1 {
                                Button("Remove", systemImage: "xmark") { session.remove(item) }
                                    .help("Remove from this batch")
                            }
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.small)
                    }
                    .padding(6)
                    .transition(.opacity)
                }
            }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch item.status {
        case .idle:
            if let estimate = item.estimate, !estimate.fitsTarget {
                badge("exclamationmark.triangle.fill", .orange)
                    .help("Can't get under \(session.targetKilobytes ?? 0) KB even at the lowest quality. Try resizing.")
            }
        case .working:
            ProgressView()
                .controlSize(.small)
                .padding(6)
                .glassEffect(.regular, in: Circle())
        case .exported(let url):
            badge("checkmark.circle.fill", .green)
                .help("Saved \(url.lastPathComponent)")
        case .failed(let message):
            badge("exclamationmark.octagon.fill", .red)
                .help(message)
        }
    }

    private func badge(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white, color)
            .padding(5)
            .glassEffect(.regular, in: Circle())
    }

    @ViewBuilder
    private var bytes: some View {
        HStack(spacing: 4) {
            Text(item.info.map { formatBytes($0.fileBytes) } ?? "—")
                .foregroundStyle(.secondary)
            Image(systemName: "arrow.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
            if let estimate = item.estimate {
                Text(formatBytes(estimate.bytes))
                    .fontWeight(.semibold)
                    .opacity(session.estimating.contains(item.id) ? 0.4 : 1)
            } else if case .failed = item.status {
                Text("Failed").foregroundStyle(.red)
            } else {
                ProgressView().controlSize(.mini)
            }
            Spacer(minLength: 4)
            if let estimate = item.estimate, let info = item.info, let savings = Savings(from: info.fileBytes, to: estimate.bytes) {
                Text(savings.text)
                    .fontWeight(.semibold)
                    .foregroundStyle(savings.color)
            }
        }
        .font(.caption)
        .monospacedDigit()
    }

    /// e.g. "HEIC → WebP", or just "PNG" when the format stays.
    private var typeChange: String {
        let from = item.info?.typeName ?? item.source.url.pathExtension.uppercased()
        let to = session.outputFormat.displayName
        return from == to ? from : "\(from) → \(to)"
    }

    /// e.g. "4032 × 3024 → 1200 × 900", or one size when it doesn't change.
    private var sizeChange: String {
        guard let size = item.info?.pixelSize else { return "" }
        let output = item.estimate?.pixelSize ?? session.recipe.outputSize(for: size)
        func text(_ size: CGSize) -> String { "\(Int(size.width)) × \(Int(size.height))" }
        return output == size ? text(size) : "\(text(size)) → \(text(output))"
    }
}

// MARK: Action bar

private struct BatchActionBar: View {
    @Bindable var session: BatchSession

    @State private var showsResize = false
    @State private var showsQuality = false

    var body: some View {
        VStack(spacing: 8) {
            if let message = session.exportMessage {
                HStack(spacing: 8) {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if !session.exportedURLs.isEmpty {
                        Button("Show in Finder") { session.revealExports() }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                    }
                }
                .font(.callout)
                .glassChip()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if session.format != session.outputFormat {
                Label("\(session.format.displayName) has no transparency, so these export as \(session.outputFormat.displayName).", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .glassChip()
            }

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    toggleButton(
                        "Remove Background", systemImage: "person.and.background.dotted",
                        isOn: session.recipe.removeBackground
                    ) {
                        session.recipe.removeBackground.toggle()
                    }
                    .help("Keeps the main subject of every image and makes everything else transparent.")

                    toggleButton(resizeTitle, systemImage: "arrow.up.left.and.arrow.down.right", isOn: session.recipe.resize != nil) {
                        showsResize.toggle()
                    }
                    .popover(isPresented: $showsResize, arrowEdge: .top) {
                        BatchResizeForm(resize: $session.recipe.resize)
                    }

                    Menu {
                        Picker("Format", selection: $session.format) {
                            ForEach(ImageFormat.writable) { Text($0.displayName).tag($0) }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } label: {
                        Label(session.format.displayName, systemImage: "photo")
                    }
                    .menuIndicator(.visible)
                    .fixedSize()
                    .help("Output format")

                    Button(session.encodeSummary, systemImage: "slider.horizontal.below.rectangle") { showsQuality.toggle() }
                        .disabled(!session.outputFormat.supportsQuality && !session.outputFormat.supportsLossless)
                        .popover(isPresented: $showsQuality, arrowEdge: .top) {
                            BatchCompressionForm(session: session)
                        }
                        .help("Quality and target size")

                    Spacer(minLength: 0)

                    Menu {
                        Picker("Save to", selection: $session.destination) {
                            Label("Next to Originals", systemImage: "folder").tag(ExportDestination.besideOriginal)
                            Label("Choose Folder…", systemImage: "folder.badge.plus").tag(ExportDestination.chooseFolder)
                            Label("Clipboard", systemImage: "doc.on.clipboard").tag(ExportDestination.clipboard)
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } label: {
                        Label("Save to", systemImage: destinationSymbol)
                    }
                    .labelStyle(.iconOnly)
                    .fixedSize()
                    .help("Where to save")

                    Button {
                        Task { await session.export() }
                    } label: {
                        if session.isExporting {
                            ProgressView().controlSize(.small)
                        } else {
                            Label(exportTitle, systemImage: "square.and.arrow.down")
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut("s")
                }
                .buttonStyle(.glass)
                .menuStyle(.button)
                .controlSize(.large)
            }
            .disabled(session.isExporting)
        }
        .animation(.spring(duration: 0.3), value: session.exportMessage)
    }

    /// A glass button that turns prominent while its setting is on.
    @ViewBuilder
    private func toggleButton(_ title: String, systemImage: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        if isOn {
            Button(title, systemImage: systemImage, action: action).buttonStyle(.glassProminent)
        } else {
            Button(title, systemImage: systemImage, action: action).buttonStyle(.glass)
        }
    }

    private var resizeTitle: String {
        switch session.recipe.resize {
        case .scale(let factor): "\(Int((factor * 100).rounded()))%"
        case .fit(let width, let height): "≤ \(width) × \(height)"
        case .exact, nil: "Resize"
        }
    }

    private var exportTitle: String {
        session.destination == .clipboard ? "Copy \(session.items.count)" : "Export \(session.items.count)"
    }

    private var destinationSymbol: String {
        switch session.destination {
        case .besideOriginal: "folder"
        case .chooseFolder: "folder.badge.plus"
        case .clipboard: "doc.on.clipboard"
        }
    }
}

// MARK: Popovers

private struct BatchResizeForm: View {
    @Binding var resize: Resize.Mode?

    private enum Mode: String, CaseIterable { case off = "Off", percent = "Percent", fit = "Fit Within" }

    @State private var mode = Mode.off
    @State private var percent = 50.0
    @State private var width = 1920
    @State private var height = 1920

    var body: some View {
        Form {
            Picker("Resize", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .off:
                Text("Images keep their size.")
                    .foregroundStyle(.secondary)
            case .percent:
                HStack {
                    Slider(value: $percent, in: 5...200, step: 5)
                    Text("\(Int(percent))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            case .fit:
                TextField("Max width", value: $width, format: .number)
                TextField("Max height", value: $height, format: .number)
                Text("Each image shrinks or grows to fit the box, keeping its shape.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: load)
        .onChange(of: mode) { save() }
        .onChange(of: percent) { save() }
        .onChange(of: width) { save() }
        .onChange(of: height) { save() }
    }

    private func load() {
        switch resize {
        case .scale(let factor):
            mode = .percent
            percent = factor * 100
        case .fit(let width, let height):
            mode = .fit
            self.width = width
            self.height = height
        case .exact, nil:
            mode = .off
        }
    }

    private func save() {
        switch mode {
        case .off: resize = nil
        case .percent: resize = .scale(percent / 100)
        case .fit: resize = .fit(width: max(1, width), height: max(1, height))
        }
    }
}

private struct BatchCompressionForm: View {
    @Bindable var session: BatchSession

    var body: some View {
        Form {
            if session.outputFormat.supportsLossless {
                Toggle("Lossless", isOn: $session.encodeOptions.lossless)
            }
            if usesQuality {
                LabeledContent("Quality") {
                    HStack {
                        Slider(value: $session.encodeOptions.quality, in: 0...1, step: 0.01)
                        Text("\(Int((session.encodeOptions.quality * 100).rounded()))")
                            .monospacedDigit()
                            .frame(width: 28, alignment: .trailing)
                    }
                }
                .disabled(session.maxBytes != nil)
            }
            if session.outputFormat.supportsEffort {
                LabeledContent("Effort") {
                    HStack {
                        Slider(value: effort, in: 0...6, step: 1)
                        Text("\(session.encodeOptions.effort)")
                            .monospacedDigit()
                            .frame(width: 28, alignment: .trailing)
                    }
                }
                .help("Higher effort makes smaller files but encodes slower.")
            }
            if usesQuality {
                LabeledContent("Target size") {
                    HStack(spacing: 6) {
                        TextField("KB", value: $session.targetKilobytes, format: .number)
                            .labelsHidden()
                            .frame(width: 70)
                        Text("KB").foregroundStyle(.secondary)
                    }
                }
                Text("With a target size, each image gets the highest quality that fits it. Leave it empty to use the quality slider.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var usesQuality: Bool {
        session.outputFormat.supportsQuality && !(session.outputFormat.supportsLossless && session.encodeOptions.lossless)
    }

    private var effort: Binding<Double> {
        Binding(get: { Double(session.encodeOptions.effort) }, set: { session.encodeOptions.effort = Int($0) })
    }
}
