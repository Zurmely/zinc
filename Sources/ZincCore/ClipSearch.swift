import Foundation

public enum ClipSearch {
    public static func filter(_ clips: [Clip], query: String) -> [Clip] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return clips }
        return clips.filter { clip in
            clip.text.lowercased().contains(normalized)
                || clip.appName.lowercased().contains(normalized)
                || (clip.pageTitle?.lowercased().contains(normalized) ?? false)
                || (clip.pageURL?.lowercased().contains(normalized) ?? false)
        }
    }
}
