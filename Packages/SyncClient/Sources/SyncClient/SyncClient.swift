import CompanionCore
import Foundation

public actor SyncConsentStore {
    private var enabledCategories: Set<MemoryCategory> = []

    public init() {}

    public func setEnabled(_ enabled: Bool, category: MemoryCategory) {
        if enabled {
            enabledCategories.insert(category)
        } else {
            enabledCategories.remove(category)
        }
    }

    public func mayEnqueue(_ record: MemoryRecordV1) -> Bool {
        guard record.category != .protectedNeverSync else { return false }
        guard record.category != .preciseLocation else { return false }
        return record.syncEligible && enabledCategories.contains(record.category)
    }

    public func mayEnqueuePreciseLocation(
        _ record: MemoryRecordV1,
        authorization: LocationSyncAuthorizationV1
    ) -> Bool {
        record.category == .preciseLocation
            && enabledCategories.contains(.preciseLocation)
            && authorization.recordRevisionDigest == record.authorizationDigest
    }
}
