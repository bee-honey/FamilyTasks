import Foundation

/// Who can see a money item. "Just me" never leaves this phone; "Family" syncs to everyone
/// in the household.
enum MoneyVisibility: String, Codable, CaseIterable, Identifiable, Sendable {
    case justMe, family

    var id: String { rawValue }

    var title: String { self == .justMe ? "Just Me" : "Family" }
    var systemImage: String { self == .justMe ? "lock.fill" : "person.2.fill" }

    var explanation: String {
        self == .justMe
            ? "Only on this phone. Nobody else in the family sees it."
            : "Everyone in the family sees it."
    }
}

enum SpendingCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case groceries, dining, bills, home, travel, transport, kids, health, shopping, fun, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .groceries: "Groceries"
        case .dining: "Eating Out"
        case .bills: "Bills"
        case .home: "Home"
        case .travel: "Travel"
        case .transport: "Getting Around"
        case .kids: "Kids"
        case .health: "Health"
        case .shopping: "Shopping"
        case .fun: "Fun"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .groceries: "cart"
        case .dining: "fork.knife"
        case .bills: "doc.text"
        case .home: "house"
        case .travel: "airplane"
        case .transport: "car"
        case .kids: "figure.2.and.child.holdinghands"
        case .health: "cross.case"
        case .shopping: "bag"
        case .fun: "ticket"
        case .other: "ellipsis.circle"
        }
    }
}

/// Money spent, optionally tied to what it was for: a trip (and its day), a task, a
/// recurring payment or a shopping trip.
struct Expense: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var title: String
    var amount: Decimal
    var date: Date
    var category: SpendingCategory
    var visibility: MoneyVisibility
    /// Email of whoever added it.
    var paidBy: String
    var notes: String
    var tripID: UUID?
    var taskID: UUID?
    var recurringTaskID: UUID?
    var shopID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        amount: Decimal,
        date: Date = Date(),
        category: SpendingCategory = .other,
        visibility: MoneyVisibility = .justMe,
        paidBy: String = "",
        notes: String = "",
        tripID: UUID? = nil,
        taskID: UUID? = nil,
        recurringTaskID: UUID? = nil,
        shopID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.date = date
        self.category = category
        self.visibility = visibility
        self.paidBy = paidBy
        self.notes = notes
        self.tripID = tripID
        self.taskID = taskID
        self.recurringTaskID = recurringTaskID
        self.shopID = shopID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, amount, date, category, visibility, paidBy, notes, tripID, taskID, recurringTaskID, shopID, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        amount = try container.decodeIfPresent(Decimal.self, forKey: .amount) ?? 0
        date = try container.decode(Date.self, forKey: .date)
        category = (try? container.decodeIfPresent(SpendingCategory.self, forKey: .category)) ?? .other
        visibility = (try? container.decodeIfPresent(MoneyVisibility.self, forKey: .visibility)) ?? .family
        paidBy = try container.decodeIfPresent(String.self, forKey: .paidBy) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        tripID = try container.decodeIfPresent(UUID.self, forKey: .tripID)
        taskID = try container.decodeIfPresent(UUID.self, forKey: .taskID)
        recurringTaskID = try container.decodeIfPresent(UUID.self, forKey: .recurringTaskID)
        shopID = try container.decodeIfPresent(UUID.self, forKey: .shopID)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? date
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

/// A spending limit: for a month overall (no category), for a category each month, or for
/// a whole trip.
struct BudgetLimit: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var category: SpendingCategory?
    var tripID: UUID?
    var amount: Decimal
    var visibility: MoneyVisibility
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        category: SpendingCategory? = nil,
        tripID: UUID? = nil,
        amount: Decimal,
        visibility: MoneyVisibility = .justMe,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.category = category
        self.tripID = tripID
        self.amount = amount
        self.visibility = visibility
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isMonthly: Bool { tripID == nil }
}

/// What the family shares: only "Family" items are ever in it.
struct BudgetPayload: Codable, Equatable, Sendable {
    var expenses: [Expense]
    var limits: [BudgetLimit]

    init(expenses: [Expense] = [], limits: [BudgetLimit] = []) {
        self.expenses = expenses
        self.limits = limits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        expenses = (try? container.decode([Expense].self, forKey: .expenses)) ?? []
        limits = (try? container.decode([BudgetLimit].self, forKey: .limits)) ?? []
    }
}

/// Which money a screen counts.
enum MoneyScope: String, CaseIterable, Identifiable {
    case all, family, justMe

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .family: "Family"
        case .justMe: "Just Me"
        }
    }

    func includes(_ visibility: MoneyVisibility) -> Bool {
        switch self {
        case .all: true
        case .family: visibility == .family
        case .justMe: visibility == .justMe
        }
    }
}

enum Money {
    /// The family's currency (set under Chores), or else the phone's.
    @MainActor static var currencyCode: String {
        ChoreMath.currencyCode(for: ChoreStore.shared.settings)
    }

    /// "$1,240" for whole amounts, "$12.50" otherwise.
    static func text(_ amount: Decimal, code: String, locale: Locale = .current) -> String {
        let whole = amount.rounded(scale: 0) == amount
        return amount.formatted(.currency(code: code).locale(locale).precision(.fractionLength(whole ? 0 : 2)))
    }

    @MainActor static func text(_ amount: Decimal) -> String {
        text(amount, code: currencyCode)
    }

    /// Reads amounts as people type them: "$2,400", "2400.50", "₹ 1,200", "12,50" in Europe.
    /// With both "." and "," the last one is the decimal point; with just one kind, it's the
    /// decimal point only when it appears once with one or two digits after it.
    static func parse(_ text: String) -> Decimal? {
        var cleaned = String(text.filter { $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") })
        guard cleaned.contains(where: \.isNumber) else { return nil }
        let marks = cleaned.filter { $0 == "." || $0 == "," }
        var decimalMark: Character?
        if Set(marks).count == 2 {
            decimalMark = marks.last
        } else if let mark = marks.first, marks.count == 1, let index = cleaned.firstIndex(of: mark) {
            let digitsAfter = cleaned.distance(from: index, to: cleaned.endIndex) - 1
            if (1...2).contains(digitsAfter) { decimalMark = mark }
        }
        cleaned = String(cleaned.compactMap { character -> Character? in
            if character == decimalMark { return "." }
            return character.isNumber ? character : nil
        })
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }
}

extension Decimal {
    func rounded(scale: Int) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }

    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}

/// Totals for a dashboard, worked out from whatever expenses it's given.
enum BudgetMath {
    static func month(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: date, duration: 1)
    }

    static func total(_ expenses: [Expense]) -> Decimal {
        expenses.reduce(0) { $0 + $1.amount }
    }

    static func byCategory(_ expenses: [Expense]) -> [(category: SpendingCategory, total: Decimal)] {
        Dictionary(grouping: expenses, by: \.category)
            .map { (category: $0.key, total: total($0.value)) }
            .sorted { $0.total != $1.total ? $0.total > $1.total : $0.category.title < $1.category.title }
    }

    /// Recurring tasks with an amount due in the month and not yet paid, soonest first.
    static func upcomingPayments(_ tasks: [RecurringTask], in month: DateInterval) -> [(task: RecurringTask, amount: Decimal)] {
        var payments: [(task: RecurringTask, amount: Decimal)] = []
        for task in tasks where task.isActive && month.contains(task.nextDueDate) {
            if let amount = Money.parse(task.amount), amount > 0 {
                payments.append((task: task, amount: amount))
            }
        }
        return payments.sorted { $0.task.nextDueDate < $1.task.nextDueDate }
    }

    /// Progress toward a limit, 0 and up (over 1 means over budget).
    static func progress(spent: Decimal, limit: Decimal) -> Double {
        guard limit > 0 else { return 0 }
        return (spent / limit).doubleValue
    }
}
