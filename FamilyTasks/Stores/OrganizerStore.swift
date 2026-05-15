import Foundation

@MainActor
final class OrganizerStore: ObservableObject {
    @Published private(set) var shops: [Shop] = [] {
        didSet { saveShopping() }
    }

    @Published private(set) var shoppingItems: [ShoppingItem] = [] {
        didSet { saveShopping() }
    }

    @Published private(set) var recurringTasks: [RecurringTask] = [] {
        didSet { saveRecurringTasks() }
    }

    private let shoppingURL: URL
    private let recurringTasksURL: URL

    init(directory: URL? = nil) {
        let documents = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        shoppingURL = documents.appendingPathComponent("family-shopping.json")
        recurringTasksURL = documents.appendingPathComponent("family-recurring-tasks.json")
        loadShopping()
        loadRecurringTasks()
        seedDefaultsIfNeeded()
    }

    func items(for shop: Shop) -> [ShoppingItem] {
        shoppingItems
            .filter { $0.shopID == shop.id }
            .sorted { lhs, rhs in
                if lhs.isPurchased != rhs.isPurchased {
                    return !lhs.isPurchased
                }
                if lhs.isNeeded != rhs.isNeeded {
                    return lhs.isNeeded
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    func addShop(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !shops.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        shops.append(Shop(name: trimmed))
    }

    func moveShop(id movingID: UUID, before targetID: UUID) {
        guard movingID != targetID,
              let sourceIndex = shops.firstIndex(where: { $0.id == movingID }),
              let targetIndex = shops.firstIndex(where: { $0.id == targetID }) else { return }

        let movingShop = shops.remove(at: sourceIndex)
        let adjustedTargetIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        shops.insert(movingShop, at: adjustedTargetIndex)
    }

    func addUsualItem(_ itemName: String, to shop: Shop) {
        let trimmed = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = shops.firstIndex(where: { $0.id == shop.id }) else { return }
        guard !shops[index].usualItems.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        shops[index].usualItems.append(trimmed)
        shops[index].usualItems.sort()
        shops[index].updatedAt = Date()
    }

    func deleteUsualItem(_ itemName: String, from shop: Shop) {
        guard let index = shops.firstIndex(where: { $0.id == shop.id }) else { return }
        shops[index].usualItems.removeAll { $0.caseInsensitiveCompare(itemName) == .orderedSame }
        shops[index].updatedAt = Date()
    }

    func addNeededItem(_ itemName: String, to shop: Shop) {
        let trimmed = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        shoppingItems.append(ShoppingItem(name: trimmed, shopID: shop.id))
        addUsualItem(trimmed, to: shop)
    }

    func toggleNeeded(_ item: ShoppingItem) {
        guard let index = shoppingItems.firstIndex(where: { $0.id == item.id }) else { return }
        shoppingItems[index].isNeeded.toggle()
        shoppingItems[index].updatedAt = Date()
    }

    func togglePurchased(_ item: ShoppingItem) {
        guard let index = shoppingItems.firstIndex(where: { $0.id == item.id }) else { return }
        shoppingItems[index].isPurchased.toggle()
        shoppingItems[index].isNeeded = !shoppingItems[index].isPurchased
        shoppingItems[index].updatedAt = Date()
    }

    func deleteShoppingItem(_ item: ShoppingItem) {
        shoppingItems.removeAll { $0.id == item.id }
    }

    func move(_ item: ShoppingItem, to shop: Shop) {
        guard let index = shoppingItems.firstIndex(where: { $0.id == item.id }) else { return }
        shoppingItems[index].shopID = shop.id
        shoppingItems[index].updatedAt = Date()
        addUsualItem(item.name, to: shop)
    }

    func closeTrip(for shop: Shop) {
        shoppingItems.removeAll { $0.shopID == shop.id && $0.isPurchased }
    }

    func addRecurringTask(_ draft: RecurringTaskDraft) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        recurringTasks.append(
            RecurringTask(
                title: title,
                notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: draft.amount.trimmingCharacters(in: .whitespacesAndNewlines),
                frequency: draft.frequency,
                nextDueDate: draft.nextDueDate,
                assignedTo: draft.assignedTo.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
    }

    func toggleRecurringActive(_ task: RecurringTask) {
        guard let index = recurringTasks.firstIndex(where: { $0.id == task.id }) else { return }
        recurringTasks[index].isActive.toggle()
        recurringTasks[index].updatedAt = Date()
    }

    func markRecurringDone(_ task: RecurringTask) {
        guard let index = recurringTasks.firstIndex(where: { $0.id == task.id }) else { return }
        recurringTasks[index].nextDueDate = task.frequency.nextDate(after: max(task.nextDueDate, Date()))
        recurringTasks[index].updatedAt = Date()
    }

    func deleteRecurringTask(at offsets: IndexSet) {
        recurringTasks.remove(atOffsets: offsets)
    }

    func deleteRecurringTask(_ task: RecurringTask) {
        recurringTasks.removeAll { $0.id == task.id }
    }

    private func seedDefaultsIfNeeded() {
        if shops.isEmpty {
            let costco = Shop(name: "Costco", usualItems: ["Milk", "Eggs", "Paper towels"])
            let target = Shop(name: "Target", usualItems: ["Laundry detergent", "Toothpaste"])
            let grocery = Shop(name: "Grocery", usualItems: ["Bananas", "Bread", "Yogurt"])
            shops = [costco, target, grocery]
            shoppingItems = [
                ShoppingItem(name: "Milk", shopID: costco.id),
                ShoppingItem(name: "Bananas", shopID: grocery.id)
            ]
        }

        if recurringTasks.isEmpty {
            recurringTasks = [
                RecurringTask(title: "Pay gardener", amount: "$", frequency: .monthly, nextDueDate: Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()),
                RecurringTask(title: "Mortgage payment", frequency: .monthly, nextDueDate: Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date())
            ]
        }
    }

    private func loadShopping() {
        guard let data = try? Data(contentsOf: shoppingURL) else { return }
        guard let payload = try? JSONDecoder().decode(ShoppingPayload.self, from: data) else { return }
        shops = payload.shops
        shoppingItems = payload.items
    }

    private func saveShopping() {
        let payload = ShoppingPayload(shops: shops, items: shoppingItems)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: shoppingURL, options: [.atomic])
    }

    private func loadRecurringTasks() {
        guard let data = try? Data(contentsOf: recurringTasksURL) else { return }
        recurringTasks = (try? JSONDecoder().decode([RecurringTask].self, from: data)) ?? []
    }

    private func saveRecurringTasks() {
        guard let data = try? JSONEncoder().encode(recurringTasks) else { return }
        try? data.write(to: recurringTasksURL, options: [.atomic])
    }
}

private struct ShoppingPayload: Codable {
    var shops: [Shop]
    var items: [ShoppingItem]
}

struct RecurringTaskDraft {
    var title = ""
    var notes = ""
    var amount = ""
    var frequency: RecurrenceFrequency = .monthly
    var nextDueDate = Date()
    var assignedTo = ""
}
