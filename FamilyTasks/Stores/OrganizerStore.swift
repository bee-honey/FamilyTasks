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

    @Published private(set) var mealIdeas: [MealIdea] = [] {
        didSet { saveMealPlan() }
    }

    @Published private(set) var plannedMeals: [PlannedMeal] = [] {
        didSet { saveMealPlan() }
    }

    private let shoppingURL: URL
    private let recurringTasksURL: URL
    private let mealPlanURL: URL
    private var isApplyingSharedData = false

    init(directory: URL? = nil) {
        let documents = directory ?? URL.documentsDirectory
        shoppingURL = documents.appendingPathComponent("family-shopping.json")
        recurringTasksURL = documents.appendingPathComponent("family-recurring-tasks.json")
        mealPlanURL = documents.appendingPathComponent("family-meal-plan.json")
        loadShopping()
        loadRecurringTasks()
        loadMealPlan()
        seedDefaultsIfNeeded()
    }

    func refreshShopping() {
        loadShopping()
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

    func updateShop(_ shop: Shop, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = shops.firstIndex(where: { $0.id == shop.id }) else { return }
        guard !shops.contains(where: { candidate in
            candidate.id != shop.id && candidate.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }) else { return }

        shops[index].name = trimmed
        shops[index].updatedAt = Date()
    }

    func moveShop(id movingID: UUID, before targetID: UUID) {
        guard movingID != targetID,
              let sourceIndex = shops.firstIndex(where: { $0.id == movingID }),
              let targetIndex = shops.firstIndex(where: { $0.id == targetID }) else { return }

        let movingShop = shops.remove(at: sourceIndex)
        let adjustedTargetIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        shops.insert(movingShop, at: adjustedTargetIndex)
    }

    func moveShopUp(_ shop: Shop) {
        guard let index = shops.firstIndex(where: { $0.id == shop.id }), index > 0 else { return }
        shops.swapAt(index, index - 1)
    }

    func moveShopDown(_ shop: Shop) {
        guard let index = shops.firstIndex(where: { $0.id == shop.id }), index < shops.index(before: shops.endIndex) else { return }
        shops.swapAt(index, index + 1)
    }

    func deleteShop(_ shop: Shop) {
        shops.removeAll { $0.id == shop.id }
        shoppingItems.removeAll { $0.shopID == shop.id }
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

    func addMealIdea(name: String, category: MealCategory, ingredients: [MealIngredient], notes: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let cleanedIngredients = cleanedIngredients(ingredients)
        let cleanedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        mealIdeas.append(MealIdea(name: trimmedName, category: category, ingredients: cleanedIngredients, notes: cleanedNotes))
        mealIdeas.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func updateMealIdea(_ meal: MealIdea, name: String, category: MealCategory, ingredients: [MealIngredient], notes: String) {
        guard let index = mealIdeas.firstIndex(where: { $0.id == meal.id }) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        mealIdeas[index].name = trimmedName
        mealIdeas[index].category = category
        mealIdeas[index].ingredients = cleanedIngredients(ingredients)
        mealIdeas[index].notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        mealIdeas[index].updatedAt = Date()
        mealIdeas.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func deleteMealIdea(_ meal: MealIdea) {
        mealIdeas.removeAll { $0.id == meal.id }
        plannedMeals.removeAll { $0.mealID == meal.id }
    }

    func planMeal(_ meal: MealIdea, on date: Date, slot: MealSlot, ingredientShopOverrides: [UUID: UUID], addIngredientsToShopping: Bool) {
        plannedMeals.append(PlannedMeal(mealID: meal.id, date: date, slot: slot, ingredientShopOverrides: ingredientShopOverrides))
        plannedMeals.sort { $0.date < $1.date }

        if addIngredientsToShopping {
            addMealIngredientsToShopping(meal, overrides: ingredientShopOverrides)
        }
    }

    func deletePlannedMeal(_ plannedMeal: PlannedMeal) {
        plannedMeals.removeAll { $0.id == plannedMeal.id }
    }

    func mealIdea(for plannedMeal: PlannedMeal) -> MealIdea? {
        mealIdeas.first { $0.id == plannedMeal.mealID }
    }

    func addMealIngredientsToShopping(_ meal: MealIdea, shop: Shop) {
        meal.ingredients.forEach { addNeededItem($0.name, to: shop) }
    }

    func addMealIngredientsToShopping(_ meal: MealIdea, overrides: [UUID: UUID]) {
        for ingredient in meal.ingredients {
            guard let shopID = overrides[ingredient.id] ?? ingredient.defaultShopID,
                  let shop = shops.first(where: { $0.id == shopID }) else { continue }
            addNeededItem(ingredient.name, to: shop)
        }
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
                assignedTo: draft.assignedTo.trimmingCharacters(in: .whitespacesAndNewlines),
                notificationPreference: draft.notificationPreference
            )
        )
    }

    func updateRecurringTask(_ task: RecurringTask, with draft: RecurringTaskDraft) {
        guard let index = recurringTasks.firstIndex(where: { $0.id == task.id }) else { return }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        recurringTasks[index].title = title
        recurringTasks[index].notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        recurringTasks[index].amount = draft.amount.trimmingCharacters(in: .whitespacesAndNewlines)
        recurringTasks[index].frequency = draft.frequency
        recurringTasks[index].nextDueDate = draft.nextDueDate
        recurringTasks[index].assignedTo = draft.assignedTo.trimmingCharacters(in: .whitespacesAndNewlines)
        recurringTasks[index].notificationPreference = draft.notificationPreference
        recurringTasks[index].updatedAt = Date()
    }

    func recurringTasks(on date: Date, calendar: Calendar = .current) -> [RecurringTask] {
        recurringTasks
            .filter { task in
                guard task.isActive else { return false }
                guard let occurrence = occurrence(for: task, on: date, calendar: calendar) else { return false }
                return calendar.isDate(occurrence, inSameDayAs: date)
            }
            .sorted { lhs, rhs in
                if lhs.nextDueDate != rhs.nextDueDate {
                    return lhs.nextDueDate < rhs.nextDueDate
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
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

    func clearRecurringAssignee(_ assignee: String) {
        let normalizedAssignee = assignee.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedAssignee.isEmpty else { return }

        recurringTasks = recurringTasks.map { task in
            guard task.assignedTo.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedAssignee else {
                return task
            }

            var updated = task
            updated.assignedTo = ""
            updated.updatedAt = Date()
            return updated
        }
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
        notifySharedDataChanged()
    }

    private func loadRecurringTasks() {
        guard let data = try? Data(contentsOf: recurringTasksURL) else { return }
        recurringTasks = (try? JSONDecoder().decode([RecurringTask].self, from: data)) ?? []
    }

    private func saveRecurringTasks() {
        guard let data = try? JSONEncoder().encode(recurringTasks) else { return }
        try? data.write(to: recurringTasksURL, options: [.atomic])
        notifySharedDataChanged()
    }

    private func loadMealPlan() {
        guard let data = try? Data(contentsOf: mealPlanURL) else { return }
        guard let payload = try? JSONDecoder().decode(MealPlanPayload.self, from: data) else { return }
        mealIdeas = payload.mealIdeas
        plannedMeals = payload.plannedMeals
    }

    private func saveMealPlan() {
        let payload = MealPlanPayload(mealIdeas: mealIdeas, plannedMeals: plannedMeals)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: mealPlanURL, options: [.atomic])
        notifySharedDataChanged()
    }

    func exportShoppingPayload() -> ShoppingPayload {
        ShoppingPayload(shops: shops, items: shoppingItems)
    }

    func exportMealPlanPayload() -> MealPlanPayload {
        MealPlanPayload(mealIdeas: mealIdeas, plannedMeals: plannedMeals)
    }

    func exportRecurringTasks() -> [RecurringTask] {
        recurringTasks
    }

    func applySharedData(shopping: ShoppingPayload, recurringTasks: [RecurringTask], mealPlan: MealPlanPayload) {
        isApplyingSharedData = true
        shops = shopping.shops
        shoppingItems = shopping.items
        self.recurringTasks = recurringTasks
        mealIdeas = mealPlan.mealIdeas
        plannedMeals = mealPlan.plannedMeals
        saveShopping()
        saveRecurringTasks()
        saveMealPlan()
        isApplyingSharedData = false
    }

    private func notifySharedDataChanged() {
        guard !isApplyingSharedData else { return }
        NotificationCenter.default.post(name: .familyDataDidChange, object: self)
    }

    private func cleanedIngredients(_ values: [MealIngredient]) -> [MealIngredient] {
        values.compactMap { ingredient in
            let trimmed = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return MealIngredient(id: ingredient.id, name: trimmed, defaultShopID: ingredient.defaultShopID)
        }
    }

    private func occurrence(for task: RecurringTask, on date: Date, calendar: Calendar) -> Date? {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        var occurrence = task.nextDueDate

        guard occurrence < dayEnd else { return nil }

        var safetyLimit = 1_000
        while occurrence < dayStart && safetyLimit > 0 {
            let next = task.frequency.nextDate(after: occurrence, calendar: calendar)
            guard next > occurrence else { return nil }
            occurrence = next
            safetyLimit -= 1
        }

        return occurrence
    }
}

struct ShoppingPayload: Codable {
    var shops: [Shop]
    var items: [ShoppingItem]
}

struct MealPlanPayload: Codable {
    var mealIdeas: [MealIdea]
    var plannedMeals: [PlannedMeal]
}

struct RecurringTaskDraft {
    var title = ""
    var notes = ""
    var amount = ""
    var frequency: RecurrenceFrequency = .monthly
    var nextDueDate = Date()
    var assignedTo = ""
    var notificationPreference = TaskNotificationPreference()

    init() {}

    init(task: RecurringTask) {
        title = task.title
        notes = task.notes
        amount = task.amount
        frequency = task.frequency
        nextDueDate = task.nextDueDate
        assignedTo = task.assignedTo
        notificationPreference = task.notificationPreference ?? TaskNotificationPreference()
    }
}
