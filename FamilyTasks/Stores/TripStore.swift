import Foundation

/// The family's trips, with each one's packing list and day-by-day plan. Everything is
/// shared with the family.
@MainActor
final class TripStore: ObservableObject {
    static let shared = TripStore()

    @Published private(set) var trips: [Trip] = []
    @Published private(set) var packingItems: [PackingItem] = []
    @Published private(set) var activities: [TripActivity] = []
    @Published private(set) var weather: [TripWeather] = []
    @Published private(set) var weatherCallLog: WeatherCallLog?

    private let storageURL: URL
    private let ownerEmail: () -> String

    init(directory: URL? = nil, ownerEmail: @escaping () -> String = HabitStore.currentProfileEmail) {
        storageURL = (directory ?? URL.documentsDirectory).appendingPathComponent("family-trips.json")
        self.ownerEmail = ownerEmail
        load()
    }

    // MARK: Reading

    /// Trips not yet over, soonest first.
    var upcomingTrips: [Trip] {
        trips.filter { !$0.isFinished }.sorted { $0.startDate < $1.startDate }
    }

    /// Finished trips, most recent first.
    var pastTrips: [Trip] {
        trips.filter(\.isFinished).sorted { $0.startDate > $1.startDate }
    }

    func trip(id: UUID) -> Trip? {
        trips.first { $0.id == id }
    }

    func packing(for trip: Trip) -> [PackingItem] {
        packingItems.filter { $0.tripID == trip.id }
    }

    func activities(for trip: Trip) -> [TripActivity] {
        activities.filter { $0.tripID == trip.id }
    }

    func activities(for trip: Trip, on day: Date, calendar: Calendar = .current) -> [TripActivity] {
        activities
            .filter { $0.tripID == trip.id && calendar.isDate($0.date, inSameDayAs: day) }
            .sorted(by: TripActivity.dayOrder)
    }

    // MARK: Trips

    @discardableResult
    func addTrip(
        name: String,
        destination: String,
        startDate: Date,
        endDate: Date,
        notes: String = "",
        packingLists: Set<PackingList> = [],
        copyingPackingFrom source: Trip? = nil,
        calendar: Calendar = .current
    ) -> Trip {
        let trip = Trip(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            destination: destination.trimmingCharacters(in: .whitespacesAndNewlines),
            startDate: calendar.startOfDay(for: startDate),
            endDate: calendar.startOfDay(for: endDate),
            notes: notes,
            createdBy: ownerEmail()
        )
        change {
            trips.append(trip)
            var names = Set<String>()
            var items: [PackingItem] = []
            func add(_ name: String, _ category: PackingCategory, forWhom: String = "") {
                guard names.insert(WeeklyIngredient.key(for: name)).inserted else { return }
                items.append(PackingItem(tripID: trip.id, name: name, category: category, forWhom: forWhom))
            }
            if let source {
                for item in packingItems where item.tripID == source.id {
                    add(item.name, item.category, forWhom: item.forWhom)
                }
            }
            for list in PackingList.allCases where packingLists.contains(list) {
                list.items.forEach { add($0.name, $0.category) }
            }
            packingItems += items
        }
        return trip
    }

    func updateTrip(_ trip: Trip) {
        guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        var updated = trip
        let calendar = Calendar.current
        updated.startDate = calendar.startOfDay(for: trip.startDate)
        updated.endDate = max(calendar.startOfDay(for: trip.endDate), updated.startDate)
        updated.updatedAt = trips[index].updatedAt
        guard updated != trips[index] else { return }
        updated.updatedAt = Date()
        change { trips[index] = updated }
    }

    /// Deletes the trip with its packing list and plan.
    func deleteTrip(_ trip: Trip) {
        change {
            trips.removeAll { $0.id == trip.id }
            packingItems.removeAll { $0.tripID == trip.id }
            activities.removeAll { $0.tripID == trip.id }
            weather.removeAll { $0.id == trip.id }
        }
    }

    // MARK: Packing

    /// Adds items not already on the trip's list. Returns how many were added.
    @discardableResult
    func addPackingItems(_ items: [(name: String, category: PackingCategory)], to trip: Trip, forWhom: String = "") -> Int {
        var existing = Set(packing(for: trip).map { WeeklyIngredient.key(for: $0.name) })
        var new: [PackingItem] = []
        for (name, category) in items {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, existing.insert(WeeklyIngredient.key(for: trimmed)).inserted else { continue }
            new.append(PackingItem(tripID: trip.id, name: trimmed, category: category, forWhom: forWhom.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        guard !new.isEmpty else { return 0 }
        change { packingItems += new }
        return new.count
    }

    func togglePacked(_ item: PackingItem) {
        guard let index = packingItems.firstIndex(where: { $0.id == item.id }) else { return }
        change {
            packingItems[index].isPacked.toggle()
            packingItems[index].updatedAt = Date()
        }
    }

    func updatePackingItem(_ item: PackingItem) {
        guard let index = packingItems.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = item
        updated.name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.forWhom = item.forWhom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updated.name.isEmpty, updated != packingItems[index] else { return }
        updated.updatedAt = Date()
        change { packingItems[index] = updated }
    }

    func deletePackingItem(_ item: PackingItem) {
        change { packingItems.removeAll { $0.id == item.id } }
    }

    /// Unpacks everything, for the trip home or reusing the list.
    func unpackAll(in trip: Trip) {
        let now = Date()
        change {
            for index in packingItems.indices where packingItems[index].tripID == trip.id && packingItems[index].isPacked {
                packingItems[index].isPacked = false
                packingItems[index].updatedAt = now
            }
        }
    }

    // MARK: Plan

    func addActivity(_ activity: TripActivity) {
        guard !activity.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        change { activities.append(cleaned(activity)) }
    }

    func updateActivity(_ activity: TripActivity) {
        guard let index = activities.firstIndex(where: { $0.id == activity.id }) else { return }
        var updated = cleaned(activity)
        guard !updated.title.isEmpty, updated != activities[index] else { return }
        updated.updatedAt = Date()
        change { activities[index] = updated }
    }

    func deleteActivity(_ activity: TripActivity) {
        change { activities.removeAll { $0.id == activity.id } }
    }

    private func cleaned(_ activity: TripActivity) -> TripActivity {
        var cleaned = activity
        cleaned.title = activity.title.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.location = activity.location.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.notes = activity.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.hasTime {
            // Any-time activities sit at noon, so time zones can't move them to another day.
            cleaned.date = Calendar.current.startOfDay(for: activity.date).addingTimeInterval(12 * 3_600)
            cleaned.reminderMinutes = nil
        }
        return cleaned
    }

    // MARK: Weather

    func weather(for trip: Trip) -> TripWeather? {
        weather.first { $0.id == trip.id }
    }

    func saveWeather(_ tripWeather: TripWeather) {
        change {
            weather.removeAll { $0.id == tripWeather.id }
            weather.append(tripWeather)
        }
    }

    func setWeatherCallLog(_ log: WeatherCallLog) {
        change { weatherCallLog = log }
    }

    private func change(_ body: () -> Void) {
        let before = exportPayload()
        body()
        let after = exportPayload()
        SyncLedger.shared.recordRemovals(from: before.trips, to: after.trips)
        SyncLedger.shared.recordRemovals(from: before.packingItems, to: after.packingItems)
        SyncLedger.shared.recordRemovals(from: before.activities, to: after.activities)
        SyncLedger.shared.recordRemovals(from: before.weather, to: after.weather)
        save()
        NotificationCenter.default.post(name: .familyDataDidChange, object: self)
    }

    // MARK: Family sharing

    func exportPayload() -> TripsPayload {
        TripsPayload(trips: trips, packingItems: packingItems, activities: activities, weather: weather, weatherCalls: weatherCallLog.map { [$0] } ?? [])
    }

    /// Takes the family's trips. Only assigns what changed; a change from someone else
    /// refreshes the trip reminders, whose text lists what's still unpacked.
    func applySharedData(_ payload: TripsPayload) {
        var changed = false
        if trips != payload.trips { trips = payload.trips; changed = true }
        if packingItems != payload.packingItems { packingItems = payload.packingItems; changed = true }
        if activities != payload.activities { activities = payload.activities; changed = true }
        // Weather doesn't change any reminders.
        let newLog = payload.weatherCalls.max { $0.updatedAt < $1.updatedAt }
        let weatherChanged = weather != payload.weather || weatherCallLog != newLog
        if weatherChanged {
            weather = payload.weather
            weatherCallLog = newLog
        }
        guard changed || weatherChanged else { return }
        save()
        guard changed else { return }
        Task { await NotificationScheduler.shared.reschedule() }
    }

    // MARK: Storage

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        guard let payload = try? JSONDecoder().decode(TripsPayload.self, from: data) else {
            PersistenceBackup.preserveUnreadableFile(at: storageURL)
            return
        }
        trips = payload.trips
        packingItems = payload.packingItems
        activities = payload.activities
        weather = payload.weather
        weatherCallLog = payload.weatherCalls.max { $0.updatedAt < $1.updatedAt }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(exportPayload()) else { return }
        try? data.write(to: storageURL, options: [.atomic])
    }
}
