import XCTest
@testable import FamilyTasks

@MainActor
final class TripModelTests: XCTestCase {
    private let calendar = Calendar.current

    private func day(_ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func thanksgiving() -> Trip {
        Trip(name: "Thanksgiving", destination: "San Diego", startDate: day(11, 23), endDate: day(11, 27))
    }

    func testTripDaysAndPhase() {
        let trip = thanksgiving()
        XCTAssertEqual(trip.days(calendar: calendar).count, 5)
        XCTAssertEqual(trip.days(calendar: calendar).last, day(11, 27))
        XCTAssertEqual(trip.phase(now: day(10, 29, hour: 15), calendar: calendar), .upcoming(daysAway: 25))
        XCTAssertEqual(trip.phaseText(now: day(11, 22, hour: 9), calendar: calendar), "Tomorrow")
        XCTAssertEqual(trip.phaseText(now: day(11, 24, hour: 9), calendar: calendar), "Day 2 of 5")
        XCTAssertEqual(trip.phase(now: day(11, 28), calendar: calendar), .finished)

        // The end can't come before the start.
        XCTAssertEqual(Trip(name: "Oops", startDate: day(11, 23), endDate: day(11, 20)).dayCount(calendar: calendar), 1)
    }

    func testShareTextListsThePlanByDayAndThePackingList() {
        let trip = thanksgiving()
        let activities = [
            TripActivity(tripID: trip.id, title: "Zoo", date: day(11, 24, hour: 10), hasTime: true, location: "Balboa Park"),
            TripActivity(tripID: trip.id, title: "Flight home", date: day(11, 27, hour: 17), hasTime: true),
            TripActivity(tripID: trip.id, title: "Beach day", date: day(11, 24, hour: 12)),
            TripActivity(tripID: UUID(), title: "Another trip", date: day(11, 24, hour: 12))
        ]
        let packing = [
            PackingItem(tripID: trip.id, name: "Sunscreen", category: .toiletries, isPacked: true),
            PackingItem(tripID: trip.id, name: "Passports", category: .documents, forWhom: "Everyone")
        ]

        let text = TripShareText.text(for: trip, packing: packing, activities: activities, calendar: calendar)

        XCTAssertTrue(text.hasPrefix("Thanksgiving\nSan Diego · "))
        XCTAssertTrue(text.contains("5 days"))
        XCTAssertTrue(text.contains("Day 2 · "))
        XCTAssertTrue(text.contains("Zoo (Balboa Park)"))
        XCTAssertFalse(text.contains("Another trip"))
        XCTAssertFalse(text.contains("Day 1 · "), "Days with nothing planned are left out")
        // Timed plans come before any-time ones.
        XCTAssertLessThan(text.range(of: "Zoo")!.lowerBound, text.range(of: "Beach day")!.lowerBound)
        XCTAssertTrue(text.contains("PACKING · 1 of 2 packed"))
        XCTAssertTrue(text.contains("☐ Passports (Everyone)"))
        XCTAssertTrue(text.contains("☑ Sunscreen"))
        // Documents come before toiletries.
        XCTAssertLessThan(text.range(of: "Passports")!.lowerBound, text.range(of: "Sunscreen")!.lowerBound)
    }

    func testPlanAndPackingListShareSeparately() {
        var trip = thanksgiving()
        trip.notes = "Hotel: Hilton Bayfront"
        let activities = [TripActivity(tripID: trip.id, title: "Zoo", date: day(11, 24, hour: 10), hasTime: true)]
        let packing = [PackingItem(tripID: trip.id, name: "Passports", category: .documents)]

        let plan = TripShareText.text(for: trip, packing: packing, activities: activities, part: .plan, calendar: calendar)
        XCTAssertTrue(plan.contains("Zoo") && plan.contains("Hilton"))
        XCTAssertFalse(plan.contains("PACKING") || plan.contains("Passports"))

        let list = TripShareText.text(for: trip, packing: packing, activities: activities, part: .packing, calendar: calendar)
        XCTAssertTrue(list.hasPrefix("Thanksgiving · Packing List\n"))
        XCTAssertTrue(list.contains("☐ Passports"))
        XCTAssertFalse(list.contains("Zoo") || list.contains("Hilton"))

        XCTAssertTrue(TripShareText.text(for: trip, packing: [], activities: activities, part: .packing, calendar: calendar).contains("Nothing on the packing list yet."))
    }

    func testMapsLinksFindThePlaceNearTheDestination() {
        XCTAssertEqual(TripMaps.query(for: "Balboa Park", near: "San Diego"), "Balboa Park, San Diego")
        XCTAssertEqual(TripMaps.query(for: "Old Town San Diego", near: "san diego"), "Old Town San Diego")
        XCTAssertEqual(TripMaps.query(for: "Balboa Park", near: ""), "Balboa Park")
        XCTAssertEqual(TripMaps.query(for: "", near: "San Diego"), "San Diego")

        XCTAssertEqual(TripMaps.url(for: "Balboa Park, San Diego", in: .apple)?.absoluteString, "https://maps.apple.com/?q=Balboa%20Park,%20San%20Diego")
        XCTAssertEqual(TripMaps.url(for: "Zoo & Park", in: .google)?.absoluteString, "https://www.google.com/maps/search/?api=1&query=Zoo%20%26%20Park")
        XCTAssertEqual(TripMaps.url(for: "Zoo", in: .google, directions: true)?.absoluteString, "https://www.google.com/maps/dir/?api=1&destination=Zoo")
        XCTAssertEqual(TripMaps.url(for: "Zoo", in: .apple, directions: true)?.absoluteString, "https://maps.apple.com/?daddr=Zoo")
    }

    func testTripAlertsRemindWhatsLeftToPackAndUpcomingPlans() throws {
        let trip = thanksgiving()
        let payload = TripsPayload(
            trips: [trip],
            packingItems: [
                PackingItem(tripID: trip.id, name: "Passports", category: .documents),
                PackingItem(tripID: trip.id, name: "Chargers", category: .electronics),
                PackingItem(tripID: trip.id, name: "Socks", category: .clothes, isPacked: true)
            ],
            activities: [
                TripActivity(tripID: trip.id, title: "Zoo", date: day(11, 24, hour: 10), hasTime: true, location: "Balboa Park", reminderMinutes: 30),
                TripActivity(tripID: trip.id, title: "Tacos", date: day(11, 24, hour: 12))
            ]
        )

        let alerts = NotificationScheduler.tripAlerts(payload, now: day(10, 29), calendar: calendar)
        func alert(_ suffix: String) -> TripAlertInfo? {
            alerts.first { $0.request.identifier.hasSuffix(suffix) }.map { TripAlertInfo(date: $0.fireDate, title: $0.request.content.title, body: $0.request.content.body) }
        }

        let leaving = try XCTUnwrap(alert(".leaving"))
        XCTAssertEqual(leaving.date, day(11, 23, hour: 6))
        XCTAssertEqual(leaving.title, "Off to San Diego today")
        XCTAssertTrue(leaving.body.contains("Passports") && leaving.body.contains("Chargers"))
        XCTAssertFalse(leaving.body.contains("Socks"))

        XCTAssertEqual(try XCTUnwrap(alert(".eve")).date, day(11, 22, hour: 20))

        let plan = try XCTUnwrap(alert(".day1"))
        XCTAssertEqual(plan.date, day(11, 24, hour: 8))
        XCTAssertEqual(plan.title, "Day 2 in San Diego")
        XCTAssertTrue(plan.body.contains("Zoo") && plan.body.contains("Tacos"))
        XCTAssertNil(alert(".day0"), "No morning plan on a day with nothing planned")

        let zoo = try XCTUnwrap(alert(".activity"))
        XCTAssertEqual(zoo.date, day(11, 24, hour: 9, minute: 30))
        XCTAssertTrue(zoo.body.contains("Balboa Park"))

        // Once the trip has started, earlier reminders aren't scheduled.
        let later = NotificationScheduler.tripAlerts(payload, now: day(11, 24, hour: 9), calendar: calendar)
        XCTAssertEqual(later.map { $0.request.identifier.components(separatedBy: ".").last }, ["activity"])
        XCTAssertFalse(later.contains { $0.request.identifier.hasSuffix(".leaving") })
    }

    func testTripAlertsAreOffWhenTurnedOff() {
        var trip = thanksgiving()
        trip.packingReminderEnabled = false
        trip.dailyPlanEnabled = false
        let payload = TripsPayload(
            trips: [trip],
            packingItems: [PackingItem(tripID: trip.id, name: "Passports")],
            activities: [TripActivity(tripID: trip.id, title: "Zoo", date: day(11, 24, hour: 10), hasTime: true)]
        )
        XCTAssertTrue(NotificationScheduler.tripAlerts(payload, now: day(10, 29), calendar: calendar).isEmpty)
    }

    func testStoreStartsPackingFromListsAndAnotherTripWithoutDuplicates() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = TripStore(directory: directory, ownerEmail: { "me@example.com" })

        let first = store.addTrip(name: "Tahoe", destination: "", startDate: day(1, 10), endDate: day(1, 12), packingLists: [.coldWeather])
        store.addPackingItems([("Snow chains", .travel)], to: first)

        let second = store.addTrip(
            name: "", destination: "San Diego", startDate: day(11, 23), endDate: day(11, 27),
            packingLists: [.essentials, .coldWeather], copyingPackingFrom: first
        )
        let names = store.packing(for: second).map(\.name)
        XCTAssertEqual(second.displayName, "Trip to San Diego")
        XCTAssertTrue(names.contains("Snow chains"))
        XCTAssertEqual(names.filter { $0 == "Gloves" }.count, 1)
        XCTAssertEqual(names.count, Set(names).count)
        XCTAssertEqual(second.createdBy, "me@example.com")

        // Adding something already there is skipped, whatever its case.
        XCTAssertEqual(store.addPackingItems([("gloves ", .clothes), ("Sunscreen", .toiletries)], to: second), 1)

        let item = try XCTUnwrap(store.packing(for: second).first)
        store.togglePacked(item)
        XCTAssertTrue(try XCTUnwrap(store.packing(for: second).first).isPacked)
        store.unpackAll(in: second)
        XCTAssertFalse(store.packing(for: second).contains(where: \.isPacked))

        // An any-time plan sits at noon with no reminder.
        store.addActivity(TripActivity(tripID: second.id, title: " Beach ", date: day(11, 24, hour: 7), reminderMinutes: 30))
        let beach = try XCTUnwrap(store.activities(for: second).first)
        XCTAssertEqual(beach.title, "Beach")
        XCTAssertEqual(beach.date, day(11, 24, hour: 12))
        XCTAssertNil(beach.reminderMinutes)

        // Saved and read back.
        let reloaded = TripStore(directory: directory)
        XCTAssertEqual(reloaded.exportPayload(), store.exportPayload())

        store.deleteTrip(second)
        XCTAssertTrue(store.packing(for: second).isEmpty)
        XCTAssertTrue(store.activities(for: second).isEmpty)
        XCTAssertEqual(store.trips.map(\.id), [first.id])
    }

    func testTripsTravelAsHouseholdRecords() {
        let trip = thanksgiving()
        let trips = TripsPayload(
            trips: [trip],
            packingItems: [PackingItem(tripID: trip.id, name: "Passports")],
            activities: [TripActivity(tripID: trip.id, title: "Zoo", date: day(11, 24, hour: 10), hasTime: true, reminderMinutes: 30)]
        )
        let records = HouseholdRecords.records(from: SharedHouseholdPayload(trips: trips), updatedBy: "me@example.com")

        XCTAssertEqual(records[trip.id.uuidString]?.kind, .trip)
        XCTAssertEqual(HouseholdRecords.payload(from: Array(records.values)).trips, trips)

        // A household saved before trips existed still loads.
        let old = try? JSONDecoder().decode(SharedHouseholdPayload.self, from: Data(#"{"tasks":[]}"#.utf8))
        XCTAssertEqual(old?.trips, TripsPayload())
    }

    // MARK: Weather

    private func weatherDay(_ month: Int, _ dayOfMonth: Int, high: Double = 20, typical: Bool = false) -> TripDayWeather {
        TripDayWeather(date: day(month, dayOfMonth), symbolName: "sun.max", conditionText: "Sunny", highCelsius: high, lowCelsius: 10, precipitationChance: 0, isTypical: typical)
    }

    func testOneWeatherLookupADayForTheWholeFamily() {
        let trip = thanksgiving()
        let farAway = day(10, 30, hour: 9)

        // Weeks out: last year's weather for the same dates, once.
        let first = TripWeatherPlanner.nextRequest(trips: [trip], weather: [], log: nil, now: farAway, calendar: calendar)
        XCTAssertEqual(first, .lastYear(tripID: trip.id, start: calendar.date(from: DateComponents(year: 2025, month: 11, day: 23))!, end: calendar.date(from: DateComponents(year: 2025, month: 11, day: 28))!))

        // Anyone in the family already looked today: no more lookups, whatever happened.
        for result in [WeatherCallLog.Result.pending, .succeeded, .failed] {
            let log = WeatherCallLog(day: "2026-10-30", result: result, calledBy: "dad@example.com", updatedAt: farAway)
            XCTAssertNil(TripWeatherPlanner.nextRequest(trips: [trip], weather: [], log: log, now: farAway, calendar: calendar))
        }

        // Once last year's weather is in, nothing more until the forecast range.
        let key = TripWeatherPlanner.key(for: trip, calendar: calendar)
        let saved = TripWeather(id: trip.id, key: key, typical: [weatherDay(11, 23, typical: true)])
        let yesterday = WeatherCallLog(day: "2026-10-29", result: .succeeded, calledBy: "", updatedAt: farAway)
        XCTAssertNil(TripWeatherPlanner.nextRequest(trips: [trip], weather: [saved], log: yesterday, now: farAway, calendar: calendar))

        // Ten days before: a fresh forecast each day.
        let close = day(11, 15, hour: 9)
        XCTAssertEqual(
            TripWeatherPlanner.nextRequest(trips: [trip], weather: [saved], log: yesterday, now: close, calendar: calendar),
            .forecast(tripID: trip.id, start: day(11, 23), end: day(11, 25))
        )
        var fresh = saved
        fresh.forecastDay = "2026-11-15"
        XCTAssertNil(TripWeatherPlanner.nextRequest(trips: [trip], weather: [fresh], log: nil, now: close, calendar: calendar))

        // Moving the trip looks it up again.
        var moved = trip
        moved.destination = "Seattle"
        XCTAssertNotNil(TripWeatherPlanner.nextRequest(trips: [moved], weather: [fresh], log: yesterday, now: close, calendar: calendar))
    }

    func testWeatherIsHiddenWhenTodaysLookupFailed() {
        let trip = thanksgiving()
        let now = day(11, 22, hour: 9)
        let saved = TripWeather(
            id: trip.id,
            key: TripWeatherPlanner.key(for: trip, calendar: calendar),
            forecast: [weatherDay(11, 23, high: 22), weatherDay(11, 24, high: 23)],
            forecastDay: "2026-11-22",
            typical: [weatherDay(11, 23, high: 18, typical: true), weatherDay(11, 26, high: 17, typical: true)]
        )

        let shown = TripWeatherPlanner.days(for: trip, weather: [saved], log: nil, now: now, calendar: calendar)
        XCTAssertEqual(shown?.map(\.highCelsius), [22, 23, 17], "Forecast first, then last year's for later days")

        let failed = WeatherCallLog(day: "2026-11-22", result: .failed, calledBy: "", updatedAt: now)
        XCTAssertNil(TripWeatherPlanner.days(for: trip, weather: [saved], log: failed, now: now, calendar: calendar))

        // A forecast gets too old to show; last year's stays.
        let later = day(11, 26, hour: 9)
        XCTAssertEqual(TripWeatherPlanner.days(for: trip, weather: [saved], log: nil, now: later, calendar: calendar)?.map(\.highCelsius), [18, 17])

        let lastYear = calendar.date(from: DateComponents(year: 2025, month: 11, day: 23))!
        let moved = TripWeatherPlanner.movedToTrip([TripDayWeather(date: lastYear, symbolName: "cloud", conditionText: "", highCelsius: 1, lowCelsius: 0, precipitationChance: 0, isTypical: false)], calendar: calendar)
        XCTAssertEqual(moved.first?.date, day(11, 23))
        XCTAssertEqual(moved.first?.isTypical, true)
    }

    func testWeatherTravelsWithTheTripRecords() {
        let trip = thanksgiving()
        let weather = TripWeather(id: trip.id, key: "k", typical: [weatherDay(11, 23, typical: true)])
        let log = WeatherCallLog(day: "2026-10-30", result: .succeeded, calledBy: "me@example.com", updatedAt: day(10, 30))
        let trips = TripsPayload(trips: [trip], weather: [weather], weatherCalls: [log])
        let records = HouseholdRecords.records(from: SharedHouseholdPayload(trips: trips), updatedBy: "me@example.com")
        XCTAssertEqual(records[trip.id.uuidString]?.kind, .trip, "The weather doesn't replace the trip's own record")
        XCTAssertEqual(HouseholdRecords.payload(from: Array(records.values)).trips, trips)
    }

    func testReminderText() {
        XCTAssertEqual(TripReminders.reminderText(nil), "None")
        XCTAssertEqual(TripReminders.reminderText(0), "At the time")
        XCTAssertEqual(TripReminders.reminderText(30), "30 minutes before")
        XCTAssertEqual(TripReminders.reminderText(120), "2 hours before")
        XCTAssertEqual(TripReminders.reminderText(1_440), "1 day before")
        XCTAssertEqual(TripReminders.listText(["A", "B", "C", "D", "E", "F"]), "A, B, C, D and 2 more")
    }
}

private struct TripAlertInfo {
    let date: Date
    let title: String
    let body: String
}
