import SwiftUI

struct ChoresView: View {
    @EnvironmentObject private var choreStore: ChoreStore
    @State private var editingChore: ChoreEditorTarget?
    @State private var isAddingKid = false
    @State private var selectedKid: KidProfile?
    @State private var isEditingSettings = false

    var body: some View {
        NavigationStack {
            List {
                if choreStore.kids.isEmpty {
                    ContentUnavailableView {
                        Label("No Kids Yet", systemImage: "figure.and.child.holdinghands")
                    } description: {
                        Text("Add your kids by name, then give them chores worth points.")
                    } actions: {
                        Button("Add a Kid") { isAddingKid = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    balancesSection
                    waitingSection
                    toDoSections
                    allChoresSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Chores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isEditingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Points settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Add Chore", systemImage: "star") { editingChore = .new }
                            .disabled(choreStore.kids.isEmpty)
                        Button("Add Kid", systemImage: "person.badge.plus") { isAddingKid = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add")
                }
            }
            .sheet(item: $editingChore) { target in
                ChoreEditorView(target: target)
            }
            .sheet(isPresented: $isAddingKid) {
                KidNameEditor(kid: nil)
            }
            .sheet(item: $selectedKid) { kid in
                KidDetailView(kidID: kid.id)
            }
            .sheet(isPresented: $isEditingSettings) {
                ChoreSettingsView()
            }
        }
    }

    private var balancesSection: some View {
        Section("Points") {
            ForEach(choreStore.kids) { kid in
                Button {
                    selectedKid = kid
                } label: {
                    HStack {
                        Text(kid.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        let balance = choreStore.balance(for: kid)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(balance) pts")
                                .font(.headline)
                                .foregroundStyle(AppTheme.primary)
                            Text(ChoreMath.formattedMoney(for: balance, settings: choreStore.settings))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .listRowBackground(AppTheme.surface)
            }
        }
    }

    @ViewBuilder
    private var waitingSection: some View {
        let waiting = choreStore.waitingForApproval
        if !waiting.isEmpty {
            Section {
                ForEach(waiting) { completion in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(kidName(completion.kidID)): \(completion.choreTitle)")
                                .font(.subheadline)
                            Text("\(completion.points) pts · \(completion.completedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            choreStore.reject(completion)
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Not done")
                        Button {
                            choreStore.approve(completion)
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(AppTheme.success)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Approve")
                    }
                    .listRowBackground(AppTheme.surface)
                }
            } header: {
                Text("Waiting for Approval")
            } footer: {
                Text("Points count once a parent approves.")
            }
        }
    }

    @ViewBuilder
    private var toDoSections: some View {
        ForEach(choreStore.kids) { kid in
            let assigned = choreStore.chores(for: kid)
            if !assigned.isEmpty {
                let toDo = assigned.filter { choreStore.status(of: $0, for: kid) == .toDo }
                Section("\(kid.name) to Do") {
                    if toDo.isEmpty {
                        Label("All done for now", systemImage: "checkmark.seal")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .listRowBackground(AppTheme.surface)
                    }
                    ForEach(toDo) { chore in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chore.title)
                                    .font(.subheadline)
                                Text("\(chore.points) pts · \(chore.frequency.title)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Done") {
                                choreStore.markDone(chore, for: kid)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .listRowBackground(AppTheme.surface)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var allChoresSection: some View {
        Section("All Chores") {
            if choreStore.chores.isEmpty {
                Button("Add a Chore") { editingChore = .new }
                    .listRowBackground(AppTheme.surface)
            }
            ForEach(choreStore.chores) { chore in
                Button {
                    editingChore = .existing(chore)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chore.title)
                            .foregroundStyle(.primary)
                        Text("\(chore.points) pts · \(chore.frequency.title) · \(kidNames(chore.kidIDs))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(AppTheme.surface)
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        choreStore.deleteChore(chore)
                    }
                }
            }
        }
    }

    private func kidName(_ id: UUID) -> String {
        choreStore.kids.first { $0.id == id }?.name ?? "Someone"
    }

    private func kidNames(_ ids: [UUID]) -> String {
        let names = choreStore.kids.filter { ids.contains($0.id) }.map(\.name)
        return names.isEmpty ? "No one yet" : ListFormatter.localizedString(byJoining: names)
    }
}

private enum ChoreEditorTarget: Identifiable {
    case new
    case existing(Chore)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let chore): chore.id.uuidString
        }
    }
}

private struct ChoreEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var choreStore: ChoreStore
    let target: ChoreEditorTarget

    @State private var title = ""
    @State private var points = 5
    @State private var frequency: RecurrenceFrequency = .daily
    @State private var kidIDs: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Chore") {
                    TextField("Make your bed", text: $title)
                        .textInputAutocapitalization(.sentences)
                    Stepper("\(points) points", value: $points, in: 1...100)
                    Text("Worth \(ChoreMath.formattedMoney(for: points, settings: choreStore.settings))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Repeats", selection: $frequency) {
                        ForEach([RecurrenceFrequency.daily, .weekly, .monthly]) { frequency in
                            Text(frequency.title).tag(frequency)
                        }
                    }
                }

                Section("For") {
                    ForEach(choreStore.kids) { kid in
                        Toggle(kid.name, isOn: Binding(
                            get: { kidIDs.contains(kid.id) },
                            set: { isOn in
                                if isOn { kidIDs.insert(kid.id) } else { kidIDs.remove(kid.id) }
                            }
                        ))
                    }
                }
            }
            .navigationTitle(isNew ? "New Chore" : "Edit Chore")
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
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || kidIDs.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    private func load() {
        switch target {
        case .new:
            if choreStore.kids.count == 1, let only = choreStore.kids.first {
                kidIDs = [only.id]
            }
        case .existing(let chore):
            title = chore.title
            points = chore.points
            frequency = chore.frequency
            kidIDs = Set(chore.kidIDs)
        }
    }

    private func save() {
        let orderedKidIDs = choreStore.kids.map(\.id).filter { kidIDs.contains($0) }
        switch target {
        case .new:
            choreStore.addChore(title: title, points: points, frequency: frequency, kidIDs: orderedKidIDs)
        case .existing(let chore):
            choreStore.updateChore(chore, title: title, points: points, frequency: frequency, kidIDs: orderedKidIDs)
        }
    }
}

private struct KidNameEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var choreStore: ChoreStore
    let kid: KidProfile?
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
            }
            .navigationTitle(kid == nil ? "Add Kid" : "Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let kid {
                            choreStore.renameKid(kid, to: name)
                        } else {
                            choreStore.addKid(named: name)
                        }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { name = kid?.name ?? "" }
        }
        .presentationDetents([.medium])
    }
}

/// A kid's running total, paying out, and history.
private struct KidDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var choreStore: ChoreStore
    let kidID: UUID
    @State private var isPayingOut = false
    @State private var isRenaming = false
    @State private var isConfirmingDelete = false

    var body: some View {
        NavigationStack {
            if let kid {
                List {
                    Section {
                        let balance = choreStore.balance(for: kid)
                        VStack(spacing: 4) {
                            Text("\(balance) points")
                                .font(.largeTitle.weight(.bold))
                                .foregroundStyle(AppTheme.primary)
                            Text("Worth \(ChoreMath.formattedMoney(for: balance, settings: choreStore.settings))")
                                .foregroundStyle(.secondary)
                            Button("Pay Out") { isPayingOut = true }
                                .buttonStyle(.borderedProminent)
                                .disabled(balance <= 0)
                                .padding(.top, 6)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }

                    Section("History") {
                        if history(for: kid).isEmpty {
                            Text("Approved chores and payouts will show here.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(history(for: kid)) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title)
                                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(entry.points > 0 ? "+\(entry.points)" : "\(entry.points)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(entry.points > 0 ? AppTheme.success : .secondary)
                            }
                        }
                    }

                    Section {
                        Button("Rename") { isRenaming = true }
                        Button("Remove \(kid.name)", role: .destructive) { isConfirmingDelete = true }
                    }
                }
                .navigationTitle(kid.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .sheet(isPresented: $isPayingOut) {
                    PayOutView(kid: kid, balance: choreStore.balance(for: kid))
                }
                .sheet(isPresented: $isRenaming) {
                    KidNameEditor(kid: kid)
                }
                .confirmationDialog("Remove \(kid.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                    Button("Remove", role: .destructive) {
                        choreStore.deleteKid(kid)
                        dismiss()
                    }
                } message: {
                    Text("Their points and history are removed for the whole family.")
                }
            }
        }
    }

    private var kid: KidProfile? {
        choreStore.kids.first { $0.id == kidID }
    }

    private struct HistoryEntry: Identifiable {
        let id: UUID
        let title: String
        let date: Date
        let points: Int
    }

    private func history(for kid: KidProfile) -> [HistoryEntry] {
        let earned = choreStore.completions
            .filter { $0.kidID == kid.id && $0.status == .approved }
            .map { HistoryEntry(id: $0.id, title: $0.choreTitle, date: $0.completedAt, points: $0.points) }
        let paid = choreStore.payouts
            .filter { $0.kidID == kid.id }
            .map { HistoryEntry(id: $0.id, title: "Paid out", date: $0.paidAt, points: -$0.points) }
        return (earned + paid).sorted { $0.date > $1.date }.prefix(100).map { $0 }
    }
}

private struct PayOutView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var choreStore: ChoreStore
    let kid: KidProfile
    let balance: Int
    @State private var points = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("\(points) points", value: $points, in: 1...max(balance, 1))
                    Text("Worth \(ChoreMath.formattedMoney(for: points, settings: choreStore.settings))")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("\(kid.name) has \(balance) points. Paying out takes them off the running total.")
                }
            }
            .navigationTitle("Pay Out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pay") {
                        choreStore.payOut(points, to: kid)
                        dismiss()
                    }
                    .disabled(points <= 0 || points > balance)
                }
            }
            .onAppear { points = balance }
        }
        .presentationDetents([.medium])
    }
}

private struct ChoreSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var choreStore: ChoreStore
    @State private var pointsPerUnit = 10

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("\(pointsPerUnit) points", value: $pointsPerUnit, in: 1...1_000)
                } header: {
                    Text("Points per \(ChoreMath.formattedMoney(for: 1, settings: ChoreSettings(pointsPerCurrencyUnit: 1)))")
                } footer: {
                    Text("\(pointsPerUnit * 10) points = \(ChoreMath.formattedMoney(for: pointsPerUnit * 10, settings: ChoreSettings(pointsPerCurrencyUnit: pointsPerUnit))). Applies to the whole family.")
                }
            }
            .navigationTitle("Points Value")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        choreStore.setPointsPerCurrencyUnit(pointsPerUnit)
                        dismiss()
                    }
                }
            }
            .onAppear { pointsPerUnit = choreStore.settings.pointsPerCurrencyUnit }
        }
        .presentationDetents([.medium])
    }
}
