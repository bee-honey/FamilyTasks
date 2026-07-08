import EventKit
import Foundation

@MainActor
final class CalendarSyncService: ObservableObject {
    @Published private(set) var authorizationStatus: EKAuthorizationStatus
    @Published private(set) var dayEvents: [CalendarDayEvent] = []
    @Published private(set) var isLoadingTodayEvents = false
    @Published private(set) var lastRefreshDate: Date?
    @Published private(set) var availableCalendars: [CalendarSelectionOption] = []
    @Published var lastErrorMessage: String?

    private let eventStore = EKEventStore()
    private let defaults = UserDefaults.standard

    private enum DefaultsKey {
        static let selectedReadCalendarIDs = "calendar.selectedReadCalendarIDs"
        static let readCalendarSelectionConfigured = "calendar.readCalendarSelectionConfigured"
        static let selectedWriteCalendarID = "calendar.selectedWriteCalendarID"
    }

    init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        refreshAvailableCalendars()
    }

    func requestAccessIfNeeded() async -> Bool {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)

        switch authorizationStatus {
        case .fullAccess, .authorized:
            refreshAvailableCalendars()
            return true
        case .notDetermined:
            do {
                let granted: Bool
                if #available(iOS 17.0, *) {
                    granted = try await eventStore.requestFullAccessToEvents()
                } else {
                    granted = try await eventStore.requestAccess(to: .event)
                }
                authorizationStatus = EKEventStore.authorizationStatus(for: .event)
                refreshAvailableCalendars()
                return granted
            } catch {
                lastErrorMessage = error.localizedDescription
                return false
            }
        case .writeOnly:
            return true
        case .denied, .restricted:
            lastErrorMessage = "Calendar access is disabled. Enable it in Settings to sync tasks."
            return false
        @unknown default:
            return false
        }
    }

    func requestFullAccessForReadingIfNeeded() async -> Bool {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)

        switch authorizationStatus {
        case .fullAccess, .authorized:
            refreshAvailableCalendars()
            return true
        case .notDetermined:
            do {
                let granted: Bool
                if #available(iOS 17.0, *) {
                    granted = try await eventStore.requestFullAccessToEvents()
                } else {
                    granted = try await eventStore.requestAccess(to: .event)
                }
                authorizationStatus = EKEventStore.authorizationStatus(for: .event)
                refreshAvailableCalendars()
                return granted
            } catch {
                lastErrorMessage = error.localizedDescription
                return false
            }
        case .writeOnly:
            lastErrorMessage = "Full calendar access is required to show calendar events in Today."
            return false
        case .denied, .restricted:
            lastErrorMessage = "Calendar access is disabled. Enable it in Settings to show calendar events."
            return false
        @unknown default:
            return false
        }
    }

    func loadTodayEvents(calendar: Calendar = .current) async {
        await loadEvents(on: Date(), calendar: calendar)
    }

    func loadEvents(on date: Date, calendar: Calendar = .current) async {
        guard await requestFullAccessForReadingIfNeeded() else { return }

        isLoadingTodayEvents = true
        defer { isLoadingTodayEvents = false }

        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let calendars = selectedReadCalendars()
        guard !calendars.isEmpty else {
            dayEvents = []
            lastRefreshDate = Date()
            return
        }

        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: calendars)

        dayEvents = eventStore.events(matching: predicate)
            .filter { !$0.isDetached }
            .map(CalendarDayEvent.init(event:))
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay {
                    return lhs.isAllDay
                }
                return lhs.startDate < rhs.startDate
            }
        lastRefreshDate = Date()
    }

    func clearTodayEvents() {
        dayEvents = []
        lastErrorMessage = nil
    }

    func removeTodayEvent(_ event: CalendarDayEvent) {
        dayEvents.removeAll { $0.id == event.id }
    }

    func refreshAvailableCalendars() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        availableCalendars = eventStore.calendars(for: .event)
            .map(CalendarSelectionOption.init(calendar:))
            .sorted { lhs, rhs in
                if lhs.sourceTitle != rhs.sourceTitle {
                    return lhs.sourceTitle.localizedCaseInsensitiveCompare(rhs.sourceTitle) == .orderedAscending
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        removeStaleCalendarSelections()
    }

    var selectedReadCalendarIDs: Set<String> {
        guard defaults.bool(forKey: DefaultsKey.readCalendarSelectionConfigured) else {
            return Set(availableCalendars.map(\.id))
        }
        return decodedCalendarIDs(from: defaults.string(forKey: DefaultsKey.selectedReadCalendarIDs) ?? "")
    }

    var selectedWriteCalendarID: String? {
        defaults.string(forKey: DefaultsKey.selectedWriteCalendarID)
    }

    func setReadCalendar(_ option: CalendarSelectionOption, isSelected: Bool) {
        var ids = selectedReadCalendarIDs
        if isSelected {
            ids.insert(option.id)
        } else {
            ids.remove(option.id)
        }
        defaults.set(true, forKey: DefaultsKey.readCalendarSelectionConfigured)
        defaults.set(encodedCalendarIDs(ids), forKey: DefaultsKey.selectedReadCalendarIDs)
        objectWillChange.send()
    }

    func setWriteCalendar(_ option: CalendarSelectionOption?) {
        if let option {
            defaults.set(option.id, forKey: DefaultsKey.selectedWriteCalendarID)
        } else {
            defaults.removeObject(forKey: DefaultsKey.selectedWriteCalendarID)
        }
        objectWillChange.send()
    }

    func selectAllReadCalendars() {
        defaults.set(true, forKey: DefaultsKey.readCalendarSelectionConfigured)
        defaults.set(encodedCalendarIDs(Set(availableCalendars.map(\.id))), forKey: DefaultsKey.selectedReadCalendarIDs)
        objectWillChange.send()
    }

    func sync(_ task: FamilyTask) async throws -> String {
        guard await requestAccessIfNeeded() else {
            throw CalendarSyncError.accessDenied
        }

        let event = task.calendarEventIdentifier
            .flatMap { eventStore.event(withIdentifier: $0) }
            ?? EKEvent(eventStore: eventStore)

        event.title = task.title
        event.notes = task.notes.isEmpty ? nil : task.notes
        event.calendar = bestCalendar()

        let start = task.dueDate ?? Date()
        event.startDate = start
        event.endDate = Calendar.current.date(byAdding: .minute, value: 30, to: start) ?? start.addingTimeInterval(1800)
        event.availability = .busy

        try eventStore.save(event, span: .thisEvent, commit: true)
        return event.eventIdentifier
    }

    private func bestCalendar() -> EKCalendar? {
        let calendars = eventStore.calendars(for: .event)
        if let selectedWriteCalendarID,
           let selectedCalendar = calendars.first(where: { $0.calendarIdentifier == selectedWriteCalendarID && $0.allowsContentModifications }) {
            return selectedCalendar
        }

        return eventStore.defaultCalendarForNewEvents
            ?? calendars.first { $0.allowsContentModifications && $0.source.title.localizedCaseInsensitiveContains("google") }
            ?? calendars.first { $0.allowsContentModifications }
    }

    private func selectedReadCalendars() -> [EKCalendar] {
        let calendars = eventStore.calendars(for: .event)
        guard defaults.bool(forKey: DefaultsKey.readCalendarSelectionConfigured) else {
            return calendars
        }

        let selectedIDs = selectedReadCalendarIDs
        return calendars.filter { selectedIDs.contains($0.calendarIdentifier) }
    }

    private func removeStaleCalendarSelections() {
        let validIDs = Set(availableCalendars.map(\.id))
        let readIDs = selectedReadCalendarIDs.intersection(validIDs)
        if defaults.bool(forKey: DefaultsKey.readCalendarSelectionConfigured) {
            defaults.set(encodedCalendarIDs(readIDs), forKey: DefaultsKey.selectedReadCalendarIDs)
        }

        if let selectedWriteCalendarID, !validIDs.contains(selectedWriteCalendarID) {
            defaults.removeObject(forKey: DefaultsKey.selectedWriteCalendarID)
        }
    }

    private func decodedCalendarIDs(from rawValue: String) -> Set<String> {
        Set(rawValue.split(separator: "|").map(String.init))
    }

    private func encodedCalendarIDs(_ ids: Set<String>) -> String {
        ids.sorted().joined(separator: "|")
    }
}

struct CalendarSelectionOption: Identifiable, Equatable {
    let id: String
    let title: String
    let sourceTitle: String
    let allowsContentModifications: Bool

    init(calendar: EKCalendar) {
        id = calendar.calendarIdentifier
        title = calendar.title
        sourceTitle = calendar.source.title
        allowsContentModifications = calendar.allowsContentModifications
    }

    var displayTitle: String {
        "\(title) (\(sourceTitle))"
    }
}

extension EKAuthorizationStatus {
    var displayTitle: String {
        switch self {
        case .notDetermined:
            return "Not Connected"
        case .restricted:
            return "Restricted"
        case .denied:
            return "Denied"
        case .authorized, .fullAccess:
            return "Connected"
        case .writeOnly:
            return "Write Only"
        @unknown default:
            return "Unknown"
        }
    }
}

struct CalendarDayEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let calendarTitle: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let notes: String

    init(event: EKEvent) {
        id = event.eventIdentifier ?? "\(event.calendarItemIdentifier)-\(event.startDate.timeIntervalSince1970)"
        title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? event.title : "Untitled event"
        calendarTitle = event.calendar.title
        startDate = event.startDate
        endDate = event.endDate
        isAllDay = event.isAllDay
        notes = event.notes ?? ""
    }
}

enum CalendarSyncError: LocalizedError {
    case accessDenied

    var errorDescription: String? {
        "Calendar access is required before tasks can sync."
    }
}
