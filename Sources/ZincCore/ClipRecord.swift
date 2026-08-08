import CloudKit
import Foundation

enum ClipRecord {
    static let recordType = "Clip"
    static let zoneName = "ZincClips"
    static let containerIdentifier = "iCloud.com.zurmely.zinc"

    static var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName)
    }

    static func recordID(for clipID: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: clipID.uuidString, zoneID: zoneID)
    }

    static func makeRecord(from clip: Clip) -> CKRecord {
        let record = CKRecord(recordType: recordType, recordID: recordID(for: clip.id))
        record["text"] = clip.text as CKRecordValue
        record["savedAt"] = clip.savedAt as CKRecordValue
        record["modifiedAt"] = clip.modifiedAt as CKRecordValue
        record["appName"] = clip.appName as CKRecordValue
        record["bundleID"] = clip.bundleID as CKRecordValue
        if let pageURL = clip.pageURL {
            record["pageURL"] = pageURL as CKRecordValue
        } else {
            record["pageURL"] = nil
        }
        if let pageTitle = clip.pageTitle {
            record["pageTitle"] = pageTitle as CKRecordValue
        } else {
            record["pageTitle"] = nil
        }
        return record
    }

    static func clip(from record: CKRecord) -> Clip? {
        guard
            let text = record["text"] as? String,
            let savedAt = record["savedAt"] as? Date,
            let appName = record["appName"] as? String,
            let bundleID = record["bundleID"] as? String,
            let id = UUID(uuidString: record.recordID.recordName)
        else {
            return nil
        }

        let modifiedAt = record["modifiedAt"] as? Date ?? savedAt
        return Clip(
            id: id,
            text: text,
            savedAt: savedAt,
            modifiedAt: modifiedAt,
            appName: appName,
            bundleID: bundleID,
            pageURL: record["pageURL"] as? String,
            pageTitle: record["pageTitle"] as? String,
            markdownPath: nil
        )
    }
}
