import AppIntents

/// Phrases Siri, Spotlight and the Action button offer without any setup.
struct FamilyTasksShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Add a task in \(.applicationName)",
                "Add a task for \(\.$assignee) in \(.applicationName)",
                "Add a \(.applicationName) task"
            ],
            shortTitle: "Add Task",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: TodayTasksIntent(),
            phrases: [
                "What's due today in \(.applicationName)",
                "What do I have today in \(.applicationName)",
                "Show today's \(.applicationName)"
            ],
            shortTitle: "Due Today",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: MarkTaskDoneIntent(),
            phrases: [
                "Mark \(\.$task) done in \(.applicationName)",
                "Mark a task done in \(.applicationName)",
                "I finished \(\.$task) in \(.applicationName)"
            ],
            shortTitle: "Mark Task Done",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: AddShoppingItemIntent(),
            phrases: [
                "Add to my shopping list in \(.applicationName)",
                "Add to my \(\.$shop) list in \(.applicationName)",
                "Add shopping item in \(.applicationName)",
                "Use \(.applicationName) to add to my shopping list"
            ],
            shortTitle: "Add Shopping Item",
            systemImageName: "cart.badge.plus"
        )
    }
}
