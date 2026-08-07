import Foundation

public struct Clip: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let text: String
    public let savedAt: Date
    public var modifiedAt: Date
    public let appName: String
    public let bundleID: String
    public let pageURL: String?
    public let pageTitle: String?
    public var markdownPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case savedAt
        case modifiedAt
        case appName
        case bundleID
        case pageURL
        case pageTitle
        case markdownPath
    }

    public init(
        id: UUID = UUID(),
        text: String,
        savedAt: Date = Date(),
        modifiedAt: Date? = nil,
        appName: String,
        bundleID: String,
        pageURL: String? = nil,
        pageTitle: String? = nil,
        markdownPath: String? = nil
    ) {
        self.id = id
        self.text = text
        self.savedAt = savedAt
        self.modifiedAt = modifiedAt ?? savedAt
        self.appName = appName
        self.bundleID = bundleID
        self.pageURL = pageURL
        self.pageTitle = pageTitle
        self.markdownPath = markdownPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? savedAt
        appName = try container.decode(String.self, forKey: .appName)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        pageURL = try container.decodeIfPresent(String.self, forKey: .pageURL)
        pageTitle = try container.decodeIfPresent(String.self, forKey: .pageTitle)
        markdownPath = try container.decodeIfPresent(String.self, forKey: .markdownPath)
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

    public func withMarkdownPath(_ path: String) -> Clip {
        var copy = self
        copy.markdownPath = path
        return copy
    }
}
