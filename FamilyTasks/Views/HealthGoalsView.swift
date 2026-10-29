import SwiftUI

// MARK: Your goals

/// One of your daily goals: today's progress, and days in a row you've met it.
struct HealthGoalRow: View {
    let goal: HealthGoal
    let snapshots: [HealthSnapshot]

    var body: some View {
        let today = HabitMath.dayKey(for: Date())
        let value = HealthGoalMath.value(of: goal, on: today, snapshots: snapshots) ?? 0
        let streak = HealthGoalMath.streak(of: goal, snapshots: snapshots).current
        let progress = value / goal.target
        HStack(spacing: 12) {
            GoalRing(progress: progress, tint: goal.metric.tint, size: 40, lineWidth: 4) {
                Image(systemName: progress >= 1 ? "checkmark" : goal.metric.systemImage)
                    .font(.system(size: 15, weight: progress >= 1 ? .heavy : .semibold))
                    .foregroundStyle(goal.metric.tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(goal.metric.targetText(goal.target, kind: .personal))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                HStack(spacing: 6) {
                    Text(progress >= 1 ? "Done today · \(goal.metric.format(value))" : "\(goal.metric.format(value)) so far")
                    if goal.isShared {
                        Image(systemName: "person.2.fill")
                            .accessibilityLabel("Shared with family")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if streak > 0 {
                Label("\(streak)", systemImage: "flame.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.orange)
                    .accessibilityLabel("\(streak) days in a row")
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

// MARK: Family

/// A family challenge: everyone's total this week toward one target, and who added what.
struct FamilyChallengeRow: View {
    let goal: HealthGoal
    let snapshots: [HealthSnapshot]
    let name: (String) -> String

    var body: some View {
        let totals = HealthGoalMath.weekTotals(of: goal, snapshots: snapshots)
        let progress = totals.total / goal.target
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                IconTile(systemImage: goal.metric.systemImage, tint: goal.metric.tint, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(goal.metric.targetText(goal.target, kind: .family))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text(progress >= 1 ? "Done! 🎉 \(goal.metric.format(totals.total))" : "\(goal.metric.format(totals.total)) so far · \(daysLeft)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(min(progress, 9.99).formatted(.percent.precision(.fractionLength(0))))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(goal.metric.tint)
            }

            ProgressView(value: min(progress, 1))
                .tint(goal.metric.tint)

            if !totals.byMember.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(totals.byMember.sorted { $0.value > $1.value }, id: \.key) { email, value in
                            HStack(spacing: 6) {
                                AssigneeAvatarView(name: email, size: 22, showsPhoto: false)
                                Text("\(name(email)) · \(goal.metric.format(value))")
                                    .font(.caption.weight(.semibold))
                            }
                            .padding(.horizontal, 8)
                            .frame(minHeight: 30)
                            .background(goal.metric.tint.opacity(0.10), in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var daysLeft: String {
        let calendar = Calendar.current
        let end = HealthGoalMath.week(containing: Date(), calendar: calendar).end
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: end).day ?? 0
        return days <= 1 ? "last day" : "\(days) days left"
    }
}

/// A family member's latest day: steps, sleep score and exercise, their shared goals, and
/// a button to cheer them on.
struct FamilyMemberHealthCard: View {
    let email: String
    let name: String
    let latest: HealthSnapshot
    let goals: [HealthGoal]
    let snapshots: [HealthSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AssigneeAvatarView(name: email, size: 34, showsPhoto: false)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.body.weight(.semibold))
                    Text(dayLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                CheerButton(email: email, name: name, highlight: highlight)
            }

            HStack(spacing: 8) {
                stat(HealthMetric.steps.format(latest.steps), systemImage: "figure.walk", tint: HealthMetric.steps.tint)
                if let score = latest.sleepScore {
                    stat("Sleep \(score)", systemImage: "moon.stars.fill", tint: HealthMetric.sleepScore.tint)
                } else if latest.sleepSeconds > 0 {
                    stat(SleepCard.hours(latest.sleepSeconds), systemImage: "bed.double.fill", tint: HealthMetric.sleepHours.tint)
                }
                if let minutes = latest.exerciseMinutes, minutes > 0 {
                    stat(HealthMetric.exerciseMinutes.format(minutes), systemImage: "figure.run", tint: HealthMetric.exerciseMinutes.tint)
                }
            }

            if !goals.isEmpty {
                WrappingStack(spacing: 6) {
                    ForEach(goals) { goal in
                        let met = (HealthGoalMath.value(of: goal, on: latest.dayID, snapshots: snapshots) ?? 0) >= goal.target
                        let streak = HealthGoalMath.streak(of: goal, snapshots: snapshots, now: latest.date).current
                        Label(
                            goal.metric.targetText(goal.target, kind: .personal) + (streak > 1 ? " · 🔥 \(streak)" : ""),
                            systemImage: met ? "checkmark.circle.fill" : "circle"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(met ? AppTheme.success : .secondary)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 26)
                        .background((met ? AppTheme.success : Color.secondary).opacity(0.10), in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var dayLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(latest.date) { return "Today, so far" }
        if calendar.isDateInYesterday(latest.date) { return "Yesterday" }
        return latest.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    /// What the cheer is for: their best number that day.
    private var highlight: String {
        let when = Calendar.current.isDateInToday(latest.date) ? "today" : "yesterday"
        if goals.contains(where: { (HealthGoalMath.value(of: $0, on: latest.dayID, snapshots: snapshots) ?? 0) >= $0.target }) {
            return "goal \(when)"
        }
        if let score = latest.sleepScore, score >= 85 { return "sleep score of \(score) \(when)" }
        return "\(HealthMetric.steps.format(latest.steps)) \(when)"
    }

    private func stat(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .frame(minHeight: 28)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

/// Clapping hands that send one family member a cheer, once a day.
struct CheerButton: View {
    let email: String
    let name: String
    let highlight: String?
    @EnvironmentObject private var taskStore: TaskStore
    @State private var cheered = false
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        if !taskStore.familyMembers.isEmpty, SharedHouseholdStore.shared.isSharingConfigured {
            Button(action: send) {
                HStack(spacing: 4) {
                    if isSending {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: cheered ? "hands.clap.fill" : "hands.clap")
                    }
                    Text(cheered ? "Cheered" : "Cheer")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(cheered ? AppTheme.onPrimary : SettingsTint.health)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(cheered ? SettingsTint.health : SettingsTint.health.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSending || cheered)
            .accessibilityLabel(cheered ? "Cheered \(name) today" : "Cheer \(name) on")
            .onAppear { cheered = FamilyAlertService.shared.wasCheeredToday(email) }
            .sensoryFeedback(trigger: cheered) { _, new in new ? .success : nil }
            .alert("Couldn't Cheer", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func send() {
        isSending = true
        Task {
            do {
                try await FamilyAlertService.shared.cheer(email, highlight: highlight)
                cheered = true
                ToastCenter.shared.show("Cheered \(name) on 👏")
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }
}

/// This week's steps for everyone, most first, as bars.
struct WeeklyStepsBoard: View {
    let snapshots: [HealthSnapshot]
    let me: String
    let name: (String) -> String

    var body: some View {
        let week = HealthGoalMath.week(containing: Date())
        let totals = Dictionary(grouping: snapshots.filter { $0.date >= week.start && $0.date < week.end }, by: \.memberEmail)
            .mapValues { $0.reduce(0) { $0 + $1.steps } }
            .sorted { $0.value > $1.value }
        let most = max(totals.first?.value ?? 1, 1)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(totals.enumerated()), id: \.element.key) { index, entry in
                HStack(spacing: 10) {
                    Text(index == 0 ? "🏆" : "\(index + 1)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .frame(width: 24)
                    AssigneeAvatarView(name: entry.key, size: 26, showsPhoto: false)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.key == me ? "You" : name(entry.key))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(HealthMetric.steps.format(entry.value))
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        GeometryReader { geometry in
                            Capsule()
                                .fill(HealthMetric.steps.tint.opacity(entry.key == me ? 0.9 : 0.5))
                                .frame(width: max(6, geometry.size.width * entry.value / most))
                        }
                        .frame(height: 6)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: Editor

/// Adds or edits a daily goal of your own, or a family challenge for the week.
struct HealthGoalEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var goalStore: HealthGoalStore
    let goal: HealthGoal?
    let kind: HealthGoal.Kind
    let familySize: Int
    @State private var metric: HealthMetric
    @State private var target: Double
    @State private var isShared: Bool

    init(goal: HealthGoal? = nil, kind: HealthGoal.Kind = .personal, familySize: Int = 1) {
        self.goal = goal
        self.kind = goal?.kind ?? kind
        self.familySize = familySize
        let metric = goal?.metric ?? .steps
        _metric = State(initialValue: metric)
        _target = State(initialValue: goal?.target ?? (kind == .family ? metric.defaultWeeklyTarget(people: familySize) : metric.defaultTarget))
        _isShared = State(initialValue: goal?.isShared ?? true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if goal == nil {
                        EditorSection(kind == .family ? "Together, This Week" : "Goal") {
                            WrappingStack(spacing: 8) {
                                ForEach(metrics) { choice in
                                    ChoiceChip(title: choice.title, isSelected: metric == choice) {
                                        metric = choice
                                        target = kind == .family ? choice.defaultWeeklyTarget(people: familySize) : choice.defaultTarget
                                    }
                                }
                            }
                        }
                    }

                    EditorSection(kind == .family ? "Family Target" : "Target") {
                        HStack(spacing: 12) {
                            IconTile(systemImage: metric.systemImage, tint: metric.tint, size: 44)
                            Text(metric.targetText(target, kind: kind))
                                .font(.headline)
                            Spacer(minLength: 0)
                        }
                        Stepper(
                            "Target",
                            value: $target,
                            in: range,
                            step: kind == .family ? metric.targetStep * Double(max(familySize, 1)) * 7 : metric.targetStep
                        )
                        .labelsHidden()
                        if kind == .family {
                            Text("Everyone's \(metric.title.lowercased()) adds up, Monday to Sunday. Only people who share Health with the family count.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if kind == .personal {
                        EditorSection("Sharing") {
                            Toggle(isOn: $isShared) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Share With Family")
                                        .font(.body.weight(.semibold))
                                    Text("They see it on the family dashboard and hear when you reach it. Needs Health sharing on.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if let goal, goalStore.isMine(goal) {
                        EditorDeleteButton(
                            title: kind == .family ? "Delete Challenge" : "Delete Goal",
                            message: kind == .family ? "It's removed for everyone." : "Its streak goes too."
                        ) {
                            goalStore.delete(goal)
                            dismiss()
                        }
                    }
                }
                .padding(20)
            }
            .background(AppTheme.background)
            .navigationTitle(goal == nil ? (kind == .family ? "New Family Challenge" : "New Goal") : "Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(goal == nil ? "Add" : "Save") {
                        if let goal {
                            goalStore.update(goal, target: target, isShared: isShared)
                        } else {
                            goalStore.add(metric: metric, target: target, kind: kind, isShared: isShared)
                        }
                        dismiss()
                    }
                }
            }
        }
    }

    /// Family challenges are for numbers that add up across people.
    private var metrics: [HealthMetric] {
        kind == .family ? HealthMetric.allCases.filter(\.isAdditive) : HealthMetric.allCases
    }

    private var range: ClosedRange<Double> {
        let daily = metric.dailyRange
        guard kind == .family else { return daily }
        let scale = 7 * Double(max(familySize, 1))
        return (daily.lowerBound * scale)...(daily.upperBound * scale)
    }
}
