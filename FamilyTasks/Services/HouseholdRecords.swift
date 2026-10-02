import Foundation

/// One record in the shared CloudKit zone, in a form that can be built and compared
/// without CloudKit. Each task, shop, shopping item, meal, idea, family member and
/// profile is its own record; health snapshots are grouped into one record per member.
struct SyncRecord: Codable, Equatable {
    enum Kind: String, Codable {
        case task
        case shop
        case shoppingItem
        case recurringTask
        case mealIdea
        case plannedMeal
        case idea
        case member
        case profile
        case health
        case household
        case kid
        case chore
        case choreCompletion
        case chorePayout
        case choreSettings
        /// The item was deleted at `updatedAt`; kept so older copies cannot bring it back.
        case deleted
    }

    var name: String
    var kind: Kind
    var payload: Data?
    var updatedAt: Date
    var updatedBy: String
}

/// Shop order and other household-wide settings that do not belong to a single item.
struct HouseholdInfo: Codable, Equatable {
    var shopOrder: [String]
}

enum HouseholdRecords {
    static let householdRecordName = "household"
    static let choreSettingsRecordName = "chore-settings"
    /// Stands in for "no known date", such as a family member added before additions were recorded.
    static let unknownDate = Date(timeIntervalSince1970: 0)

    static func profileRecordName(_ email: String) -> String { "profile:\(email)" }
    static func healthRecordName(_ email: String) -> String { "health:\(email)" }

    /// The records that describe `payload`. A deletion only produces a deleted marker
    /// when no newer edit of the same item exists and it is recent enough to be kept.
    static func records(from payload: SharedHouseholdPayload, updatedBy: String) -> [String: SyncRecord] {
        var records: [String: SyncRecord] = [:]

        func add<Item: SyncMergeable & Encodable>(_ items: [Item], as kind: SyncRecord.Kind) {
            for item in items {
                guard let data = try? JSONEncoder().encode(item) else { continue }
                records[item.syncID] = SyncRecord(name: item.syncID, kind: kind, payload: data, updatedAt: item.updatedAt, updatedBy: updatedBy)
            }
        }

        add(payload.tasks, as: .task)
        add(payload.shopping.shops, as: .shop)
        add(payload.shopping.items, as: .shoppingItem)
        add(payload.recurringTasks, as: .recurringTask)
        add(payload.mealPlan.mealIdeas, as: .mealIdea)
        add(payload.mealPlan.plannedMeals, as: .plannedMeal)
        add(payload.ideas, as: .idea)
        add(payload.chores.kids, as: .kid)
        add(payload.chores.chores, as: .chore)
        add(payload.chores.completions, as: .choreCompletion)
        add(payload.chores.payouts, as: .chorePayout)

        if payload.chores.settings.updatedAt > unknownDate, let data = try? JSONEncoder().encode(payload.chores.settings) {
            records[choreSettingsRecordName] = SyncRecord(
                name: choreSettingsRecordName,
                kind: .choreSettings,
                payload: data,
                updatedAt: payload.chores.settings.updatedAt,
                updatedBy: updatedBy
            )
        }

        for email in payload.familyMembers {
            let key = SyncLedger.memberKey(email)
            guard let data = try? JSONEncoder().encode(email) else { continue }
            records[key] = SyncRecord(
                name: key,
                kind: .member,
                payload: data,
                updatedAt: payload.memberAdditions[key] ?? unknownDate,
                updatedBy: updatedBy
            )
        }

        for profile in payload.profiles {
            let name = profileRecordName(profile.normalizedEmail)
            guard let data = try? JSONEncoder().encode(profile) else { continue }
            records[name] = SyncRecord(name: name, kind: .profile, payload: data, updatedAt: profile.updatedAt, updatedBy: updatedBy)
        }

        for (email, snapshots) in Dictionary(grouping: payload.healthSnapshots, by: \.memberEmail) {
            let sorted = snapshots.sorted { $0.date < $1.date }
            let name = healthRecordName(email)
            guard let data = try? JSONEncoder().encode(sorted) else { continue }
            records[name] = SyncRecord(
                name: name,
                kind: .health,
                payload: data,
                updatedAt: sorted.map(\.updatedAt).max() ?? unknownDate,
                updatedBy: updatedBy
            )
        }

        let info = HouseholdInfo(shopOrder: payload.shopping.shops.map(\.syncID))
        if let data = try? JSONEncoder().encode(info) {
            records[householdRecordName] = SyncRecord(
                name: householdRecordName,
                kind: .household,
                payload: data,
                updatedAt: payload.shopping.orderUpdatedAt ?? unknownDate,
                updatedBy: updatedBy
            )
        }

        let retentionCutoff = Date().addingTimeInterval(-SyncLedger.retention)
        for (key, deletedAt) in payload.deletions where deletedAt >= retentionCutoff {
            if let live = records[key], live.updatedAt > deletedAt { continue }
            records[key] = SyncRecord(name: key, kind: .deleted, payload: nil, updatedAt: deletedAt, updatedBy: updatedBy)
        }

        return records
    }

    /// Rebuilds the household from records, in the order given. Records this version
    /// cannot read (for example from a newer app version) are skipped.
    static func payload(from records: [SyncRecord]) -> SharedHouseholdPayload {
        var payload = SharedHouseholdPayload()
        var shopOrder: [String] = []
        let decoder = JSONDecoder()

        func decode<T: Decodable>(_ type: T.Type, _ record: SyncRecord) -> T? {
            record.payload.flatMap { try? decoder.decode(type, from: $0) }
        }

        for record in records {
            switch record.kind {
            case .task:
                decode(FamilyTask.self, record).map { payload.tasks.append($0) }
            case .shop:
                decode(Shop.self, record).map { payload.shopping.shops.append($0) }
            case .shoppingItem:
                decode(ShoppingItem.self, record).map { payload.shopping.items.append($0) }
            case .recurringTask:
                decode(RecurringTask.self, record).map { payload.recurringTasks.append($0) }
            case .mealIdea:
                decode(MealIdea.self, record).map { payload.mealPlan.mealIdeas.append($0) }
            case .plannedMeal:
                decode(PlannedMeal.self, record).map { payload.mealPlan.plannedMeals.append($0) }
            case .idea:
                decode(IdeaNote.self, record).map { payload.ideas.append($0) }
            case .kid:
                decode(KidProfile.self, record).map { payload.chores.kids.append($0) }
            case .chore:
                decode(Chore.self, record).map { payload.chores.chores.append($0) }
            case .choreCompletion:
                decode(ChoreCompletion.self, record).map { payload.chores.completions.append($0) }
            case .chorePayout:
                decode(ChorePayout.self, record).map { payload.chores.payouts.append($0) }
            case .choreSettings:
                decode(ChoreSettings.self, record).map { payload.chores.settings = $0 }
            case .member:
                guard let email = decode(String.self, record) else { continue }
                payload.familyMembers.append(email)
                if record.updatedAt > unknownDate {
                    payload.memberAdditions[record.name] = record.updatedAt
                }
            case .profile:
                decode(SharedMemberProfile.self, record).map { payload.profiles.append($0) }
            case .health:
                decode([HealthSnapshot].self, record).map { payload.healthSnapshots.append(contentsOf: $0) }
            case .household:
                guard let info = decode(HouseholdInfo.self, record) else { continue }
                shopOrder = info.shopOrder
                payload.shopping.orderUpdatedAt = record.updatedAt > unknownDate ? record.updatedAt : nil
            case .deleted:
                payload.deletions[record.name] = record.updatedAt
            }
        }

        let position = Dictionary(shopOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
        payload.shopping.shops = payload.shopping.shops.enumerated()
            .sorted { lhs, rhs in
                let left = position[lhs.element.syncID] ?? Int.max
                let right = position[rhs.element.syncID] ?? Int.max
                return left != right ? left < right : lhs.offset < rhs.offset
            }
            .map(\.element)
        payload.familyMembers.sort()
        return payload
    }

    /// The records to upload: anything missing from the cloud, newer than the cloud
    /// copy, or a deletion of an item edited at the same moment.
    static func changes(desired: [String: SyncRecord], current: [String: SyncRecord]) -> [SyncRecord] {
        desired.values
            .filter { record in
                guard let existing = current[record.name] else { return true }
                if record.updatedAt != existing.updatedAt {
                    return record.updatedAt > existing.updatedAt
                }
                return record.kind == .deleted && existing.kind != .deleted
            }
            .sorted { $0.name < $1.name }
    }

    /// Deleted markers old enough that every device has forgotten the deletion too.
    static func expiredDeletions(in records: [SyncRecord], now: Date = Date()) -> [String] {
        let cutoff = now.addingTimeInterval(-SyncLedger.retention)
        return records
            .filter { $0.kind == .deleted && $0.updatedAt < cutoff }
            .map(\.name)
            .sorted()
    }
}
