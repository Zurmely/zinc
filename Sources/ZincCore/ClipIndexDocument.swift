import Foundation

/// On-disk envelope for `clips.json`. Versioned so future schema changes can migrate
/// instead of discarding history. Legacy bare `[Clip]` arrays remain readable.
struct ClipIndexDocument: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var clips: [Clip]

    init(version: Int = Self.currentVersion, clips: [Clip]) {
        self.version = version
        self.clips = clips
    }
}
