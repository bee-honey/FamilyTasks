import Foundation

/// What kind of someday idea it is, which decides what it can turn into: a place goes on a
/// trip, food goes into Your Meals, anything can become a task.
enum IdeaKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case place, food, activity, watch, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .place: "Place"
        case .food: "Food"
        case .activity: "Activity"
        case .watch: "Watch & Read"
        case .other: "Other"
        }
    }

    var pluralTitle: String {
        switch self {
        case .place: "Places"
        case .food: "Food"
        case .activity: "Activities"
        case .watch: "Watch & Read"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .place: "mappin.and.ellipse"
        case .food: "fork.knife"
        case .activity: "figure.walk"
        case .watch: "play.rectangle"
        case .other: "lightbulb"
        }
    }

    /// The word for having done it: "Visited", "Cooked".
    var doneTitle: String {
        switch self {
        case .place: "Visited"
        case .food: "Cooked"
        case .activity: "Done"
        case .watch: "Watched"
        case .other: "Done"
        }
    }

    var markDoneTitle: String {
        switch self {
        case .place: "We Went"
        case .food: "We Made It"
        case .activity: "We Did It"
        case .watch: "We Watched It"
        case .other: "Done"
        }
    }

    /// A best guess from where the link points and what the page is about. The person
    /// saving it can always change it.
    static func guess(link: URL?, text: String) -> IdeaKind {
        let host = link?.host()?.lowercased() ?? ""
        let path = link?.path.lowercased() ?? ""
        let words = text.lowercased()

        let mapHosts = ["maps.apple.com", "maps.app.goo.gl", "yelp.", "tripadvisor.", "opentable.", "airbnb.", "booking.com"]
        if mapHosts.contains(where: host.contains) || (host.contains("google.") && path.hasPrefix("/maps")) || (host == "goo.gl" && path.hasPrefix("/maps")) {
            return .place
        }

        let foodHosts = ["allrecipes.", "foodnetwork.", "seriouseats.", "bonappetit.", "epicurious.", "tasty.co", "nytcooking", "cooking.nytimes", "budgetbytes.", "indianhealthyrecipes.", "hebbarskitchen."]
        let foodWords = ["recipe", "how to make", "how to cook", "cooking", "bake ", "baking", "dinner idea", "biryani", "curry", "pasta", "dessert"]
        if foodHosts.contains(where: host.contains) || foodWords.contains(where: words.contains) {
            return .food
        }

        let watchHosts = ["youtube.", "youtu.be", "netflix.", "imdb.", "primevideo.", "disneyplus.", "hulu.", "spotify.", "podcasts.apple.com", "goodreads.", "tv.apple.com", "books.apple.com"]
        if watchHosts.contains(where: host.contains) {
            return .watch
        }
        return .other
    }
}

struct IdeaNote: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var notes: String
    var link: String
    var tags: [String]
    var latitude: Double?
    var longitude: Double?
    var kind: IdeaKind
    /// For places: the name or address to find on a map.
    var location: String
    /// From the link's page: a picture and where it's from ("YouTube").
    var imageURL: String
    var siteName: String
    /// Email of whoever saved it.
    var addedBy: String
    var doneAt: Date?
    /// 1 to 5 stars, once done.
    var rating: Int?
    /// How it went.
    var doneNote: String
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
        kind: IdeaKind = .other,
        location: String = "",
        imageURL: String = "",
        siteName: String = "",
        addedBy: String = "",
        doneAt: Date? = nil,
        rating: Int? = nil,
        doneNote: String = "",
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
        self.kind = kind
        self.location = location
        self.imageURL = imageURL
        self.siteName = siteName
        self.addedBy = addedBy
        self.doneAt = doneAt
        self.rating = rating
        self.doneNote = doneNote
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, notes, link, tags, latitude, longitude, kind, location, imageURL, siteName, addedBy, doneAt, rating, doneNote, createdAt, updatedAt
    }

    /// Ideas saved before kinds and previews existed still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        link = try container.decodeIfPresent(String.self, forKey: .link) ?? ""
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        kind = (try? container.decodeIfPresent(IdeaKind.self, forKey: .kind)) ?? .other
        location = try container.decodeIfPresent(String.self, forKey: .location) ?? ""
        imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL) ?? ""
        siteName = try container.decodeIfPresent(String.self, forKey: .siteName) ?? ""
        addedBy = try container.decodeIfPresent(String.self, forKey: .addedBy) ?? ""
        doneAt = try container.decodeIfPresent(Date.self, forKey: .doneAt)
        rating = try container.decodeIfPresent(Int.self, forKey: .rating)
        doneNote = try container.decodeIfPresent(String.self, forKey: .doneNote) ?? ""
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    var isDone: Bool { doneAt != nil }

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

    var image: URL? {
        imageURL.isEmpty ? nil : URL(string: imageURL)
    }

    /// Where the link goes, for a button: "YouTube", or the site's address.
    var sourceName: String? {
        if !siteName.isEmpty { return siteName }
        guard let host = url?.host() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// What to search a map for.
    var mapQuery: String {
        location.isEmpty ? title : location
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

    /// Whether two links are the same page, ignoring tracking bits like "?si=" or "utm_".
    static func sameLink(_ lhs: String, _ rhs: String) -> Bool {
        let left = canonicalLink(lhs), right = canonicalLink(rhs)
        return !left.isEmpty && left == right
    }

    static func canonicalLink(_ link: String) -> String {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed), let host = components.host?.lowercased() else {
            return trimmed.lowercased()
        }
        let tracking: Set<String> = ["si", "feature", "igsh", "igshid", "s", "t", "ref", "fbclid", "gclid"]
        components.queryItems = components.queryItems?.filter { item in
            !tracking.contains(item.name) && !item.name.hasPrefix("utm_")
        }
        if components.queryItems?.isEmpty == true { components.queryItems = nil }
        let path = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return (host.hasPrefix("www.") ? String(host.dropFirst(4)) : host) + path + query
    }
}

struct IdeaDraft {
    var title = ""
    var notes = ""
    var link = ""
    var tags: Set<String> = []
    var customTag = ""
    var kind: IdeaKind = .other
    var location = ""
    var imageURL = ""
    var siteName = ""
    var latitude: Double?
    var longitude: Double?

    init() {}

    init(note: IdeaNote) {
        title = note.title
        notes = note.notes
        link = note.link
        tags = Set(note.tags)
        kind = note.kind
        location = note.location
        imageURL = note.imageURL
        siteName = note.siteName
        latitude = note.latitude
        longitude = note.longitude
    }

    var normalizedTags: [String] {
        var values = Array(tags)
        let trimmedCustomTag = customTag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCustomTag.isEmpty {
            values.append(trimmedCustomTag)
        }
        return IdeaNote.normalizedTags(values)
    }

    /// Fills in what the link's page says, without overwriting anything typed.
    mutating func apply(_ preview: LinkPreview) {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { title = preview.title }
        if imageURL.isEmpty { imageURL = preview.imageURL }
        if siteName.isEmpty { siteName = preview.siteName }
        if location.isEmpty, let place = preview.place {
            location = place.name
            latitude = place.latitude
            longitude = place.longitude
        }
    }
}
