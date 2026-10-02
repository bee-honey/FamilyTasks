import SwiftUI

/// Fills the week's empty slots from the saved meals, then lets the family review and
/// change each suggestion before it goes on the plan.
struct GenerateMealPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var organizerStore: OrganizerStore
    /// The days to fill: the rest of the week shown.
    let days: [Date]
    /// Called after adding, with whether to go on to Shop for This Week.
    let onAdded: (_ shopNext: Bool) -> Void

    @State private var slots: Set<MealSlot> = [.breakfast, .dinner]
    @State private var proposals: [MealPlanGenerator.Proposal]?
    @State private var shopNext = true
    @State private var addingCategory: MealCategory?
    @State private var editingMeal: MealIdea?
    @State private var choosingFor: MealPlanGenerator.Proposal?
    @State private var skipQuestion: MealIdea?
    @State private var askedAbout: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List {
                if let proposals {
                    reviewSections(proposals)
                } else {
                    optionsSections
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle(proposals == nil ? "Generate Meal Plan" : "Your Week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if let proposals {
                        Button("Add to Plan") { add(proposals) }
                            .fontWeight(.semibold)
                            .disabled(!proposals.contains { $0.mealID != nil })
                    } else {
                        Button("Generate") { generate() }
                            .fontWeight(.semibold)
                            .disabled(slots.isEmpty || !shortfalls.isEmpty || emptySlotCount == 0)
                    }
                }
            }
            .sheet(item: $addingCategory) { category in
                MealEditorView(initialCategory: category)
            }
            .sheet(item: $editingMeal) { meal in
                MealEditorView(meal: meal)
            }
            .sheet(item: $choosingFor) { proposal in
                ChooseMealView(category: MealPlanGenerator.category(for: proposal.slot)) { mealID in
                    replace(proposal, with: mealID)
                }
            }
            .alert(
                "Stop suggesting \(skipQuestion?.name ?? "this meal")?",
                isPresented: Binding(get: { skipQuestion != nil }, set: { if !$0 { skipQuestion = nil } }),
                presenting: skipQuestion
            ) { meal in
                Button("Stop Suggesting") {
                    organizerStore.setSkipInGeneratedPlans(true, for: meal.id)
                }
                Button("Keep Suggesting", role: .cancel) {}
            } message: { _ in
                Text("Leave it out of generated plans, for example when it's out of season. You can change this when editing the meal.")
            }
        }
    }

    // MARK: Choosing what to fill

    private var orderedSlots: [MealSlot] {
        MealSlot.allCases.filter { slots.contains($0) }
    }

    private var emptySlotCount: Int {
        MealPlanGenerator.emptySlots(days: days, slots: orderedSlots, planned: organizerStore.plannedMeals).count
    }

    private var shortfalls: [MealPlanGenerator.Shortfall] {
        MealPlanGenerator.shortfalls(days: days, slots: orderedSlots, meals: organizerStore.mealIdeas, planned: organizerStore.plannedMeals)
    }

    @ViewBuilder
    private var optionsSections: some View {
        Section {
            ForEach(MealSlot.allCases) { slot in
                Toggle(isOn: Binding(
                    get: { slots.contains(slot) },
                    set: { isOn in
                        if isOn { slots.insert(slot) } else { slots.remove(slot) }
                    }
                )) {
                    Label(slot.title, systemImage: slot.systemImage)
                        .labelStyle(.tile(AppTheme.primary))
                }
            }
        } header: {
            Text("Fill")
        } footer: {
            Text(emptySlotCount == 0
                 ? "Every one of these meals is already planned."
                 : "Fills \(emptySlotCount) empty \(emptySlotCount == 1 ? "slot" : "slots") from \(days.first.map(dayTitle) ?? "") on. Meals you've planned stay.")
        }
        .listRowBackground(AppTheme.surface)

        ForEach(shortfalls, id: \.category) { shortfall in
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Not enough \(shortfall.category.title.lowercased()) meals", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(AppTheme.goldAccent)
                    Text(shortfallText(shortfall))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                Button {
                    addingCategory = shortfall.category
                } label: {
                    Label("Add \(shortfall.category.title) Meal", systemImage: "plus")
                }
            }
            .listRowBackground(AppTheme.surface)
        }
    }

    private func shortfallText(_ shortfall: MealPlanGenerator.Shortfall) -> String {
        let type = shortfall.category.title.lowercased()
        let saved = MealPlanGenerator.eligibleMeals(organizerStore.mealIdeas, for: shortfall.category).count
        let have = saved == 1 ? "1 \(type) meal" : "\(saved) \(type) meals"
        return "You have \(have), enough for \(shortfall.canFill) of the \(shortfall.needed) slots. Add at least 7 so the week can rotate, or let some repeat: edit a meal and raise Times a Week."
    }

    private func generate() {
        withAnimation {
            proposals = MealPlanGenerator.generate(days: days, slots: orderedSlots, meals: organizerStore.mealIdeas, planned: organizerStore.plannedMeals)
        }
    }

    // MARK: Reviewing

    @ViewBuilder
    private func reviewSections(_ proposals: [MealPlanGenerator.Proposal]) -> some View {
        Section {
            Button {
                generate()
            } label: {
                Label("Shuffle All", systemImage: "shuffle")
            }
            Button {
                withAnimation { self.proposals = nil }
            } label: {
                Label("Change What to Fill", systemImage: "slider.horizontal.3")
            }
        }
        .listRowBackground(AppTheme.surface)

        ForEach(days, id: \.self) { day in
            let rows = proposals
                .filter { Calendar.current.isDate($0.day, inSameDayAs: day) }
                .sorted { MealSlot.allCases.firstIndex(of: $0.slot)! < MealSlot.allCases.firstIndex(of: $1.slot)! }
            if !rows.isEmpty {
                Section(dayTitle(day)) {
                    ForEach(rows) { proposal in
                        proposalRow(proposal)
                    }
                }
                .listRowBackground(AppTheme.surface)
            }
        }

        let missing = mealsMissingIngredients(proposals)
        if !missing.isEmpty {
            Section {
                ForEach(missing) { meal in
                    HStack {
                        Text(meal.name)
                        Spacer()
                        Button("Add Ingredients") { editingMeal = meal }
                            .font(.subheadline.weight(.semibold))
                    }
                }
            } header: {
                Text("No ingredients yet")
            } footer: {
                Text("These meals have no ingredients, so they can't go on the shopping list.")
            }
            .listRowBackground(AppTheme.surface)
        }

        Section {
            Toggle(isOn: $shopNext) {
                Label("Then Shop for This Week", systemImage: "cart.badge.plus")
                    .labelStyle(.tile(AppTheme.coolAccent))
            }
        } footer: {
            Text("Gathers the ingredients of every meal this week, grouped by shop, to add to the shopping list.")
        }
        .listRowBackground(AppTheme.surface)
    }

    private func proposalRow(_ proposal: MealPlanGenerator.Proposal) -> some View {
        let meal = proposal.mealID.flatMap { id in organizerStore.mealIdeas.first { $0.id == id } }
        return HStack(spacing: 12) {
            IconTile(systemImage: proposal.slot.systemImage, tint: AppTheme.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(proposal.slot.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(meal?.name ?? "Left empty")
                    .font(.body.weight(meal == nil ? .regular : .semibold))
                    .foregroundStyle(meal == nil ? .secondary : .primary)
                if let meal, meal.ingredients.isEmpty {
                    Label("No ingredients", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.goldAccent)
                }
            }
            Spacer(minLength: 8)
            Menu {
                Button("Suggest Another", systemImage: "shuffle") { suggestAnother(for: proposal) }
                Button("Choose Meal…", systemImage: "list.bullet") { choosingFor = proposal }
                if proposal.mealID != nil {
                    Button("Leave Empty", systemImage: "xmark", role: .destructive) { replace(proposal, with: nil) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Change \(proposal.slot.title.lowercased())")
        }
    }

    private func suggestAnother(for proposal: MealPlanGenerator.Proposal) {
        guard let current = proposals else { return }
        var random = SystemRandomNumberGenerator()
        let next = MealPlanGenerator.alternative(
            for: proposal,
            in: current,
            meals: organizerStore.mealIdeas,
            planned: organizerStore.plannedMeals,
            days: days,
            using: &random
        )
        replace(proposal, with: next)
    }

    /// Swaps a suggestion; the first time a meal is replaced, asks whether to stop suggesting it.
    private func replace(_ proposal: MealPlanGenerator.Proposal, with mealID: UUID?) {
        guard var current = proposals, let index = current.firstIndex(where: { $0.id == proposal.id }) else { return }
        let replaced = current[index].mealID
        current[index].mealID = mealID
        proposals = current

        if let replaced, replaced != mealID, !askedAbout.contains(replaced),
           let meal = organizerStore.mealIdeas.first(where: { $0.id == replaced }), !meal.skipInGeneratedPlans {
            askedAbout.insert(replaced)
            skipQuestion = meal
        }
    }

    private func mealsMissingIngredients(_ proposals: [MealPlanGenerator.Proposal]) -> [MealIdea] {
        let ids = Set(proposals.compactMap(\.mealID))
        return organizerStore.mealIdeas.filter { ids.contains($0.id) && $0.ingredients.isEmpty }
    }

    private func add(_ proposals: [MealPlanGenerator.Proposal]) {
        organizerStore.planMeals(proposals.compactMap { proposal in
            proposal.mealID.map { ($0, proposal.day.addingTimeInterval(12 * 3_600), proposal.slot) }
        })
        onAdded(shopNext)
        dismiss()
    }

    private func dayTitle(_ day: Date) -> String {
        Calendar.current.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

/// Every meal of one type, to pick for a slot.
private struct ChooseMealView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var organizerStore: OrganizerStore
    let category: MealCategory
    let onChoose: (UUID) -> Void

    var body: some View {
        NavigationStack {
            List(organizerStore.mealIdeas.filter { $0.category == category }) { meal in
                Button {
                    onChoose(meal.id)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meal.name)
                            .foregroundStyle(AppTheme.ink)
                        if meal.skipInGeneratedPlans {
                            Text("Not suggested in generated plans")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listRowBackground(AppTheme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle(category.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
