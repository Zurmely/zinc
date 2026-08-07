import Foundation

public struct Clip: Identifiable, Codable, Equatable, Hashable {
    public let id: UUID
    public let text: String
    public var savedAt: Date
    public let appName: String
    public let bundleID: String
    public let pageURL: String?
    public let pageTitle: String?
    public var markdownPath: String?

    public init(
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

    public var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 120 {
            return trimmed
        }
        return String(trimmed.prefix(117)) + "..."
    }

    public var contextLabel: String {
        if let pageTitle, !pageTitle.isEmpty {
            return pageTitle
        }
        if let pageURL, let host = URL(string: pageURL)?.host {
            return host
        }
        return appName
    }
}
