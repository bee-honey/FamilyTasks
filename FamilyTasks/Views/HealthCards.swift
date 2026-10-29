import SwiftUI

// MARK: Pieces

/// A ring that fills toward a goal, with whatever's inside it in the middle.
struct GoalRing<Center: View>: View {
    let progress: Double
    let tint: Color
    var size: CGFloat = 44
    var lineWidth: CGFloat = 5
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center
        }
        .frame(width: size, height: size)
        .animation(.snappy, value: progress)
    }
}

/// One number with a ring toward its goal: "8,240 steps · of 10,000".
private struct ActivityTile: View {
    let metric: HealthMetric
    let value: Double?
    let target: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            GoalRing(progress: (value ?? 0) / target, tint: tint, size: 40, lineWidth: 4) {
                Image(systemName: metric.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(value.map(metric.format) ?? "–")
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("of \(metric.format(target))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.title): \(value.map(metric.format) ?? "no data") of \(metric.format(target))")
    }
}

extension HealthMetric {
    var tint: Color {
        switch self {
        case .steps: AppTheme.warmAccent
        case .exerciseMinutes: AppTheme.success
        case .activeEnergy: AppTheme.goldAccent
        case .sleepHours: AppTheme.coolAccent
        case .sleepScore: AppTheme.softAccent
        }
    }
}

// MARK: Today

/// Today's steps, exercise, active energy and last night's sleep, each against your goal
/// for it, or a usual target when you haven't set one.
struct TodayActivityCard: View {
    let today: HealthSnapshot?
    let goals: [HealthGoal]

    private let metrics: [HealthMetric] = [.steps, .exerciseMinutes, .activeEnergy, .sleepHours]

    var body: some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(metrics) { metric in
                ActivityTile(
                    metric: metric,
                    value: today.flatMap(metric.value(in:)),
                    target: goals.first { $0.metric == metric }?.target ?? metric.defaultTarget,
                    tint: metric.tint
                )
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: Sleep

struct SleepCard: View {
    let night: SleepNight?
    let recentDays: [HealthSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let night, let score = SleepScore.score(for: night) {
                HStack(spacing: 16) {
                    GoalRing(progress: Double(score) / 100, tint: AppTheme.softAccent, size: 76, lineWidth: 8) {
                        VStack(spacing: 0) {
                            Text("\(score)")
                                .font(.title2.weight(.bold).monospacedDigit())
                            Text("score")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(SleepScore.label(for: score))
                            .font(.headline)
                        Text("Last night · \(Self.hours(night.asleep)) asleep")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let average = weekAverage {
                            Text("7-night average \(average)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)

                if let deepAndREM = night.deepAndREM, let awake = night.awake {
                    HStack(spacing: 8) {
                        part("Asleep", Self.hours(night.asleep), tint: AppTheme.coolAccent)
                        part("Deep + REM", Self.hours(deepAndREM), tint: AppTheme.softAccent)
                        part("Awake", Self.minutes(awake), tint: AppTheme.goldAccent)
                    }
                    Text("Half the score is how long you slept. The rest is deep and REM sleep, and how little you woke.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Based on how long you slept. Wear Apple Watch to bed to include deep sleep and time awake.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No sleep recorded last night")
                            .font(.subheadline.weight(.semibold))
                        Text("Wear Apple Watch to bed, or set up Sleep in the Health app, to get a sleep score.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    IconTile(systemImage: "moon.zzz.fill", tint: AppTheme.softAccent, size: 36)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var weekAverage: Int? {
        let scores = recentDays.suffix(7).compactMap(\.sleepScore)
        guard scores.count >= 2 else { return nil }
        return Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
    }

    private func part(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    static func hours(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        return "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }

    static func minutes(_ seconds: TimeInterval) -> String {
        "\(Int((seconds / 60).rounded())) min"
    }
}

// MARK: Heart

/// Resting heart rate, HRV and cardio fitness: this week's average and how it compares
/// with the week before.
struct HeartCard: View {
    let recentDays: [HealthSnapshot]

    struct Row: Identifiable {
        var id: String { title }
        let title: String
        let unit: String
        let systemImage: String
        let value: KeyPath<HealthSnapshot, Double?>
        /// Lower is better for resting heart rate; higher for the others.
        let lowerIsBetter: Bool
        let note: String
    }

    static let rows = [
        Row(title: "Resting Heart Rate", unit: "bpm", systemImage: "heart.fill", value: \.restingHeartRate, lowerIsBetter: true,
            note: "Your heart rate at rest. Lower usually means fitter and better rested."),
        Row(title: "HRV", unit: "ms", systemImage: "waveform.path.ecg", value: \.hrv, lowerIsBetter: false,
            note: "Heart rate variability: the small changes in time between beats. Higher than your usual often means you've recovered well."),
        Row(title: "Cardio Fitness", unit: "VO₂ max", systemImage: "lungs.fill", value: \.vo2Max, lowerIsBetter: false,
            note: "How well your body uses oxygen when you exercise. Brisk walks and runs with Apple Watch keep it up to date."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Self.rows.filter { average(of: $0.value, weeksAgo: 0) != nil }) { row in
                rowView(row)
            }
        }
        .padding(.vertical, 4)
    }

    static func hasData(_ days: [HealthSnapshot]) -> Bool {
        days.contains { $0.restingHeartRate != nil || $0.hrv != nil || $0.vo2Max != nil }
    }

    private func rowView(_ row: Row) -> some View {
        let now = average(of: row.value, weeksAgo: 0) ?? 0
        let before = average(of: row.value, weeksAgo: 1)
        return HStack(alignment: .top, spacing: 12) {
            IconTile(systemImage: row.systemImage, tint: AppTheme.warmAccent, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    Text(now.formatted(.number.precision(.fractionLength(0))))
                        .font(.headline.monospacedDigit())
                    Text(row.unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let before, before > 0 {
                    trend(change: now - before, unit: row.unit, lowerIsBetter: row.lowerIsBetter)
                } else {
                    Text("Average over the last 7 days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(row.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func trend(change: Double, unit: String, lowerIsBetter: Bool) -> some View {
        let rounded = Int(change.rounded())
        let better = lowerIsBetter ? rounded < 0 : rounded > 0
        let text: String
        let symbol: String
        if rounded == 0 {
            text = "Same as the week before"
            symbol = "equal"
        } else {
            text = "\(abs(rounded)) \(unit) \(rounded > 0 ? "higher" : "lower") than the week before"
            symbol = rounded > 0 ? "arrow.up.right" : "arrow.down.right"
        }
        return Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(rounded == 0 ? Color.secondary : (better ? AppTheme.success : AppTheme.warmAccent))
    }

    /// The average of the days that have a value, this week (`weeksAgo` 0) or earlier.
    private func average(of value: KeyPath<HealthSnapshot, Double?>, weeksAgo: Int) -> Double? {
        let end = recentDays.count - weeksAgo * 7
        guard end > 0 else { return nil }
        let values = recentDays[max(0, end - 7)..<end].compactMap { $0[keyPath: value] }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

// MARK: Body

/// Weight, height and BMI, from Health or entered here.
struct BodyCard: View {
    let weight: HealthReading?
    let height: HealthReading?
    @AppStorage(BodyEntryView.weightKey) private var manualWeightKg = 0.0
    @AppStorage(BodyEntryView.heightKey) private var manualHeightMeters = 0.0
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                stat("Weight", weightKg.map(BodyMath.weightText) ?? "–", detail: weightDetail)
                stat("Height", heightMeters.map(BodyMath.heightText) ?? "–", detail: height == nil && manualHeightMeters > 0 ? "Entered here" : nil)
                stat("BMI", bmi.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "–", detail: bmi.map { BodyMath.BMICategory(bmi: $0).title })
            }

            if let bmi {
                BMIScale(bmi: bmi)
            }

            Button {
                isEditing = true
            } label: {
                Label(weight == nil || height == nil ? "Enter Weight and Height" : "Edit", systemImage: "pencil")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderless)

            Text("BMI is a rough guide for adults. It doesn't account for muscle, age or build, and doesn't apply to children.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $isEditing) {
            BodyEntryView(healthWeight: weight, healthHeight: height)
        }
    }

    private var weightKg: Double? {
        weight?.value ?? (manualWeightKg > 0 ? manualWeightKg : nil)
    }

    private var heightMeters: Double? {
        height?.value ?? (manualHeightMeters > 0 ? manualHeightMeters : nil)
    }

    private var weightDetail: String? {
        if let weight {
            return weight.date.formatted(.relative(presentation: .named))
        }
        return manualWeightKg > 0 ? "Entered here" : nil
    }

    private var bmi: Double? {
        guard let weightKg, let heightMeters else { return nil }
        return BodyMath.bmi(weightKg: weightKg, heightMeters: heightMeters)
    }

    private func stat(_ title: String, _ value: String, detail: String?) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.coolAccent)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .padding(.horizontal, 4)
        .background(AppTheme.coolAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The adult BMI bands from 15 to 40, with a marker at `bmi`.
private struct BMIScale: View {
    let bmi: Double
    private let range = 15.0...40.0
    private let bands: [(upper: Double, category: BodyMath.BMICategory)] = [
        (18.5, .underweight), (25, .healthy), (30, .overweight), (40, .obese),
    ]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    ForEach(Array(bands.enumerated()), id: \.offset) { index, band in
                        let lower = index == 0 ? range.lowerBound : bands[index - 1].upper
                        Capsule()
                            .fill(color(band.category).opacity(0.55))
                            .frame(width: max(0, width * (band.upper - lower) / (range.upperBound - range.lowerBound) - 2))
                    }
                }
                Circle()
                    .fill(AppTheme.ink)
                    .overlay(Circle().stroke(AppTheme.surface, lineWidth: 2))
                    .frame(width: 14, height: 14)
                    .offset(x: width * (min(max(bmi, range.lowerBound), range.upperBound) - range.lowerBound) / (range.upperBound - range.lowerBound) - 7)
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }

    private func color(_ category: BodyMath.BMICategory) -> Color {
        switch category {
        case .underweight: AppTheme.coolAccent
        case .healthy: AppTheme.success
        case .overweight: AppTheme.goldAccent
        case .obese: AppTheme.warmAccent
        }
    }
}

/// Weight and height for BMI when Health doesn't have them. Kept on this phone only.
struct BodyEntryView: View {
    static let weightKey = "health.manualWeightKg"
    static let heightKey = "health.manualHeightMeters"

    @Environment(\.dismiss) private var dismiss
    @AppStorage(weightKey) private var manualWeightKg = 0.0
    @AppStorage(heightKey) private var manualHeightMeters = 0.0
    let healthWeight: HealthReading?
    let healthHeight: HealthReading?
    @State private var weight: Double?
    @State private var height: Double?

    private var usesMetric: Bool { Locale.current.measurementSystem == .metric }
    private var weightUnit: UnitMass { usesMetric ? .kilograms : .pounds }
    private var heightUnit: UnitLength { usesMetric ? .centimeters : .inches }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let healthWeight {
                        LabeledContent("Weight", value: BodyMath.weightText(kg: healthWeight.value))
                    } else {
                        field("Weight", value: $weight, unit: weightUnit.symbol)
                    }
                    if let healthHeight {
                        LabeledContent("Height", value: BodyMath.heightText(meters: healthHeight.value))
                    } else {
                        field("Height", value: $height, unit: heightUnit.symbol)
                    }
                } footer: {
                    Text(healthWeight != nil || healthHeight != nil
                         ? "Numbers from the Health app are used when there are any. Update them there."
                         : "Kept on this phone only. If you add weight or height to the Health app, those are used instead.")
                }
            }
            .navigationTitle("Weight and Height")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.medium])
    }

    private func field(_ title: String, value: Binding<Double?>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }

    private func load() {
        if manualWeightKg > 0 {
            weight = Measurement(value: manualWeightKg, unit: UnitMass.kilograms).converted(to: weightUnit).value
        }
        if manualHeightMeters > 0 {
            height = Measurement(value: manualHeightMeters, unit: UnitLength.meters).converted(to: heightUnit).value
        }
    }

    private func save() {
        if healthWeight == nil {
            manualWeightKg = weight.map { Measurement(value: $0, unit: weightUnit).converted(to: .kilograms).value } ?? 0
        }
        if healthHeight == nil {
            manualHeightMeters = height.map { Measurement(value: $0, unit: heightUnit).converted(to: .meters).value } ?? 0
        }
    }
}

// MARK: Tips and wind-down

struct HealthTipCard: View {
    let tip: HealthTip

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(systemImage: tip.topic.systemImage, tint: AppTheme.success, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(tip.title)
                    .font(.subheadline.weight(.semibold))
                Text(tip.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// The 3-2-1 routine for tonight's bedtime, with reminders for each step.
struct WindDownCard: View {
    @AppStorage(WindDownSettings.enabledKey) private var remindersOn = false
    @AppStorage(WindDownSettings.bedtimeHourKey) private var bedtimeHour = WindDownSettings.defaultBedtimeHour
    @AppStorage(WindDownSettings.bedtimeMinuteKey) private var bedtimeMinute = WindDownSettings.defaultBedtimeMinute
    @AppStorage("notifications.enabled") private var notificationsEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker("Bedtime", selection: bedtime, displayedComponents: .hourAndMinute)
                .font(.subheadline.weight(.semibold))

            ForEach(WindDownStep.allCases) { step in
                HStack(spacing: 12) {
                    IconTile(systemImage: step.systemImage, tint: AppTheme.softAccent, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(step.title)
                            .font(.subheadline.weight(.semibold))
                        Text("\(step.hoursBefore) \(step.hoursBefore == 1 ? "hour" : "hours") before bed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    let time = step.time(bedtimeHour: bedtimeHour, bedtimeMinute: bedtimeMinute)
                    Text(WindDownSettings.timeText(hour: time.hour, minute: time.minute))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                }
                .accessibilityElement(children: .combine)
            }

            Toggle(isOn: $remindersOn) {
                Text("Remind Me Each Night")
                    .font(.subheadline.weight(.semibold))
            }
            .onChange(of: remindersOn) { _, on in
                HealthReminders.changed(turningOn: on, notificationsEnabled: $notificationsEnabled)
            }
        }
        .padding(.vertical, 4)
    }

    private var bedtime: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: bedtimeHour, minute: bedtimeMinute, second: 0, of: Date()) ?? Date() },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                bedtimeHour = parts.hour ?? bedtimeHour
                bedtimeMinute = parts.minute ?? bedtimeMinute
                HealthReminders.reschedule()
            }
        )
    }
}

/// Turning on a health reminder turns on notifications too, asking iOS if it hasn't yet.
@MainActor
enum HealthReminders {
    static func changed(turningOn: Bool, notificationsEnabled: Binding<Bool>) {
        if turningOn && !notificationsEnabled.wrappedValue {
            notificationsEnabled.wrappedValue = true
            Task {
                let granted = await NotificationScheduler.shared.requestAuthorization()
                if !granted { notificationsEnabled.wrappedValue = false }
                await FamilyAlertService.shared.updateSubscription()
            }
        } else {
            reschedule()
        }
    }

    static func reschedule() {
        Task { await NotificationScheduler.shared.reschedule() }
    }
}
