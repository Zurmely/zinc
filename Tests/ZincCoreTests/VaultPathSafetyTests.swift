import Foundation
import XCTest
@testable import ZincCore

final class VaultPathSafetyTests: XCTestCase {
    func testRejectsSiblingDirectoryWithSharedNamePrefix() {
        let vault = URL(fileURLWithPath: "/Users/me/Zinc")
        let sibling = URL(fileURLWithPath: "/Users/me/Zinc-backup/notes.md")
        let inside = URL(fileURLWithPath: "/Users/me/Zinc/notes.md")

        XCTAssertFalse(VaultPathSafety.contains(sibling, vaultRoot: vault))
        XCTAssertTrue(VaultPathSafety.contains(inside, vaultRoot: vault))
    }

    func testRejectsVaultRootByDefault() {
        let vault = URL(fileURLWithPath: "/Users/me/Zinc")
        XCTAssertFalse(VaultPathSafety.contains(vault, vaultRoot: vault))
        XCTAssertTrue(VaultPathSafety.contains(vault, vaultRoot: vault, allowRoot: true))
    }

    func testRejectsPathsOutsideAndAboveVault() {
        let vault = URL(fileURLWithPath: "/Users/me/Zinc")
        XCTAssertFalse(VaultPathSafety.contains(URL(fileURLWithPath: "/Users/me"), vaultRoot: vault))
        XCTAssertFalse(VaultPathSafety.contains(URL(fileURLWithPath: "/Users/me/Other/notes.md"), vaultRoot: vault))
        XCTAssertFalse(VaultPathSafety.contains(URL(fileURLWithPath: "/tmp/notes.md"), vaultRoot: vault))
    }

    func testAllowsNestedPathsInsideVault() {
        let vault = URL(fileURLWithPath: "/Users/me/Zinc")
        let nested = URL(fileURLWithPath: "/Users/me/Zinc/2024/08/notes.md")
        XCTAssertTrue(VaultPathSafety.contains(nested, vaultRoot: vault))
    }

    func testResolvesRelativeComponents() {
        let vault = URL(fileURLWithPath: "/Users/me/Zinc")
        let escapeAttempt = URL(fileURLWithPath: "/Users/me/Zinc/../Zinc-backup/x.md")
        let legitRelative = URL(fileURLWithPath: "/Users/me/Zinc/subdir/../notes.md")

        XCTAssertFalse(VaultPathSafety.contains(escapeAttempt, vaultRoot: vault))
        XCTAssertTrue(VaultPathSafety.contains(legitRelative, vaultRoot: vault))
    }

    func testSymlinkedVaultResolvesBothDirections() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("zinc-path-safety-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: base) }

        let realVault = base.appendingPathComponent("RealVault", isDirectory: true)
        let linkVault = base.appendingPathComponent("LinkVault", isDirectory: false)
        let outside = base.appendingPathComponent("Outside", isDirectory: true)

        try fm.createDirectory(at: realVault, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: linkVault, withDestinationURL: realVault)

        let fileViaReal = realVault.appendingPathComponent("notes.md")
        let fileViaLink = linkVault.appendingPathComponent("notes.md")
        let outsideFile = outside.appendingPathComponent("notes.md")
        let escapeViaLink = linkVault.appendingPathComponent("..").appendingPathComponent("Outside").appendingPathComponent("x.md")

        // File reached through symlink when vault is the real path.
        XCTAssertTrue(VaultPathSafety.contains(fileViaLink, vaultRoot: realVault))
        // File on real path when vault is the symlink.
        XCTAssertTrue(VaultPathSafety.contains(fileViaReal, vaultRoot: linkVault))
        // Outside of vault remains rejected.
        XCTAssertFalse(VaultPathSafety.contains(outsideFile, vaultRoot: realVault))
        XCTAssertFalse(VaultPathSafety.contains(outsideFile, vaultRoot: linkVault))
        XCTAssertFalse(VaultPathSafety.contains(escapeViaLink, vaultRoot: linkVault))
    }

    func testSymlinkInsideVaultPointingOutsideIsRejected() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("zinc-path-safety-out-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: base) }

        let vault = base.appendingPathComponent("Vault", isDirectory: true)
        let outside = base.appendingPathComponent("Outside", isDirectory: true)
        try fm.createDirectory(at: vault, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)

        let outsideFile = outside.appendingPathComponent("secret.md")
        try "secret".write(to: outsideFile, atomically: true, encoding: .utf8)

        let linkInVault = vault.appendingPathComponent("secret.md")
        try fm.createSymbolicLink(at: linkInVault, withDestinationURL: outsideFile)

        XCTAssertFalse(VaultPathSafety.contains(linkInVault, vaultRoot: vault))
    }

    func testPruningNeverConsidersVaultRootContained() {
        let vault = URL(fileURLWithPath: "/Users/me/Zinc")
        let child = URL(fileURLWithPath: "/Users/me/Zinc/folder")
        // Mirrors pruneEmptyDirectories: only true for paths strictly inside the vault.
        XCTAssertTrue(VaultPathSafety.contains(child, vaultRoot: vault))
        XCTAssertFalse(VaultPathSafety.contains(vault, vaultRoot: vault))
    }

    func testRelativePathRoundTrip() {
        let vault = URL(fileURLWithPath: "/Users/me/Zinc", isDirectory: true)
        let absolute = URL(fileURLWithPath: "/Users/me/Zinc/2024-08/07/Safari/note.md")
        let relative = VaultPathSafety.relativePath(of: absolute, to: vault)
        XCTAssertEqual(relative, "2024-08/07/Safari/note.md")

        let resolved = VaultPathSafety.resolveMarkdownURL(relative!, vaultRoot: vault)
        XCTAssertEqual(resolved.path, absolute.path)
    }

    func testAbsoluteStoredPathResolvesUnchanged() {
        let vault = URL(fileURLWithPath: "/Users/me/Zinc", isDirectory: true)
        let absolute = "/Users/me/OldZinc/note.md"
        let resolved = VaultPathSafety.resolveMarkdownURL(absolute, vaultRoot: vault)
        XCTAssertEqual(resolved.path, absolute)
    }
}
