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
        assignedTo: String = "",
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
        self.isActive = isActive
        self.notificationPreference = notificationPreference
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
