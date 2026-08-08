import Foundation

/// User preferences for markdown export behaviour.
final class ExportSettings: ObservableObject {
    static let shared = ExportSettings()

    private enum Keys {
        static let downloadRemoteImages = "zinc.export.downloadRemoteImages"
    }

    @Published var downloadRemoteImages: Bool {
        didSet { UserDefaults.standard.set(downloadRemoteImages, forKey: Keys.downloadRemoteImages) }
    }

    private init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Keys.downloadRemoteImages) == nil {
            downloadRemoteImages = false
        } else {
            downloadRemoteImages = defaults.bool(forKey: Keys.downloadRemoteImages)
        }
    }
}
