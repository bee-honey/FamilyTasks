import Foundation

/// A child who does chores. Kids are added by name and don't need their own phone;
/// a parent marks chores done for them.
struct KidProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A repeating chore worth points, done once per period by each kid it's assigned to.
struct Chore: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var points: Int
    var frequency: RecurrenceFrequency
    var kidIDs: [UUID]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        points: Int,
        frequency: RecurrenceFrequency = .daily,
        kidIDs: [UUID] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.points = points
        self.frequency = frequency
        self.kidIDs = kidIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// One time a kid did a chore. It earns points once a parent approves it.
struct ChoreCompletion: Identifiable, Codable, Equatable {
    enum Status: String, Codable {
        case waitingForApproval
        case approved
    }

    var id: UUID
    var choreID: UUID
    var kidID: UUID
    /// Kept so history still reads right after the chore is renamed or deleted.
    var choreTitle: String
    var points: Int
    var status: Status
    var markedBy: String
    var completedAt: Date
    var approvedBy: String?
    var approvedAt: Date?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        choreID: UUID,
        kidID: UUID,
        choreTitle: String,
        points: Int,
        status: Status = .waitingForApproval,
        markedBy: String = "",
        completedAt: Date = Date(),
        approvedBy: String? = nil,
        approvedAt: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.choreID = choreID
        self.kidID = kidID
        self.choreTitle = choreTitle
        self.points = points
        self.status = status
        self.markedBy = markedBy
        self.completedAt = completedAt
        self.approvedBy = approvedBy
        self.approvedAt = approvedAt
        self.updatedAt = updatedAt
    }
}

/// Points paid out to a kid, which come off their running total.
struct ChorePayout: Identifiable, Codable, Equatable {
    var id: UUID
    var kidID: UUID
    var points: Int
    var paidBy: String
    var paidAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), kidID: UUID, points: Int, paidBy: String = "", paidAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.kidID = kidID
        self.points = points
        self.paidBy = paidBy
        self.paidAt = paidAt
        self.updatedAt = updatedAt
    }
}

struct ChoreSettings: Codable, Equatable {
    /// How many points make one unit of the local currency (10 points = $1 by default).
    var pointsPerCurrencyUnit: Int = 10
    var updatedAt: Date = HouseholdRecords.unknownDate
}

/// Everything about chores, as stored on this device and shared with the family.
struct ChoresPayload: Codable, Equatable {
    var kids: [KidProfile] = []
    var chores: [Chore] = []
    var completions: [ChoreCompletion] = []
    var payouts: [ChorePayout] = []
    var settings = ChoreSettings()

    init(kids: [KidProfile] = [], chores: [Chore] = [], completions: [ChoreCompletion] = [], payouts: [ChorePayout] = [], settings: ChoreSettings = ChoreSettings()) {
        self.kids = kids
        self.chores = chores
        self.completions = completions
        self.payouts = payouts
        self.settings = settings
    }

    private enum CodingKeys: String, CodingKey {
        case kids, chores, completions, payouts, settings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kids = (try? container.decode([KidProfile].self, forKey: .kids)) ?? []
        chores = (try? container.decode([Chore].self, forKey: .chores)) ?? []
        completions = (try? container.decode([ChoreCompletion].self, forKey: .completions)) ?? []
        payouts = (try? container.decode([ChorePayout].self, forKey: .payouts)) ?? []
        settings = (try? container.decode(ChoreSettings.self, forKey: .settings)) ?? ChoreSettings()
    }
}

/// Where a chore stands for one kid in the current period (today, this week or this month).
enum ChoreStatus: Equatable {
    case toDo
    case waitingForApproval
    case done
}

enum ChoreMath {
    /// Approved points minus what has been paid out.
    static func balance(for kidID: UUID, completions: [ChoreCompletion], payouts: [ChorePayout]) -> Int {
        let earned = completions
            .filter { $0.kidID == kidID && $0.status == .approved }
            .reduce(0) { $0 + $1.points }
        let paid = payouts
            .filter { $0.kidID == kidID }
            .reduce(0) { $0 + $1.points }
        return earned - paid
    }

    /// The day, week, month or year a chore repeats over, containing `date`.
    static func period(of frequency: RecurrenceFrequency, containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let component: Calendar.Component = switch frequency {
        case .daily: .day
        case .weekly: .weekOfYear
        case .monthly: .month
        case .yearly: .year
        }
        return calendar.dateInterval(of: component, for: date) ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86_400)
    }

    static func status(of chore: Chore, for kidID: UUID, completions: [ChoreCompletion], now: Date = Date(), calendar: Calendar = .current) -> ChoreStatus {
        let period = period(of: chore.frequency, containing: now, calendar: calendar)
        let thisPeriod = completions.filter { completion in
            completion.choreID == chore.id && completion.kidID == kidID
                && completion.completedAt >= period.start && completion.completedAt < period.end
        }
        if thisPeriod.contains(where: { $0.status == .approved }) { return .done }
        if !thisPeriod.isEmpty { return .waitingForApproval }
        return .toDo
    }

    static func money(for points: Int, settings: ChoreSettings) -> Decimal {
        Decimal(points) / Decimal(max(settings.pointsPerCurrencyUnit, 1))
    }

    /// "$4.50" in the device's currency.
    static func formattedMoney(for points: Int, settings: ChoreSettings, locale: Locale = .current) -> String {
        let code = locale.currency?.identifier ?? "USD"
        return money(for: points, settings: settings).formatted(.currency(code: code).locale(locale))
    }
}
