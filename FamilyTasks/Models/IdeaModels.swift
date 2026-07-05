import Foundation

struct IdeaNote: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var notes: String
    var link: String
    var tags: [String]
    var latitude: Double?
    var longitude: Double?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        link: String = "",
        tags: [String] = [],
        latitude: Double? = nil,
        longitude: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.link = link
        self.tags = Self.normalizedTags(tags)
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayTags: [String] {
        Self.normalizedTags(tags)
    }

    var url: URL? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }

    static let suggestedTags = [
        "Food",
        "Fun",
        "Outdoor",
        "Kids"
    ]

    static func normalizedTags(_ values: [String]) -> [String] {
        let cleaned = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(cleaned)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}

struct IdeaDraft {
    var title = ""
    var notes = ""
    var link = ""
    var tags: Set<String> = []
    var customTag = ""

    init() {}

    init(note: IdeaNote) {
        title = note.title
        notes = note.notes
        link = note.link
        tags = Set(note.tags)
    }

    var normalizedTags: [String] {
        var values = Array(tags)
        let trimmedCustomTag = customTag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCustomTag.isEmpty {
            values.append(trimmedCustomTag)
        }
        return IdeaNote.normalizedTags(values)
    }
}
