import ImageKit
import SwiftUI

/// Interactive crop frame over the displayed image. Works in normalized, top-left-origin
/// coordinates (the same space `Crop` uses), so it's independent of the on-screen scale.
struct CropOverlay: View {
    @Binding var rect: CGRect
    /// Normalized width / height, nil for free-form.
    let aspect: CGFloat?

    @State private var dragStart: CGRect?
    private let space = "crop"

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let frame = CGRect(
                x: rect.minX * size.width, y: rect.minY * size.height,
                width: rect.width * size.width, height: rect.height * size.height
            )
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: size))
                    path.addRect(frame)
                }
                .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                ThirdsGrid()
                    .stroke(Color.white.opacity(0.45), lineWidth: 0.5)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .allowsHitTesting(false)

                Rectangle()
                    .strokeBorder(Color.white, lineWidth: 1.5)
                    .contentShape(Rectangle())
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .gesture(moveGesture(in: size))
                    .onHover { inside in inside ? NSCursor.openHand.push() : NSCursor.pop() }

                ForEach(Corner.allCases) { corner in
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.4), radius: 1.5)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle().inset(by: -6))
                        .position(corner.point(in: frame))
                        .gesture(resizeGesture(corner, in: size))
                }
            }
            .coordinateSpace(name: space)
        }
    }

    private func moveGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .onChanged { value in
                let start = dragStart ?? rect
                dragStart = start
                rect = CropGeometry.moved(start, by: CGSize(
                    width: value.translation.width / size.width,
                    height: value.translation.height / size.height
                ))
            }
            .onEnded { _ in dragStart = nil }
    }

    private func resizeGesture(_ corner: Corner, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
            .onChanged { value in
                let start = dragStart ?? rect
                dragStart = start
                let origin = corner.point(in: start)
                let point = CGPoint(
                    x: min(max(0, origin.x + value.translation.width / size.width), 1),
                    y: min(max(0, origin.y + value.translation.height / size.height), 1)
                )
                rect = CropGeometry.rect(
                    anchor: corner.opposite.point(in: start), point: point,
                    towardRight: corner.isRight, towardBottom: corner.isBottom, aspect: aspect
                )
            }
            .onEnded { _ in dragStart = nil }
    }
}

private enum Corner: CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight

    var id: Self { self }
    var isRight: Bool { self == .topRight || self == .bottomRight }
    var isBottom: Bool { self == .bottomLeft || self == .bottomRight }

    var opposite: Corner {
        switch self {
        case .topLeft: .bottomRight
        case .topRight: .bottomLeft
        case .bottomLeft: .topRight
        case .bottomRight: .topLeft
        }
    }

    func point(in rect: CGRect) -> CGPoint {
        CGPoint(x: isRight ? rect.maxX : rect.minX, y: isBottom ? rect.maxY : rect.minY)
    }
}

private struct ThirdsGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for fraction in [1.0 / 3, 2.0 / 3] {
            path.move(to: CGPoint(x: rect.minX + rect.width * fraction, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * fraction, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * fraction))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * fraction))
        }
        return path
    }
}
