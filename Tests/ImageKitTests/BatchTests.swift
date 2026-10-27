import CoreImage
import Foundation
import ImageIO
import Testing
@testable import ImageKit

/// Writes `image` to a temporary file, optionally tagged with an EXIF orientation.
private func write(_ image: CIImage, format: ImageFormat, orientation: Int? = nil) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(format.fileExtension)
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, format.utType.identifier as CFString, 1, nil))
    let properties: [CFString: Any] = orientation.map { [kCGImagePropertyOrientation: $0] } ?? [:]
    CGImageDestinationAddImage(destination, try ImageExporter.prepare(image, for: format), properties as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return url
}

@Suite struct BatchTests {
    @Test func infoReadsSizeTypeAndBytes() throws {
        let url = try write(solid(width: 40, height: 30), format: .png)
        defer { try? FileManager.default.removeItem(at: url) }
        let info = try #require(ImageInfo(contentsOf: url))
        #expect(info.pixelSize == CGSize(width: 40, height: 30))
        #expect(info.format == .png)
        #expect(info.typeName == "PNG")
        #expect(info.fileBytes == (try Data(contentsOf: url).count))
    }

    @Test func infoAppliesRotatingOrientation() throws {
        // 6 = rotated 90° clockwise, so the displayed image is portrait.
        let url = try write(solid(width: 40, height: 30), format: .jpeg, orientation: 6)
        defer { try? FileManager.default.removeItem(at: url) }
        let info = try #require(ImageInfo(contentsOf: url))
        #expect(info.pixelSize == CGSize(width: 30, height: 40))
        #expect(try info.pixelSize == ImageLoader.load(contentsOf: url).extent.size)
    }

    @Test func infoIsNilForNonImages() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(ImageInfo(contentsOf: url) == nil)
    }

    @Test func recipeRemovesBackgroundBeforeResizing() {
        let recipe = BatchRecipe(removeBackground: true, resize: .scale(0.5))
        #expect(recipe.operations.map(\.title) == ["Remove Background", "Resize"])
        #expect(BatchRecipe().operations.isEmpty)
        #expect(BatchRecipe().isEmpty)
    }

    @Test func recipeOutputSizeFitsWithoutStretching() {
        let recipe = BatchRecipe(resize: .fit(width: 100, height: 100))
        #expect(recipe.outputSize(for: CGSize(width: 400, height: 200)) == CGSize(width: 100, height: 50))
        #expect(BatchRecipe().outputSize(for: CGSize(width: 400, height: 200)) == CGSize(width: 400, height: 200))
    }

    @Test func removedBackgroundSwitchesToAFormatWithAlpha() {
        let recipe = BatchRecipe(removeBackground: true)
        #expect(recipe.effectiveFormat(.jpeg) == .png)
        #expect(recipe.effectiveFormat(.bmp) == .png)
        #expect(recipe.effectiveFormat(.webp) == .webp)
        #expect(BatchRecipe().effectiveFormat(.jpeg) == .jpeg)
    }

    @Test func renderAppliesTheRecipe() async throws {
        let url = try write(solid(width: 80, height: 40), format: .png)
        defer { try? FileManager.default.removeItem(at: url) }
        let image = try await BatchProcessor.render(url, recipe: BatchRecipe(resize: .scale(0.5)))
        #expect(image.width == 40 && image.height == 20)
    }

    @Test func encodeFitsTargetOrReportsThatItCant() throws {
        let random = CIFilter(name: "CIRandomGenerator")!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 256, height: 256))
        let image = try Renderer.cgImage(from: random)
        let unbounded = try BatchProcessor.encode(image, format: .jpeg, options: EncodeOptions(quality: 1))
        let fitted = try BatchProcessor.encode(image, format: .jpeg, options: EncodeOptions(quality: 1), maxBytes: unbounded.data.count / 2)
        #expect(fitted.fitsTarget)
        #expect(fitted.data.count <= unbounded.data.count / 2)

        let impossible = try BatchProcessor.encode(image, format: .jpeg, options: EncodeOptions(), maxBytes: 100)
        #expect(!impossible.fitsTarget)
        #expect(impossible.data.count > 100)
    }
}
