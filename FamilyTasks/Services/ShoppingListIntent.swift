import AppIntents
import Foundation

struct ShopEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Shop"
    static let defaultQuery = ShopQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ShopQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [ShopEntity] {
        shops().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [ShopEntity] {
        shops().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [ShopEntity] {
        shops()
    }

    @MainActor
    private func shops() -> [ShopEntity] {
        OrganizerStore.shared.shops.map { ShopEntity(id: $0.id, name: $0.name) }
    }
}

struct AddShoppingItemIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Shopping Item"
    static let description = IntentDescription("Adds an item to the Family Tasks shopping list.")
    static let openAppWhenRun = false

    @Parameter(title: "Item")
    var itemName: String

    @Parameter(title: "Shop", description: "Leave empty to use your first shop.")
    var shop: ShopEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$itemName) to \(\.$shop)")
    }

    /// Runs in the app's process (launched in the background if needed), so it edits the
    /// same store the app uses and the item reaches the family straight away.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let item = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.isEmpty else {
            return .result(dialog: "Tell me which item to add.")
        }

        let store = OrganizerStore.shared
        if store.shops.isEmpty {
            store.addShop(named: "Shopping")
        }
        guard let target = shop.flatMap({ chosen in store.shops.first { $0.id == chosen.id } }) ?? store.shops.first else {
            return .result(dialog: "I couldn't find a shopping list to add to.")
        }

        store.addNeededItem(item, to: target)
        await SharedHouseholdStore.shared.uploadNow(waitingAtMost: .seconds(8))
        return .result(dialog: "Added \(item) to \(target.name).")
    }
}
