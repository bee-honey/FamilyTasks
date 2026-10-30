import SwiftUI

struct HealthView: View {
    var isPushed = false
    @EnvironmentObject private var organizerStore: OrganizerStore
    @EnvironmentObject private var taskStore: TaskStore
    @EnvironmentObject private var sharedHouseholdStore: SharedHouseholdStore
    @EnvironmentObject private var goalStore: HealthGoalStore
    @AppStorage("profile.email") private var profileEmail = ""
    @StateObject private var healthService = HealthMetricsService()
    @State private var selectedScope = HealthMetricScope.week
    @AppStorage("health.section.enabled") private var healthSectionEnabled = false
    @AppStorage("health.share.enabled") private var healthSharingEnabled = false
    @State private var isShowingSettings = false
    @State private var editingGoal: GoalEditing?

    /// Which goal editor is open: a new goal or challenge, or an existing one.
    private enum GoalEditing: Identifiable {
        case new(HealthGoal.Kind)
        case existing(HealthGoal)

        var id: String {
            switch self {
            case .new(let kind): "new-\(kind.rawValue)"
            case .existing(let goal): goal.id.uuidString
            }
        }
    }

    var body: some View {
        List {
            Section {
                ScreenHeader(eyebrow: "You and your family", title: "Health") {
                    if healthSectionEnabled {
                        Button {
                            Task { await refresh() }
                        } label: {
                            Group {
                                if healthService.isLoading {
                                    ProgressView()
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.headline)
                                }
                            }
                            .foregroundStyle(AppTheme.ink)
                            .frame(width: 44, height: 44)
                            .background(AppTheme.surface, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(healthService.isLoading)
                        .accessibilityLabel(healthService.isLoading ? "Refreshing health data" : "Refresh health data")
                    }
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                            .frame(width: 44, height: 44)
                            .background(AppTheme.surface, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Health settings")
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 4))
            .listRowBackground(Color.clear)

            if healthSectionEnabled {
                mySections
                familySections
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        IconTile(systemImage: "heart.fill", tint: SettingsTint.health, size: 44)
                        Text("Health is off")
                            .font(.headline)
                        Text("Turn it on to see your activity, sleep score, heart and BMI, set goals, and cheer each other on if you share with your family. Each person turns it on on their own phone.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button {
                            isShowingSettings = true
                        } label: {
                            PillButtonLabel(title: "Set Up Health", systemImage: "heart", isProminent: true)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 6)
                }
            }

            Section {
                HealthTipCard(tip: HealthTips.tip(for: Date()))
            } header: {
                SectionTitle(text: "Tip of the Day")
            }

            Section {
                WindDownCard()
            } header: {
                SectionTitle(text: "3-2-1 Wind-Down")
            } footer: {
                Text("No food 3 hours before bed, no drinks 2 hours before, no screens in the last hour.")
            }

            if healthSectionEnabled {
                historySections
            }

            Section {
                EmptyView()
            } footer: {
                Text("Family Tasks isn't a medical app. Scores, BMI and tips are general guidance, not a diagnosis. Talk to a doctor about anything that worries you.")
            }
        }
        .listRowBackground(AppTheme.surface)
        .scrollContentBackground(.hidden)
        // Header at the same height on every tab.
        .contentMargins(.top, 0, for: .scrollContent)
        .background(AppTheme.background)
        .mainScreenNavigationBar(title: "Health", isPushed: isPushed)
        .navigationDestination(isPresented: $isShowingSettings) {
            HealthSettingsView().backButton("Health")
        }
        .sheet(item: $editingGoal) { editing in
            switch editing {
            case .new(let kind):
                HealthGoalEditorView(kind: kind, familySize: familySize)
            case .existing(let goal):
                HealthGoalEditorView(goal: goal, familySize: familySize)
            }
        }
        .task {
            if healthSectionEnabled {
                await refresh()
            }
        }
        .refreshable {
            if healthSectionEnabled {
                await refresh()
            }
        }
    }

    // MARK: You

    @ViewBuilder
    private var mySections: some View {
        Section {
            TodayActivityCard(today: healthService.recentDays.last, goals: goalStore.myGoals)
        } header: {
            SectionTitle(text: "Today")
        }

        Section {
            SleepCard(night: healthService.lastNight, recentDays: healthService.recentDays)
        } header: {
            SectionTitle(text: "Sleep")
        }

        if HeartCard.hasData(healthService.recentDays) {
            Section {
                HeartCard(recentDays: healthService.recentDays)
            } header: {
                SectionTitle(text: "Heart")
            }
        }

        Section {
            BodyCard(weight: healthService.weight, height: healthService.height)
        } header: {
            SectionTitle(text: "Body")
        }

        Section {
            ForEach(goalStore.myGoals) { goal in
                Button {
                    editingGoal = .existing(goal)
                } label: {
                    HealthGoalRow(goal: goal, snapshots: healthService.recentDays)
                }
                .buttonStyle(.plain)
            }
            Button {
                editingGoal = .new(.personal)
            } label: {
                Label(goalStore.myGoals.isEmpty ? "Set a Goal" : "Add a Goal", systemImage: "plus.circle.fill")
                    .font(.body.weight(.semibold))
            }
        } header: {
            SectionTitle(text: "Your Goals")
        } footer: {
            if goalStore.myGoals.isEmpty {
                Text("Pick a daily target for steps, exercise, active energy or sleep. Share it and the family sees your streak and can cheer you on.")
            }
        }
    }

    // MARK: Family

    @ViewBuilder
    private var familySections: some View {
        if !healthSharingEnabled {
            Section {
                Button {
                    isShowingSettings = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Share With Your Family")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                            Text("See each other's steps, sleep and goals, start family challenges and cheer each other on.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        IconTile(systemImage: "person.2.fill", tint: AppTheme.primary, size: 36)
                    }
                }
                .buttonStyle(.plain)
            } header: {
                SectionTitle(text: "Family")
            }
        } else {
            Section {
                ForEach(goalStore.challenges) { goal in
                    Button {
                        editingGoal = .existing(goal)
                    } label: {
                        FamilyChallengeRow(goal: goal, snapshots: everyone, name: memberName)
                    }
                    .buttonStyle(.plain)
                    .disabled(!goalStore.isMine(goal))
                }
                Button {
                    editingGoal = .new(.family)
                } label: {
                    Label("Start a Family Challenge", systemImage: "flag.checkered")
                        .font(.body.weight(.semibold))
                }
            } header: {
                SectionTitle(text: "Family Challenges")
            } footer: {
                if goalStore.challenges.isEmpty {
                    Text("Set a target to reach together this week, like 300,000 steps between you.")
                }
            }

            Section {
                if latestByMember.isEmpty {
                    Text("Nobody else is sharing Health yet. When family members turn on sharing in Health Settings on their phones, they show up here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(latestByMember, id: \.memberEmail) { latest in
                        FamilyMemberHealthCard(
                            email: latest.memberEmail,
                            name: memberName(latest.memberEmail),
                            latest: latest,
                            goals: goalStore.familyGoals.filter { $0.ownerEmail == latest.memberEmail },
                            snapshots: organizerStore.healthSnapshots
                        )
                    }
                }
            } header: {
                SectionTitle(text: "Family")
            }

            if latestByMember.count > 0 {
                Section {
                    WeeklyStepsBoard(snapshots: everyone, me: me, name: memberName)
                } header: {
                    SectionTitle(text: "Steps This Week")
                }
            }
        }
    }

    // MARK: History

    @ViewBuilder
    private var historySections: some View {
        Section {
            HStack(spacing: 8) {
                ForEach(HealthMetricScope.allCases) { scope in
                    ChoiceChip(title: scope.title, isSelected: selectedScope == scope) {
                        selectedScope = scope
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } header: {
            SectionTitle(text: "History")
        }

        Section {
            if !familySummaries.isEmpty {
                ForEach(familySummaries) { summary in
                    HealthMemberMetricRow(
                        email: summary.memberEmail,
                        name: memberName(summary.memberEmail),
                        steps: HealthMetricSummary.stepText(for: summary.steps),
                        sleep: HealthMetricSummary.sleepText(for: summary.sleepSeconds)
                    )
                }
            } else if healthService.isLoading {
                ProgressView("Loading health data")
            } else if let summary = selectedSummary {
                HealthMemberMetricRow(
                    email: profileEmail,
                    name: "You",
                    steps: summary.stepText,
                    sleep: summary.sleepText
                )
            } else {
                ContentUnavailableView(
                    "No Health Data",
                    systemImage: "heart.slash",
                    description: Text("Allow Health access and turn on Health sharing in Health Settings.")
                )
            }
        } header: {
            SectionTitle(text: "Total Steps and Sleep")
        }

        // Day has nothing to break down beyond the summary above.
        if selectedScope == .day {
            EmptyView()
        } else if !familyDailyGroups.isEmpty {
            Section {
                switch selectedScope {
                case .day, .week, .month:
                    FamilyHealthDetailList(groups: familyDailyGroups)
                case .year:
                    FamilyHealthDetailList(groups: familyMonthlyGroups)
                }
            } header: {
                SectionTitle(text: detailTitle)
            }
        } else if let summary = selectedSummary, !summary.points.isEmpty {
            Section {
                switch selectedScope {
                case .day, .week, .year:
                    HealthDetailList(points: summary.points)
                case .month:
                    HealthCalendarGrid(points: summary.points)
                }
            } header: {
                SectionTitle(text: detailTitle)
            }
        }
    }

    // MARK: Data

    private func refresh() async {
        await healthService.refresh()
        await HealthSyncCoordinator.shared.syncRecentIfStale(
            taskStore: taskStore,
            organizerStore: organizerStore,
            sharedHouseholdStore: sharedHouseholdStore
        )
        goalStore.announceAchievements(mine: healthService.recentDays, family: organizerStore.healthSnapshots)
    }

    private var me: String {
        FamilyAlert.normalized(profileEmail)
    }

    private var familySize: Int {
        max(Set(organizerStore.healthSnapshots.map(\.memberEmail)).union([me]).count, 1)
    }

    /// Everyone's shared days, with this person's own fresh from Health.
    private var everyone: [HealthSnapshot] {
        HealthGoalStore.replacingOwn(organizerStore.healthSnapshots, with: healthService.recentDays, owner: me)
    }

    /// Each other family member's most recent day from the last week.
    private var latestByMember: [HealthSnapshot] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: Date())) ?? .distantPast
        return Dictionary(grouping: organizerStore.healthSnapshots.filter { $0.memberEmail != me && $0.date >= cutoff }, by: \.memberEmail)
            .compactMap { _, days in days.max { $0.date < $1.date } }
            .sorted { memberName($0.memberEmail).localizedCaseInsensitiveCompare(memberName($1.memberEmail)) == .orderedAscending }
    }

    private var selectedSummary: HealthMetricSummary? {
        healthService.summaries.first { $0.scope == selectedScope }
    }

    private var familySnapshots: [HealthSnapshot] {
        organizerStore.healthSnapshots(for: selectedScope)
    }

    private var familySummaries: [HealthSnapshotSummary] {
        Dictionary(grouping: familySnapshots, by: \.memberEmail)
            .map { email, snapshots in
                HealthSnapshotSummary(
                    memberEmail: email,
                    initials: snapshots.last?.displayInitials ?? "ME",
                    steps: snapshots.reduce(0) { $0 + $1.steps },
                    sleepSeconds: snapshots.reduce(0) { $0 + $1.sleepSeconds }
                )
            }
            .sorted { $0.initials.localizedCaseInsensitiveCompare($1.initials) == .orderedAscending }
    }

    private var familyDailyGroups: [FamilyHealthPeriodGroup] {
        let formatter = DateFormatter()
        switch selectedScope {
        case .week:
            formatter.dateFormat = "EEE M/d"
        case .month:
            formatter.dateFormat = "MMM d"
        default:
            formatter.dateFormat = "d"
        }
        return Dictionary(grouping: familySnapshots, by: \.dayID)
            .map { _, snapshots in
                let date = snapshots.first?.date ?? Date()
                return FamilyHealthPeriodGroup(
                    id: snapshots.first?.dayID ?? UUID().uuidString,
                    title: selectedScope == .day ? "Today" : formatter.string(from: date),
                    date: date,
                    snapshots: snapshots.sorted { $0.displayInitials < $1.displayInitials }
                )
            }
            .sorted { $0.date < $1.date }
    }

    private var familyMonthlyGroups: [FamilyHealthPeriodGroup] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        let grouped = Dictionary(grouping: familySnapshots) { snapshot in
            Calendar.current.dateInterval(of: .month, for: snapshot.date)?.start ?? snapshot.date
        }

        return grouped.map { month, snapshots in
            let monthlySnapshots = Dictionary(grouping: snapshots, by: \.memberEmail).map { email, memberSnapshots in
                HealthSnapshot(
                    memberEmail: email,
                    memberInitials: memberSnapshots.last?.displayInitials ?? "",
                    date: month,
                    dayID: formatter.string(from: month),
                    steps: memberSnapshots.reduce(0) { $0 + $1.steps },
                    sleepSeconds: memberSnapshots.reduce(0) { $0 + $1.sleepSeconds },
                    updatedAt: memberSnapshots.map(\.updatedAt).max() ?? Date()
                )
            }
            return FamilyHealthPeriodGroup(
                id: formatter.string(from: month),
                title: formatter.string(from: month),
                date: month,
                snapshots: monthlySnapshots.sorted { $0.displayInitials < $1.displayInitials }
            )
        }
        .sorted { $0.date < $1.date }
    }

    private var detailTitle: String {
        switch selectedScope {
        case .day: "Today"
        case .week: "Daily Breakdown"
        case .month: "Daily Breakdown"
        case .year: "Monthly Breakdown"
        }
    }

    private func memberName(_ email: String) -> String {
        email.caseInsensitiveCompare(profileEmail.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
            ? "You"
            : Assignee.memberName(for: email)
    }
}


private struct HealthSnapshotSummary: Identifiable {
    var id: String { memberEmail }
    let memberEmail: String
    let initials: String
    let steps: Double
    let sleepSeconds: TimeInterval
}

private struct FamilyHealthPeriodGroup: Identifiable {
    let id: String
    let title: String
    let date: Date
    let snapshots: [HealthSnapshot]
}

private struct FamilyHealthDetailList: View {
    let groups: [FamilyHealthPeriodGroup]

    var body: some View {
        ForEach(groups) { group in
            VStack(alignment: .leading, spacing: 8) {
                Text(group.title)
                    .font(.body.weight(.semibold))
                ForEach(group.snapshots) { snapshot in
                    HealthSnapshotCompactRow(snapshot: snapshot)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct FamilyHealthCalendarGrid: View {
    let groups: [FamilyHealthPeriodGroup]

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title)
                        .font(.caption2.weight(.semibold))
                    ForEach(group.snapshots.prefix(5)) { snapshot in
                        HStack(spacing: 3) {
                            Text(snapshot.displayInitials)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(AppTheme.primary)
                            Text(HealthMetricSummary.stepText(for: snapshot.steps))
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
                .padding(5)
                .background(AppTheme.primarySoft, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.vertical, 4)
    }
}

private struct HealthSnapshotCompactRow: View {
    let snapshot: HealthSnapshot

    var body: some View {
        HStack(spacing: 10) {
            AssigneeAvatarView(name: snapshot.memberEmail, size: 28, showsPhoto: false)
            Label("\(HealthMetricSummary.stepText(for: snapshot.steps)) steps", systemImage: "figure.walk")
                .font(.subheadline)
                .labelStyle(.titleAndIcon)
            Spacer()
            Label(HealthMetricSummary.sleepText(for: snapshot.sleepSeconds), systemImage: "bed.double.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// A family member's avatar and name, with steps and sleep as colored stats.
private struct HealthMemberMetricRow: View {
    let email: String
    let name: String
    let steps: String
    let sleep: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AssigneeAvatarView(name: email, size: 36, showsPhoto: false)
                Text(name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
            }

            HStack(spacing: 10) {
                stat(steps, unit: "steps", systemImage: "figure.walk", tint: AppTheme.warmAccent)
                stat(sleep, unit: "sleep", systemImage: "bed.double.fill", tint: AppTheme.coolAccent)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(steps) steps, \(sleep) sleep")
    }

    private func stat(_ value: String, unit: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            IconTile(systemImage: systemImage, tint: tint, size: 32)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct HealthDetailList: View {
    let points: [HealthMetricPoint]

    var body: some View {
        ForEach(points) { point in
            HStack {
                Text(point.title)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 78, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(HealthMetricSummary.stepText(for: point.steps)) steps")
                    Text("\(HealthMetricSummary.sleepText(for: point.sleepSeconds)) sleep")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }
}

private struct HealthCalendarGrid: View {
    let points: [HealthMetricPoint]

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(points) { point in
                VStack(spacing: 4) {
                    Text(point.title)
                        .font(.caption2.weight(.semibold))
                    Text(HealthMetricSummary.stepText(for: point.steps))
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Image(systemName: "bed.double.fill")
                        .font(.caption2)
                        .foregroundStyle(point.sleepSeconds > 0 ? AppTheme.primary : .secondary.opacity(0.45))
                }
                .frame(maxWidth: .infinity, minHeight: 58)
                .padding(4)
                .background(calendarColor(for: point), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.vertical, 4)
    }

    private func calendarColor(for point: HealthMetricPoint) -> Color {
        let intensity = min(max(point.steps / 10_000, 0.12), 1)
        return AppTheme.primary.opacity(0.08 + intensity * 0.22)
    }
}

private struct HealthMetricPill: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppTheme.primarySoft, in: RoundedRectangle(cornerRadius: 8))
    }
}
