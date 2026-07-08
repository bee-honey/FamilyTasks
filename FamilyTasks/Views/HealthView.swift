import SwiftUI

struct HealthView: View {
    @EnvironmentObject private var organizerStore: OrganizerStore
    @AppStorage("profile.email") private var profileEmail = ""
    @AppStorage("profile.initials") private var profileInitials = ""
    @StateObject private var healthService = HealthMetricsService()
    @State private var selectedScope = HealthMetricScope.day

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Range", selection: $selectedScope) {
                        ForEach(HealthMetricScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    if !familySummaries.isEmpty {
                        ForEach(familySummaries) { summary in
                            HealthMemberMetricRow(
                                initials: summary.initials,
                                name: summary.memberEmail,
                                steps: HealthMetricSummary.stepText(for: summary.steps),
                                sleep: HealthMetricSummary.sleepText(for: summary.sleepSeconds)
                            )
                        }
                    } else if healthService.isLoading {
                        ProgressView("Loading health data")
                    } else if let summary = selectedSummary {
                        HealthMemberMetricRow(
                            initials: displayInitials,
                            name: profileEmail.isEmpty ? "You" : profileEmail,
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
                    Text("Family Summary")
                } footer: {
                    Text("Each member opts in on their own device. Shared Health keeps only daily steps and sleep summaries in family iCloud data.")
                }

                if !familyDailyGroups.isEmpty {
                    Section(detailTitle) {
                        switch selectedScope {
                        case .day, .week, .month:
                            FamilyHealthDetailList(groups: familyDailyGroups)
                        case .year:
                            FamilyHealthDetailList(groups: familyMonthlyGroups)
                        }
                    }
                } else if let summary = selectedSummary, !summary.points.isEmpty {
                    Section(detailTitle) {
                        switch selectedScope {
                        case .day:
                            HealthDetailList(points: summary.points)
                        case .week:
                            HealthDetailList(points: summary.points)
                        case .month:
                            HealthCalendarGrid(points: summary.points)
                        case .year:
                            HealthDetailList(points: summary.points)
                        }
                    }
                }
            }
            .navigationTitle("Health")
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await healthService.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh health data")
                }
            }
            .task {
                await healthService.refresh()
            }
        }
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

    private var displayInitials: String {
        let trimmedInitials = profileInitials.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedInitials.isEmpty {
            return String(trimmedInitials.prefix(3)).uppercased()
        }

        let localPart = profileEmail.split(separator: "@").first.map(String.init) ?? ""
        let parts = localPart.split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" || $0 == " " })
        let letters = parts.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "ME" : String(letters).uppercased()
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
                    .font(.subheadline.weight(.semibold))
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
        HStack(spacing: 8) {
            Text(snapshot.displayInitials)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(AppTheme.primary, in: Circle())
            Text("\(HealthMetricSummary.stepText(for: snapshot.steps)) steps")
                .font(.subheadline)
            Spacer()
            Text("\(HealthMetricSummary.sleepText(for: snapshot.sleepSeconds)) sleep")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct HealthMemberMetricRow: View {
    let initials: String
    let name: String
    let steps: String
    let sleep: String

    var body: some View {
        HStack(spacing: 10) {
            Text(initials)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(AppTheme.primary, in: Circle())

            Text(initials)
                .font(.headline)
                .lineLimit(1)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Label("\(steps) steps", systemImage: "figure.walk")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Label("\(sleep) sleep", systemImage: "bed.double")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .labelStyle(.titleAndIcon)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(steps) steps, \(sleep) sleep")
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
