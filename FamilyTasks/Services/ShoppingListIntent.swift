import AppIntents
import Foundation

struct AddShoppingItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Shopping Item"
    static var description = IntentDescription("Adds an item to the Family Tasks shopping list.")
    static var openAppWhenRun = false

    @Parameter(title: "Item")
    var itemName: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$itemName) to the shopping list")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let item = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.isEmpty else {
            return .result(dialog: "Tell me which item to add.")
        }

        let shopName = try ShoppingListIntentStore.addNeededItem(item)
        return .result(dialog: "Added \(item) to \(shopName).")
    }
}

struct FamilyTasksShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddShoppingItemIntent(),
            phrases: [
                "Add to my shopping list in \(.applicationName)",
                "Add shopping item in \(.applicationName)",
                "Use \(.applicationName) to add to my shopping list"
            ],
            shortTitle: "Add Shopping Item",
            systemImageName: "cart.badge.plus"
        )
    }
}

private enum ShoppingListIntentStore {
    static func addNeededItem(_ itemName: String) throws -> String {
        let storageURL = URL.documentsDirectory.appendingPathComponent("family-shopping.json")
        var payload = loadPayload(from: storageURL)

        if payload.shops.isEmpty {
            payload.shops = [Shop(name: "Shopping")]
        }

        let shop = payload.shops[0]
        payload.items.append(ShoppingItem(name: itemName, shopID: shop.id))

        if let index = payload.shops.firstIndex(where: { $0.id == shop.id }) {
            if !payload.shops[index].usualItems.contains(where: { $0.caseInsensitiveCompare(itemName) == .orderedSame }) {
                payload.shops[index].usualItems.append(itemName)
                payload.shops[index].usualItems.sort()
            }
            payload.shops[index].updatedAt = Date()
        }

        let data = try JSONEncoder().encode(payload)
        try data.write(to: storageURL, options: [.atomic])
        UserDefaults.standard.set(true, forKey: FamilySharingDefaults.localIntentChangeFlagKey)
        return shop.name
    }

    private static func loadPayload(from url: URL) -> ShoppingPayload {
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(ShoppingPayload.self, from: data) else {
            return ShoppingPayload(shops: [], items: [])
        }
        return payload
    }
}
