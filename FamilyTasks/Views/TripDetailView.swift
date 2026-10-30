import SwiftUI

/// One trip: its day-by-day plan and its packing checklist, with a way to share the
/// whole thing as text.
struct TripDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tripStore: TripStore
    let tripID: UUID

    enum Tab: String, CaseIterable, Identifiable {
        case plan, packing
        var id: String { rawValue }
        var title: String { self == .plan ? "Day by Day" : "Packing" }
    }

    @State private var tab: Tab = .plan
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
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(trip.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ShareLink(item: TripShareText.text(for: trip, packing: tripStore.packingItems, activities: tripStore.activities)) {
                    Label("Share Trip", systemImage: "square.and.arrow.up")
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
                Text([trip.destination == trip.displayName ? "" : trip.destination, trip.dateText()].filter { !$0.isEmpty }.joined(separator: " · "))
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
                    Button {
                        editingActivity = activity
                    } label: {
                        TripActivityRow(activity: activity)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(AppTheme.surface)
                    .swipeActions(edge: .trailing) {
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

/// A trip day a new activity is being added to.
private struct NewActivityDay: Identifiable {
    let day: Date
    var id: Date { day }
}

private struct TripActivityRow: View {
    let activity: TripActivity

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
                    Text("\(Image(systemName: "mappin.and.ellipse")) \(activity.location)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
