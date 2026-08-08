import AppKit
import Foundation
import ZincCore

final class MarkdownExporter {
    static let shared = MarkdownExporter()

    private static let remoteImageDownloadBudget: TimeInterval = 10
    private let posixLocale = Locale(identifier: "en_US_POSIX")

    private init() {}

    func export(
        selection: RichSelection,
        clip: Clip,
        completion: ((Result<URL, ZincError>) -> Void)? = nil
    ) {
        Task {
            await MainActor.run {
                MarkdownPreviewStore.shared.markExportPending(clip.id)
            }
            let result = await performExport(selection: selection, clip: clip)
            await MainActor.run {
                MarkdownPreviewStore.shared.markExportComplete(clip.id)
                completion?(result)
            }
        }
    }

    private func performExport(selection: RichSelection, clip: Clip) async -> Result<URL, ZincError> {
        guard VaultSettings.ensureVaultExists(reportFailure: false) else {
            let error = VaultSettings.lastHealthError
                ?? .vaultUnavailable(
                    path: VaultSettings.vaultURL.path,
                    message: "Vault is not writable"
                )
            return .failure(error)
        }

        let savedAt = clip.savedAt
        let appFolder = sanitizeAppName(clip.appName)
        let monthFolder = formatMonth(savedAt)
        let dayFolder = formatDay(savedAt)
        let timestampBase = formatTimestamp(savedAt)

        let directory = VaultSettings.vaultURL
            .appendingPathComponent(monthFolder, isDirectory: true)
            .appendingPathComponent(dayFolder, isDirectory: true)
            .appendingPathComponent(appFolder, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return .failure(.exportDirectoryFailed(error))
        }

        let fileURL = uniqueFileURL(in: directory, baseName: timestampBase, extension: "md")
        let assetsFolderName = "\(fileURL.deletingPathExtension().lastPathComponent)-assets"
        let assetsDirectory = directory.appendingPathComponent(assetsFolderName, isDirectory: true)

        var markdownBody: String
        var imageReferences: [HTMLToMarkdown.ImageReference] = []

        if let html = selection.html {
            let converted = HTMLToMarkdown.convert(html)
            markdownBody = converted.markdown
            imageReferences = converted.imageReferences
        } else {
            markdownBody = selection.plainText
        }

        if !selection.images.isEmpty || !imageReferences.isEmpty {
            do {
                try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
            } catch {
                return .failure(.exportDirectoryFailed(error))
            }

            switch await processImages(
                markdown: markdownBody,
                pasteboardImages: selection.images,
                imageReferences: imageReferences,
                assetsDirectory: assetsDirectory,
                assetsFolderName: assetsFolderName
            ) {
            case .success(let body):
                markdownBody = body
            case .failure(let error):
                return .failure(error)
            }
        }

        let content = buildDocument(clip: clip, body: markdownBody)

        do {
            let tempURL = fileURL.appendingPathExtension("tmp")
            try content.write(to: tempURL, atomically: true, encoding: .utf8)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: fileURL)
            let storedPath = VaultSettings.storedMarkdownPath(for: fileURL)
            ClipStore.shared.setMarkdownPath(storedPath, for: clip.id)
            NSLog("Zinc: exported markdown to \(fileURL.path)")
            return .success(fileURL)
        } catch {
            return .failure(.markdownWriteFailed(error))
        }
    }

    private func buildDocument(clip: Clip, body: String) -> String {
        var frontMatter = [
            "---",
            "id: \(clip.id.uuidString)",
            "app: \(YamlEscape.escape(clip.appName))",
            "bundle: \(YamlEscape.escape(clip.bundleID))",
        ]

        if let pageURL = clip.pageURL, !pageURL.isEmpty {
            frontMatter.append("url: \(YamlEscape.escape(pageURL))")
        }
        if let pageTitle = clip.pageTitle, !pageTitle.isEmpty {
            frontMatter.append("title: \(YamlEscape.escape(pageTitle))")
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let saved = isoFormatter.string(from: clip.savedAt)
        frontMatter.append("saved: \(saved)")
        frontMatter.append("---")

        return frontMatter.joined(separator: "\n") + "\n\n" + body.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    internal func processImages(
        markdown: String,
        pasteboardImages: [PasteboardImage],
        imageReferences: [HTMLToMarkdown.ImageReference],
        assetsDirectory: URL,
        assetsFolderName: String
    ) async -> Result<String, ZincError> {
        var result = markdown
        var imageIndex = 1
        var sourceToLocalPath: [String: String] = [:]

        let pasteboardToWrite: [PasteboardImage]
        if imageReferences.isEmpty {
            pasteboardToWrite = pasteboardImages
        } else {
            let duplicateCount = min(pasteboardImages.count, imageReferences.count)
            pasteboardToWrite = Array(pasteboardImages.dropFirst(duplicateCount))
        }

        var pasteboardReferences: [String] = []
        for image in pasteboardToWrite {
            let fileName = "image-\(imageIndex).\(image.fileExtension)"
            let fileURL = assetsDirectory.appendingPathComponent(fileName)
            do {
                try image.data.write(to: fileURL, options: .atomic)
                let relativePath = "\(assetsFolderName)/\(fileName)"
                pasteboardReferences.append(relativePath)
                imageIndex += 1
            } catch {
                return .failure(.imageWriteFailed(error))
            }
        }

        if !pasteboardReferences.isEmpty {
            let imageMarkdown = pasteboardReferences
                .map { "![image](\($0))" }
                .joined(separator: "\n\n")
            if result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result = imageMarkdown
            } else {
                result += "\n\n" + imageMarkdown
            }
        }

        var remoteReferences: [HTMLToMarkdown.ImageReference] = []

        for reference in imageReferences {
            let source = reference.originalSource
            if let existingPath = sourceToLocalPath[source] {
                result = result.replacingOccurrences(of: reference.markdownSource, with: existingPath)
                continue
            }

            if source.hasPrefix("data:") {
                switch writeDataURI(source, index: imageIndex, assetsDirectory: assetsDirectory, assetsFolderName: assetsFolderName) {
                case .success(let localPath):
                    if let localPath {
                        sourceToLocalPath[source] = localPath
                        result = result.replacingOccurrences(of: reference.markdownSource, with: localPath)
                        imageIndex += 1
                    }
                case .failure(let error):
                    return .failure(error)
                }
            } else if source.hasPrefix("http://") || source.hasPrefix("https://") {
                remoteReferences.append(reference)
            }
        }

        if ExportSettings.shared.downloadRemoteImages, !remoteReferences.isEmpty {
            var uniqueRemote: [(reference: HTMLToMarkdown.ImageReference, index: Int)] = []
            var seenSources: Set<String> = []
            for reference in remoteReferences {
                let source = reference.originalSource
                if sourceToLocalPath[source] != nil { continue }
                if seenSources.insert(source).inserted {
                    uniqueRemote.append((reference, imageIndex))
                    imageIndex += 1
                }
            }

            let downloads = await fetchRemoteImagesConcurrently(
                references: uniqueRemote,
                assetsDirectory: assetsDirectory,
                assetsFolderName: assetsFolderName
            )
            for (markdownSource, localPath) in downloads {
                if let reference = imageReferences.first(where: { $0.markdownSource == markdownSource }) {
                    sourceToLocalPath[reference.originalSource] = localPath
                }
            }

            for reference in imageReferences {
                let source = reference.originalSource
                guard source.hasPrefix("http://") || source.hasPrefix("https://"),
                      let localPath = sourceToLocalPath[source] else { continue }
                result = result.replacingOccurrences(of: reference.markdownSource, with: localPath)
            }
        }

        return .success(result)
    }

    private func writeDataURI(
        _ source: String,
        index: Int,
        assetsDirectory: URL,
        assetsFolderName: String
    ) -> Result<String?, ZincError> {
        guard let commaIndex = source.firstIndex(of: ",") else { return .success(nil) }
        let metadata = String(source[source.index(after: source.startIndex)..<commaIndex])
        let payload = String(source[source.index(after: commaIndex)...])

        let ext: String
        if metadata.contains("image/png") {
            ext = "png"
        } else if metadata.contains("image/jpeg") || metadata.contains("image/jpg") {
            ext = "jpg"
        } else if metadata.contains("image/gif") {
            ext = "gif"
        } else if metadata.contains("image/webp") {
            ext = "webp"
        } else {
            ext = "png"
        }

        let data: Data?
        if metadata.contains(";base64") {
            data = Data(base64Encoded: payload)
        } else {
            data = payload.removingPercentEncoding?.data(using: .utf8)
        }

        guard let data, !data.isEmpty else { return .success(nil) }

        let fileName = "image-\(index).\(ext)"
        let fileURL = assetsDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL, options: .atomic)
            return .success("\(assetsFolderName)/\(fileName)")
        } catch {
            return .failure(.imageWriteFailed(error))
        }
    }

    private func fetchRemoteImagesConcurrently(
        references: [(reference: HTMLToMarkdown.ImageReference, index: Int)],
        assetsDirectory: URL,
        assetsFolderName: String
    ) async -> [(String, String)] {
        let deadline = Date().addingTimeInterval(Self.remoteImageDownloadBudget)

        return await withTaskGroup(of: (String, String?).self) { group in
            for item in references {
                let markdownSource = item.reference.markdownSource
                let source = item.reference.originalSource
                let index = item.index
                group.addTask {
                    if Date() >= deadline {
                        return (markdownSource, nil)
                    }
                    let path = await self.fetchRemoteImage(
                        from: source,
                        index: index,
                        assetsDirectory: assetsDirectory,
                        assetsFolderName: assetsFolderName
                    )
                    return (markdownSource, path)
                }
            }

            var results: [(String, String)] = []
            for await (markdownSource, localPath) in group {
                if let localPath {
                    results.append((markdownSource, localPath))
                }
                if Date() >= deadline {
                    group.cancelAll()
                }
            }
            return results
        }
    }

    private func fetchRemoteImage(
        from urlString: String,
        index: Int,
        assetsDirectory: URL,
        assetsFolderName: String
    ) async -> String? {
        guard let url = URL(string: urlString) else { return nil }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        let session = URLSession(configuration: config)

        do {
            let (downloadedData, response) = try await session.data(from: url)
            guard !downloadedData.isEmpty else { return nil }

            let responseContentType = (response as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Content-Type")
            let ext = extensionForContentType(responseContentType) ?? url.pathExtension.nilIfEmpty ?? "png"
            let fileName = "image-\(index).\(ext)"
            let fileURL = assetsDirectory.appendingPathComponent(fileName)
            try downloadedData.write(to: fileURL, options: .atomic)
            return "\(assetsFolderName)/\(fileName)"
        } catch {
            if !Task.isCancelled {
                ErrorReporter.log(.imageWriteFailed(error))
            }
            return nil
        }
    }

    private func extensionForContentType(_ contentType: String?) -> String? {
        guard let contentType else { return nil }
        if contentType.contains("png") { return "png" }
        if contentType.contains("jpeg") || contentType.contains("jpg") { return "jpg" }
        if contentType.contains("gif") { return "gif" }
        if contentType.contains("webp") { return "webp" }
        return nil
    }

    private func uniqueFileURL(in directory: URL, baseName: String, extension ext: String) -> URL {
        var candidate = directory.appendingPathComponent("\(baseName).\(ext)")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-\(suffix).\(ext)")
            suffix += 1
        }
        return candidate
    }

    private func sanitizeAppName(_ name: String) -> String {
        name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatMonth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = posixLocale
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    private func formatDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = posixLocale
        formatter.timeZone = .current
        formatter.dateFormat = "dd"
        return formatter.string(from: date)
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = posixLocale
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: date)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
