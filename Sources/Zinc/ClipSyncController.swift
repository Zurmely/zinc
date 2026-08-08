import CloudKit
import SwiftUI
import ZincCore

@MainActor
final class ClipSyncController: ObservableObject {
    static let shared = ClipSyncController()

    @Published var settings = SyncSettings.shared
    @Published private(set) var status: ClipCloudSync.Status = .disabled
    @Published private(set) var lastSyncedAt: Date?

    private let cloudSync = ClipCloudSync.shared
    private var refreshTask: Task<Void, Never>?

    private init() {
        refreshFromCloudSync()
        startRefreshing()
    }

    func setEnabled(_ enabled: Bool) {
        settings.iCloudSyncEnabled = enabled
        ClipStore.shared.handleSyncEnabledChanged(enabled)
        refreshFromCloudSync()
    }

    func refreshFromCloudSync() {
        status = cloudSync.status
        lastSyncedAt = cloudSync.lastSyncedAt
    }

    private func startRefreshing() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor in
            while !Task.isCancelled {
                refreshFromCloudSync()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
