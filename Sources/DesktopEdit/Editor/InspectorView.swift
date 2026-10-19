import ImageKit
import SwiftUI

struct InspectorView: View {
    @Bindable var session: EditSession

    var body: some View {
        Form {
            Section {
                LabeledContent("Size", value: "\(Int(session.currentSize.width)) × \(Int(session.currentSize.height)) px")
                if !session.operations.isEmpty {
                    LabeledContent("Edits", value: session.operations.map(\.title).joined(separator: " → "))
                }
                HStack {
                    Button("Undo", systemImage: "arrow.uturn.backward") { session.undo() }
                        .keyboardShortcut("z")
                    Button("Reset", systemImage: "arrow.counterclockwise") { session.reset() }
                }
                .disabled(session.operations.isEmpty || session.isCropping)
            }

            CropSection(session: session)

            Section("Background") {
                Button("Remove Background", systemImage: "person.and.background.dotted") {
                    Task { await session.apply(RemoveBackground()) }
                }
                Text("Keeps the main subject and makes everything else transparent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(session.isCropping)

            ResizeSection(session: session)
                .disabled(session.isCropping)

            ExportSection(session: session)
                .disabled(session.isCropping)
        }
        .formStyle(.grouped)
        .disabled(session.isWorking || session.current == nil)
    }
}

private struct CropSection: View {
    @Bindable var session: EditSession

    var body: some View {
        Section("Crop") {
            Picker("Aspect", selection: $session.cropAspect) {
                ForEach(CropAspect.allCases) { Text($0.rawValue).tag($0) }
            }
            if session.isCropping {
                LabeledContent("Selection", value: "\(Int(session.cropPixelSize.width)) × \(Int(session.cropPixelSize.height)) px")
                HStack {
                    Button("Cancel") { session.isCropping = false }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Apply Crop") { Task { await session.applyCrop() } }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                Button("Crop…", systemImage: "crop") { session.beginCrop() }
            }
        }
    }
}

private struct ResizeSection: View {
    @Bindable var session: EditSession

    private enum Mode: String, CaseIterable { case percent = "Percent", pixels = "Pixels" }

    @State private var mode = Mode.percent
    @State private var percent = 50.0
    @State private var width = 0
    @State private var height = 0
    @State private var keepAspect = true

    var body: some View {
        Section("Resize") {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .percent:
                HStack {
                    Slider(value: $percent, in: 5...200, step: 5)
                    Text("\(Int(percent))%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            case .pixels:
                TextField("Width", value: widthBinding, format: .number)
                TextField("Height", value: heightBinding, format: .number)
                Toggle("Keep aspect ratio", isOn: $keepAspect)
            }

            LabeledContent("Result", value: "\(Int(target.width)) × \(Int(target.height)) px")
            Button("Resize", systemImage: "arrow.up.left.and.arrow.down.right") {
                Task { await session.apply(operation) }
            }
            .disabled(width < 1 || height < 1 || target == session.currentSize)
        }
        .onAppear(perform: syncToImage)
        .onChange(of: session.currentSize) { syncToImage() }
    }

    /// With the aspect locked this is a "fit" so batch images with other shapes aren't stretched.
    private var operation: Resize {
        switch mode {
        case .percent: Resize(.scale(percent / 100))
        case .pixels: Resize(keepAspect ? .fit(width: width, height: height) : .exact(width: width, height: height))
        }
    }

    private var target: CGSize {
        session.currentSize == .zero ? .zero : operation.targetSize(for: session.currentSize)
    }

    private var aspect: Double {
        session.currentSize.height > 0 ? session.currentSize.width / session.currentSize.height : 1
    }

    private var widthBinding: Binding<Int> {
        Binding(get: { width }, set: { newValue in
            width = max(1, newValue)
            if keepAspect { height = max(1, Int((Double(width) / aspect).rounded())) }
        })
    }

    private var heightBinding: Binding<Int> {
        Binding(get: { height }, set: { newValue in
            height = max(1, newValue)
            if keepAspect { width = max(1, Int((Double(height) * aspect).rounded())) }
        })
    }

    private func syncToImage() {
        width = Int(session.currentSize.width)
        height = Int(session.currentSize.height)
    }
}

private struct ExportSection: View {
    @Bindable var session: EditSession

    var body: some View {
        Section("Export") {
            Picker("Format", selection: $session.exportFormat) {
                ForEach(ImageFormat.writable) { Text($0.displayName).tag($0) }
            }
            if session.exportFormat.supportsQuality {
                LabeledContent("Quality") {
                    HStack {
                        Slider(value: $session.exportQuality, in: 0.1...1)
                        Text("\(Int(session.exportQuality * 100))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
            if !session.exportFormat.supportsAlpha && session.hasTransparencyEdit {
                Label("\(session.exportFormat.displayName) has no transparency, so the background will be white.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Picker("Save to", selection: $session.destination) {
                Text("Next to original").tag(ExportDestination.besideOriginal)
                Text("Choose folder…").tag(ExportDestination.chooseFolder)
                Text("Clipboard").tag(ExportDestination.clipboard)
            }
            if session.sources.count > 1 && session.destination != .clipboard {
                Toggle("Apply edits to all \(session.sources.count) images", isOn: $session.exportAll)
            }
            Button {
                Task { await session.export() }
            } label: {
                Label(session.destination == .clipboard ? "Copy" : "Export", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("s")

            if let message = session.exportMessage {
                HStack {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Spacer()
                    if !session.exportedURLs.isEmpty {
                        Button("Show in Finder") { session.revealExports() }
                            .controlSize(.small)
                    }
                }
            }
        }
    }
}
