import SwiftUI

struct HealthView: View {
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

                Section("Family Comparison") {
                    if healthService.isLoading {
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
                            description: Text("Allow Health access in View Settings to compare steps and sleep.")
                        )
                    }

                    Text("This view currently shows this device only. To compare 5 family members, each person needs to opt in and sync a small steps/sleep summary; then these rows and calendar cells can show each member by initials and color.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let summary = selectedSummary, !summary.points.isEmpty {
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

    private var detailTitle: String {
        switch selectedScope {
        case .day: "Today"
        case .week: "Daily Breakdown"
        case .month: "Month Calendar"
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

private struct HealthMemberMetricRow: View {
    let initials: String
    let name: String
    let steps: String
    let sleep: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(initials)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.primary, in: Circle())
                Text(initials)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
            }

            HStack(spacing: 12) {
                HealthMetricPill(title: "Steps", value: steps, icon: "figure.walk")
                HealthMetricPill(title: "Sleep", value: sleep, icon: "bed.double")
            }
        }
        .padding(.vertical, 6)
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
