import Charts
import SwiftUI

/// The spending dashboard: this month against the budget, where the money went, payments
/// still due, trips, and every expense. Each item is either "Just me" or "Family".
struct BudgetView: View {
    @EnvironmentObject private var budgetStore: BudgetStore
    @EnvironmentObject private var organizerStore: OrganizerStore
    @EnvironmentObject private var tripStore: TripStore
    var isPushed = false

    @State private var month = Date()
    @AppStorage("budget.scope") private var scopeRaw = MoneyScope.all.rawValue
    @State private var isAdding = false
    @State private var editingExpense: Expense?
    @State private var isEditingLimits = false
    @State private var openTripID: UUID?

    var body: some View {
        // Shown inside a tab's NavigationStack, or pushed from Family.
        List {
            Section {
                ScreenHeader(eyebrow: eyebrow, title: "Budget") {
                    HeaderAddButton(accessibilityLabel: "Add expense") { isAdding = true }
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 4))
            .listRowBackground(Color.clear)

            Section {
                VStack(spacing: 12) {
                    monthSwitcher
                    Picker("Show", selection: $scopeRaw) {
                        ForEach(MoneyScope.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            .listRowBackground(Color.clear)

            Section {
                summaryCard
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            .listRowBackground(Color.clear)

            if !byCategory.isEmpty {
                categorySection
            }
            if !upcomingPayments.isEmpty {
                paymentsSection
            }
            if !tripSpending.isEmpty {
                tripsSection
            }
            expensesSection
        }
        .scrollContentBackground(.hidden)
        // Header at the same height on every tab.
        .contentMargins(.top, 0, for: .scrollContent)
        .background(AppTheme.background)
        .mainScreenNavigationBar(title: "Budget", isPushed: isPushed)
        .navigationDestination(item: $openTripID) { tripID in
            TripDetailView(tripID: tripID, initialTab: .spending).backButton("Budget")
        }
        .sheet(isPresented: $isAdding) {
            ExpenseEditorView(expense: nil, prefill: ExpensePrefill(date: defaultNewDate))
        }
        .sheet(item: $editingExpense) { expense in
            ExpenseEditorView(expense: expense)
        }
        .sheet(isPresented: $isEditingLimits) {
            BudgetLimitsView()
        }
    }

    // MARK: Data

    private var scope: MoneyScope { MoneyScope(rawValue: scopeRaw) ?? .all }
    private var monthInterval: DateInterval { BudgetMath.month(containing: month) }
    private var isThisMonth: Bool { monthInterval.contains(Date()) }
    private var monthExpenses: [Expense] { budgetStore.expenses(in: monthInterval, scope: scope) }
    private var spent: Decimal { BudgetMath.total(monthExpenses) }
    private var byCategory: [(category: SpendingCategory, total: Decimal)] { BudgetMath.byCategory(monthExpenses) }

    private var lastMonthSpent: Decimal? {
        guard let previous = Calendar.current.date(byAdding: .month, value: -1, to: monthInterval.start) else { return nil }
        let expenses = budgetStore.expenses(in: BudgetMath.month(containing: previous), scope: scope)
        return expenses.isEmpty ? nil : BudgetMath.total(expenses)
    }

    private var upcomingPayments: [(task: RecurringTask, amount: Decimal)] {
        // Payments behind schedule still count as due this month.
        var interval = monthInterval
        if isThisMonth { interval = DateInterval(start: .distantPast, end: monthInterval.end) }
        return BudgetMath.upcomingPayments(organizerStore.visibleRecurringTasks, in: interval)
    }

    /// Trips with spending or a budget that are coming up or happened this month.
    private var tripSpending: [(trip: Trip, spent: Decimal, limit: Decimal?)] {
        tripStore.trips
            .filter { trip in
                !trip.isFinished || monthInterval.intersects(DateInterval(start: trip.startDate, end: trip.endDate.addingTimeInterval(86_399)))
            }
            .compactMap { trip in
                let expenses = budgetStore.expenses(for: trip).filter { scope.includes($0.visibility) }
                let limit = budgetStore.tripLimit(for: trip).flatMap { scope.includes($0.visibility) ? $0.amount : nil }
                guard !expenses.isEmpty || limit != nil else { return nil }
                return (trip: trip, spent: BudgetMath.total(expenses), limit: limit)
            }
            .sorted { $0.trip.startDate < $1.trip.startDate }
    }

    private var eyebrow: String {
        let count = monthExpenses.count
        if count == 0 { return isThisMonth ? "This month" : "No spending" }
        return "\(count) \(count == 1 ? "expense" : "expenses")"
    }

    private var defaultNewDate: Date {
        isThisMonth ? Date() : monthInterval.start.addingTimeInterval(12 * 3_600)
    }

    // MARK: Sections

    private var monthSwitcher: some View {
        HStack {
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left").frame(width: 36, height: 36)
            }
            .accessibilityLabel("Previous month")
            Spacer()
            Text(monthInterval.start.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            if !isThisMonth {
                Button("This Month") { month = Date() }
                    .font(.caption.weight(.semibold))
            }
            Spacer()
            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right").frame(width: 36, height: 36)
            }
            .accessibilityLabel("Next month")
        }
        .buttonStyle(.borderless)
    }

    private func shiftMonth(_ step: Int) {
        month = Calendar.current.date(byAdding: .month, value: step, to: monthInterval.start) ?? month
    }

    private var summaryCard: some View {
        let limit = budgetStore.monthlyLimit(scope: scope)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Spent")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(Money.text(spent))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(AppTheme.ink)
                        .contentTransition(.numericText())
                }
                Spacer()
                Button(limit == nil ? "Set Budget" : "Budgets") { isEditingLimits = true }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
            }
            if let limit {
                let progress = BudgetMath.progress(spent: spent, limit: limit.amount)
                ProgressView(value: min(progress, 1))
                    .tint(progressTint(progress))
                HStack {
                    Text(spent <= limit.amount ? "\(Money.text(limit.amount - spent)) left" : "\(Money.text(spent - limit.amount)) over")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(spent <= limit.amount ? AppTheme.ink : AppTheme.destructive)
                    Spacer()
                    Text("of \(Money.text(limit.amount)) · \(limit.visibility.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let comparison = comparisonText {
                Text(comparison)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if scope == .all, !monthExpenses.isEmpty {
                let family = BudgetMath.total(monthExpenses.filter { $0.visibility == .family })
                Text("\(Image(systemName: MoneyVisibility.family.systemImage)) Family \(Money.text(family))   \(Image(systemName: MoneyVisibility.justMe.systemImage)) Just me \(Money.text(spent - family))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var comparisonText: String? {
        guard let lastMonthSpent, lastMonthSpent > 0 else { return nil }
        let change = ((spent - lastMonthSpent) / lastMonthSpent).doubleValue
        let percent = abs(change).formatted(.percent.precision(.fractionLength(0)))
        let previous = Calendar.current.date(byAdding: .month, value: -1, to: monthInterval.start)?.formatted(.dateTime.month(.wide)) ?? "last month"
        if abs(change) < 0.01 { return "About the same as \(previous)" }
        return change > 0 ? "\(percent) more than \(previous)" : "\(percent) less than \(previous)"
    }

    private var categorySection: some View {
        Section {
            Chart(byCategory, id: \.category) { entry in
                SectorMark(angle: .value("Spent", entry.total.doubleValue), innerRadius: .ratio(0.62), angularInset: 1.5)
                    .cornerRadius(3)
                    .foregroundStyle(spendingTint(entry.category))
            }
            .frame(height: 170)
            .chartBackground { _ in
                VStack(spacing: 0) {
                    Text(Money.text(spent))
                        .font(.headline)
                    Text("\(byCategory.count) \(byCategory.count == 1 ? "category" : "categories")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
            .accessibilityHidden(true)

            ForEach(byCategory, id: \.category) { entry in
                CategorySpendRow(
                    category: entry.category,
                    total: entry.total,
                    share: spent > 0 ? (entry.total / spent).doubleValue : 0,
                    limit: budgetStore.categoryLimit(entry.category, scope: scope)?.amount
                )
            }
        } header: {
            SectionTitle(text: "Where It Went")
        }
        .listRowBackground(AppTheme.surface)
    }

    private var paymentsSection: some View {
        let total = upcomingPayments.reduce(Decimal(0)) { $0 + $1.amount }
        return Section {
            ForEach(upcomingPayments, id: \.task.id) { payment in
                HStack(spacing: 12) {
                    IconTile(systemImage: "repeat", tint: AppTheme.primary, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(payment.task.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                        Text(dueText(payment.task.nextDueDate))
                            .font(.caption)
                            .foregroundStyle(payment.task.nextDueDate < Calendar.current.startOfDay(for: Date()) ? AppTheme.overdue : .secondary)
                    }
                    Spacer()
                    Text(Money.text(payment.amount))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                    Button("Paid") {
                        RecurringPayment.markDone(payment.task, organizer: organizerStore)
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(AppTheme.success)
                }
            }
        } header: {
            SectionTitle(text: "Still to Pay · \(Money.text(total))")
        } footer: {
            Text("From Recurring, for ones with an amount. Marking one paid adds it here as spent.")
        }
        .listRowBackground(AppTheme.surface)
    }

    private func dueText(_ date: Date) -> String {
        let calendar = Calendar.current
        if date < calendar.startOfDay(for: Date()) { return "Overdue · \(date.formatted(.dateTime.month(.abbreviated).day()))" }
        if calendar.isDateInToday(date) { return "Due today" }
        if calendar.isDateInTomorrow(date) { return "Due tomorrow" }
        return "Due \(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
    }

    private var tripsSection: some View {
        Section {
            ForEach(tripSpending, id: \.trip.id) { entry in
                Button {
                    openTripID = entry.trip.id
                } label: {
                    HStack(spacing: 12) {
                        IconTile(systemImage: "suitcase.rolling", tint: AppTheme.coolAccent, size: 36)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.trip.displayName)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                            if let limit = entry.limit {
                                let progress = BudgetMath.progress(spent: entry.spent, limit: limit)
                                ProgressView(value: min(progress, 1))
                                    .tint(progressTint(progress))
                                Text("\(Money.text(entry.spent)) of \(Money.text(limit))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("\(Money.text(entry.spent)) spent · \(entry.trip.dateText())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            SectionTitle(text: "Trips")
        }
        .listRowBackground(AppTheme.surface)
    }

    private var expensesSection: some View {
        Section {
            if monthExpenses.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(budgetStore.expenses.isEmpty ? "Nothing tracked yet" : "Nothing spent this month")
                        .font(.subheadline.weight(.semibold))
                    Text("Tap + to add an expense. Spending also comes in when you finish shopping, mark a recurring payment paid, give a task a cost or add to a trip.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(monthExpenses) { expense in
                    Button {
                        editingExpense = expense
                    } label: {
                        ExpenseRow(expense: expense, tripName: expense.tripID.flatMap { tripStore.trip(id: $0)?.displayName })
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            budgetStore.delete(expense)
                        }
                    }
                }
            }
        } header: {
            SectionTitle(text: monthExpenses.isEmpty ? "Expenses" : "Expenses · \(monthExpenses.count)")
        }
        .listRowBackground(AppTheme.surface)
    }
}

// MARK: Pieces

func spendingTint(_ category: SpendingCategory) -> Color {
    switch category {
    case .groceries: AppTheme.success
    case .dining: AppTheme.brightAccent
    case .bills: AppTheme.primary
    case .home: AppTheme.warmAccent
    case .travel: AppTheme.coolAccent
    case .transport: AppTheme.taskDelegate
    case .kids: AppTheme.softAccent
    case .health: AppTheme.destructive
    case .shopping: AppTheme.goldAccent
    case .fun: AppTheme.taskDo
    case .other: Color.gray
    }
}

private func progressTint(_ progress: Double) -> Color {
    if progress > 1 { return AppTheme.destructive }
    if progress > 0.85 { return AppTheme.warning }
    return AppTheme.success
}

private struct CategorySpendRow: View {
    let category: SpendingCategory
    let total: Decimal
    let share: Double
    let limit: Decimal?

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemImage: category.systemImage, tint: spendingTint(category), size: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(category.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Spacer()
                    Text(Money.text(total))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                }
                if let limit {
                    let progress = BudgetMath.progress(spent: total, limit: limit)
                    ProgressView(value: min(progress, 1))
                        .tint(progressTint(progress))
                    Text(total <= limit ? "\(Money.text(limit - total)) left of \(Money.text(limit))" : "\(Money.text(total - limit)) over \(Money.text(limit))")
                        .font(.caption2)
                        .foregroundStyle(total <= limit ? Color.secondary : AppTheme.destructive)
                } else {
                    Text(share.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ExpenseRow: View {
    let expense: Expense
    var tripName: String?
    var showsDate = true

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemImage: expense.category.systemImage, tint: spendingTint(expense.category), size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.text(expense.amount))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(AppTheme.ink)
                Image(systemName: expense.visibility.systemImage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(expense.visibility.title)
            }
        }
        .contentShape(Rectangle())
    }

    private var detail: String {
        var parts: [String] = []
        if showsDate { parts.append(expense.date.formatted(.dateTime.month(.abbreviated).day())) }
        if let tripName { parts.append(tripName) }
        else if expense.recurringTaskID != nil { parts.append("Recurring") }
        else if expense.shopID != nil { parts.append("Shopping") }
        else if expense.taskID != nil { parts.append("Task") }
        else { parts.append(expense.category.title) }
        if expense.visibility == .family, !expense.paidBy.isEmpty, expense.paidBy != HabitStore.currentProfileEmail() {
            parts.append(Assignee.memberName(for: expense.paidBy))
        }
        return parts.joined(separator: " · ")
    }
}

/// Just me or Family, with what that means.
struct MoneyVisibilityPicker: View {
    @Binding var visibility: MoneyVisibility

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Who can see it", selection: $visibility) {
                ForEach(MoneyVisibility.allCases) { option in
                    Label(option.title, systemImage: option.systemImage).tag(option)
                }
            }
            .pickerStyle(.segmented)
            Text(visibility.explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

extension MoneyVisibility {
    static let defaultKey = "budget.defaultVisibility"

    /// New money starts private unless chosen otherwise.
    static var defaultForNew: MoneyVisibility {
        UserDefaults.standard.string(forKey: defaultKey).flatMap(MoneyVisibility.init(rawValue:)) ?? .justMe
    }

    static func remember(_ visibility: MoneyVisibility) {
        UserDefaults.standard.set(visibility.rawValue, forKey: defaultKey)
    }
}

/// Marking a recurring payment done also records what it cost.
@MainActor
enum RecurringPayment {
    static func markDone(_ task: RecurringTask, organizer: OrganizerStore) {
        let store = BudgetStore.shared
        guard let expense = store.markPaid(task, organizer: organizer, visibility: .defaultForNew) else { return }
        ToastCenter.shared.show("\(Money.text(expense.amount)) for \(task.title) added to Budget", systemImage: "chart.pie.fill", actionTitle: "Don't Add") {
            store.delete(expense)
        }
    }
}

/// A money field: the currency symbol and a decimal keypad.
struct AmountField: View {
    let title: String
    @Binding var text: String
    var font: Font = .title2.weight(.bold)

    var body: some View {
        HStack(spacing: 6) {
            Text(currencySymbol)
                .font(font)
                .foregroundStyle(.secondary)
            TextField(title, text: $text)
                .font(font)
                .keyboardType(.decimalPad)
        }
    }

    private var currencySymbol: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Money.currencyCode
        return formatter.currencySymbol ?? "$"
    }
}

extension Decimal {
    /// For editing: "12.5" rather than "$12.50".
    var editingText: String {
        self == 0 ? "" : NSDecimalNumber(decimal: self).stringValue
    }
}

// MARK: Editors

/// What a new expense starts with when added from a trip day, a shop and so on.
struct ExpensePrefill {
    var title = ""
    var date = Date()
    var category: SpendingCategory = .other
    var tripID: UUID?
    var shopID: UUID?
}

struct ExpenseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var budgetStore: BudgetStore
    @EnvironmentObject private var tripStore: TripStore
    let expense: Expense?

    @State private var amountText: String
    @State private var title: String
    @State private var category: SpendingCategory
    @State private var date: Date
    @State private var visibility: MoneyVisibility
    @State private var tripID: UUID?
    @State private var notes: String
    private let shopID: UUID?
    @FocusState private var isAmountFocused: Bool

    init(expense: Expense?, prefill: ExpensePrefill = ExpensePrefill()) {
        self.expense = expense
        _amountText = State(initialValue: expense?.amount.editingText ?? "")
        _title = State(initialValue: expense?.title ?? prefill.title)
        _category = State(initialValue: expense?.category ?? prefill.category)
        _date = State(initialValue: expense?.date ?? prefill.date)
        _visibility = State(initialValue: expense?.visibility ?? .defaultForNew)
        _tripID = State(initialValue: expense?.tripID ?? prefill.tripID)
        _notes = State(initialValue: expense?.notes ?? "")
        shopID = expense?.shopID ?? prefill.shopID
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        AmountField(title: "0", text: $amountText, font: .system(.largeTitle, design: .rounded).weight(.bold))
                            .focused($isAmountFocused)
                        TextField("What for? Dinner, tickets, gas", text: $title)
                            .font(.headline)
                    }

                    EditorSection("Category") {
                        WrappingStack(spacing: 8) {
                            ForEach(SpendingCategory.allCases) { option in
                                Button {
                                    category = option
                                } label: {
                                    Label(option.title, systemImage: option.systemImage)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(category == option ? AppTheme.onAvatar : spendingTint(option))
                                        .padding(.horizontal, 12)
                                        .frame(minHeight: 34)
                                        .background(category == option ? spendingTint(option) : spendingTint(option).opacity(0.15), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(category == option ? .isSelected : [])
                            }
                        }
                    }

                    EditorSection("Who Can See It") {
                        MoneyVisibilityPicker(visibility: $visibility)
                    }

                    EditorSection("Details") {
                        VStack(spacing: 0) {
                            DatePicker("Date", selection: $date, displayedComponents: .date)
                                .padding(12)
                            if !tripChoices.isEmpty {
                                Divider().padding(.leading, 12)
                                Picker("Trip", selection: $tripID) {
                                    Text("None").tag(UUID?.none)
                                    ForEach(tripChoices) { trip in
                                        Text(trip.displayName).tag(Optional(trip.id))
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                            }
                            Divider().padding(.leading, 12)
                            TextField("Notes", text: $notes, axis: .vertical)
                                .lineLimit(1...4)
                                .padding(12)
                        }
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    if let expense {
                        EditorDeleteButton(title: "Delete Expense", message: expense.visibility == .family ? "It's removed for everyone in the family." : "It's removed from this phone.") {
                            budgetStore.delete(expense)
                            dismiss()
                        }
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.background)
            .navigationTitle(expense == nil ? "New Expense" : "Edit Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(expense == nil ? "Add" : "Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(amount == nil)
                }
            }
            .onAppear {
                if expense == nil { isAmountFocused = true }
            }
        }
    }

    private var amount: Decimal? {
        Money.parse(amountText).flatMap { $0 > 0 ? $0 : nil }
    }

    private var tripChoices: [Trip] {
        tripStore.upcomingTrips + tripStore.pastTrips.prefix(5)
    }

    private func save() {
        guard let amount else { return }
        var updated = expense ?? Expense(title: title, amount: amount, shopID: shopID)
        updated.title = title
        updated.amount = amount
        updated.category = category
        updated.date = date
        updated.visibility = visibility
        updated.tripID = tripID
        updated.notes = notes
        if expense == nil {
            budgetStore.add(updated)
            MoneyVisibility.remember(visibility)
        } else {
            budgetStore.update(updated)
        }
        dismiss()
    }
}

/// The monthly budget overall and by category.
struct BudgetLimitsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var budgetStore: BudgetStore
    @State private var overallText = ""
    @State private var categoryTexts: [SpendingCategory: String] = [:]
    @State private var visibility: MoneyVisibility = .defaultForNew

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AmountField(title: "Monthly budget", text: $overallText, font: .title3.weight(.semibold))
                } header: {
                    Text("Each Month")
                } footer: {
                    Text("Everything together. Leave empty for no limit.")
                }
                Section {
                    ForEach(SpendingCategory.allCases) { category in
                        HStack {
                            Label(category.title, systemImage: category.systemImage)
                                .foregroundStyle(AppTheme.ink)
                            Spacer()
                            TextField("No limit", text: Binding(
                                get: { categoryTexts[category] ?? "" },
                                set: { categoryTexts[category] = $0 }
                            ))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                        }
                    }
                } header: {
                    Text("By Category")
                }
                Section {
                    MoneyVisibilityPicker(visibility: $visibility)
                } header: {
                    Text("Who Can See These Budgets")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Budgets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        let monthly = budgetStore.limits.filter(\.isMonthly)
        if let overall = monthly.first(where: { $0.category == nil }) {
            overallText = overall.amount.editingText
            visibility = overall.visibility
        } else if let any = monthly.first {
            visibility = any.visibility
        }
        for limit in monthly {
            if let category = limit.category { categoryTexts[category] = limit.amount.editingText }
        }
    }

    private func save() {
        budgetStore.setLimit(Money.parse(overallText), visibility: visibility)
        for category in SpendingCategory.allCases {
            budgetStore.setLimit(Money.parse(categoryTexts[category] ?? ""), category: category, visibility: visibility)
        }
        dismiss()
    }
}

/// After "Done Shopping": what the trip to the shop cost.
struct ShoppingSpendView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var budgetStore: BudgetStore
    let shop: Shop
    let itemCount: Int

    @State private var amountText = ""
    @State private var visibility: MoneyVisibility = .defaultForNew
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AmountField(title: "Total", text: $amountText)
                        .focused($isFocused)
                } footer: {
                    Text("\(itemCount) \(itemCount == 1 ? "item" : "items") bought. Added to Budget under Groceries.")
                }
                Section("Who Can See It") {
                    MoneyVisibilityPicker(visibility: $visibility)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Spent at \(shop.name)?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .fontWeight(.semibold)
                        .disabled(Money.parse(amountText).map { $0 <= 0 } ?? true)
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard let amount = Money.parse(amountText), amount > 0 else { return }
        budgetStore.add(Expense(
            title: shop.name,
            amount: amount,
            category: .groceries,
            visibility: visibility,
            notes: "\(itemCount) \(itemCount == 1 ? "item" : "items")",
            shopID: shop.id
        ))
        MoneyVisibility.remember(visibility)
        ToastCenter.shared.show("\(Money.text(amount)) at \(shop.name) added to Budget", systemImage: "chart.pie.fill")
        dismiss()
    }
}
