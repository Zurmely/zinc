import AppKit
import Foundation
import XCTest
@testable import ZincLib

final class MarkdownImageExportTests: XCTestCase {
    private let onePixelPNG = Data(base64Encoded: """
        iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==
        """)!

    private let onePixelJPEG = Data(base64Encoded: """
        /9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDAREAAhEBAxEB/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/xAAUAQEAAAAAAAAAAAAAAAAAAAAA/8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAwDAQACEQMRAD8A0f/Z
        """)!

    // MARK: - Issue #17: one image per pasteboard item, correct extension

    func testMultiFlavorPasteboardItemProducesSingleImage() throws {
        let tiffData = try XCTUnwrap(NSImage(data: onePixelPNG)?.tiffRepresentation)

        let item = NSPasteboardItem()
        item.setData(onePixelPNG, forType: .png)
        item.setData(tiffData, forType: .tiff)

        let pasteboard = NSPasteboard.withUniqueName()
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        let selection = try XCTUnwrap(RichSelection.read(from: pasteboard))
        XCTAssertEqual(selection.images.count, 1)
        XCTAssertEqual(selection.images[0].fileExtension, "png")
    }

    func testDetectedExtensionMatchesBytes() {
        XCTAssertEqual(RichSelection.detectedImageExtension(for: onePixelPNG), "png")
        XCTAssertEqual(RichSelection.detectedImageExtension(for: onePixelJPEG), "jpg")
    }

    func testWrittenFileExtensionMatchesEncodedFormat() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("zinc-image-ext-\(UUID().uuidString)", isDirectory: true)
        let assets = base.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let image = PasteboardImage(data: onePixelJPEG, fileExtension: "jpg")
        let result = await MarkdownExporter.shared.processImages(
            markdown: "",
            pasteboardImages: [image],
            imageReferences: [],
            assetsDirectory: assets,
            assetsFolderName: "assets"
        )

        let markdown = try result.get()
        XCTAssertTrue(markdown.contains("![image](assets/image-1.jpg)"))

        let written = assets.appendingPathComponent("image-1.jpg")
        let bytes = try Data(contentsOf: written)
        XCTAssertEqual(RichSelection.detectedImageExtension(for: bytes), "jpg")
    }

    // MARK: - Issue #16: every written asset is referenced

    func testTextPlusImageProducesBoth() async throws {
        let base = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let assets = base.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

        let image = PasteboardImage(data: onePixelPNG, fileExtension: "png")
        let result = await MarkdownExporter.shared.processImages(
            markdown: "Caption text",
            pasteboardImages: [image],
            imageReferences: [],
            assetsDirectory: assets,
            assetsFolderName: "assets"
        )

        let markdown = try result.get()
        XCTAssertTrue(markdown.contains("Caption text"))
        XCTAssertTrue(markdown.contains("![image](assets/image-1.png)"))
        try assertAllAssetsReferenced(markdown: markdown, assetsDirectory: assets)
    }

    func testMultiplePasteboardImagesEachReferenced() async throws {
        let base = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let assets = base.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

        let images = [
            PasteboardImage(data: onePixelPNG, fileExtension: "png"),
            PasteboardImage(data: onePixelJPEG, fileExtension: "jpg"),
        ]
        let result = await MarkdownExporter.shared.processImages(
            markdown: "Intro",
            pasteboardImages: images,
            imageReferences: [],
            assetsDirectory: assets,
            assetsFolderName: "assets"
        )

        let markdown = try result.get()
        XCTAssertTrue(markdown.contains("![image](assets/image-1.png)"))
        XCTAssertTrue(markdown.contains("![image](assets/image-2.jpg)"))
        try assertAllAssetsReferenced(markdown: markdown, assetsDirectory: assets)
    }

    // MARK: - Issue #18: placeholder substitution and deduplication

    func testHTMLToMarkdownUsesPlaceholdersNotRawURLs() {
        let url = "https://example.com/photo.png"
        let html = "<a href=\"\(url)\"><img src=\"\(url)\" alt=\"photo\"></a>"
        let converted = HTMLToMarkdown.convert(html)

        XCTAssertTrue(converted.markdown.contains("](\(url))"))
        XCTAssertTrue(converted.markdown.contains("zinc-image-placeholder-0"))
        XCTAssertFalse(converted.markdown.contains("![photo](\(url))"))
    }

    func testSelfLinkedImagePreservesHref() async throws {
        let dataURI = "data:image/png;base64,\(onePixelPNG.base64EncodedString())"
        let html = "<a href=\"\(dataURI)\"><img src=\"\(dataURI)\" alt=\"linked\"></a>"
        let converted = HTMLToMarkdown.convert(html)

        let base = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let assets = base.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

        let result = await MarkdownExporter.shared.processImages(
            markdown: converted.markdown,
            pasteboardImages: [],
            imageReferences: converted.imageReferences,
            assetsDirectory: assets,
            assetsFolderName: "assets"
        )

        let markdown = try result.get()
        XCTAssertTrue(markdown.contains("](\(dataURI))"), "Link href must keep the original URL")
        XCTAssertTrue(markdown.contains("![linked](assets/image-1.png)"), "Image src should be localized")
        XCTAssertFalse(markdown.contains("](assets/image-1.png))](assets/image-1.png)"))
        try assertAllAssetsReferenced(markdown: markdown, assetsDirectory: assets)
    }

    func testRepeatedImageProducesOneFileAndTwoReferences() async throws {
        let dataURI = "data:image/png;base64,\(onePixelPNG.base64EncodedString())"
        let html = "<p>Before</p><img src=\"\(dataURI)\" alt=\"a\"><img src=\"\(dataURI)\" alt=\"b\">"
        let converted = HTMLToMarkdown.convert(html)

        let base = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let assets = base.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

        let result = await MarkdownExporter.shared.processImages(
            markdown: converted.markdown,
            pasteboardImages: [],
            imageReferences: converted.imageReferences,
            assetsDirectory: assets,
            assetsFolderName: "assets"
        )

        let markdown = try result.get()
        let assetFiles = try FileManager.default.contentsOfDirectory(at: assets, includingPropertiesForKeys: nil)
        XCTAssertEqual(assetFiles.count, 1)
        XCTAssertEqual(assetFiles[0].lastPathComponent, "image-1.png")

        let localPath = "assets/image-1.png"
        XCTAssertEqual(markdown.components(separatedBy: "![a](\(localPath))").count - 1, 1)
        XCTAssertEqual(markdown.components(separatedBy: "![b](\(localPath))").count - 1, 1)
        try assertAllAssetsReferenced(markdown: markdown, assetsDirectory: assets)
    }

    // MARK: - Helpers

    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("zinc-image-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func assertAllAssetsReferenced(markdown: String, assetsDirectory: URL) throws {
        let files = try FileManager.default.contentsOfDirectory(at: assetsDirectory, includingPropertiesForKeys: nil)
        for file in files where !file.hasDirectoryPath {
            XCTAssertTrue(
                markdown.contains(file.lastPathComponent),
                "Asset \(file.lastPathComponent) is not referenced in markdown"
            )
        }
    }
}
