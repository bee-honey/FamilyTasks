import Foundation

/// Spending and budgets. "Family" items sync with the household; "Just me" items are kept
/// in a separate file that is never shared, and switching an item to "Just me" removes it
/// from everyone else's phones.
@MainActor
final class BudgetStore: ObservableObject {
    static let shared = BudgetStore()

    /// Shared with the family.
    @Published private(set) var familyExpenses: [Expense] = []
    @Published private(set) var familyLimits: [BudgetLimit] = []
    /// Only on this phone.
    @Published private(set) var privateExpenses: [Expense] = []
    @Published private(set) var privateLimits: [BudgetLimit] = []

    private let familyURL: URL
    private let privateURL: URL
    private let ownerEmail: () -> String

    init(directory: URL? = nil, ownerEmail: @escaping () -> String = HabitStore.currentProfileEmail) {
        let directory = directory ?? URL.documentsDirectory
        familyURL = directory.appendingPathComponent("family-budget.json")
        privateURL = directory.appendingPathComponent("private-budget.json")
        self.ownerEmail = ownerEmail
        load()
    }

    // MARK: Reading

    var expenses: [Expense] { familyExpenses + privateExpenses }
    var limits: [BudgetLimit] { familyLimits + privateLimits }

    func expenses(in interval: DateInterval, scope: MoneyScope = .all) -> [Expense] {
        expenses
            .filter { interval.contains($0.date) && scope.includes($0.visibility) }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.createdAt > $1.createdAt }
    }

    func expenses(for trip: Trip) -> [Expense] {
        expenses.filter { $0.tripID == trip.id }.sorted { $0.date < $1.date }
    }

    func expense(forTask taskID: UUID) -> Expense? {
        expenses.first { $0.taskID == taskID }
    }

    /// The month's overall limit (no category), preferring a family one.
    func monthlyLimit(scope: MoneyScope = .all) -> BudgetLimit? {
        limits.filter { $0.isMonthly && $0.category == nil && scope.includes($0.visibility) }
            .sorted { $0.visibility == .family && $1.visibility != .family }
            .first
    }

    func categoryLimit(_ category: SpendingCategory, scope: MoneyScope = .all) -> BudgetLimit? {
        limits.first { $0.isMonthly && $0.category == category && scope.includes($0.visibility) }
    }

    func tripLimit(for trip: Trip) -> BudgetLimit? {
        limits.first { $0.tripID == trip.id }
    }

    // MARK: Expenses

    @discardableResult
    func add(_ expense: Expense) -> Expense? {
        guard expense.amount > 0 else { return nil }
        var new = cleaned(expense)
        if new.paidBy.isEmpty { new.paidBy = ownerEmail() }
        change {
            if new.visibility == .family { familyExpenses.append(new) } else { privateExpenses.append(new) }
        }
        return new
    }

    /// Saves changes, moving it between "Just me" and "Family" if that changed.
    func update(_ expense: Expense) {
        guard let existing = expenses.first(where: { $0.id == expense.id }) else { return }
        var updated = cleaned(expense)
        guard updated != existing else { return }
        updated.updatedAt = Date()
        change {
            familyExpenses.removeAll { $0.id == expense.id }
            privateExpenses.removeAll { $0.id == expense.id }
            if updated.visibility == .family { familyExpenses.append(updated) } else { privateExpenses.append(updated) }
        }
    }

    func delete(_ expense: Expense) {
        change {
            familyExpenses.removeAll { $0.id == expense.id }
            privateExpenses.removeAll { $0.id == expense.id }
        }
    }

    /// A task's cost: adds, changes or (with no amount) removes the expense tied to it.
    func setCost(_ amount: Decimal?, taskID: UUID, title: String, date: Date?, category: SpendingCategory, visibility: MoneyVisibility) {
        let existing = expense(forTask: taskID)
        guard let amount, amount > 0 else {
            if let existing { delete(existing) }
            return
        }
        if var existing {
            existing.title = title
            existing.amount = amount
            existing.category = category
            existing.visibility = visibility
            update(existing)
        } else {
            add(Expense(title: title, amount: amount, date: date ?? Date(), category: category, visibility: visibility, taskID: taskID))
        }
    }

    /// Marks a recurring payment paid: records what it cost (when it has an amount) and moves
    /// it to its next date. Returns the expense recorded.
    @discardableResult
    func markPaid(_ task: RecurringTask, organizer: OrganizerStore, visibility: MoneyVisibility, now: Date = Date()) -> Expense? {
        var recorded: Expense?
        if let amount = Money.parse(task.amount), amount > 0 {
            // Dated when it was due, unless that's still ahead.
            recorded = add(Expense(
                title: task.title,
                amount: amount,
                date: min(task.nextDueDate, now),
                category: .bills,
                visibility: visibility,
                recurringTaskID: task.id
            ))
        }
        organizer.markRecurringDone(task)
        return recorded
    }

    private func cleaned(_ expense: Expense) -> Expense {
        var cleaned = expense
        cleaned.title = expense.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.title.isEmpty { cleaned.title = expense.category.title }
        cleaned.notes = expense.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.amount = expense.amount.rounded(scale: 2)
        return cleaned
    }

    // MARK: Budgets

    /// Sets a limit (monthly overall, monthly for a category, or for a trip). Nil or zero
    /// removes it.
    func setLimit(_ amount: Decimal?, category: SpendingCategory? = nil, tripID: UUID? = nil, visibility: MoneyVisibility) {
        let matches: (BudgetLimit) -> Bool = { $0.category == category && $0.tripID == tripID }
        let existing = limits.first(where: matches)
        change {
            familyLimits.removeAll(where: matches)
            privateLimits.removeAll(where: matches)
            guard let amount, amount > 0 else { return }
            var limit = existing ?? BudgetLimit(category: category, tripID: tripID, amount: amount, visibility: visibility)
            if limit.amount != amount || limit.visibility != visibility { limit.updatedAt = Date() }
            limit.amount = amount.rounded(scale: 2)
            limit.visibility = visibility
            if visibility == .family { familyLimits.append(limit) } else { privateLimits.append(limit) }
        }
    }

    private func change(_ body: () -> Void) {
        let before = exportPayload()
        body()
        let after = exportPayload()
        SyncLedger.shared.recordRemovals(from: before.expenses, to: after.expenses)
        SyncLedger.shared.recordRemovals(from: before.limits, to: after.limits)
        save()
        if before != after {
            NotificationCenter.default.post(name: .familyDataDidChange, object: self)
        }
    }

    // MARK: Family sharing

    /// Only "Family" items: "Just me" ones never leave the phone.
    func exportPayload() -> BudgetPayload {
        BudgetPayload(expenses: familyExpenses, limits: familyLimits)
    }

    func applySharedData(_ payload: BudgetPayload) {
        let expenses = payload.expenses.filter { $0.visibility == .family }
        let limits = payload.limits.filter { $0.visibility == .family }
        var changed = false
        if familyExpenses != expenses { familyExpenses = expenses; changed = true }
        if familyLimits != limits { familyLimits = limits; changed = true }
        if changed { save() }
    }

    // MARK: Storage

    private func load() {
        if let payload = read(familyURL) {
            familyExpenses = payload.expenses
            familyLimits = payload.limits
        }
        if let payload = read(privateURL) {
            privateExpenses = payload.expenses
            privateLimits = payload.limits
        }
    }

    private func read(_ url: URL) -> BudgetPayload? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let payload = try? JSONDecoder().decode(BudgetPayload.self, from: data) else {
            PersistenceBackup.preserveUnreadableFile(at: url)
            return nil
        }
        return payload
    }

    private func save() {
        if let data = try? JSONEncoder().encode(exportPayload()) {
            try? data.write(to: familyURL, options: [.atomic])
        }
        if let data = try? JSONEncoder().encode(BudgetPayload(expenses: privateExpenses, limits: privateLimits)) {
            try? data.write(to: privateURL, options: [.atomic])
        }
    }
}
