import Foundation

enum Assignee {
    static let everyone = "__familytasks_everyone__"

    static func isEveryone(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines) == everyone
    }

    static func displayName(for value: String) -> String {
        isEveryone(value) ? "Everyone" : value
    }

    /// How to refer to a member stored by email: "sam.smith@example.com" → "Sam Smith".
    static func memberName(for email: String) -> String {
        let localPart = email.split(separator: "@").first.map(String.init) ?? email
        let name = localPart
            .split(whereSeparator: { ".-_+".contains($0) || $0.isNumber })
            .map { $0.capitalized }
            .joined(separator: " ")
        return name.isEmpty ? email : name
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
    var assignedToEmails: [String]
    var createdBy: String
    var calendarEventIdentifier: String?
    var notificationPreference: TaskNotificationPreference?
    /// Where the task happens, if anywhere.
    var location: TaskLocation?
    /// Email of the family member who marked the task done, and when.
    var completedBy: String?
    var completedAt: Date?
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
        assignedToEmails: [String] = [],
        createdBy: String = "",
        calendarEventIdentifier: String? = nil,
        notificationPreference: TaskNotificationPreference? = nil,
        location: TaskLocation? = nil,
        completedBy: String? = nil,
        completedAt: Date? = nil,
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
        self.assignedToEmails = Self.normalizedAssigneeEmails(assignedToEmails, legacyAssignedTo: assignedTo)
        self.createdBy = createdBy.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.calendarEventIdentifier = calendarEventIdentifier
        self.notificationPreference = notificationPreference
        self.location = location
        self.completedBy = completedBy
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case notes
        case dueDate
        case isUrgent
        case isImportant
        case isDone
        case assignedTo
        case assignedToEmails
        case createdBy
        case calendarEventIdentifier
        case notificationPreference
        case location
        case completedBy
        case completedAt
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        title = (try? container.decode(String.self, forKey: .title)) ?? ""
        notes = (try? container.decode(String.self, forKey: .notes)) ?? ""
        dueDate = try? container.decodeIfPresent(Date.self, forKey: .dueDate)
        isUrgent = (try? container.decode(Bool.self, forKey: .isUrgent)) ?? false
        isImportant = (try? container.decode(Bool.self, forKey: .isImportant)) ?? true
        isDone = (try? container.decode(Bool.self, forKey: .isDone)) ?? false
        assignedTo = (try? container.decode(String.self, forKey: .assignedTo)) ?? ""
        let decodedAssignees = (try? container.decode([String].self, forKey: .assignedToEmails)) ?? []
        assignedToEmails = Self.normalizedAssigneeEmails(decodedAssignees, legacyAssignedTo: assignedTo)
        createdBy = ((try? container.decode(String.self, forKey: .createdBy)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        calendarEventIdentifier = try? container.decodeIfPresent(String.self, forKey: .calendarEventIdentifier)
        notificationPreference = try? container.decodeIfPresent(TaskNotificationPreference.self, forKey: .notificationPreference)
        location = try? container.decodeIfPresent(TaskLocation.self, forKey: .location)
        completedBy = try? container.decodeIfPresent(String.self, forKey: .completedBy)
        completedAt = try? container.decodeIfPresent(Date.self, forKey: .completedAt)
        createdAt = (try? container.decode(Date.self, forKey: .createdAt)) ?? Date()
        updatedAt = (try? container.decode(Date.self, forKey: .updatedAt)) ?? createdAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(notes, forKey: .notes)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
        try container.encode(isUrgent, forKey: .isUrgent)
        try container.encode(isImportant, forKey: .isImportant)
        try container.encode(isDone, forKey: .isDone)
        try container.encode(assignedTo, forKey: .assignedTo)
        try container.encode(assignedToEmails, forKey: .assignedToEmails)
        try container.encode(createdBy, forKey: .createdBy)
        try container.encodeIfPresent(calendarEventIdentifier, forKey: .calendarEventIdentifier)
        try container.encodeIfPresent(notificationPreference, forKey: .notificationPreference)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(completedBy, forKey: .completedBy)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
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

    var isAssignedToEveryone: Bool {
        Assignee.isEveryone(assignedTo)
    }

    var assigneeEmails: [String] {
        guard !isAssignedToEveryone else { return [] }
        return Self.normalizedAssigneeEmails(assignedToEmails, legacyAssignedTo: assignedTo)
    }

    /// Who the avatar shows: the first person on it other than the viewer, since the
    /// editor always adds its creator; the viewer only when it's theirs alone.
    func avatarAssignee(viewerEmail: String) -> String {
        if isAssignedToEveryone { return Assignee.everyone }
        let viewer = viewerEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return assigneeEmails.first { $0.caseInsensitiveCompare(viewer) != .orderedSame }
            ?? assigneeEmails.first
            ?? assignedTo
    }

    var primaryAssigneeForAvatar: String {
        avatarAssignee(viewerEmail: UserDefaults.standard.string(forKey: "profile.email") ?? "")
    }

    var assignmentSummary: String {
        if isAssignedToEveryone {
            return "Everyone"
        }
        let emails = assigneeEmails
        if emails.isEmpty {
            return "Unassigned"
        }
        if emails.count == 1 {
            return emails[0]
        }
        return "\(emails[0]) +\(emails.count - 1)"
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

    static func normalizedAssigneeEmails(_ values: [String], legacyAssignedTo: String = "") -> [String] {
        let candidates = values + [legacyAssignedTo]
        let emails = candidates
            .flatMap { value in
                value.split(separator: ",").map(String.init)
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && !Assignee.isEveryone($0) }
        return Array(Set(emails)).sorted()
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
        case .doNow: "Urgent + Important"
        case .schedule: "Important Only"
        case .delegate: "Urgent Only"
        case .delete: "Not Urgent or Important"
        }
    }

    var subtitle: String {
        switch self {
        case .doNow: "Urgent and important"
        case .schedule: "Important, not urgent"
        case .delegate: "Urgent, not important"
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

extension FamilyTask {
    /// "Done by Sam · 3:40 PM", "Done by you · Sep 30", or nil while the task is open.
    func completionSummary(viewerEmail: String, now: Date = Date(), calendar: Calendar = .current) -> String? {
        guard isDone, let completedBy, !completedBy.isEmpty else { return nil }
        let who = completedBy.caseInsensitiveCompare(viewerEmail.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
            ? "you"
            : Assignee.memberName(for: completedBy)
        guard let completedAt else { return "Done by \(who)" }
        let when = calendar.isDate(completedAt, inSameDayAs: now)
            ? completedAt.formatted(date: .omitted, time: .shortened)
            : completedAt.formatted(.dateTime.month(.abbreviated).day())
        return "Done by \(who) · \(when)"
    }
}

/// A task another family member finished, for the "Sam finished Take out bins" notification.
struct TaskCompletion: Equatable {
    var who: String
    var title: String

    /// Tasks that were open here and that someone else has since finished, recently
    /// enough to be news. Tasks this device never saw open (for example when first
    /// joining a share) are left out.
    static func newlyCompleted(before: [FamilyTask], after: [FamilyTask], viewerEmail: String, now: Date = Date()) -> [TaskCompletion] {
        let viewer = viewerEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let wasOpen = Set(before.filter { !$0.isDone }.map(\.id))
        let recent = now.addingTimeInterval(-86_400)

        return after.compactMap { task in
            guard task.isDone,
                  wasOpen.contains(task.id),
                  let completedBy = task.completedBy?.lowercased(), !completedBy.isEmpty, completedBy != viewer,
                  let completedAt = task.completedAt, completedAt >= recent,
                  task.isVisible(to: viewer) else { return nil }
            return TaskCompletion(who: Assignee.memberName(for: completedBy), title: task.title)
        }
    }

    /// One notification for everything finished in a sync.
    static func notificationBody(for completions: [TaskCompletion]) -> String {
        let people = completions.reduce(into: [String]()) { names, completion in
            if !names.contains(completion.who) { names.append(completion.who) }
        }
        let titles = completions.map(\.title)
        let tasks = switch titles.count {
        case 1: titles[0]
        case 2: "\(titles[0]) and \(titles[1])"
        default: "\(titles[0]), \(titles[1]) and \(titles.count - 2) more"
        }

        if people.count == 1 {
            return "\(people[0]) finished \(tasks)."
        }
        return "\(ListFormatter.localizedString(byJoining: people)) finished \(tasks)."
    }
}

extension TaskBucket {
    /// The short label on task tags: "Do now", "Schedule", "Delegate", "Someday".
    var tagTitle: String {
        switch self {
        case .doNow: "Do now"
        case .schedule: "Schedule"
        case .delegate: "Delegate"
        case .delete: "Someday"
        }
    }
}

/// A place for a task: picked from map search (with an address and coordinates) or typed.
struct TaskLocation: Codable, Equatable, Sendable {
    var name: String
    var address: String?
    var latitude: Double?
    var longitude: Double?

    var hasCoordinates: Bool {
        latitude != nil && longitude != nil
    }

    /// The name and address, for searching by text.
    var searchText: String {
        [name, address].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ", ")
    }
}

/// The maps apps a task's location can be opened in.
enum MapApp: String, CaseIterable, Identifiable {
    case apple
    case google
    case waze

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: "Apple Maps"
        case .google: "Google Maps"
        case .waze: "Waze"
        }
    }

    /// A scheme to check whether the app is installed; nil when it can always be offered
    /// (Apple Maps is built in, and Google Maps falls back to the web).
    var installCheckURL: URL? {
        switch self {
        case .apple, .google: nil
        case .waze: URL(string: "waze://")
        }
    }

    /// Opens the location in this app. Google Maps and Waze links open their app when it's
    /// installed and the website otherwise.
    func url(for location: TaskLocation) -> URL? {
        var components: URLComponents
        switch self {
        case .apple:
            components = URLComponents(string: "https://maps.apple.com/")!
            if let latitude = location.latitude, let longitude = location.longitude {
                components.queryItems = [
                    URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"),
                    URLQueryItem(name: "q", value: location.name)
                ]
            } else {
                components.queryItems = [URLQueryItem(name: "q", value: location.searchText)]
            }
        case .google:
            components = URLComponents(string: "https://www.google.com/maps/search/")!
            let query = location.address == nil
                ? (location.latitude.flatMap { lat in location.longitude.map { "\(lat),\($0)" } } ?? location.searchText)
                : location.searchText
            components.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: query)]
        case .waze:
            components = URLComponents(string: "https://waze.com/ul")!
            if let latitude = location.latitude, let longitude = location.longitude {
                components.queryItems = [URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"), URLQueryItem(name: "navigate", value: "yes")]
            } else {
                components.queryItems = [URLQueryItem(name: "q", value: location.searchText), URLQueryItem(name: "navigate", value: "yes")]
            }
        }
        return components.url
    }
}
