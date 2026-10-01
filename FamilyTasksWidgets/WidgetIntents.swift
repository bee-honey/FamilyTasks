import AppIntents
import WidgetKit

/// Checks a task off from the Today widget.
struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Task"
    static let isDiscoverable = false

    @Parameter(title: "Task")
    var taskID: String

    init() {}

    init(taskID: UUID) {
        self.taskID = taskID.uuidString
    }

    func perform() async throws -> some IntentResult {
        WidgetCheckOff.record(.completeTask, id: taskID)
        return .result()
    }
}

/// Checks a shopping item off from the Shopping widget.
struct PurchaseItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Item Bought"
    static let isDiscoverable = false

    @Parameter(title: "Item")
    var itemID: String

    init() {}

    init(itemID: UUID) {
        self.itemID = itemID.uuidString
    }

    func perform() async throws -> some IntentResult {
        WidgetCheckOff.record(.purchaseItem, id: itemID)
        return .result()
    }
}

enum WidgetCheckOff {
    /// Queues the check-off for the app and hides it from the widgets right away.
    static func record(_ kind: WidgetAction.Kind, id: String) {
        guard let uuid = UUID(uuidString: id), let storage = WidgetStorage.shared else { return }
        let action = WidgetAction(kind: kind, id: uuid, date: Date())
        try? storage.record(action)

        var snapshot = storage.loadSnapshot()
        snapshot.apply(action)
        storage.save(snapshot)
    }
}

struct ShopEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Shop"
    static let defaultQuery = ShopQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ShopQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ShopEntity] {
        allShops().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ShopEntity] {
        allShops()
    }

    private func allShops() -> [ShopEntity] {
        (WidgetStorage.shared?.loadSnapshot().shops ?? []).map { ShopEntity(id: $0.id.uuidString, name: $0.name) }
    }
}

struct SelectShopIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Shop"
    static let description = IntentDescription("Show what's needed at one shop.")

    @Parameter(title: "Shop")
    var shop: ShopEntity?

    init() {}
}
