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
                    }
                }

                Section("Settings") {
                    NavigationLink(value: AppSection.profile) {
                        Label(AppSection.profile.title, systemImage: AppSection.profile.systemImage)
                    }
                }
            }
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
            case .recurring:
                RecurringTasksView()
            case .profile:
                ProfileView()
            }
        }
    }
}

private enum AppSection: String, CaseIterable, Identifiable {
    case today
    case matrix
    case shopping
    case recurring
    case profile

    var id: String { rawValue }

    static var primarySections: [AppSection] {
        [.today, .matrix, .shopping, .recurring]
    }

    var title: String {
        switch self {
        case .today: "Today"
        case .matrix: "Task Matrix"
        case .shopping: "Shopping"
        case .recurring: "Recurring"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .matrix: "square.grid.2x2"
        case .shopping: "cart"
        case .recurring: "repeat"
        case .profile: "person.crop.circle"
        }
    }
}
