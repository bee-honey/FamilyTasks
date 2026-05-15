import EventKit
import Foundation

@MainActor
final class CalendarSyncService: ObservableObject {
    @Published private(set) var authorizationStatus: EKAuthorizationStatus
    @Published private(set) var todayEvents: [CalendarDayEvent] = []
    @Published private(set) var isLoadingTodayEvents = false
    @Published var lastErrorMessage: String?

    private let eventStore = EKEventStore()

    init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    func requestAccessIfNeeded() async -> Bool {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)

        switch authorizationStatus {
        case .fullAccess, .authorized:
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
        guard await requestFullAccessForReadingIfNeeded() else { return }

        isLoadingTodayEvents = true
        defer { isLoadingTodayEvents = false }

        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)

        todayEvents = eventStore.events(matching: predicate)
            .filter { !$0.isDetached }
            .map(CalendarDayEvent.init(event:))
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay {
                    return lhs.isAllDay
                }
                return lhs.startDate < rhs.startDate
            }
    }

    func clearTodayEvents() {
        todayEvents = []
        lastErrorMessage = nil
    }

    func removeTodayEvent(_ event: CalendarDayEvent) {
        todayEvents.removeAll { $0.id == event.id }
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
        return calendars.first { $0.allowsContentModifications && $0.source.title.localizedCaseInsensitiveContains("google") }
            ?? eventStore.defaultCalendarForNewEvents
            ?? calendars.first { $0.allowsContentModifications }
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
