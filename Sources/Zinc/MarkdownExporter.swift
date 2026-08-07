import AppKit
import Foundation
import ZincCore

final class MarkdownExporter {
    static let shared = MarkdownExporter()

    private let queue = DispatchQueue(label: "com.zurmely.zinc.export")
    private let posixLocale = Locale(identifier: "en_US_POSIX")

    private init() {}

    func export(selection: RichSelection, clip: Clip) {
        queue.async { [self] in
            self.performExport(selection: selection, clip: clip)
        }
    }

    private func performExport(selection: RichSelection, clip: Clip) {
        guard VaultSettings.ensureVaultExists() else { return }

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
            NSLog("Zinc: failed to create export directory: \(error)")
            return
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
                markdownBody = processImages(
                    markdown: markdownBody,
                    pasteboardImages: selection.images,
                    imageReferences: imageReferences,
                    assetsDirectory: assetsDirectory,
                    assetsFolderName: assetsFolderName
                )
            } catch {
                NSLog("Zinc: failed to create assets directory: \(error)")
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
            ClipStore.shared.setMarkdownPath(fileURL.path, for: clip.id)
            NSLog("Zinc: exported markdown to \(fileURL.path)")
        } catch {
            NSLog("Zinc: failed to write markdown: \(error)")
        }
    }

    private func buildDocument(clip: Clip, body: String) -> String {
        var frontMatter = [
            "---",
            "id: \(clip.id.uuidString)",
            "app: \(yamlEscape(clip.appName))",
            "bundle: \(yamlEscape(clip.bundleID))",
        ]

        if let pageURL = clip.pageURL, !pageURL.isEmpty {
            frontMatter.append("url: \(yamlEscape(pageURL))")
        }
        if let pageTitle = clip.pageTitle, !pageTitle.isEmpty {
            frontMatter.append("title: \(yamlEscape(pageTitle))")
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        let saved = isoFormatter.string(from: clip.savedAt)
        frontMatter.append("saved: \(saved)")
        frontMatter.append("---")

        return frontMatter.joined(separator: "\n") + "\n\n" + body.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private func processImages(
        markdown: String,
        pasteboardImages: [PasteboardImage],
        imageReferences: [HTMLToMarkdown.ImageReference],
        assetsDirectory: URL,
        assetsFolderName: String
    ) -> String {
        var result = markdown
        var imageIndex = 1

        for image in pasteboardImages {
            let fileName = "image-\(imageIndex).\(normalizedExtension(image.fileExtension))"
            let fileURL = assetsDirectory.appendingPathComponent(fileName)
            do {
                let data = normalizedImageData(image)
                try data.write(to: fileURL, options: .atomic)
                let relativePath = "\(assetsFolderName)/\(fileName)"
                if result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result = "![image](\(relativePath))"
                }
                imageIndex += 1
            } catch {
                NSLog("Zinc: failed to write pasteboard image: \(error)")
            }
        }

        for reference in imageReferences {
            let source = reference.originalSource
            if source.hasPrefix("data:") {
                if let localPath = writeDataURI(source, index: imageIndex, assetsDirectory: assetsDirectory, assetsFolderName: assetsFolderName) {
                    result = result.replacingOccurrences(of: reference.markdownSource, with: localPath)
                    imageIndex += 1
                }
            } else if source.hasPrefix("http://") || source.hasPrefix("https://") {
                if let localPath = fetchRemoteImage(from: source, index: imageIndex, assetsDirectory: assetsDirectory, assetsFolderName: assetsFolderName) {
                    result = result.replacingOccurrences(of: reference.markdownSource, with: localPath)
                    imageIndex += 1
                }
            }
        }

        return result
    }

    private func writeDataURI(
        _ source: String,
        index: Int,
        assetsDirectory: URL,
        assetsFolderName: String
    ) -> String? {
        guard let commaIndex = source.firstIndex(of: ",") else { return nil }
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

        guard let data, !data.isEmpty else { return nil }

        let fileName = "image-\(index).\(ext)"
        let fileURL = assetsDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL, options: .atomic)
            return "\(assetsFolderName)/\(fileName)"
        } catch {
            NSLog("Zinc: failed to write data URI image: \(error)")
            return nil
        }
    }

    private func fetchRemoteImage(
        from urlString: String,
        index: Int,
        assetsDirectory: URL,
        assetsFolderName: String
    ) -> String? {
        guard let url = URL(string: urlString) else { return nil }

        let semaphore = DispatchSemaphore(value: 0)
        var downloadedData: Data?
        var responseContentType: String?

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        let session = URLSession(configuration: config)

        let task = session.dataTask(with: url) { data, response, error in
            if let error {
                NSLog("Zinc: failed to fetch image \(urlString): \(error)")
            }
            downloadedData = data
            if let httpResponse = response as? HTTPURLResponse {
                responseContentType = httpResponse.value(forHTTPHeaderField: "Content-Type")
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 6)

        guard let downloadedData, !downloadedData.isEmpty else { return nil }

        let ext = extensionForContentType(responseContentType) ?? url.pathExtension.nilIfEmpty ?? "png"
        let fileName = "image-\(index).\(ext)"
        let fileURL = assetsDirectory.appendingPathComponent(fileName)

        do {
            try downloadedData.write(to: fileURL, options: .atomic)
            return "\(assetsFolderName)/\(fileName)"
        } catch {
            NSLog("Zinc: failed to write remote image: \(error)")
            return nil
        }
    }

    private func normalizedImageData(_ image: PasteboardImage) -> Data {
        if image.fileExtension == "png" {
            return image.data
        }
        if let nsImage = NSImage(data: image.data),
           let tiff = nsImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            return png
        }
        return image.data
    }

    private func normalizedExtension(_ ext: String) -> String {
        ext == "tiff" ? "png" : ext
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

    private func yamlEscape(_ value: String) -> String {
        if value.contains(":") || value.contains("#") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        return value
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
