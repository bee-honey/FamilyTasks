import Foundation

struct Shop: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var usualItems: [String]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        usualItems: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.usualItems = usualItems
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ShoppingItem: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var shopID: UUID
    var isNeeded: Bool
    var isPurchased: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        shopID: UUID,
        isNeeded: Bool = true,
        isPurchased: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.shopID = shopID
        self.isNeeded = isNeeded
        self.isPurchased = isPurchased
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum RecurrenceFrequency: String, CaseIterable, Codable, Identifiable {
    case daily
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        }
    }

    func nextDate(after date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date) ?? date
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .yearly:
            return calendar.date(byAdding: .year, value: 1, to: date) ?? date
        }
    }
}

struct RecurringTask: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var notes: String
    var amount: String
    var frequency: RecurrenceFrequency
    var nextDueDate: Date
    var assignedTo: String
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        amount: String = "",
        frequency: RecurrenceFrequency = .monthly,
        nextDueDate: Date = Date(),
        assignedTo: String = "",
        isActive: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.amount = amount
        self.frequency = frequency
        self.nextDueDate = nextDueDate
        self.assignedTo = assignedTo
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
