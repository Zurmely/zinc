import Foundation

public enum SavedAtFormat {
    private static let minute: TimeInterval = 60
    private static let hour = 60 * minute
    private static let day = 24 * hour
    private static let monthThreshold = 30 * day

    public static func string(for date: Date, relativeTo now: Date = .now) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))

        if elapsed < minute {
            return "now"
        }

        if elapsed >= monthThreshold {
            return date.formatted(date: .abbreviated, time: .omitted)
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated

        if elapsed < hour {
            let minutes = Int(elapsed / minute)
            return formatter.localizedString(fromTimeInterval: -Double(minutes) * minute)
        }

        if elapsed < day {
            let hours = Int(elapsed / hour)
            return formatter.localizedString(fromTimeInterval: -Double(hours) * hour)
        }

        let days = Int(elapsed / day)
        return formatter.localizedString(fromTimeInterval: -Double(days) * day)
    }
}
