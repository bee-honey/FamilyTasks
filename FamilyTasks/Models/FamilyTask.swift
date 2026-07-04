import Foundation

enum Assignee {
    static let everyone = "__familytasks_everyone__"

    static func isEveryone(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines) == everyone
    }

    static func displayName(for value: String) -> String {
        isEveryone(value) ? "Everyone" : value
    }
}

struct FamilyTask: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var notes: String
    var dueDate: Date?
    var isUrgent: Bool
    var isImportant: Bool
    var isDone: Bool
    var assignedTo: String
    var calendarEventIdentifier: String?
    var notificationPreference: TaskNotificationPreference?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        dueDate: Date? = nil,
        isUrgent: Bool = false,
        isImportant: Bool = true,
        isDone: Bool = false,
        assignedTo: String = "",
        calendarEventIdentifier: String? = nil,
        notificationPreference: TaskNotificationPreference? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.isUrgent = isUrgent
        self.isImportant = isImportant
        self.isDone = isDone
        self.assignedTo = assignedTo
        self.calendarEventIdentifier = calendarEventIdentifier
        self.notificationPreference = notificationPreference
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var bucket: TaskBucket {
        TaskBucket(urgent: isUrgent, important: isImportant)
    }

    var priorityMarkers: [String] {
        var markers: [String] = []
        if isUrgent {
            markers.append("U")
        }
        if isImportant {
            markers.append("I")
        }
        return markers
    }
}

struct TaskNotificationPreference: Codable, Equatable {
    var usesDefaultSettings: Bool
    var customEnabled: Bool
    var leadMinutes: Int
    var leadMinutesList: [Int]

    init(
        usesDefaultSettings: Bool = true,
        customEnabled: Bool = true,
        leadMinutes: Int = 60,
        leadMinutesList: [Int]? = nil
    ) {
        self.usesDefaultSettings = usesDefaultSettings
        self.customEnabled = customEnabled
        self.leadMinutes = leadMinutes
        self.leadMinutesList = Self.normalizedLeadMinutes(leadMinutesList ?? [leadMinutes])
    }

    var selectedLeadMinutes: [Int] {
        Self.normalizedLeadMinutes(leadMinutesList.isEmpty ? [leadMinutes] : leadMinutesList)
    }

    private enum CodingKeys: String, CodingKey {
        case usesDefaultSettings
        case customEnabled
        case leadMinutes
        case leadMinutesList
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usesDefaultSettings = (try? container.decode(Bool.self, forKey: .usesDefaultSettings)) ?? true
        customEnabled = (try? container.decode(Bool.self, forKey: .customEnabled)) ?? true
        leadMinutes = (try? container.decode(Int.self, forKey: .leadMinutes)) ?? 60
        let decodedList = (try? container.decode([Int].self, forKey: .leadMinutesList)) ?? [leadMinutes]
        leadMinutesList = Self.normalizedLeadMinutes(decodedList)
    }

    private static func normalizedLeadMinutes(_ values: [Int]) -> [Int] {
        let validValues = Set(NotificationLeadTimeOption.options.map(\.minutes))
        let normalized = Array(Set(values.filter { validValues.contains($0) })).sorted()
        return normalized.isEmpty ? [60] : normalized
    }
}

enum TaskBucket: String, CaseIterable, Identifiable {
    case doNow
    case schedule
    case delegate
    case delete

    var id: String { rawValue }

    init(urgent: Bool, important: Bool) {
        switch (urgent, important) {
        case (true, true):
            self = .doNow
        case (false, true):
            self = .schedule
        case (true, false):
            self = .delegate
        case (false, false):
            self = .delete
        }
    }

    var title: String {
        switch self {
        case .doNow: "Do"
        case .schedule: "Schedule"
        case .delegate: "Delegate"
        case .delete: "Drop"
        }
    }

    var subtitle: String {
        switch self {
        case .doNow: "Urgent + important"
        case .schedule: "Important, not urgent"
        case .delegate: "Urgent, less important"
        case .delete: "Neither urgent nor important"
        }
    }

    var flags: (urgent: Bool, important: Bool) {
        switch self {
        case .doNow: (true, true)
        case .schedule: (false, true)
        case .delegate: (true, false)
        case .delete: (false, false)
        }
    }

    var sortPriority: Int {
        switch self {
        case .doNow: 0
        case .schedule: 1
        case .delegate: 2
        case .delete: 3
        }
    }
}
