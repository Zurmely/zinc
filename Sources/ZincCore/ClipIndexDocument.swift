import Foundation

/// On-disk envelope for `clips.json`. Versioned so future schema changes can migrate
/// instead of discarding history. Legacy bare `[Clip]` arrays remain readable.
public struct ClipIndexDocument: Codable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var clips: [Clip]

    public init(version: Int = Self.currentVersion, clips: [Clip]) {
        self.version = version
        self.clips = clips
    }
}
