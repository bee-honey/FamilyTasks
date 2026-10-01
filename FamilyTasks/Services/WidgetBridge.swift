import Combine
import Foundation
import WidgetKit

/// Keeps the widgets' snapshot up to date and applies check-offs made in widgets.
@MainActor
final class WidgetBridge {
    static let shared = WidgetBridge()

    private let storage: WidgetStorage?
    private weak var taskStore: TaskStore?
    private weak var organizerStore: OrganizerStore?
    private var observation: AnyCancellable?
    private var lastPublished: WidgetSnapshot?

    init(storage: WidgetStorage? = WidgetStorage.shared) {
        self.storage = storage
    }

    func configure(taskStore: TaskStore, organizerStore: OrganizerStore) {
        guard self.taskStore !== taskStore || self.organizerStore !== organizerStore else { return }
        self.taskStore = taskStore
        self.organizerStore = organizerStore

        // Covers local edits and data arriving from family sharing alike.
        observation = taskStore.objectWillChange
            .merge(with: organizerStore.objectWillChange)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.publish()
                }
            }

        applyPendingActions()
        publish()
    }

    /// Applies check-offs made in widgets since the app last ran.
    func applyPendingActions() {
        guard let storage, let taskStore, let organizerStore else { return }
        for (url, action) in storage.pendingActions() {
            switch action.kind {
            case .completeTask:
                taskStore.markDone(taskID: action.id, at: action.date)
            case .purchaseItem:
                organizerStore.markPurchased(itemID: action.id, at: action.date)
            }
            storage.removeAction(at: url)
        }
    }

    func publish() {
        guard let storage, let taskStore, let organizerStore else { return }

        var snapshot = Self.snapshot(
            tasks: taskStore.visibleTasks,
            shops: organizerStore.shops,
            items: organizerStore.shoppingItems
        )
        // Keep showing check-offs the app has not applied yet.
        for (_, action) in storage.pendingActions() {
            snapshot.apply(action)
        }

        guard snapshot != lastPublished else { return }
        storage.save(snapshot)
        lastPublished = snapshot
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func snapshot(tasks: [FamilyTask], shops: [Shop], items: [ShoppingItem], now: Date = Date(), calendar: Calendar = .current) -> WidgetSnapshot {
        let horizon = calendar.date(byAdding: .day, value: 8, to: calendar.startOfDay(for: now)) ?? now
        let taskRows = tasks
            .compactMap { task -> WidgetSnapshot.TaskRow? in
                guard !task.isDone, let dueDate = task.dueDate, dueDate < horizon else { return nil }
                return WidgetSnapshot.TaskRow(id: task.id, title: task.title, dueDate: dueDate, isUrgent: task.isUrgent, isImportant: task.isImportant)
            }
            .sorted { lhs, rhs in
                if (lhs.isUrgent && lhs.isImportant) != (rhs.isUrgent && rhs.isImportant) {
                    return lhs.isUrgent && lhs.isImportant
                }
                return lhs.dueDate < rhs.dueDate
            }

        let shopRows = shops.map { shop in
            WidgetSnapshot.ShopRow(
                id: shop.id,
                name: shop.name,
                items: items
                    .filter { $0.shopID == shop.id && $0.isNeeded && !$0.isPurchased }
                    .sorted { $0.createdAt < $1.createdAt }
                    .map { WidgetSnapshot.ItemRow(id: $0.id, name: $0.name) }
            )
        }

        return WidgetSnapshot(tasks: taskRows, shops: shopRows)
    }
}
