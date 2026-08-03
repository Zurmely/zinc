import Foundation

struct Clip: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let text: String
    let savedAt: Date
    let appName: String
    let bundleID: String
    let pageURL: String?
    let pageTitle: String?
    var markdownPath: String?

    init(
        id: UUID = UUID(),
        text: String,
        savedAt: Date = Date(),
        appName: String,
        bundleID: String,
        pageURL: String? = nil,
        pageTitle: String? = nil,
        markdownPath: String? = nil
    ) {
        self.id = id
        self.text = text
        self.savedAt = savedAt
        self.appName = appName
        self.bundleID = bundleID
        self.pageURL = pageURL
        self.pageTitle = pageTitle
        self.markdownPath = markdownPath
    }

    var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 120 {
            return trimmed
        }
        return String(trimmed.prefix(117)) + "..."
    }

    var contextLabel: String {
        if let pageTitle, !pageTitle.isEmpty {
            return pageTitle
        }
        if let pageURL, let host = URL(string: pageURL)?.host {
            return host
        }
        return appName
    }
}
