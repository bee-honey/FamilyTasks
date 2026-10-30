import Foundation

/// A family trip: where, which days, what to pack and what to do each day. Trips are
/// shared with the whole family.
struct Trip: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var destination: String
    /// The first and last days, each at the start of the day.
    var startDate: Date
    var endDate: Date
    var notes: String
    /// A reminder of what's still unpacked on the morning the trip starts.
    var packingReminderEnabled: Bool
    var packingReminderHour: Int
    var packingReminderMinute: Int
    /// The same reminder the evening before, at `TripReminders.eveningBeforeHour`.
    var remindEveningBefore: Bool
    /// The day's plan each morning of the trip, at `TripReminders.dailyPlanHour`.
    var dailyPlanEnabled: Bool
    var createdBy: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        destination: String = "",
        startDate: Date,
        endDate: Date,
        notes: String = "",
        packingReminderEnabled: Bool = true,
        packingReminderHour: Int = 6,
        packingReminderMinute: Int = 0,
        remindEveningBefore: Bool = true,
        dailyPlanEnabled: Bool = true,
        createdBy: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.destination = destination
        self.startDate = startDate
        self.endDate = max(endDate, startDate)
        self.notes = notes
        self.packingReminderEnabled = packingReminderEnabled
        self.packingReminderHour = packingReminderHour
        self.packingReminderMinute = packingReminderMinute
        self.remindEveningBefore = remindEveningBefore
        self.dailyPlanEnabled = dailyPlanEnabled
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Every day of the trip, first to last.
    func days(calendar: Calendar = .current) -> [Date] {
        let first = calendar.startOfDay(for: startDate)
        let last = calendar.startOfDay(for: endDate)
        var days: [Date] = []
        var day = first
        while day <= last, days.count < 366 {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    func dayCount(calendar: Calendar = .current) -> Int {
        days(calendar: calendar).count
    }

    /// "Sun, Nov 23 – Thu, Nov 27", or one day when it starts and ends the same day.
    func dateText(calendar: Calendar = .current) -> String {
        let format = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        if calendar.isDate(startDate, inSameDayAs: endDate) {
            return startDate.formatted(format)
        }
        return "\(startDate.formatted(format)) – \(endDate.formatted(format))"
    }

    enum Phase: Equatable {
        case upcoming(daysAway: Int)
        case underway(day: Int)
        case finished
    }

    func phase(now: Date = Date(), calendar: Calendar = .current) -> Phase {
        let today = calendar.startOfDay(for: now)
        let first = calendar.startOfDay(for: startDate)
        let last = calendar.startOfDay(for: endDate)
        if today < first {
            return .upcoming(daysAway: calendar.dateComponents([.day], from: today, to: first).day ?? 0)
        }
        if today > last { return .finished }
        return .underway(day: (calendar.dateComponents([.day], from: first, to: today).day ?? 0) + 1)
    }

    /// "In 25 days", "Tomorrow", "Day 2 of 5", "Done".
    func phaseText(now: Date = Date(), calendar: Calendar = .current) -> String {
        switch phase(now: now, calendar: calendar) {
        case .upcoming(let days): days == 1 ? "Tomorrow" : "In \(days) days"
        case .underway(let day): "Day \(day) of \(dayCount(calendar: calendar))"
        case .finished: "Done"
        }
    }

    var isFinished: Bool { phase() == .finished }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let place = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        return place.isEmpty ? "Trip" : "Trip to \(place)"
    }

    /// "San Diego", else the trip's name, for notification text.
    var placeName: String {
        let place = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        return place.isEmpty ? displayName : place
    }
}

enum PackingCategory: String, Codable, CaseIterable, Identifiable {
    case documents
    case clothes
    case toiletries
    case electronics
    case health
    case kids
    case travel
    case home
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .documents: "Documents and Money"
        case .clothes: "Clothes"
        case .toiletries: "Toiletries"
        case .electronics: "Electronics"
        case .health: "Health"
        case .kids: "Kids"
        case .travel: "For the Journey"
        case .home: "Before You Leave"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .documents: "wallet.pass"
        case .clothes: "tshirt"
        case .toiletries: "comb"
        case .electronics: "powerplug"
        case .health: "cross.case"
        case .kids: "figure.and.child.holdinghands"
        case .travel: "suitcase.rolling"
        case .home: "house"
        case .other: "shippingbox"
        }
    }
}

/// One thing to pack or do before leaving.
struct PackingItem: Identifiable, Codable, Equatable {
    var id: UUID
    var tripID: UUID
    var name: String
    var category: PackingCategory
    var isPacked: Bool
    /// Who it's for or who's bringing it, such as "Asha"; empty for everyone.
    var forWhom: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        tripID: UUID,
        name: String,
        category: PackingCategory = .other,
        isPacked: Bool = false,
        forWhom: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.tripID = tripID
        self.name = name
        self.category = category
        self.isPacked = isPacked
        self.forWhom = forWhom
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Something planned on one day of a trip, at a time or any time that day.
struct TripActivity: Identifiable, Codable, Equatable {
    var id: UUID
    var tripID: UUID
    var title: String
    /// The day, and the time when `hasTime` is set.
    var date: Date
    var hasTime: Bool
    var location: String
    var notes: String
    /// Minutes before `date` to remind; nil for no reminder. Only used with a time.
    var reminderMinutes: Int?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        tripID: UUID,
        title: String,
        date: Date,
        hasTime: Bool = false,
        location: String = "",
        notes: String = "",
        reminderMinutes: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.tripID = tripID
        self.title = title
        self.date = date
        self.hasTime = hasTime
        self.location = location
        self.notes = notes
        self.reminderMinutes = reminderMinutes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// When to remind, if it has a time and a reminder.
    var reminderDate: Date? {
        guard hasTime, let reminderMinutes else { return nil }
        return date.addingTimeInterval(-Double(reminderMinutes) * 60)
    }

    var timeText: String? {
        hasTime ? date.formatted(date: .omitted, time: .shortened) : nil
    }

    /// Timed activities in time order first, then the rest in the order they were added.
    static func dayOrder(_ lhs: TripActivity, _ rhs: TripActivity) -> Bool {
        switch (lhs.hasTime, rhs.hasTime) {
        case (true, true): lhs.date < rhs.date
        case (true, false): true
        case (false, true): false
        case (false, false): lhs.createdAt < rhs.createdAt
        }
    }
}

struct TripsPayload: Codable, Equatable {
    var trips: [Trip] = []
    var packingItems: [PackingItem] = []
    var activities: [TripActivity] = []

    init(trips: [Trip] = [], packingItems: [PackingItem] = [], activities: [TripActivity] = []) {
        self.trips = trips
        self.packingItems = packingItems
        self.activities = activities
    }

    private enum CodingKeys: String, CodingKey {
        case trips, packingItems, activities
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trips = (try? container.decode([Trip].self, forKey: .trips)) ?? []
        packingItems = (try? container.decode([PackingItem].self, forKey: .packingItems)) ?? []
        activities = (try? container.decode([TripActivity].self, forKey: .activities)) ?? []
    }
}

/// Ready-made packing lists to start a trip from.
enum PackingList: String, CaseIterable, Identifiable {
    case essentials
    case clothes
    case toiletries
    case electronics
    case health
    case kids
    case beach
    case coldWeather
    case flying
    case roadTrip
    case beforeYouLeave

    var id: String { rawValue }

    var title: String {
        switch self {
        case .essentials: "Essentials"
        case .clothes: "Clothes"
        case .toiletries: "Toiletries"
        case .electronics: "Electronics"
        case .health: "Health"
        case .kids: "Kids"
        case .beach: "Beach"
        case .coldWeather: "Cold Weather"
        case .flying: "Flying"
        case .roadTrip: "Road Trip"
        case .beforeYouLeave: "Before You Leave"
        }
    }

    /// Lists most trips need, picked when a trip is created.
    static let defaults: Set<PackingList> = [.essentials, .clothes, .toiletries, .electronics, .health, .beforeYouLeave]

    var items: [(name: String, category: PackingCategory)] {
        switch self {
        case .essentials:
            [("ID or driver's license", .documents), ("Wallet and cards", .documents), ("Some cash", .documents),
             ("Hotel or stay confirmation", .documents), ("Health insurance cards", .documents), ("House keys", .documents)]
        case .clothes:
            [("Tops", .clothes), ("Pants and shorts", .clothes), ("Underwear", .clothes), ("Socks", .clothes),
             ("Pajamas", .clothes), ("Sweater or light jacket", .clothes), ("Comfortable walking shoes", .clothes), ("One nicer outfit", .clothes)]
        case .toiletries:
            [("Toothbrushes and toothpaste", .toiletries), ("Deodorant", .toiletries), ("Shampoo and soap", .toiletries),
             ("Hairbrush and hair ties", .toiletries), ("Moisturizer and lip balm", .toiletries), ("Razor", .toiletries)]
        case .electronics:
            [("Phone chargers", .electronics), ("Power bank", .electronics), ("Headphones", .electronics),
             ("Car charger", .electronics), ("Tablet for the kids", .electronics)]
        case .health:
            [("Daily medicines", .health), ("Pain and fever relief", .health), ("Band-aids", .health),
             ("Glasses or contacts", .health), ("Hand sanitizer", .health)]
        case .kids:
            [("Diapers and wipes", .kids), ("Kids' snacks", .kids), ("Toys and books", .kids), ("Stroller", .kids),
             ("Car seat", .kids), ("Spare clothes in the day bag", .kids), ("Kids' medicines", .kids)]
        case .beach:
            [("Swimsuits", .clothes), ("Sunscreen", .toiletries), ("Sunglasses", .travel), ("Hats", .clothes),
             ("Beach towels", .travel), ("Flip-flops", .clothes)]
        case .coldWeather:
            [("Warm coats", .clothes), ("Gloves", .clothes), ("Beanies", .clothes), ("Thermals", .clothes), ("Boots", .clothes)]
        case .flying:
            [("Boarding passes", .documents), ("Passports", .documents), ("Neck pillows", .travel),
             ("Empty water bottles", .travel), ("Snacks for the flight", .travel), ("Luggage tags", .travel)]
        case .roadTrip:
            [("Driver's license and registration", .documents), ("Snacks and drinks", .travel), ("Road trip playlist", .travel),
             ("Car phone mount", .electronics), ("Trash bags", .travel), ("Check tire pressure", .home)]
        case .beforeYouLeave:
            [("Lock doors and windows", .home), ("Set the thermostat", .home), ("Take out the trash", .home),
             ("Empty the fridge of perishables", .home), ("Water the plants", .home), ("Hold the mail", .home)]
        }
    }
}

enum TripReminders {
    static let eveningBeforeHour = 20
    static let dailyPlanHour = 8
    static let reminderChoices: [Int?] = [nil, 0, 15, 30, 60, 120, 1_440]

    static func reminderText(_ minutes: Int?) -> String {
        switch minutes {
        case nil: "None"
        case 0: "At the time"
        case 1_440: "1 day before"
        case let minutes? where minutes % 60 == 0: minutes == 60 ? "1 hour before" : "\(minutes / 60) hours before"
        case let minutes?: "\(minutes) minutes before"
        }
    }

    /// "Passport, Chargers and 3 more".
    static func listText(_ names: [String], limit: Int = 4) -> String {
        guard names.count > limit else { return ListFormatter.localizedString(byJoining: names) }
        return names.prefix(limit).joined(separator: ", ") + " and \(names.count - limit) more"
    }
}

/// The whole trip as plain text to send in Messages, WhatsApp or email.
enum TripShareText {
    static func text(for trip: Trip, packing: [PackingItem], activities: [TripActivity], calendar: Calendar = .current) -> String {
        var lines: [String] = []
        lines.append(trip.displayName)
        var subtitle = trip.dateText(calendar: calendar)
        let days = trip.dayCount(calendar: calendar)
        subtitle += " · \(days) \(days == 1 ? "day" : "days")"
        let place = trip.destination.trimmingCharacters(in: .whitespacesAndNewlines)
        if !place.isEmpty, place != trip.displayName { subtitle = "\(place) · " + subtitle }
        lines.append(subtitle)

        let notes = trip.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            lines.append("")
            lines.append(notes)
        }

        let tripActivities = activities.filter { $0.tripID == trip.id }
        if !tripActivities.isEmpty {
            lines.append("")
            lines.append("DAY BY DAY")
            for (index, day) in trip.days(calendar: calendar).enumerated() {
                let planned = tripActivities
                    .filter { calendar.isDate($0.date, inSameDayAs: day) }
                    .sorted(by: TripActivity.dayOrder)
                guard !planned.isEmpty else { continue }
                lines.append("")
                lines.append("Day \(index + 1) · \(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))")
                for activity in planned {
                    var line = "• "
                    if let time = activity.timeText { line += "\(time)  " }
                    line += activity.title
                    let location = activity.location.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !location.isEmpty { line += " (\(location))" }
                    lines.append(line)
                    let activityNotes = activity.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !activityNotes.isEmpty { lines.append("   \(activityNotes)") }
                }
            }
        }

        let items = packing.filter { $0.tripID == trip.id }
        if !items.isEmpty {
            lines.append("")
            lines.append("PACKING · \(items.filter(\.isPacked).count) of \(items.count) packed")
            for category in PackingCategory.allCases {
                let inCategory = items.filter { $0.category == category }
                guard !inCategory.isEmpty else { continue }
                lines.append("")
                lines.append(category.title)
                for item in inCategory {
                    let who = item.forWhom.trimmingCharacters(in: .whitespacesAndNewlines)
                    lines.append("\(item.isPacked ? "☑" : "☐") \(item.name)\(who.isEmpty ? "" : " (\(who))")")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}
