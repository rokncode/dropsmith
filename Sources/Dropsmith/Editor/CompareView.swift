import ImageKit
import SwiftUI

/// Squoosh-style before/after: the current image on the left of the divider, the same image
/// decoded from the actual encoded bytes on the right.
struct CompareView: View {
    @Bindable var session: EditSession
    let original: CGImage

    @State private var split: CGFloat = 0.5
    @State private var actualSize = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.clear
                if actualSize {
                    ScrollView([.horizontal, .vertical]) {
                        comparison
                            .frame(width: CGFloat(original.width) / displayScale, height: CGFloat(original.height) / displayScale)
                            .padding(28)
                    }
                } else {
                    comparison
                        .aspectRatio(CGSize(width: original.width, height: original.height), contentMode: .fit)
                        .frame(maxWidth: CGFloat(original.width), maxHeight: CGFloat(original.height))
                        .padding(28)
                }
            }
            .overlay(alignment: .topLeading) { badge("Original") }
            .overlay(alignment: .topTrailing) { badge(session.encodeSummary) }

            statsBar
                .glassPanel(cornerRadius: 18)
                .padding([.horizontal, .bottom], 10)
        }
    }

    private var comparison: some View {
        let interpolation: Image.Interpolation = actualSize ? .none : .high
        return ZStack {
            Image(decorative: original, scale: 1).resizable().interpolation(interpolation)
            if let compressed = session.comparison?.image {
                Image(decorative: compressed, scale: 1).resizable().interpolation(interpolation)
                    .mask {
                        GeometryReader { geometry in
                            Rectangle()
                                .frame(width: geometry.size.width * (1 - split))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
            }
        }
        .background(Checkerboard())
        .overlay { divider }
    }

    private var divider: some View {
        GeometryReader { geometry in
            let x = geometry.size.width * split
            ZStack {
                Color.clear.contentShape(Rectangle())
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: geometry.size.height)
                    .shadow(color: .black.opacity(0.35), radius: 2)
                    .position(x: x, y: geometry.size.height / 2)
                Image(systemName: "chevron.left.chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black.opacity(0.7))
                    .frame(width: 30, height: 30)
                    .glassEffect(.regular.tint(.white.opacity(0.6)), in: Circle())
                    .position(x: x, y: geometry.size.height / 2)
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                split = min(max(0, value.location.x / max(geometry.size.width, 1)), 1)
            })
            .onHover { inside in inside ? NSCursor.resizeLeftRight.push() : NSCursor.pop() }
        }
    }

    private var statsBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Original file").font(.caption).foregroundStyle(.secondary)
                Text(session.originalBytes.map(formatBytes) ?? "—").font(.headline).monospacedDigit()
            }
            Spacer()
            Picker("Zoom", selection: $actualSize) {
                Text("Fit").tag(false)
                Text("100%").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(session.encodeSummary).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if session.isEncoding { ProgressView().controlSize(.small) }
                    Text(session.comparison.map { formatBytes($0.bytes) } ?? "—").font(.headline).monospacedDigit()
                    if let savings = CompareView.savings(session) {
                        Text(savings.text)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(savings.color)
                    }
                }
            }
            Button("Done") { session.isComparing = false }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.glass)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .glassChip()
            .padding(12)
    }

    static func savings(_ session: EditSession) -> Savings? {
        guard let original = session.originalBytes, let bytes = session.comparison?.bytes else { return nil }
        return Savings(from: original, to: bytes)
    }
}

/// Size change of an encoded file, e.g. "−87%" when it's smaller than the original file.
struct Savings {
    let text: String
    let isSmaller: Bool

    init?(from original: Int, to bytes: Int) {
        guard original > 0 else { return nil }
        let change = Double(bytes) / Double(original) - 1
        let percent = Int((abs(change) * 100).rounded())
        text = change <= 0 ? "−\(percent)%" : "+\(percent)%"
        isSmaller = change <= 0
    }

    var color: Color { isSmaller ? .green : .red }
}

func formatBytes(_ bytes: Int) -> String {
    Int64(bytes).formatted(.byteCount(style: .file))
}
