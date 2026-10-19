import CoreImage
import Testing
@testable import ImageKit

@Suite struct ResizeTests {
    @Test(arguments: [
        (Resize.Mode.scale(0.5), CGSize(width: 100, height: 50)),
        (.fit(width: 50, height: 50), CGSize(width: 50, height: 25)),
        (.exact(width: 30, height: 70), CGSize(width: 30, height: 70)),
    ])
    func producesTargetSize(mode: Resize.Mode, expected: CGSize) async throws {
        let output = try await Resize(mode).apply(to: solid(width: 200, height: 100))
        #expect(output.extent == CGRect(origin: .zero, size: expected))
        let rendered = try Renderer.cgImage(from: output)
        #expect(CGSize(width: rendered.width, height: rendered.height) == expected)
    }

    @Test func neverProducesZeroSize() {
        #expect(Resize(.scale(0.001)).targetSize(for: CGSize(width: 100, height: 100)) == CGSize(width: 1, height: 1))
    }

    @Test func keepsEdgesOpaque() async throws {
        let output = try await Resize(.scale(0.37)).apply(to: solid(width: 101, height: 77))
        #expect(pixel(output, x: 0, y: 0)[3] == 255)
    }
}
