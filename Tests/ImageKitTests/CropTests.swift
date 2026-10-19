import CoreImage
import Testing
@testable import ImageKit

@Suite struct CropTests {
    @Test func mapsNormalizedRectToPixels() async throws {
        let output = try await Crop(normalizedRect: CGRect(x: 0.25, y: 0, width: 0.5, height: 0.5))
            .apply(to: solid(width: 200, height: 100))
        #expect(output.extent == CGRect(x: 0, y: 0, width: 100, height: 50))
    }

    @Test func topLeftOriginSelectsTopOfImage() async throws {
        // Blue bottom half, red top half (Core Image y grows upward).
        let image = solid(width: 10, height: 10, color: .red)
            .cropped(to: CGRect(x: 0, y: 5, width: 10, height: 5))
            .composited(over: solid(width: 10, height: 10, color: .blue))
        let top = try await Crop(normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 0.5)).apply(to: image)
        #expect(pixel(top, x: 2, y: 2) == [255, 0, 0, 255])
    }

    @Test func rejectsEmptyRect() async {
        await #expect(throws: ImageKitError.invalidCrop) {
            try await Crop(normalizedRect: CGRect(x: 2, y: 2, width: 1, height: 1)).apply(to: solid(width: 10, height: 10))
        }
    }
}

@Suite struct CropGeometryTests {
    @Test func centeredRectFitsAspect() {
        #expect(CropGeometry.centeredRect(aspect: 2) == CGRect(x: 0, y: 0.25, width: 1, height: 0.5))
        #expect(CropGeometry.centeredRect(aspect: 0.5) == CGRect(x: 0.25, y: 0, width: 0.5, height: 1))
    }

    @Test func dragKeepsCornerOnItsSideAndInBounds() {
        let rect = CropGeometry.rect(anchor: CGPoint(x: 0.5, y: 0.5), point: CGPoint(x: 0.2, y: 2),
                                     towardRight: true, towardBottom: true, aspect: nil)
        #expect(rect == CGRect(x: 0.5, y: 0.5, width: CropGeometry.minimumSize, height: 0.5))
    }

    @Test func dragHonorsAspectWithinBounds() {
        let rect = CropGeometry.rect(anchor: CGPoint(x: 0, y: 0.5), point: CGPoint(x: 1, y: 0.6),
                                     towardRight: true, towardBottom: true, aspect: 1)
        #expect(rect == CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5))
    }

    @Test func moveClampsInsideUnitSquare() {
        let rect = CropGeometry.moved(CGRect(x: 0.5, y: 0.5, width: 0.4, height: 0.4), by: CGSize(width: 1, height: -1))
        #expect(rect == CGRect(x: 0.6, y: 0, width: 0.4, height: 0.4))
    }
}
