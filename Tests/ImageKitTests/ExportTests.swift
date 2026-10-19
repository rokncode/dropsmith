import CoreImage
import Foundation
import ImageIO
import Testing
@testable import ImageKit

@Suite struct ExportTests {
    @Test func coreFormatsAreWritable() {
        #expect(Set([.png, .jpeg, .heic, .tiff]).isSubset(of: ImageFormat.writable))
    }

    @Test(arguments: ImageFormat.writable)
    func roundTripsFormatAndSize(format: ImageFormat) throws {
        let data = try ImageExporter.data(for: solid(width: 64, height: 32), format: format)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == format.utType.identifier)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 64 && image.height == 32)
    }

    @Test func jpegFlattensTransparencyToWhite() throws {
        let transparent = solid(width: 8, height: 8, color: .clear)
        let data = try ImageExporter.data(for: transparent, format: .jpeg)
        let decoded = try #require(CIImage(data: data))
        #expect(pixel(decoded, x: 4, y: 4).prefix(3).allSatisfy { $0 > 250 })
    }

    @Test func formatFromExtension() {
        #expect(ImageFormat(fileExtension: "JPG") == .jpeg)
        #expect(ImageFormat(fileExtension: "heic") == .heic)
        #expect(ImageFormat(fileExtension: "txt") == nil)
    }

    @Test func outputNamingAvoidsCollisions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("photo.png")

        let first = OutputNaming.uniqueURL(for: source, format: .jpeg, in: directory)
        #expect(first.lastPathComponent == "photo-edited.jpg")
        try Data().write(to: first)
        #expect(OutputNaming.uniqueURL(for: source, format: .jpeg, in: directory).lastPathComponent == "photo-edited-2.jpg")
    }
}
