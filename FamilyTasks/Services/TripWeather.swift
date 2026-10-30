import CoreLocation
import Foundation
import MapKit
import WeatherKit

/// One trip day's weather: Apple Weather's forecast, or last year's weather on the same
/// date as a guide to what's typical.
struct TripDayWeather: Codable, Equatable, Sendable {
    var date: Date
    var symbolName: String
    var conditionText: String
    var highCelsius: Double
    var lowCelsius: Double
    /// 0 to 1; for last year's weather, 1 if it rained and 0 if not.
    var precipitationChance: Double
    var isTypical: Bool

    var highText: String { TripWeatherPlanner.temperatureText(highCelsius) }
    var lowText: String { TripWeatherPlanner.temperatureText(lowCelsius) }
}

/// A trip's weather, shared with the family so only one phone ever looks it up.
struct TripWeather: Identifiable, Codable, Equatable, Sendable {
    /// The trip's id.
    var id: UUID
    /// The place and dates it was looked up for; a change looks it up again.
    var key: String
    var forecast: [TripDayWeather]
    /// The day ("2026-11-20") the forecast was fetched.
    var forecastDay: String?
    /// Last year's weather, moved onto this trip's dates. Fetched once; the past doesn't change.
    var typical: [TripDayWeather]
    var updatedAt: Date

    init(id: UUID, key: String, forecast: [TripDayWeather] = [], forecastDay: String? = nil, typical: [TripDayWeather] = [], updatedAt: Date = Date()) {
        self.id = id
        self.key = key
        self.forecast = forecast
        self.forecastDay = forecastDay
        self.typical = typical
        self.updatedAt = updatedAt
    }
}

/// The family's one weather lookup a day: who made it and whether it worked. Shared, so the
/// rest of the family doesn't make another.
struct WeatherCallLog: Codable, Equatable, Sendable {
    enum Result: String, Codable, Sendable {
        case pending, succeeded, failed
    }

    /// "2026-11-20"
    var day: String
    var result: Result
    var calledBy: String
    var updatedAt: Date
}

/// Decides whether today's single lookup is needed and for which trip, and what each trip
/// shows. Kept free of WeatherKit so it can be tested.
enum TripWeatherPlanner {
    /// Apple Weather forecasts about ten days ahead.
    static let forecastDays = 10
    /// A forecast this old is no longer shown.
    static let forecastShelfLifeDays = 2

    enum Request: Equatable {
        /// The forecast for these days (end exclusive).
        case forecast(tripID: UUID, start: Date, end: Date)
        /// The same dates a year ago (end exclusive), as a guide for a trip further out.
        case lastYear(tripID: UUID, start: Date, end: Date)

        var tripID: UUID {
            switch self {
            case .forecast(let id, _, _), .lastYear(let id, _, _): id
            }
        }
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func key(for trip: Trip, calendar: Calendar = .current) -> String {
        [trip.destination.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), dayKey(trip.startDate, calendar: calendar), dayKey(trip.endDate, calendar: calendar)]
            .joined(separator: "|")
    }

    /// Today's lookup, or nil when the family already made one today or nothing needs it.
    /// A trip starting within ten days gets a fresh forecast; otherwise the soonest trip
    /// without last year's weather gets that, once.
    static func nextRequest(trips: [Trip], weather: [TripWeather], log: WeatherCallLog?, now: Date, calendar: Calendar = .current) -> Request? {
        let todayKey = dayKey(now, calendar: calendar)
        guard log?.day != todayKey else { return nil }
        let today = calendar.startOfDay(for: now)
        guard let windowEnd = calendar.date(byAdding: .day, value: forecastDays, to: today) else { return nil }

        let candidates = trips
            .filter { !$0.isFinished && !$0.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.startDate < $1.startDate }

        for trip in candidates {
            let days = trip.days(calendar: calendar)
            guard let first = days.first, let last = days.last,
                  let afterLast = calendar.date(byAdding: .day, value: 1, to: last),
                  first < windowEnd, afterLast > today else { continue }
            let saved = weather.first { $0.id == trip.id }
            if saved?.key != key(for: trip, calendar: calendar) || saved?.forecastDay != todayKey {
                return .forecast(tripID: trip.id, start: max(first, today), end: min(afterLast, windowEnd))
            }
        }

        for trip in candidates {
            let saved = weather.first { $0.id == trip.id }
            guard saved?.key != key(for: trip, calendar: calendar) || saved?.typical.isEmpty == true else { continue }
            let days = trip.days(calendar: calendar)
            guard let first = days.first, let last = days.last,
                  let start = calendar.date(byAdding: .year, value: -1, to: first),
                  let lastYearLast = calendar.date(byAdding: .year, value: -1, to: last),
                  let end = calendar.date(byAdding: .day, value: 1, to: lastYearLast),
                  end <= today else { continue }
            return .lastYear(tripID: trip.id, start: start, end: end)
        }
        return nil
    }

    /// The weather to show for each of the trip's days, or nil to show none: when there's
    /// nothing for it, or when today's lookup failed (such as when the account's allowance
    /// is used up).
    static func days(for trip: Trip, weather: [TripWeather], log: WeatherCallLog?, now: Date, calendar: Calendar = .current) -> [TripDayWeather]? {
        if let log, log.day == dayKey(now, calendar: calendar), log.result == .failed { return nil }
        guard let saved = weather.first(where: { $0.id == trip.id }), saved.key == key(for: trip, calendar: calendar) else { return nil }

        var forecast: [TripDayWeather] = []
        if let forecastDay = saved.forecastDay,
           let oldest = calendar.date(byAdding: .day, value: -forecastShelfLifeDays, to: calendar.startOfDay(for: now)),
           forecastDay >= dayKey(oldest, calendar: calendar) {
            forecast = saved.forecast
        }
        let today = calendar.startOfDay(for: now)
        let days = trip.days(calendar: calendar).compactMap { day -> TripDayWeather? in
            if day >= today, let match = forecast.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) { return match }
            return saved.typical.first { calendar.isDate($0.date, inSameDayAs: day) }
        }
        return days.isEmpty ? nil : days
    }

    /// Moves last year's days onto this year's trip dates.
    static func movedToTrip(_ days: [TripDayWeather], calendar: Calendar = .current) -> [TripDayWeather] {
        days.compactMap { day in
            guard let date = calendar.date(byAdding: .year, value: 1, to: day.date) else { return nil }
            var moved = day
            moved.date = calendar.startOfDay(for: date)
            moved.isTypical = true
            return moved
        }
    }

    /// In the person's own units: "68°" in the US, "20°" elsewhere.
    static func temperatureText(_ celsius: Double) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}

/// Makes the family's one Apple Weather lookup a day, only when someone opens Trips.
@MainActor
final class TripWeatherService {
    static let shared = TripWeatherService()

    private var isRunning = false

    func refreshIfNeeded(tripStore: TripStore = .shared, now: Date = Date()) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        // Someone else in the family may already have made today's lookup.
        let household = SharedHouseholdStore.shared
        if household.isSharingConfigured, nextRequest(tripStore, now: now) != nil {
            await household.refreshFromCloud()
        }
        guard let request = nextRequest(tripStore, now: now),
              let trip = tripStore.trip(id: request.tripID) else { return }

        // Claim today's lookup before making it, and tell the family straight away.
        let today = TripWeatherPlanner.dayKey(now)
        let me = HabitStore.currentProfileEmail()
        tripStore.setWeatherCallLog(WeatherCallLog(day: today, result: .pending, calledBy: me, updatedAt: now))
        if household.isSharingConfigured {
            await household.uploadNow(waitingAtMost: .seconds(3))
        }

        do {
            let days = try await fetch(request, place: trip.destination)
            guard !days.isEmpty else { throw CocoaError(.featureUnsupported) }
            var saved = tripStore.weather(for: trip) ?? TripWeather(id: trip.id, key: TripWeatherPlanner.key(for: trip))
            if saved.key != TripWeatherPlanner.key(for: trip) {
                saved = TripWeather(id: trip.id, key: TripWeatherPlanner.key(for: trip))
            }
            switch request {
            case .forecast:
                saved.forecast = days
                saved.forecastDay = today
            case .lastYear:
                saved.typical = TripWeatherPlanner.movedToTrip(days)
            }
            saved.updatedAt = Date()
            tripStore.saveWeather(saved)
            tripStore.setWeatherCallLog(WeatherCallLog(day: today, result: .succeeded, calledBy: me, updatedAt: Date()))
            await WeatherCredit.loadIfNeeded()
        } catch {
            // Out of lookups or unreachable: show no weather until tomorrow's try.
            tripStore.setWeatherCallLog(WeatherCallLog(day: today, result: .failed, calledBy: me, updatedAt: Date()))
        }
    }

    private func nextRequest(_ tripStore: TripStore, now: Date) -> TripWeatherPlanner.Request? {
        TripWeatherPlanner.nextRequest(trips: tripStore.trips, weather: tripStore.weather, log: tripStore.weatherCallLog, now: now)
    }

    /// One WeatherKit request, for daily weather only.
    private func fetch(_ request: TripWeatherPlanner.Request, place: String) async throws -> [TripDayWeather] {
        guard let location = await location(for: place) else { throw CocoaError(.fileNoSuchFile) }
        let isForecast: Bool
        let start: Date, end: Date
        switch request {
        case .forecast(_, let from, let to):
            (isForecast, start, end) = (true, from, to)
        case .lastYear(_, let from, let to):
            (isForecast, start, end) = (false, from, to)
        }
        let daily = try await WeatherService.shared.weather(for: location, including: .daily(startDate: start, endDate: end))
        let calendar = Calendar.current
        return daily.forecast.map { day in
            TripDayWeather(
                date: calendar.startOfDay(for: day.date),
                symbolName: day.symbolName,
                conditionText: day.condition.description,
                highCelsius: day.highTemperature.converted(to: .celsius).value,
                lowCelsius: day.lowTemperature.converted(to: .celsius).value,
                precipitationChance: isForecast ? day.precipitationChance : (day.precipitationAmount.converted(to: .millimeters).value >= 1 ? 1 : 0),
                isTypical: !isForecast
            )
        }
    }

    /// Finds the place with Apple Maps, which doesn't count toward weather lookups.
    private func location(for place: String) async -> CLLocation? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = place
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        if #available(iOS 26, *) {
            return item.location
        }
        return CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)
    }
}

/// Apple Weather's required credit: its mark and a link to its data sources. Fetched once
/// per phone and kept; it isn't a weather lookup.
@MainActor
enum WeatherCredit {
    private static let lightKey = "weather.credit.light"
    private static let darkKey = "weather.credit.dark"
    private static let legalKey = "weather.credit.legal"

    static var lightMark: URL? { UserDefaults.standard.url(forKey: lightKey) }
    static var darkMark: URL? { UserDefaults.standard.url(forKey: darkKey) }
    static var legalPage: URL? { UserDefaults.standard.url(forKey: legalKey) }

    static func loadIfNeeded() async {
        guard legalPage == nil, let attribution = try? await WeatherService.shared.attribution else { return }
        UserDefaults.standard.set(attribution.combinedMarkLightURL, forKey: lightKey)
        UserDefaults.standard.set(attribution.combinedMarkDarkURL, forKey: darkKey)
        UserDefaults.standard.set(attribution.legalPageURL, forKey: legalKey)
    }
}
