import EventKit
import Foundation

@MainActor
final class CalendarSyncService: ObservableObject {
    @Published private(set) var authorizationStatus: EKAuthorizationStatus
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

enum CalendarSyncError: LocalizedError {
    case accessDenied

    var errorDescription: String? {
        "Calendar access is required before tasks can sync."
    }
}
