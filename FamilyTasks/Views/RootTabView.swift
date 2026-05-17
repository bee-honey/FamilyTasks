import SwiftUI

struct RootTabView: View {
    @State private var selection: AppSection? = .today

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Family Tasks") {
                    ForEach(AppSection.primarySections) { section in
                        NavigationLink(value: section) {
                            Label(section.title, systemImage: section.systemImage)
                        }
                        .listRowBackground(AppTheme.surface)
                    }
                }

                Section("Settings") {
                    NavigationLink(value: AppSection.profile) {
                        Label(AppSection.profile.title, systemImage: AppSection.profile.systemImage)
                    }
                    .listRowBackground(AppTheme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
        } detail: {
            switch selection ?? .today {
            case .today:
                TodayTasksView()
            case .matrix:
                TaskBoardView()
            case .shopping:
                ShoppingView()
            case .mealPlan:
                MealPlanView()
            case .recurring:
                RecurringTasksView()
            case .profile:
                ProfileView()
            }
        }
        .tint(AppTheme.primary)
    }
}

private enum AppSection: String, CaseIterable, Identifiable {
    case today
    case matrix
    case shopping
    case mealPlan
    case recurring
    case profile

    var id: String { rawValue }

    static var primarySections: [AppSection] {
        [.today, .matrix, .shopping, .mealPlan, .recurring]
    }

    var title: String {
        switch self {
        case .today: "Schedule"
        case .matrix: "Task Matrix"
        case .shopping: "Shopping"
        case .mealPlan: "Meal Plan"
        case .recurring: "Recurring"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "calendar"
        case .matrix: "square.grid.2x2"
        case .shopping: "cart"
        case .mealPlan: "fork.knife"
        case .recurring: "repeat"
        case .profile: "person.crop.circle"
        }
    }
}
