import Foundation

@MainActor
final class OrganizerStore: ObservableObject {
    /// The app-wide store. Background work must use this instance too, so there is
    /// only ever one in-memory copy writing the organizer files.
    static let shared = OrganizerStore()

    @Published private(set) var shops: [Shop] = [] {
        didSet { recordRemovals(from: oldValue, to: shops); saveShopping() }
    }

    @Published private(set) var shoppingItems: [ShoppingItem] = [] {
        didSet { recordRemovals(from: oldValue, to: shoppingItems); saveShopping() }
    }

    @Published private(set) var recurringTasks: [RecurringTask] = [] {
        didSet { recordRemovals(from: oldValue, to: recurringTasks); saveRecurringTasks() }
    }

    @Published private(set) var mealIdeas: [MealIdea] = [] {
        didSet { recordRemovals(from: oldValue, to: mealIdeas); saveMealPlan() }
    }

    @Published private(set) var plannedMeals: [PlannedMeal] = [] {
        didSet { recordRemovals(from: oldValue, to: plannedMeals); saveMealPlan() }
    }

    @Published private(set) var ideaNotes: [IdeaNote] = [] {
        didSet { recordRemovals(from: oldValue, to: ideaNotes); saveIdeas() }
    }

    @Published private(set) var healthSnapshots: [HealthSnapshot] = [] {
        didSet { recordRemovals(from: oldValue, to: healthSnapshots); saveHealthSnapshots() }
    }

    private let shoppingURL: URL
    private let recurringTasksURL: URL
    private let mealPlanURL: URL
    private let ideasURL: URL
    private let healthSnapshotsURL: URL
    private var shopOrderUpdatedAt: Date?
    private var isApplyingSharedData = false

    init(directory: URL? = nil) {
        let documents = directory ?? URL.documentsDirectory
        shoppingURL = documents.appendingPathComponent("family-shopping.json")
        recurringTasksURL = documents.appendingPathComponent("family-recurring-tasks.json")
        mealPlanURL = documents.appendingPathComponent("family-meal-plan.json")
        ideasURL = documents.appendingPathComponent("family-ideas.json")
        healthSnapshotsURL = documents.appendingPathComponent("family-health-snapshots.json")
        let fileManager = FileManager.default
        let isFirstShoppingLaunch = !fileManager.fileExists(atPath: shoppingURL.path)
        let isFirstRecurringLaunch = !fileManager.fileExists(atPath: recurringTasksURL.path)
        loadShopping()
        loadRecurringTasks()
        loadMealPlan()
        loadIdeas()
        loadHealthSnapshots()
        seedDefaults(shopping: isFirstShoppingLaunch, recurringTasks: isFirstRecurringLaunch)
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
        markShopOrderChanged()
    }

    func moveShopUp(_ shop: Shop) {
        guard let index = shops.firstIndex(where: { $0.id == shop.id }), index > 0 else { return }
        shops.swapAt(index, index - 1)
        markShopOrderChanged()
    }

    func moveShopDown(_ shop: Shop) {
        guard let index = shops.firstIndex(where: { $0.id == shop.id }), index < shops.index(before: shops.endIndex) else { return }
        shops.swapAt(index, index + 1)
        markShopOrderChanged()
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

    /// Adds several items at once (one save and one sync), skipping any already needed
    /// at the same shop.
    func addNeededItems(_ items: [(name: String, shopID: UUID)]) {
        var updatedItems = shoppingItems
        var updatedShops = shops
        let now = Date()

        for (name, shopID) in items {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let shopIndex = updatedShops.firstIndex(where: { $0.id == shopID }) else { continue }
            let alreadyNeeded = updatedItems.contains { item in
                item.shopID == shopID && item.isNeeded && !item.isPurchased && item.name.caseInsensitiveCompare(trimmed) == .orderedSame
            }
            guard !alreadyNeeded else { continue }

            updatedItems.append(ShoppingItem(name: trimmed, shopID: shopID, createdAt: now, updatedAt: now))
            if !updatedShops[shopIndex].usualItems.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                updatedShops[shopIndex].usualItems.append(trimmed)
                updatedShops[shopIndex].usualItems.sort()
                updatedShops[shopIndex].updatedAt = now
            }
        }

        if updatedShops != shops { shops = updatedShops }
        if updatedItems != shoppingItems { shoppingItems = updatedItems }
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

    /// Marks an item bought as of `date` (a check-off made in a widget), unless it was
    /// already bought or edited after that.
    func markPurchased(itemID: UUID, at date: Date) {
        guard let index = shoppingItems.firstIndex(where: { $0.id == itemID }),
              !shoppingItems[index].isPurchased,
              shoppingItems[index].updatedAt <= date else { return }
        shoppingItems[index].isPurchased = true
        shoppingItems[index].isNeeded = false
        shoppingItems[index].updatedAt = date
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
            guard let shopID = overrides[ingredient.id],
                  let shop = shops.first(where: { $0.id == shopID }) else { continue }
            addNeededItem(ingredient.name, to: shop)
        }
    }

    /// Every ingredient of the meals planned between `start` and `end`, combined.
    func weeklyIngredients(from start: Date, to end: Date) -> [WeeklyIngredient] {
        Self.weeklyIngredients(plannedMeals: plannedMeals, mealIdeas: mealIdeas, shops: shops, shoppingItems: shoppingItems, from: start, to: end)
    }

    /// Combines the ingredients of the planned meals in a date range, once per ingredient
    /// name, with the shop chosen when the meal was planned, else the ingredient's default
    /// shop. Ingredients already on the shopping list are marked so they are not added twice.
    static func weeklyIngredients(
        plannedMeals: [PlannedMeal],
        mealIdeas: [MealIdea],
        shops: [Shop],
        shoppingItems: [ShoppingItem],
        from start: Date,
        to end: Date
    ) -> [WeeklyIngredient] {
        let shopIDs = Set(shops.map(\.id))
        let alreadyNeeded = Set(shoppingItems.filter { $0.isNeeded && !$0.isPurchased }.map { WeeklyIngredient.key(for: $0.name) })
        var ingredientsByKey: [String: WeeklyIngredient] = [:]
        var order: [String] = []

        for planned in plannedMeals.filter({ $0.date >= start && $0.date < end }).sorted(by: { $0.date < $1.date }) {
            guard let meal = mealIdeas.first(where: { $0.id == planned.mealID }) else { continue }
            for ingredient in meal.ingredients {
                let key = WeeklyIngredient.key(for: ingredient.name)
                guard !key.isEmpty else { continue }
                let shopID = [planned.ingredientShopOverrides[ingredient.id], ingredient.defaultShopID]
                    .compactMap { $0 }
                    .first { shopIDs.contains($0) }

                if var existing = ingredientsByKey[key] {
                    existing.shopID = existing.shopID ?? shopID
                    if !existing.mealNames.contains(meal.name) {
                        existing.mealNames.append(meal.name)
                    }
                    ingredientsByKey[key] = existing
                } else {
                    ingredientsByKey[key] = WeeklyIngredient(
                        id: key,
                        name: ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines),
                        shopID: shopID,
                        mealNames: [meal.name],
                        isAlreadyNeeded: alreadyNeeded.contains(key)
                    )
                    order.append(key)
                }
            }
        }

        return order.compactMap { ingredientsByKey[$0] }
    }

    func ideas(tag: String? = nil) -> [IdeaNote] {
        ideaNotes
            .filter { idea in
                guard let tag else { return true }
                return idea.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
            }
            .sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }
    }

    func addIdea(_ draft: IdeaDraft) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        ideaNotes.append(
            IdeaNote(
                title: title,
                notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                link: draft.link.trimmingCharacters(in: .whitespacesAndNewlines),
                tags: draft.normalizedTags
            )
        )
    }

    func updateIdea(_ idea: IdeaNote, with draft: IdeaDraft) {
        guard let index = ideaNotes.firstIndex(where: { $0.id == idea.id }) else { return }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        ideaNotes[index].title = title
        ideaNotes[index].notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        ideaNotes[index].link = draft.link.trimmingCharacters(in: .whitespacesAndNewlines)
        ideaNotes[index].tags = draft.normalizedTags
        ideaNotes[index].updatedAt = Date()
    }

    func deleteIdea(_ idea: IdeaNote) {
        ideaNotes.removeAll { $0.id == idea.id }
    }

    func upsertHealthSnapshots(_ snapshots: [HealthSnapshot]) {
        guard !snapshots.isEmpty else { return }
        healthSnapshots = mergedHealthSnapshots(existing: healthSnapshots, incoming: snapshots)
    }

    func healthSnapshots(for scope: HealthMetricScope, calendar: Calendar = .current) -> [HealthSnapshot] {
        let now = Date()
        let start: Date
        switch scope {
        case .day:
            start = calendar.startOfDay(for: now)
        case .week:
            start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        case .month:
            start = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        case .year:
            start = calendar.dateInterval(of: .year, for: now)?.start ?? calendar.startOfDay(for: now)
        }

        return healthSnapshots
            .filter { $0.date >= start && $0.date <= now }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date < rhs.date }
                return lhs.displayInitials.localizedCaseInsensitiveCompare(rhs.displayInitials) == .orderedAscending
            }
    }

    var visibleRecurringTasks: [RecurringTask] {
        recurringTasks.filter { $0.isVisible(to: Self.currentProfileEmailValue()) }
    }

    func addRecurringTask(_ draft: RecurringTaskDraft) {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let assignment = normalizedRecurringAssignment(from: draft)
        recurringTasks.append(
            RecurringTask(
                title: title,
                notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: draft.amount.trimmingCharacters(in: .whitespacesAndNewlines),
                frequency: draft.frequency,
                nextDueDate: draft.nextDueDate,
                assignedTo: assignment.primaryValue,
                assignedToEmails: assignment.emails,
                createdBy: Self.currentProfileEmailValue(),
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
        let assignment = normalizedRecurringAssignment(from: draft)
        recurringTasks[index].assignedTo = assignment.primaryValue
        recurringTasks[index].assignedToEmails = assignment.emails
        if recurringTasks[index].createdBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recurringTasks[index].createdBy = Self.currentProfileEmailValue()
        }
        recurringTasks[index].notificationPreference = draft.notificationPreference
        recurringTasks[index].updatedAt = Date()
    }

    func recurringTasks(on date: Date, calendar: Calendar = .current) -> [RecurringTask] {
        visibleRecurringTasks
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
        recurringTasks[index].nextDueDate = nextOccurrence(afterCompleting: task)
        recurringTasks[index].updatedAt = Date()
    }

    /// Advances along the task's own schedule (keeping its day and time) to the first
    /// occurrence after now, rather than restarting the schedule from the moment it was
    /// marked done.
    private func nextOccurrence(afterCompleting task: RecurringTask, calendar: Calendar = .current) -> Date {
        let now = Date()
        var next = task.frequency.nextDate(after: task.nextDueDate, calendar: calendar)
        var safetyLimit = 1_000
        while next <= now && safetyLimit > 0 {
            let candidate = task.frequency.nextDate(after: next, calendar: calendar)
            guard candidate > next else { break }
            next = candidate
            safetyLimit -= 1
        }
        return next
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
            guard task.assigneeEmails.contains(where: { $0.caseInsensitiveCompare(normalizedAssignee) == .orderedSame }) else {
                return task
            }

            var updated = task
            updated.assignedToEmails.removeAll { $0.caseInsensitiveCompare(normalizedAssignee) == .orderedSame }
            if updated.assignedTo.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(normalizedAssignee) == .orderedSame {
                updated.assignedTo = updated.assignedToEmails.first ?? ""
            }
            updated.updatedAt = Date()
            return updated
        }
    }

    /// Only seeds examples on first launch; an empty list later means the user cleared it.
    private func seedDefaults(shopping: Bool, recurringTasks seedRecurring: Bool) {
        if shopping {
            let costco = Shop(name: "Costco", usualItems: ["Milk", "Eggs", "Paper towels"])
            let target = Shop(name: "Target", usualItems: ["Laundry detergent", "Toothpaste"])
            let grocery = Shop(name: "Grocery", usualItems: ["Bananas", "Bread", "Yogurt"])
            shops = [costco, target, grocery]
            shoppingItems = [
                ShoppingItem(name: "Milk", shopID: costco.id),
                ShoppingItem(name: "Bananas", shopID: grocery.id)
            ]
        }

        if seedRecurring {
            recurringTasks = [
                RecurringTask(title: "Pay gardener", amount: "$", frequency: .monthly, nextDueDate: Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()),
                RecurringTask(title: "Mortgage payment", frequency: .monthly, nextDueDate: Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date())
            ]
        }
    }

    private func loadShopping() {
        guard let data = try? Data(contentsOf: shoppingURL) else { return }
        guard let payload = try? JSONDecoder().decode(ShoppingPayload.self, from: data) else {
            PersistenceBackup.preserveUnreadableFile(at: shoppingURL)
            return
        }
        shopOrderUpdatedAt = payload.orderUpdatedAt
        if shops != payload.shops {
            shops = payload.shops
        }
        if shoppingItems != payload.items {
            shoppingItems = payload.items
        }
    }

    private func saveShopping() {
        let payload = ShoppingPayload(shops: shops, items: shoppingItems, orderUpdatedAt: shopOrderUpdatedAt)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: shoppingURL, options: [.atomic])
        notifySharedDataChanged()
    }

    private func loadRecurringTasks() {
        guard let data = try? Data(contentsOf: recurringTasksURL) else { return }
        do {
            recurringTasks = try JSONDecoder().decode([RecurringTask].self, from: data)
        } catch {
            PersistenceBackup.preserveUnreadableFile(at: recurringTasksURL)
        }
    }

    private func saveRecurringTasks() {
        guard let data = try? JSONEncoder().encode(recurringTasks) else { return }
        try? data.write(to: recurringTasksURL, options: [.atomic])
        notifySharedDataChanged()
    }

    private func loadMealPlan() {
        guard let data = try? Data(contentsOf: mealPlanURL) else { return }
        guard let payload = try? JSONDecoder().decode(MealPlanPayload.self, from: data) else {
            PersistenceBackup.preserveUnreadableFile(at: mealPlanURL)
            return
        }
        mealIdeas = payload.mealIdeas
        plannedMeals = payload.plannedMeals
    }

    private func saveMealPlan() {
        let payload = MealPlanPayload(mealIdeas: mealIdeas, plannedMeals: plannedMeals)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: mealPlanURL, options: [.atomic])
        notifySharedDataChanged()
    }

    private func loadIdeas() {
        guard let data = try? Data(contentsOf: ideasURL) else { return }
        guard let notes = try? JSONDecoder().decode([IdeaNote].self, from: data) else {
            PersistenceBackup.preserveUnreadableFile(at: ideasURL)
            return
        }
        ideaNotes = notes
    }

    private func saveIdeas() {
        guard let data = try? JSONEncoder().encode(ideaNotes) else { return }
        try? data.write(to: ideasURL, options: [.atomic])
        notifySharedDataChanged()
    }

    private func loadHealthSnapshots() {
        guard let data = try? Data(contentsOf: healthSnapshotsURL),
              let snapshots = try? JSONDecoder().decode([HealthSnapshot].self, from: data) else { return }
        healthSnapshots = snapshots
    }

    private func saveHealthSnapshots() {
        guard let data = try? JSONEncoder().encode(healthSnapshots) else { return }
        try? data.write(to: healthSnapshotsURL, options: [.atomic])
        notifySharedDataChanged()
    }

    func exportShoppingPayload() -> ShoppingPayload {
        ShoppingPayload(shops: shops, items: shoppingItems, orderUpdatedAt: shopOrderUpdatedAt)
    }

    func exportMealPlanPayload() -> MealPlanPayload {
        MealPlanPayload(mealIdeas: mealIdeas, plannedMeals: plannedMeals)
    }

    func exportRecurringTasks() -> [RecurringTask] {
        recurringTasks
    }

    func exportVisibleRecurringTasks() -> [RecurringTask] {
        visibleRecurringTasks
    }

    func exportIdeas() -> [IdeaNote] {
        ideaNotes
    }

    func exportHealthSnapshots() -> [HealthSnapshot] {
        healthSnapshots
    }

    /// Only assigns what changed, so a sync with nothing new does not rewrite files or redraw views.
    func applySharedData(shopping: ShoppingPayload, recurringTasks: [RecurringTask], mealPlan: MealPlanPayload, ideas: [IdeaNote], healthSnapshots: [HealthSnapshot]) {
        isApplyingSharedData = true
        let shoppingChanged = shops != shopping.shops || shoppingItems != shopping.items
        if shopOrderUpdatedAt != shopping.orderUpdatedAt {
            shopOrderUpdatedAt = shopping.orderUpdatedAt
            if !shoppingChanged { saveShopping() }
        }
        if shops != shopping.shops { shops = shopping.shops }
        if shoppingItems != shopping.items { shoppingItems = shopping.items }
        if self.recurringTasks != recurringTasks { self.recurringTasks = recurringTasks }
        if mealIdeas != mealPlan.mealIdeas { mealIdeas = mealPlan.mealIdeas }
        if plannedMeals != mealPlan.plannedMeals { plannedMeals = mealPlan.plannedMeals }
        if ideaNotes != ideas { ideaNotes = ideas }
        let snapshots = mergedHealthSnapshots(existing: self.healthSnapshots, incoming: healthSnapshots)
        if self.healthSnapshots != snapshots { self.healthSnapshots = snapshots }
        isApplyingSharedData = false
    }

    private func markShopOrderChanged() {
        shopOrderUpdatedAt = Date()
        saveShopping()
    }

    private func recordRemovals<Item: SyncMergeable>(from oldItems: [Item], to newItems: [Item]) {
        guard !isApplyingSharedData else { return }
        SyncLedger.shared.recordRemovals(from: oldItems, to: newItems)
    }

    private func notifySharedDataChanged() {
        guard !isApplyingSharedData else { return }
        NotificationCenter.default.post(name: .familyDataDidChange, object: self)
    }

    private func mergedHealthSnapshots(existing: [HealthSnapshot], incoming: [HealthSnapshot]) -> [HealthSnapshot] {
        var snapshotsByID: [String: HealthSnapshot] = [:]

        for snapshot in existing + incoming {
            guard !snapshot.memberEmail.isEmpty else { continue }
            if let current = snapshotsByID[snapshot.id], current.updatedAt > snapshot.updatedAt {
                continue
            }
            snapshotsByID[snapshot.id] = snapshot
        }

        let cutoff = Calendar.current.date(byAdding: .day, value: -400, to: Date()) ?? .distantPast
        return snapshotsByID.values
            .filter { $0.date >= cutoff }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date < rhs.date }
                return lhs.memberEmail.localizedCaseInsensitiveCompare(rhs.memberEmail) == .orderedAscending
            }
    }

    private func cleanedIngredients(_ values: [MealIngredient]) -> [MealIngredient] {
        values.compactMap { ingredient in
            let trimmed = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return MealIngredient(id: ingredient.id, name: trimmed, defaultShopID: ingredient.defaultShopID)
        }
    }

    private static func currentProfileEmailValue() -> String {
        UserDefaults.standard.string(forKey: "profile.email")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private func normalizedRecurringAssignment(from draft: RecurringTaskDraft) -> (primaryValue: String, emails: [String]) {
        if draft.assignsToEveryone {
            return (Assignee.everyone, [])
        }

        var emails = FamilyTask.normalizedAssigneeEmails(draft.assignedToEmails, legacyAssignedTo: draft.assignedTo)
        let creator = Self.currentProfileEmailValue()
        if TaskStore.isValidEmail(creator), !emails.contains(where: { $0.caseInsensitiveCompare(creator) == .orderedSame }) {
            emails.append(creator)
            emails.sort()
        }
        return (emails.first ?? "", emails)
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

/// One ingredient on the "Shop for This Week" list.
struct WeeklyIngredient: Identifiable, Equatable {
    /// The ingredient name ignoring case, accents and surrounding spaces, so "Onions" and "onions " combine.
    var id: String
    var name: String
    var shopID: UUID?
    /// The meals that use it, in the order they are planned.
    var mealNames: [String]
    var isAlreadyNeeded: Bool

    static func key(for name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

struct ShoppingPayload: Codable {
    var shops: [Shop]
    var items: [ShoppingItem]
    var orderUpdatedAt: Date?
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
    var assignedTo = Assignee.everyone
    var assignedToEmails: [String] = []
    var assignsToEveryone = true
    var notificationPreference = TaskNotificationPreference()

    init() {}

    init(task: RecurringTask) {
        title = task.title
        notes = task.notes
        amount = task.amount
        frequency = task.frequency
        nextDueDate = task.nextDueDate
        assignedTo = task.assignedTo
        assignedToEmails = task.assigneeEmails
        assignsToEveryone = task.isAssignedToEveryone
        notificationPreference = task.notificationPreference ?? TaskNotificationPreference()
    }
}
