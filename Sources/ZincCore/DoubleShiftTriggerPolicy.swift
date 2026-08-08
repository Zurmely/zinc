import Foundation

/// Pure decision logic for when the double-modifier capture trigger should be suppressed.
public enum DoubleShiftTriggerPolicy {
    public static func shouldSuppress(
        frontmostBundleID: String?,
        zincBundleID: String?,
        excludedBundleIDs: [String]
    ) -> Bool {
        if let zincBundleID, let frontmostBundleID, frontmostBundleID == zincBundleID {
            return true
        }
        guard let frontmostBundleID, !frontmostBundleID.isEmpty else { return false }
        return excludedBundleIDs.contains(frontmostBundleID)
    }
}
