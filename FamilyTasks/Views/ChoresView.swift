import SwiftUI

struct ChoresView: View {
    @EnvironmentObject private var choreStore: ChoreStore
    var isPushed = false
    @State private var editingChore: ChoreEditorTarget?
    @State private var isAddingKid = false
    @State private var isEditingSettings = false

    var body: some View {
        // Shown inside a tab's NavigationStack, or pushed from Family.
        List {
            Section {
                ScreenHeader(eyebrow: summary, title: "Chores", showsProfile: !isPushed) {
                    Menu {
                        Button("Add Chore", systemImage: "star") { editingChore = .new }
                            .disabled(choreStore.kids.isEmpty)
                        Button("Add Kid", systemImage: "person.badge.plus") { isAddingKid = true }
                    } label: {
                        HeaderAddLabel()
                    }
                    .accessibilityLabel("Add chore or kid")
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 4))
            .listRowBackground(Color.clear)

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

            Section {
                Button {
                    isEditingSettings = true
                } label: {
                    HStack(spacing: 14) {
                        IconTile(systemImage: "dollarsign.circle", tint: AppTheme.success, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Points & Money")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                            Text("\(choreStore.settings.pointsPerCurrencyUnit * 10) points = \(ChoreMath.formattedMoney(for: choreStore.settings.pointsPerCurrencyUnit * 10, settings: choreStore.settings))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("Change")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.primary)
                    }
                }
                .listRowBackground(AppTheme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .mainScreenNavigationBar(title: "Chores", isPushed: isPushed)
        .sheet(item: $editingChore) { target in
            ChoreEditorView(target: target)
        }
        .sheet(isPresented: $isAddingKid) {
            KidNameEditor(kid: nil)
        }
        .sheet(isPresented: $isEditingSettings) {
            ChoreSettingsView()
        }
    }

    private var summary: String {
        let waiting = choreStore.waitingForApproval.count
        if waiting > 0 { return "\(waiting) to approve" }
        let kids = choreStore.kids.count
        return kids == 1 ? "1 kid" : "\(kids) kids"
    }

    private var balancesSection: some View {
        Section {
            ForEach(choreStore.kids) { kid in
                NavigationLink {
                    KidDetailView(kidID: kid.id)
                } label: {
                    HStack(spacing: 12) {
                        AssigneeAvatarView(name: kid.name, size: 36, showsPhoto: false)
                        Text(kid.name)
                            .font(.body.weight(.semibold))
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
                    }
                }
                .listRowBackground(AppTheme.surface)
            }
        } header: {
            SectionTitle(text: "Points")
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
                        Button("Not Yet") {
                            choreStore.reject(completion)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Button("Approve") {
                            choreStore.approve(completion)
                            ToastCenter.shared.show("+\(completion.points) points for \(kidName(completion.kidID))", systemImage: "star.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.success)
                        .controlSize(.small)
                    }
                    .listRowBackground(AppTheme.surface)
                }
            } header: {
                SectionTitle(text: "Waiting for Approval")
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
                Section {
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
                } header: {
                    SectionTitle(text: "\(kid.name) to Do")
                }
            }
        }
    }

    @ViewBuilder
    private var allChoresSection: some View {
        Section {
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
        } header: {
            SectionTitle(text: "All Chores")
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
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    TextField("What's the chore?", text: $title, axis: .vertical)
                        .font(.title2.weight(.bold))
                        .textInputAutocapitalization(.sentences)
                        .focused($isTitleFocused)

                    EditorSection("For") {
                        WrappingStack(spacing: 8) {
                            ForEach(choreStore.kids) { kid in
                                ChoiceChip(title: kid.name, isSelected: kidIDs.contains(kid.id)) {
                                    if kidIDs.contains(kid.id) { kidIDs.remove(kid.id) } else { kidIDs.insert(kid.id) }
                                }
                            }
                        }
                    }

                    EditorSection("Points") {
                        Stepper(value: $points, in: 1...100) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(points) points")
                                    .font(.body.weight(.semibold))
                                Text("Worth \(ChoreMath.formattedMoney(for: points, settings: choreStore.settings))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    EditorSection("Repeats") {
                        WrappingStack(spacing: 8) {
                            ForEach([RecurrenceFrequency.daily, .weekly, .monthly]) { choice in
                                ChoiceChip(title: choice.title, isSelected: frequency == choice) {
                                    frequency = choice
                                }
                            }
                        }
                    }

                    if case .existing(let chore) = target {
                        EditorDeleteButton(title: "Delete Chore", message: "Points already approved stay with each kid.") {
                            choreStore.deleteChore(chore)
                            dismiss()
                        }
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.background)
            .navigationTitle(isNew ? "New Chore" : "Edit Chore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") {
                        save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || kidIDs.isEmpty)
                }
            }
            .onAppear {
                load()
                if isNew { isTitleFocused = true }
            }
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
        // Pushed from Chores.
        Group {
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
                .scrollContentBackground(.hidden)
                .background(AppTheme.background)
                .navigationTitle(kid.name)
                .navigationBarTitleDisplayMode(.inline)
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
    /// nil means each phone's own currency.
    @State private var currencyCode: String?
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        CurrencyPickerView(selection: $currencyCode)
                    } label: {
                        LabeledContent("Currency", value: CurrencyPickerView.name(for: currencyCode))
                    }
                } footer: {
                    Text("Applies to the whole family.")
                }

                Section {
                    Stepper("\(pointsPerUnit) points", value: $pointsPerUnit, in: 1...1_000)
                } header: {
                    Text("Points per \(ChoreMath.formattedMoney(for: 1, settings: draft(pointsPerUnit: 1)))")
                } footer: {
                    Text("\(pointsPerUnit * 10) points = \(ChoreMath.formattedMoney(for: pointsPerUnit * 10, settings: draft(pointsPerUnit: pointsPerUnit)))")
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
                        choreStore.updateSettings(pointsPerCurrencyUnit: pointsPerUnit, currencyCode: currencyCode)
                        dismiss()
                    }
                }
            }
            .onAppear {
                // onAppear runs again when returning from the currency list; loading the
                // saved values then would throw away the currency just picked.
                guard !hasLoaded else { return }
                hasLoaded = true
                pointsPerUnit = choreStore.settings.pointsPerCurrencyUnit
                currencyCode = choreStore.settings.currencyCode
            }
        }
    }

    private func draft(pointsPerUnit: Int) -> ChoreSettings {
        ChoreSettings(pointsPerCurrencyUnit: pointsPerUnit, currencyCode: currencyCode)
    }
}

/// Every currency the phone knows, searchable by name or code.
private struct CurrencyPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String?
    @State private var searchText = ""

    var body: some View {
        List {
            if searchText.isEmpty {
                Section {
                    row(code: nil)
                }
            }
            Section {
                ForEach(filteredCodes, id: \.self) { code in
                    row(code: code)
                }
            }
        }
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search currencies")
    }

    private func row(code: String?) -> some View {
        Button {
            selection = code
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.name(for: code))
                        .foregroundStyle(.primary)
                    Text(code ?? "Uses \(Self.phoneCurrencyCode) on each phone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selection == code {
                    Image(systemName: "checkmark")
                        .foregroundStyle(AppTheme.primary)
                }
            }
        }
    }

    private var filteredCodes: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Self.allCodes }
        return Self.allCodes.filter { code in
            code.localizedCaseInsensitiveContains(query) || Self.name(for: code).localizedCaseInsensitiveContains(query)
        }
    }

    private static var phoneCurrencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    /// The phone's currency first, then the rest by name.
    private static let allCodes: [String] = {
        let others = Locale.commonISOCurrencyCodes
            .filter { $0 != phoneCurrencyCode }
            .sorted { name(for: $0).localizedCaseInsensitiveCompare(name(for: $1)) == .orderedAscending }
        return [phoneCurrencyCode] + others
    }()

    static func name(for code: String?) -> String {
        guard let code else { return "Phone's Currency" }
        let name = Locale.current.localizedString(forCurrencyCode: code) ?? code
        return "\(name) (\(code))"
    }
}
