import Foundation

public final class SyncSettings: ObservableObject {
    public static let shared = SyncSettings()

    private let defaults: UserDefaults
    private let enabledKey = "zinc.iCloudSyncEnabled"

    @Published public var iCloudSyncEnabled: Bool {
        didSet {
            guard iCloudSyncEnabled != oldValue else { return }
            defaults.set(iCloudSyncEnabled, forKey: enabledKey)
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        iCloudSyncEnabled = defaults.bool(forKey: enabledKey)
    }
}
