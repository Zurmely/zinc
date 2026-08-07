import Foundation
import XCTest
@testable import ZincCore

final class ClipIndexFileTests: XCTestCase {
    private var tempDirectory: URL!
    private var indexFile: ClipIndexFile!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zinc-index-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        indexFile = ClipIndexFile(directoryURL: tempDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        indexFile = nil
    }

    func testValidVersionedLoad() throws {
        let clips = [sampleClip(text: "hello")]
        try indexFile.save(clips)

        let data = try Data(contentsOf: indexFile.fileURL)
        let document = try JSONDecoder.iso8601.decode(ClipIndexDocument.self, from: data)
        XCTAssertEqual(document.version, ClipIndexDocument.currentVersion)
        XCTAssertEqual(document.clips, clips)

        let result = indexFile.load()
        XCTAssertEqual(result, .loaded(clips))
    }

    func testLegacyBareArrayLoad() throws {
        let clips = [sampleClip(text: "legacy")]
        let data = try JSONEncoder.iso8601.encode(clips)
        try data.write(to: indexFile.fileURL)

        let result = indexFile.load()
        XCTAssertEqual(result, .loaded(clips))
    }

    func testCorruptLoadPreservesFileAndDoesNotOverwrite() throws {
        let corruptBytes = Data("{not-valid-json".utf8)
        try corruptBytes.write(to: indexFile.fileURL)

        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        let stamped = ClipIndexFile(
            directoryURL: tempDirectory,
            now: { fixedNow }
        )
        let result = stamped.load()

        guard case .corrupt(let preservedURL) = result else {
            return XCTFail("expected corrupt result, got \(result)")
        }

        XCTAssertTrue(preservedURL.lastPathComponent.hasPrefix("clips.corrupt-"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: preservedURL.path))
        XCTAssertEqual(try Data(contentsOf: preservedURL), corruptBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stamped.fileURL.path))

        // A subsequent save must create a fresh clips.json without touching the quarantine.
        try stamped.save([sampleClip(text: "fresh")])
        XCTAssertTrue(FileManager.default.fileExists(atPath: stamped.fileURL.path))
        XCTAssertEqual(try Data(contentsOf: preservedURL), corruptBytes)
        XCTAssertNotEqual(try Data(contentsOf: stamped.fileURL), corruptBytes)
    }

    func testAtomicReplaceKeepsPreviousContentsUntilSwap() throws {
        let first = [sampleClip(text: "first")]
        let second = [sampleClip(text: "second")]
        try indexFile.save(first)

        let before = try Data(contentsOf: indexFile.fileURL)
        try indexFile.save(second)
        let after = try Data(contentsOf: indexFile.fileURL)

        XCTAssertNotEqual(before, after)
        XCTAssertEqual(indexFile.load(), .loaded(second))

        // Rolling backup holds the previous good index.
        XCTAssertTrue(indexFile.hasBackup)
        XCTAssertEqual(indexFile.loadBackup(), first)

        // Live file must remain valid JSON for the whole operation — never absent.
        XCTAssertTrue(FileManager.default.fileExists(atPath: indexFile.fileURL.path))
    }

    func testMissingFileReturnsMissing() {
        XCTAssertEqual(indexFile.load(), .missing)
    }

    func testSaveCreatesVersionedEnvelopeOnFirstWrite() throws {
        try indexFile.save([sampleClip(text: "one")])
        let data = try Data(contentsOf: indexFile.fileURL)
        let document = try JSONDecoder.iso8601.decode(ClipIndexDocument.self, from: data)
        XCTAssertEqual(document.version, 1)
        XCTAssertEqual(document.clips.count, 1)
    }
}

final class VaultReindexerTests: XCTestCase {
    func testClipFromMarkdownFrontMatter() {
        let id = UUID()
        let markdown = """
        ---
        id: \(id.uuidString)
        app: Safari
        bundle: com.apple.Safari
        url: https://example.com
        title: Example
        saved: 2026-08-02T23:42:07Z
        ---

        Hello vault
        """

        let clip = VaultReindexer.clip(fromMarkdown: markdown, markdownPath: "/tmp/example.md")
        XCTAssertEqual(clip?.id, id)
        XCTAssertEqual(clip?.text, "Hello vault")
        XCTAssertEqual(clip?.appName, "Safari")
        XCTAssertEqual(clip?.bundleID, "com.apple.Safari")
        XCTAssertEqual(clip?.pageURL, "https://example.com")
        XCTAssertEqual(clip?.pageTitle, "Example")
        XCTAssertEqual(clip?.markdownPath, "/tmp/example.md")
    }

    func testMergePrefersExistingOnConflict() {
        let id = UUID()
        let existing = Clip(
            id: id,
            text: "in-memory",
            savedAt: Date(timeIntervalSince1970: 100),
            appName: "A",
            bundleID: "a"
        )
        let vault = Clip(
            id: id,
            text: "from-vault",
            savedAt: Date(timeIntervalSince1970: 200),
            appName: "B",
            bundleID: "b",
            markdownPath: "/vault/x.md"
        )
        let other = Clip(
            id: UUID(),
            text: "only-vault",
            savedAt: Date(timeIntervalSince1970: 300),
            appName: "C",
            bundleID: "c",
            markdownPath: "/vault/y.md"
        )

        let merged = VaultReindexer.merge(existing: [existing], fromVault: [vault, other])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first?.text, "only-vault")
        XCTAssertEqual(merged.first(where: { $0.id == id })?.text, "in-memory")
    }

    func testReindexWalksVaultMarkdown() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("zinc-vault-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let folder = vault
            .appendingPathComponent("2026-08", isDirectory: true)
            .appendingPathComponent("02", isDirectory: true)
            .appendingPathComponent("Safari", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let id = UUID()
        let md = """
        ---
        id: \(id.uuidString)
        app: Safari
        bundle: com.apple.Safari
        saved: 2026-08-02T12:00:00Z
        ---

        Captured text
        """
        try md.write(to: folder.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)

        let clips = VaultReindexer.reindex(vaultURL: vault)
        XCTAssertEqual(clips.count, 1)
        XCTAssertEqual(clips[0].id, id)
        XCTAssertEqual(clips[0].text, "Captured text")
        // macOS temp paths may surface as /var/... or /private/var/...
        XCTAssertEqual(
            clips[0].markdownPath.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path },
            folder.appendingPathComponent("note.md").resolvingSymlinksInPath().path
        )
    }
}

// MARK: - Helpers

private func sampleClip(text: String) -> Clip {
    Clip(
        id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
        text: text,
        savedAt: Date(timeIntervalSince1970: 1_700_000_000),
        appName: "TestApp",
        bundleID: "com.example.test"
    )
}

private extension JSONEncoder {
    static var iso8601: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
