import CloudKit
import Foundation

@available(macOS 14.0, iOS 17.0, *)
@MainActor
public final class ClipCloudSync: NSObject, ObservableObject {
    public enum Status: Equatable {
        case disabled
        case unavailable(String)
        case idle
        case syncing
        case error(String)

        public var label: String {
            switch self {
            case .disabled:
                return "Off"
            case let .unavailable(message):
                return message
            case .idle:
                return "Up to date"
            case .syncing:
                return "Syncing…"
            case let .error(message):
                return message
            }
        }
    }

    public static let shared = ClipCloudSync()

    @Published public private(set) var status: Status = .disabled
    @Published public private(set) var lastSyncedAt: Date?

    public var onRemoteUpserts: (([Clip]) -> Void)?
    public var onRemoteDeletes: ((Set<UUID>) -> Void)?

    private let container: CKContainer
    private var syncEngine: CKSyncEngine?
    private var pendingSaves: [UUID: Clip] = [:]
    private var pendingDeletes: Set<UUID> = []
    private var isRunning = false
    private let stateDefaultsKey = "zinc.cloudKitSyncEngineState"

    private override init() {
        container = CKContainer(identifier: ClipRecord.containerIdentifier)
        super.init()
    }

    public func setEnabled(_ enabled: Bool) async {
        if enabled {
            await start()
        } else {
            stop()
        }
    }

    public func start() async {
        guard !isRunning else { return }

        do {
            let accountStatus = try await container.accountStatus()
            guard accountStatus == .available else {
                status = .unavailable(accountStatusMessage(accountStatus))
                return
            }

            try await ensureZoneExists()
            let configuration = CKSyncEngine.Configuration(
                database: container.privateCloudDatabase,
                stateSerialization: loadStateSerialization(),
                delegate: self
            )
            syncEngine = CKSyncEngine(configuration)
            isRunning = true
            status = .syncing
            try await syncEngine?.fetchChanges()
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    public func stop() {
        syncEngine = nil
        isRunning = false
        pendingSaves.removeAll()
        pendingDeletes.removeAll()
        status = .disabled
    }

    public func enqueueSave(_ clip: Clip) {
        guard isRunning, let syncEngine else { return }
        pendingDeletes.remove(clip.id)
        pendingSaves[clip.id] = clip
        syncEngine.state.hasPendingUntrackedChanges = true
        status = .syncing
        Task {
            do {
                try await syncEngine.sendChanges()
            } catch {
                status = .error(error.localizedDescription)
            }
        }
    }

    public func enqueueDelete(ids: Set<UUID>) {
        guard isRunning, let syncEngine, !ids.isEmpty else { return }
        for id in ids {
            pendingSaves.removeValue(forKey: id)
            pendingDeletes.insert(id)
        }
        syncEngine.state.hasPendingUntrackedChanges = true
        status = .syncing
        Task {
            do {
                try await syncEngine.sendChanges()
            } catch {
                status = .error(error.localizedDescription)
            }
        }
    }

    public func uploadAll(_ clips: [Clip]) {
        guard isRunning, let syncEngine else { return }
        for clip in clips {
            pendingSaves[clip.id] = clip
        }
        syncEngine.state.hasPendingUntrackedChanges = true
        status = .syncing
        Task {
            do {
                try await syncEngine.sendChanges()
            } catch {
                status = .error(error.localizedDescription)
            }
        }
    }

    public func fetchChanges() {
        guard isRunning, let syncEngine else { return }
        status = .syncing
        Task {
            do {
                try await syncEngine.fetchChanges()
            } catch {
                status = .error(error.localizedDescription)
            }
        }
    }

    private func ensureZoneExists() async throws {
        let zone = CKRecordZone(zoneID: ClipRecord.zoneID)
        _ = try await container.privateCloudDatabase.modifyRecordZones(saving: [zone], deleting: [])
    }

    private func accountStatusMessage(_ status: CKAccountStatus) -> String {
        switch status {
        case .noAccount:
            return "Sign in to iCloud"
        case .restricted:
            return "iCloud restricted"
        case .couldNotDetermine:
            return "iCloud unavailable"
        case .temporarilyUnavailable:
            return "iCloud temporarily unavailable"
        case .available:
            return "Available"
        @unknown default:
            return "iCloud unavailable"
        }
    }

    private func loadStateSerialization() -> CKSyncEngine.State.Serialization? {
        guard let data = UserDefaults.standard.data(forKey: stateDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func persistStateSerialization(_ state: CKSyncEngine.State.Serialization) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: stateDefaultsKey)
    }

    private func handleFetchedRecords(_ records: [CKRecord], deletedIDs: [CKRecord.ID]) {
        let upserts = records.compactMap(ClipRecord.clip(from:))
        let deletedClipIDs = Set(
            deletedIDs.compactMap { UUID(uuidString: $0.recordName) }
        )

        if !upserts.isEmpty {
            onRemoteUpserts?(upserts)
        }
        if !deletedClipIDs.isEmpty {
            onRemoteDeletes?(deletedClipIDs)
        }

        if !upserts.isEmpty || !deletedClipIDs.isEmpty {
            lastSyncedAt = Date()
            status = .idle
        }
    }

    private func clearSentChanges(savedRecords: [CKRecord], deletedRecordIDs: [CKRecord.ID]) {
        for record in savedRecords {
            if let id = UUID(uuidString: record.recordID.recordName) {
                pendingSaves.removeValue(forKey: id)
            }
        }
        for recordID in deletedRecordIDs {
            if let id = UUID(uuidString: recordID.recordName) {
                pendingDeletes.remove(id)
            }
        }

        if pendingSaves.isEmpty && pendingDeletes.isEmpty {
            syncEngine?.state.hasPendingUntrackedChanges = false
            lastSyncedAt = Date()
            status = .idle
        }
    }
}

@available(macOS 14.0, iOS 17.0, *)
extension ClipCloudSync: CKSyncEngineDelegate {
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case let .stateUpdate(stateUpdate):
            persistStateSerialization(stateUpdate.stateSerialization)

        case let .fetchedRecordZoneChanges(changes):
            handleFetchedRecords(
                changes.modifications.map(\.record),
                deletedIDs: changes.deletions.map(\.recordID)
            )

        case let .sentRecordZoneChanges(changes):
            clearSentChanges(
                savedRecords: changes.savedRecords,
                deletedRecordIDs: changes.deletedRecordIDs
            )

        case .didFetchChanges, .didSendChanges:
            if pendingSaves.isEmpty && pendingDeletes.isEmpty {
                lastSyncedAt = Date()
                status = .idle
            }

        case .willFetchChanges, .willSendChanges, .fetchedDatabaseChanges, .sentDatabaseChanges,
             .willFetchRecordZoneChanges, .didFetchRecordZoneChanges, .accountChange:
            break

        @unknown default:
            break
        }
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard !pendingSaves.isEmpty || !pendingDeletes.isEmpty else {
            syncEngine.state.hasPendingUntrackedChanges = false
            return nil
        }

        let records = pendingSaves.values.map { ClipRecord.makeRecord(from: $0) }
        let deleteIDs = pendingDeletes.map { ClipRecord.recordID(for: $0) }

        return CKSyncEngine.RecordZoneChangeBatch(
            recordsToSave: records,
            recordIDsToDelete: deleteIDs,
            atomicByZone: true
        )
    }
}
