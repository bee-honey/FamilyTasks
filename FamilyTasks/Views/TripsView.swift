import SwiftUI

/// The family's trips: the ones coming up or underway first, then past ones.
struct TripsView: View {
    @EnvironmentObject private var tripStore: TripStore
    var isPushed = false
    @State private var isAdding = false
    /// The trip whose page is open. Pushed by state rather than a link value, since More's
    /// navigation path only holds its own destinations.
    @State private var openTripID: UUID?

    var body: some View {
        // Shown inside a tab's NavigationStack, or pushed from More.
        let upcoming = tripStore.upcomingTrips
        let past = tripStore.pastTrips
        List {
            Section {
                ScreenHeader(eyebrow: summary(upcoming: upcoming), title: "Trips") {
                    HeaderAddButton(accessibilityLabel: "Plan a trip") { isAdding = true }
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 4))
            .listRowBackground(Color.clear)

            if tripStore.trips.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Trips Yet", systemImage: "suitcase.rolling")
                    } description: {
                        Text("Plan where you're going, what to pack and what to do each day. Everyone in the family sees it, and you'll get a reminder of what's left to pack the morning you leave.")
                    } actions: {
                        Button("Plan a Trip") { isAdding = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .listRowBackground(Color.clear)
            }

            if !upcoming.isEmpty {
                Section {
                    ForEach(upcoming) { trip in
                        tripButton(trip)
                        .listRowBackground(AppTheme.surface)
                    }
                } header: {
                    SectionTitle(text: "Coming Up")
                }
            }

            if !past.isEmpty {
                Section {
                    ForEach(past) { trip in
                        tripButton(trip)
                        .listRowBackground(AppTheme.surface)
                    }
                } header: {
                    SectionTitle(text: "Past Trips")
                } footer: {
                    Text("Start a new trip from one of these to reuse its packing list.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        // Header at the same height on every tab.
        .contentMargins(.top, 0, for: .scrollContent)
        .background(AppTheme.background)
        .mainScreenNavigationBar(title: "Trips", isPushed: isPushed)
        .navigationDestination(item: $openTripID) { tripID in
            TripDetailView(tripID: tripID).backButton("Trips")
        }
        .sheet(isPresented: $isAdding) {
            TripEditorView()
        }
    }

    private func tripButton(_ trip: Trip) -> some View {
        Button {
            openTripID = trip.id
        } label: {
            HStack {
                TripRow(trip: trip)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func summary(upcoming: [Trip]) -> String {
        guard let next = upcoming.first else {
            return tripStore.trips.isEmpty ? "Plan a getaway" : "Nothing planned"
        }
        return "\(next.placeName) · \(next.phaseText())"
    }
}

/// A trip in a list: name, dates, how far away it is and how much is packed.
struct TripRow: View {
    @EnvironmentObject private var tripStore: TripStore
    let trip: Trip

    var body: some View {
        let packing = tripStore.packing(for: trip)
        let packed = packing.filter(\.isPacked).count
        HStack(spacing: 12) {
            IconTile(systemImage: "suitcase.rolling.fill", tint: trip.isFinished ? .secondary : AppTheme.coolAccent, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(trip.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)
                Text(trip.dateText())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(trip.phaseText())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(trip.isFinished ? Color.secondary : AppTheme.coolAccent)
                    if !packing.isEmpty, !trip.isFinished {
                        Text("\(Image(systemName: "checklist")) \(packed) of \(packing.count) packed")
                            .font(.caption)
                            .foregroundStyle(packed == packing.count ? AppTheme.success : .secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// A new trip, with packing lists to start from, or an existing trip's details and reminders.
struct TripEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tripStore: TripStore
    let trip: Trip?
    var onDelete: (() -> Void)?

    @State private var name: String
    @State private var destination: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var notes: String
    @State private var packingReminderEnabled: Bool
    @State private var packingReminderTime: Date
    @State private var remindEveningBefore: Bool
    @State private var dailyPlanEnabled: Bool
    @State private var packingLists: Set<PackingList> = PackingList.defaults
    @State private var copyFromID: UUID?
    @FocusState private var isNameFocused: Bool
    @FocusState private var isDestinationFocused: Bool
    @StateObject private var placeSearch = TripPlaceSearch(resultTypes: [.address, .pointOfInterest])

    init(trip: Trip? = nil, onDelete: (() -> Void)? = nil) {
        self.trip = trip
        self.onDelete = onDelete
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
        _name = State(initialValue: trip?.name ?? "")
        _destination = State(initialValue: trip?.destination ?? "")
        _startDate = State(initialValue: trip?.startDate ?? tomorrow)
        _endDate = State(initialValue: trip?.endDate ?? calendar.date(byAdding: .day, value: 3, to: tomorrow) ?? tomorrow)
        _notes = State(initialValue: trip?.notes ?? "")
        _packingReminderEnabled = State(initialValue: trip?.packingReminderEnabled ?? true)
        let hour = trip?.packingReminderHour ?? 6
        let minute = trip?.packingReminderMinute ?? 0
        _packingReminderTime = State(initialValue: calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date())
        _remindEveningBefore = State(initialValue: trip?.remindEveningBefore ?? true)
        _dailyPlanEnabled = State(initialValue: trip?.dailyPlanEnabled ?? true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Trip name, like Thanksgiving", text: $name, axis: .vertical)
                            .font(.title2.weight(.bold))
                            .focused($isNameFocused)
                        TextField("Where to? San Diego", text: $destination)
                            .textInputAutocapitalization(.words)
                            .foregroundStyle(.secondary)
                            .focused($isDestinationFocused)
                            .onChange(of: destination) { _, text in
                                if isDestinationFocused { placeSearch.search(text) }
                            }
                        if isDestinationFocused, !placeSearch.suggestions.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(placeSearch.suggestions) { suggestion in
                                    Button {
                                        destination = suggestion.title
                                        placeSearch.clear()
                                        isDestinationFocused = false
                                    } label: {
                                        PlaceSuggestionRow(suggestion: suggestion)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 9)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    if suggestion != placeSearch.suggestions.last {
                                        Divider().padding(.leading, 44)
                                    }
                                }
                            }
                            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    EditorSection("Dates") {
                        VStack(spacing: 0) {
                            DatePicker("Leaving", selection: $startDate, displayedComponents: .date)
                                .padding(12)
                                .onChange(of: startDate) { _, start in
                                    if endDate < start { endDate = start }
                                }
                            Divider().padding(.leading, 12)
                            DatePicker("Coming Back", selection: $endDate, in: startDate..., displayedComponents: .date)
                                .padding(12)
                        }
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Text(dayCountText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if trip == nil {
                        packingStartSection
                    }

                    EditorSection("Reminders") {
                        VStack(spacing: 0) {
                            Toggle(isOn: $packingReminderEnabled) {
                                Label("What's Left to Pack", systemImage: "checklist")
                                    .labelStyle(.tile(AppTheme.coolAccent))
                            }
                            .padding(12)
                            if packingReminderEnabled {
                                Divider().padding(.leading, 56)
                                DatePicker("The Morning You Leave", selection: $packingReminderTime, displayedComponents: .hourAndMinute)
                                    .padding(12)
                                Divider().padding(.leading, 12)
                                Toggle("And the Evening Before", isOn: $remindEveningBefore)
                                    .padding(12)
                            }
                            Divider().padding(.leading, 56)
                            Toggle(isOn: $dailyPlanEnabled) {
                                Label("Each Day's Plan at 8 AM", systemImage: "sun.max")
                                    .labelStyle(.tile(AppTheme.goldAccent))
                            }
                            .padding(12)
                        }
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Text("Activities with a time can also remind you before they start. Reminders need notifications on in Settings.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    EditorSection("Notes") {
                        TextField("Flight numbers, where you're staying, who's feeding the cat", text: $notes, axis: .vertical)
                            .lineLimit(3...8)
                            .padding(12)
                            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    if trip != nil {
                        EditorDeleteButton(title: "Delete Trip", message: "Its packing list and plan are deleted for everyone in the family.") {
                            if let trip { tripStore.deleteTrip(trip) }
                            dismiss()
                            onDelete?()
                        }
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.background)
            .navigationTitle(trip == nil ? "New Trip" : "Edit Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(trip == nil ? "Add" : "Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if trip == nil { isNameFocused = true }
            }
        }
    }

    @ViewBuilder
    private var packingStartSection: some View {
        let pastTrips = tripStore.trips.sorted { $0.startDate > $1.startDate }
        EditorSection("Start the Packing List With") {
            WrappingStack(spacing: 8) {
                ForEach(PackingList.allCases) { list in
                    ChoiceChip(title: list.title, isSelected: packingLists.contains(list)) {
                        if packingLists.contains(list) { packingLists.remove(list) } else { packingLists.insert(list) }
                    }
                }
            }
            if !pastTrips.isEmpty {
                Picker(selection: $copyFromID) {
                    Text("Don't Copy").tag(UUID?.none)
                    ForEach(pastTrips) { past in
                        Text(past.displayName).tag(UUID?.some(past.id))
                    }
                } label: {
                    Label("Copy a List From", systemImage: "doc.on.doc")
                }
                .pickerStyle(.menu)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Text(packingCountText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var packingCountText: String {
        var names = Set<String>()
        for list in packingLists { list.items.forEach { names.insert(WeeklyIngredient.key(for: $0.name)) } }
        if let copyFromID, let source = tripStore.trip(id: copyFromID) {
            tripStore.packing(for: source).forEach { names.insert(WeeklyIngredient.key(for: $0.name)) }
        }
        return names.isEmpty
            ? "Start with an empty list and add your own."
            : "Starts with \(names.count) items. Add, remove or tick them off later."
    }

    private var dayCountText: String {
        let days = (Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: startDate), to: Calendar.current.startOfDay(for: endDate)).day ?? 0) + 1
        return days == 1 ? "A day trip." : "\(days) days, \(days - 1) \(days - 1 == 1 ? "night" : "nights")."
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let time = Calendar.current.dateComponents([.hour, .minute], from: packingReminderTime)
        if var updated = trip {
            updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.destination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.startDate = startDate
            updated.endDate = endDate
            updated.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.packingReminderEnabled = packingReminderEnabled
            updated.packingReminderHour = time.hour ?? 6
            updated.packingReminderMinute = time.minute ?? 0
            updated.remindEveningBefore = remindEveningBefore
            updated.dailyPlanEnabled = dailyPlanEnabled
            tripStore.updateTrip(updated)
        } else {
            var created = tripStore.addTrip(
                name: name,
                destination: destination,
                startDate: startDate,
                endDate: endDate,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                packingLists: packingLists,
                copyingPackingFrom: copyFromID.flatMap(tripStore.trip(id:))
            )
            created.packingReminderEnabled = packingReminderEnabled
            created.packingReminderHour = time.hour ?? 6
            created.packingReminderMinute = time.minute ?? 0
            created.remindEveningBefore = remindEveningBefore
            created.dailyPlanEnabled = dailyPlanEnabled
            tripStore.updateTrip(created)
        }
        dismiss()
    }
}
