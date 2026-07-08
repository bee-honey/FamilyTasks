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

struct MealIngredient: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var defaultShopID: UUID?

    init(id: UUID = UUID(), name: String, defaultShopID: UUID? = nil) {
        self.id = id
        self.name = name
        self.defaultShopID = defaultShopID
    }
}

enum MealSlot: String, CaseIterable, Codable, Identifiable {
    case breakfast
    case lunch
    case dinner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        }
    }

    var systemImage: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon"
        }
    }
}

enum MealCategory: String, CaseIterable, Codable, Identifiable {
    case breakfast
    case mainCourse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: "Breakfast"
        case .mainCourse: "Main Course"
        }
    }

    var systemImage: String {
        switch self {
        case .breakfast: "sunrise"
        case .mainCourse: "fork.knife"
        }
    }
}

struct MealIdea: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var category: MealCategory
    var ingredients: [MealIngredient]
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        category: MealCategory = .mainCourse,
        ingredients: [MealIngredient] = [],
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.ingredients = ingredients
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case category
        case ingredients
        case notes
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        category = (try? container.decode(MealCategory.self, forKey: .category)) ?? .mainCourse
        if let decodedIngredients = try? container.decode([MealIngredient].self, forKey: .ingredients) {
            ingredients = decodedIngredients
        } else {
            let oldIngredients = (try? container.decode([String].self, forKey: .ingredients)) ?? []
            ingredients = oldIngredients.map { MealIngredient(name: $0) }
        }
        notes = (try? container.decode(String.self, forKey: .notes)) ?? ""
        createdAt = (try? container.decode(Date.self, forKey: .createdAt)) ?? Date()
        updatedAt = (try? container.decode(Date.self, forKey: .updatedAt)) ?? Date()
    }
}

struct PlannedMeal: Identifiable, Codable, Equatable {
    var id: UUID
    var mealID: UUID
    var date: Date
    var slot: MealSlot
    var ingredientShopOverrides: [UUID: UUID]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        mealID: UUID,
        date: Date = Date(),
        slot: MealSlot = .dinner,
        ingredientShopOverrides: [UUID: UUID] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.mealID = mealID
        self.date = date
        self.slot = slot
        self.ingredientShopOverrides = ingredientShopOverrides
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case mealID
        case date
        case slot
        case ingredientShopOverrides
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        mealID = try container.decode(UUID.self, forKey: .mealID)
        date = try container.decode(Date.self, forKey: .date)
        slot = (try? container.decode(MealSlot.self, forKey: .slot)) ?? .dinner
        ingredientShopOverrides = (try? container.decode([UUID: UUID].self, forKey: .ingredientShopOverrides)) ?? [:]
        createdAt = (try? container.decode(Date.self, forKey: .createdAt)) ?? Date()
        updatedAt = (try? container.decode(Date.self, forKey: .updatedAt)) ?? Date()
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
    var assignedToEmails: [String]
    var createdBy: String
    var isActive: Bool
    var notificationPreference: TaskNotificationPreference?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        amount: String = "",
        frequency: RecurrenceFrequency = .monthly,
        nextDueDate: Date = Date(),
        assignedTo: String = Assignee.everyone,
        assignedToEmails: [String] = [],
        createdBy: String = "",
        isActive: Bool = true,
        notificationPreference: TaskNotificationPreference? = nil,
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
        self.assignedToEmails = FamilyTask.normalizedAssigneeEmails(assignedToEmails, legacyAssignedTo: assignedTo)
        self.createdBy = createdBy.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.isActive = isActive
        self.notificationPreference = notificationPreference
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case notes
        case amount
        case frequency
        case nextDueDate
        case assignedTo
        case assignedToEmails
        case createdBy
        case isActive
        case notificationPreference
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        notes = (try? container.decode(String.self, forKey: .notes)) ?? ""
        amount = (try? container.decode(String.self, forKey: .amount)) ?? ""
        frequency = (try? container.decode(RecurrenceFrequency.self, forKey: .frequency)) ?? .monthly
        nextDueDate = (try? container.decode(Date.self, forKey: .nextDueDate)) ?? Date()
        assignedTo = (try? container.decode(String.self, forKey: .assignedTo)) ?? Assignee.everyone
        let decodedAssignees = (try? container.decode([String].self, forKey: .assignedToEmails)) ?? []
        assignedToEmails = FamilyTask.normalizedAssigneeEmails(decodedAssignees, legacyAssignedTo: assignedTo)
        createdBy = ((try? container.decode(String.self, forKey: .createdBy)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        isActive = (try? container.decode(Bool.self, forKey: .isActive)) ?? true
        notificationPreference = try? container.decodeIfPresent(TaskNotificationPreference.self, forKey: .notificationPreference)
        createdAt = (try? container.decode(Date.self, forKey: .createdAt)) ?? Date()
        updatedAt = (try? container.decode(Date.self, forKey: .updatedAt)) ?? createdAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(notes, forKey: .notes)
        try container.encode(amount, forKey: .amount)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(nextDueDate, forKey: .nextDueDate)
        try container.encode(assignedTo, forKey: .assignedTo)
        try container.encode(assignedToEmails, forKey: .assignedToEmails)
        try container.encode(createdBy, forKey: .createdBy)
        try container.encode(isActive, forKey: .isActive)
        try container.encodeIfPresent(notificationPreference, forKey: .notificationPreference)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    var isAssignedToEveryone: Bool {
        Assignee.isEveryone(assignedTo)
    }

    var assigneeEmails: [String] {
        guard !isAssignedToEveryone else { return [] }
        return FamilyTask.normalizedAssigneeEmails(assignedToEmails, legacyAssignedTo: assignedTo)
    }

    var primaryAssigneeForAvatar: String {
        if isAssignedToEveryone { return Assignee.everyone }
        return assigneeEmails.first ?? assignedTo
    }

    func isVisible(to profileEmail: String) -> Bool {
        let email = profileEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !email.isEmpty else { return true }
        if isAssignedToEveryone { return true }
        let creator = createdBy.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if creator.isEmpty { return true }
        if creator == email { return true }
        return assigneeEmails.contains { $0.caseInsensitiveCompare(email) == .orderedSame }
    }
}
