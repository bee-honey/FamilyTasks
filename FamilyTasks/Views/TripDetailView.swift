import MapKit
import SwiftUI

/// One trip: its day-by-day plan and its packing checklist, with a way to share the
/// whole thing as text.
struct TripDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tripStore: TripStore
    @EnvironmentObject private var budgetStore: BudgetStore
    let tripID: UUID

    enum Tab: String, CaseIterable, Identifiable {
        case plan, packing, spending
        var id: String { rawValue }
        var title: String {
            switch self {
            case .plan: "Day by Day"
            case .packing: "Packing"
            case .spending: "Spending"
            }
        }
    }

    @State private var tab: Tab
    @State private var newExpense: NewTripExpense?
    @State private var editingExpense: Expense?
    @State private var isSettingBudget = false

    init(tripID: UUID, initialTab: Tab = .plan) {
        self.tripID = tripID
        _tab = State(initialValue: initialTab)
    }

    @State private var isEditingTrip = false
    @State private var newActivityDay: NewActivityDay?
    @State private var editingActivity: TripActivity?
    @State private var editingItem: PackingItem?
    @State private var isAddingLists = false
    @State private var newItemName = ""
    @State private var newItemCategory: PackingCategory = .other

    var body: some View {
        Group {
            if let trip = tripStore.trip(id: tripID) {
                content(trip)
            } else {
                ContentUnavailableView("Trip Deleted", systemImage: "suitcase.rolling", description: Text("Someone in the family deleted this trip."))
            }
        }
        .background(AppTheme.background)
    }

    private func content(_ trip: Trip) -> some View {
        List {
            Section {
                header(trip)
                Picker("Show", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.top, 4)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 4, trailing: 4))
            .listRowBackground(Color.clear)

            switch tab {
            case .plan: planSections(trip)
            case .packing: packingSections(trip)
            case .spending: spendingSections(trip)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(trip.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    ForEach(TripShareText.Part.allCases, id: \.self) { part in
                        ShareLink(item: TripShareText.text(for: trip, packing: tripStore.packingItems, activities: tripStore.activities, part: part)) {
                            Label(part.title, systemImage: part.systemImage)
                        }
                    }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                Button("Edit", systemImage: "pencil") { isEditingTrip = true }
            }
        }
        .sheet(isPresented: $isEditingTrip) {
            TripEditorView(trip: trip) { dismiss() }
        }
        .sheet(item: $newActivityDay) { new in
            TripActivityEditorView(trip: trip, activity: nil, day: new.day)
        }
        .sheet(item: $editingActivity) { activity in
            TripActivityEditorView(trip: trip, activity: activity, day: activity.date)
        }
        .sheet(item: $editingItem) { item in
            PackingItemEditorView(item: item)
        }
        .sheet(isPresented: $isAddingLists) {
            AddPackingListsView(trip: trip)
        }
        .sheet(item: $newExpense) { new in
            ExpenseEditorView(expense: nil, prefill: ExpensePrefill(date: new.date, category: new.category, tripID: trip.id))
        }
        .sheet(item: $editingExpense) { expense in
            ExpenseEditorView(expense: expense)
        }
        .sheet(isPresented: $isSettingBudget) {
            TripBudgetView(trip: trip)
        }
    }

    private func header(_ trip: Trip) -> some View {
        let packing = tripStore.packing(for: trip)
        let packed = packing.filter(\.isPacked).count
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.phaseText().uppercased())
                    .font(.footnote.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(AppTheme.coolAccent)
                Text(trip.displayName)
                    .font(.title.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                if !trip.destination.isEmpty {
                    Menu {
                        MapsMenuItems(query: trip.destination)
                    } label: {
                        Text("\(Image(systemName: "mappin.and.ellipse")) \(trip.destination)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.coolAccent)
                    }
                    .accessibilityHint("Opens in Maps")
                }
                Text(trip.dateText())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !packing.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(packed), total: Double(packing.count))
                        .tint(packed == packing.count ? AppTheme.success : AppTheme.coolAccent)
                    Text(packed == packing.count ? "All packed" : "\(packed) of \(packing.count) packed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if !trip.notes.isEmpty {
                Text(trip.notes)
                    .font(.subheadline)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    // MARK: Day by day

    @ViewBuilder
    private func planSections(_ trip: Trip) -> some View {
        ForEach(Array(trip.days().enumerated()), id: \.element) { index, day in
            let planned = tripStore.activities(for: trip, on: day)
            Section {
                ForEach(planned) { activity in
                    TripActivityRow(activity: activity, destination: trip.destination)
                        .onTapGesture { editingActivity = activity }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { editingActivity = activity }
                        .listRowBackground(AppTheme.surface)
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                tripStore.deleteActivity(activity)
                            }
                        }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { editingActivity = activity }
                            if !activity.location.isEmpty {
                                MapsMenuItems(query: TripMaps.query(for: activity.location, near: trip.destination))
                            }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                tripStore.deleteActivity(activity)
                            }
                        }
                }
                Button {
                    newActivityDay = NewActivityDay(day: day)
                } label: {
                    Label(planned.isEmpty ? "Plan Something" : "Add to This Day", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .listRowBackground(AppTheme.surface)
            } header: {
                HStack {
                    SectionTitle(text: "Day \(index + 1) · \(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))")
                    if Calendar.current.isDateInToday(day) {
                        Text("Today")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.coolAccent)
                            .textCase(nil)
                    }
                }
            }
        }
    }

    // MARK: Packing

    @ViewBuilder
    private func packingSections(_ trip: Trip) -> some View {
        let packing = tripStore.packing(for: trip)
        Section {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.headline)
                    .foregroundStyle(AppTheme.primary)
                TextField("Add something to pack", text: $newItemName)
                    .submitLabel(.done)
                    .onSubmit { addItem(to: trip) }
                Menu {
                    Picker("Group", selection: $newItemCategory) {
                        ForEach(PackingCategory.allCases) { category in
                            Label(category.title, systemImage: category.systemImage).tag(category)
                        }
                    }
                } label: {
                    Image(systemName: newItemCategory.systemImage)
                        .frame(width: 32, height: 32)
                        .background(AppTheme.surfaceMuted, in: Circle())
                }
                .accessibilityLabel("Group: \(newItemCategory.title)")
            }
            .listRowBackground(AppTheme.surface)
            HStack {
                Button {
                    isAddingLists = true
                } label: {
                    Label("Add from Lists", systemImage: "text.badge.plus")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
                Spacer()
                if packing.contains(where: \.isPacked) {
                    Button("Unpack All") { tripStore.unpackAll(in: trip) }
                        .font(.subheadline)
                        .buttonStyle(.borderless)
                }
            }
            .listRowBackground(AppTheme.surface)
        } footer: {
            if packing.isEmpty {
                Text("Add your own items or start from ready-made lists. Tick things off as they go in the bag; everyone sees the same list.")
            }
        }

        ForEach(PackingCategory.allCases) { category in
            let items = packing.filter { $0.category == category }
            if !items.isEmpty {
                Section {
                    ForEach(items) { item in
                        PackingItemRow(item: item) { tripStore.togglePacked(item) }
                            .listRowBackground(AppTheme.surface)
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    tripStore.deletePackingItem(item)
                                }
                                Button("Edit", systemImage: "pencil") { editingItem = item }
                                    .tint(AppTheme.primary)
                            }
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { editingItem = item }
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    tripStore.deletePackingItem(item)
                                }
                            }
                    }
                } header: {
                    let packed = items.filter(\.isPacked).count
                    SectionTitle(text: "\(category.title) · \(packed)/\(items.count)")
                }
            }
        }
    }

    private func addItem(to trip: Trip) {
        let name = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if tripStore.addPackingItems([(name, newItemCategory)], to: trip) == 0 {
            ToastCenter.shared.show("\(name) is already on the list", systemImage: "checklist")
        }
        newItemName = ""
    }
}

// MARK: Spending

extension TripDetailView {
    @ViewBuilder
    private func spendingSections(_ trip: Trip) -> some View {
        let expenses = budgetStore.expenses(for: trip)
        let days = trip.days()
        let calendar = Calendar.current
        let bookedAhead = expenses.filter { expense in !days.contains { calendar.isDate($0, inSameDayAs: expense.date) } }

        Section {
            tripBudgetCard(trip, expenses: expenses)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
        .listRowBackground(Color.clear)

        Section {
            ForEach(bookedAhead) { expense in
                expenseRow(expense, showsDate: true)
            }
            Button {
                newExpense = NewTripExpense(date: Date(), category: .travel)
            } label: {
                Label(bookedAhead.isEmpty ? "Add Flights, Hotel or Tickets" : "Add a Booking", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .listRowBackground(AppTheme.surface)
        } header: {
            SectionTitle(text: bookedAhead.isEmpty ? "Booked Ahead" : "Booked Ahead · \(Money.text(BudgetMath.total(bookedAhead)))")
        }

        ForEach(Array(days.enumerated()), id: \.element) { index, day in
            let spent = expenses.filter { calendar.isDate($0.date, inSameDayAs: day) }
            Section {
                ForEach(spent) { expense in
                    expenseRow(expense, showsDate: false)
                }
                Button {
                    newExpense = NewTripExpense(date: day.addingTimeInterval(12 * 3_600), category: .dining)
                } label: {
                    Label("Add Expense", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .listRowBackground(AppTheme.surface)
            } header: {
                let dayText = "Day \(index + 1) · \(day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
                SectionTitle(text: spent.isEmpty ? dayText : "\(dayText) · \(Money.text(BudgetMath.total(spent)))")
            }
        }
    }

    private func expenseRow(_ expense: Expense, showsDate: Bool) -> some View {
        Button {
            editingExpense = expense
        } label: {
            ExpenseRow(expense: expense, showsDate: showsDate)
        }
        .buttonStyle(.plain)
        .listRowBackground(AppTheme.surface)
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                budgetStore.delete(expense)
            }
        }
    }

    private func tripBudgetCard(_ trip: Trip, expenses: [Expense]) -> some View {
        let total = BudgetMath.total(expenses)
        let limit = budgetStore.tripLimit(for: trip)
        let top = BudgetMath.byCategory(expenses).prefix(3)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trip spending")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(Money.text(total))
                        .font(.system(.title, design: .rounded).weight(.bold))
                }
                Spacer()
                Button(limit == nil ? "Set Budget" : "Edit Budget") { isSettingBudget = true }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
            }
            if let limit {
                let progress = BudgetMath.progress(spent: total, limit: limit.amount)
                ProgressView(value: min(progress, 1))
                    .tint(progress > 1 ? AppTheme.destructive : progress > 0.85 ? AppTheme.warning : AppTheme.success)
                Text(total <= limit.amount ? "\(Money.text(limit.amount - total)) left of \(Money.text(limit.amount)) · \(limit.visibility.title)" : "\(Money.text(total - limit.amount)) over \(Money.text(limit.amount))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(total <= limit.amount ? Color.secondary : AppTheme.destructive)
            }
            if !top.isEmpty {
                Text(top.map { "\($0.category.title) \(Money.text($0.total))" }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// An expense being added to a trip, on a day or booked ahead.
private struct NewTripExpense: Identifiable {
    let id = UUID()
    let date: Date
    let category: SpendingCategory
}

/// A budget for the whole trip.
private struct TripBudgetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var budgetStore: BudgetStore
    let trip: Trip
    @State private var amountText = ""
    @State private var visibility: MoneyVisibility = .defaultForNew

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AmountField(title: "Trip budget", text: $amountText)
                } footer: {
                    Text("Everything for \(trip.displayName), including bookings made ahead. Leave empty for no budget.")
                }
                Section("Who Can See It") {
                    MoneyVisibilityPicker(visibility: $visibility)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Trip Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        budgetStore.setLimit(Money.parse(amountText), tripID: trip.id, visibility: visibility)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                if let limit = budgetStore.tripLimit(for: trip) {
                    amountText = limit.amount.editingText
                    visibility = limit.visibility
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// A trip day a new activity is being added to.
private struct NewActivityDay: Identifiable {
    let day: Date
    var id: Date { day }
}

private struct TripActivityRow: View {
    let activity: TripActivity
    let destination: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(activity.timeText ?? "Any time")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(activity.hasTime ? AppTheme.coolAccent : .secondary)
                .frame(width: 76, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(activity.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                if !activity.location.isEmpty {
                    Menu {
                        MapsMenuItems(query: TripMaps.query(for: activity.location, near: destination))
                    } label: {
                        Text("\(Image(systemName: "mappin.and.ellipse")) \(activity.location)")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppTheme.coolAccent)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityHint("Opens in Maps")
                }
                if !activity.notes.isEmpty {
                    Text(activity.notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if activity.reminderDate != nil {
                Image(systemName: "bell.fill")
                    .font(.caption)
                    .foregroundStyle(AppTheme.goldAccent)
                    .accessibilityLabel("Reminder: \(TripReminders.reminderText(activity.reminderMinutes))")
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

private struct PackingItemRow: View {
    let item: PackingItem
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: item.isPacked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isPacked ? AppTheme.success : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .strikethrough(item.isPacked)
                        .foregroundStyle(item.isPacked ? .secondary : AppTheme.ink)
                    if !item.forWhom.isEmpty {
                        Text(item.forWhom)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(item.isPacked ? .isSelected : [])
    }
}

/// Something to do on a trip day: what, when, where, and an optional reminder.
struct TripActivityEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tripStore: TripStore
    let trip: Trip
    let activity: TripActivity?

    @State private var title: String
    @State private var day: Date
    @State private var hasTime: Bool
    @State private var time: Date
    @State private var location: String
    @State private var notes: String
    @State private var reminderMinutes: Int?
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isLocationFocused: Bool
    @StateObject private var placeSearch = TripPlaceSearch()

    init(trip: Trip, activity: TripActivity?, day: Date) {
        self.trip = trip
        self.activity = activity
        let calendar = Calendar.current
        _title = State(initialValue: activity?.title ?? "")
        _day = State(initialValue: calendar.startOfDay(for: day))
        _hasTime = State(initialValue: activity?.hasTime ?? false)
        _time = State(initialValue: activity?.hasTime == true ? activity!.date : calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day) ?? day)
        _location = State(initialValue: activity?.location ?? "")
        _notes = State(initialValue: activity?.notes ?? "")
        _reminderMinutes = State(initialValue: activity == nil ? 30 : activity?.reminderMinutes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What's the plan? Zoo, beach, dinner", text: $title, axis: .vertical)
                        .font(.headline)
                        .focused($isTitleFocused)
                    TextField("Where", text: $location)
                        .textInputAutocapitalization(.words)
                        .focused($isLocationFocused)
                        .onChange(of: location) { _, text in
                            if isLocationFocused { placeSearch.search(text) }
                        }
                    if isLocationFocused {
                        ForEach(placeSearch.suggestions) { suggestion in
                            Button {
                                location = suggestion.title
                                placeSearch.clear()
                                isLocationFocused = false
                            } label: {
                                PlaceSuggestionRow(suggestion: suggestion)
                            }
                        }
                    } else if !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Menu {
                            MapsMenuItems(query: TripMaps.query(for: location, near: trip.destination))
                        } label: {
                            Label("Show on Map", systemImage: "map")
                        }
                    }
                } footer: {
                    if isLocationFocused, !placeSearch.suggestions.isEmpty {
                        Text("Places from Apple Maps\(trip.destination.isEmpty ? "" : " near \(trip.destination)").")
                    }
                }
                Section {
                    Picker("Day", selection: $day) {
                        ForEach(Array(trip.days().enumerated()), id: \.element) { index, tripDay in
                            Text("Day \(index + 1) · \(tripDay.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))").tag(tripDay)
                        }
                    }
                    Toggle("At a Set Time", isOn: $hasTime.animation())
                    if hasTime {
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        Picker("Remind Me", selection: $reminderMinutes) {
                            ForEach(TripReminders.reminderChoices, id: \.self) { minutes in
                                Text(TripReminders.reminderText(minutes)).tag(minutes)
                            }
                        }
                    }
                } footer: {
                    if !hasTime {
                        Text("Any-time plans show in the morning's list for the day.")
                    }
                }
                Section("Notes") {
                    TextField("Tickets, booking number, what to bring", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
                if let activity {
                    Section {
                        Button("Delete", role: .destructive) {
                            tripStore.deleteActivity(activity)
                            dismiss()
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle(activity == nil ? "New Plan" : "Edit Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(activity == nil ? "Add" : "Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if activity == nil { isTitleFocused = true }
            }
            .task { await placeSearch.focus(on: trip.destination) }
        }
        .presentationDetents([.large])
    }

    private func save() {
        let calendar = Calendar.current
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        let date = hasTime
            ? calendar.date(bySettingHour: clock.hour ?? 10, minute: clock.minute ?? 0, second: 0, of: day) ?? day
            : day
        var updated = activity ?? TripActivity(tripID: trip.id, title: title, date: date)
        updated.title = title
        updated.date = date
        updated.hasTime = hasTime
        updated.location = location
        updated.notes = notes
        updated.reminderMinutes = hasTime ? reminderMinutes : nil
        if activity == nil {
            tripStore.addActivity(updated)
        } else {
            tripStore.updateActivity(updated)
        }
        dismiss()
    }
}

private struct PackingItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tripStore: TripStore
    let item: PackingItem
    @State private var name: String
    @State private var category: PackingCategory
    @State private var forWhom: String

    init(item: PackingItem) {
        self.item = item
        _name = State(initialValue: item.name)
        _category = State(initialValue: item.category)
        _forWhom = State(initialValue: item.forWhom)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Item", text: $name)
                Picker("Group", selection: $category) {
                    ForEach(PackingCategory.allCases) { Text($0.title).tag($0) }
                }
                Section {
                    TextField("For or brought by, like Asha", text: $forWhom)
                        .textInputAutocapitalization(.words)
                } footer: {
                    Text("Leave empty when it's for everyone.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = item
                        updated.name = name
                        updated.category = category
                        updated.forWhom = forWhom
                        tripStore.updatePackingItem(updated)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Ready-made lists and other trips' lists to add to this trip's packing.
private struct AddPackingListsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tripStore: TripStore
    let trip: Trip
    @State private var lists: Set<PackingList> = []
    @State private var otherTrips: Set<UUID> = []

    var body: some View {
        let others = tripStore.trips.filter { $0.id != trip.id && !tripStore.packing(for: $0).isEmpty }
        NavigationStack {
            List {
                Section {
                    ForEach(PackingList.allCases) { list in
                        selectionRow(
                            title: list.title,
                            detail: list.items.map(\.name).joined(separator: ", "),
                            isSelected: lists.contains(list)
                        ) {
                            if lists.contains(list) { lists.remove(list) } else { lists.insert(list) }
                        }
                    }
                } header: {
                    Text("Ready-Made Lists")
                }
                if !others.isEmpty {
                    Section {
                        ForEach(others) { other in
                            selectionRow(
                                title: other.displayName,
                                detail: "\(tripStore.packing(for: other).count) items · \(other.dateText())",
                                isSelected: otherTrips.contains(other.id)
                            ) {
                                if otherTrips.contains(other.id) { otherTrips.remove(other.id) } else { otherTrips.insert(other.id) }
                            }
                        }
                    } header: {
                        Text("From Other Trips")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Add from Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }
                        .fontWeight(.semibold)
                        .disabled(lists.isEmpty && otherTrips.isEmpty)
                }
            }
        }
    }

    private func selectionRow(title: String, detail: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? AppTheme.success : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(AppTheme.ink)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(AppTheme.surface)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func add() {
        var items: [(name: String, category: PackingCategory)] = []
        for list in PackingList.allCases where lists.contains(list) {
            items += list.items
        }
        for other in tripStore.trips where otherTrips.contains(other.id) {
            items += tripStore.packing(for: other).map { ($0.name, $0.category) }
        }
        let added = tripStore.addPackingItems(items, to: trip)
        ToastCenter.shared.show(added == 0 ? "Everything's already on the list" : "Added \(added) \(added == 1 ? "item" : "items")", systemImage: "checklist")
        dismiss()
    }
}

// MARK: Maps

/// "Open in Apple Maps" and "Open in Google Maps", with directions, for a menu.
struct MapsMenuItems: View {
    @Environment(\.openURL) private var openURL
    let query: String

    var body: some View {
        Section(query) {
            ForEach(TripMaps.App.allCases, id: \.self) { app in
                Button(app.title, systemImage: "map") { open(app, directions: false) }
            }
        }
        Section {
            ForEach(TripMaps.App.allCases, id: \.self) { app in
                Button(app.directionsTitle, systemImage: "arrow.triangle.turn.up.right.diamond") { open(app, directions: true) }
            }
        }
    }

    private func open(_ app: TripMaps.App, directions: Bool) {
        if let url = TripMaps.url(for: query, in: app, directions: directions) { openURL(url) }
    }
}

/// A place Apple Maps suggests while typing.
struct PlaceSuggestion: Identifiable, Hashable {
    let title: String
    let subtitle: String
    var id: String { title + "|" + subtitle }
}

struct PlaceSuggestionRow: View {
    let suggestion: PlaceSuggestion

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill")
                .font(.title3)
                .foregroundStyle(AppTheme.coolAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .foregroundStyle(AppTheme.ink)
                if !suggestion.subtitle.isEmpty {
                    Text(suggestion.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// Suggests places from Apple Maps as someone types, favoring ones near the trip. MapKit
/// calls the delegate on the main thread, which the preconcurrency conformance checks.
@MainActor
final class TripPlaceSearch: NSObject, ObservableObject, @preconcurrency MKLocalSearchCompleterDelegate {
    @Published private(set) var suggestions: [PlaceSuggestion] = []
    private let completer = MKLocalSearchCompleter()

    init(resultTypes: MKLocalSearchCompleter.ResultType = [.pointOfInterest, .address]) {
        super.init()
        completer.delegate = self
        completer.resultTypes = resultTypes
    }

    /// Centers suggestions on the trip's destination, so "Zoo" finds the one there.
    func focus(on destination: String) async {
        let place = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !place.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = place
        guard let response = try? await MKLocalSearch(request: request).start() else { return }
        completer.region = response.boundingRegion
    }

    func search(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            clear()
            return
        }
        completer.queryFragment = query
    }

    func clear() {
        completer.cancel()
        completer.queryFragment = ""
        suggestions = []
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        guard !completer.queryFragment.isEmpty else { return }
        suggestions = completer.results.prefix(5).map { PlaceSuggestion(title: $0.title, subtitle: $0.subtitle) }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
    }
}
