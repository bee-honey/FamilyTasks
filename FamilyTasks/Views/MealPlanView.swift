import SwiftUI

struct MealPlanView: View {
    @EnvironmentObject private var organizerStore: OrganizerStore
    @State private var selectedTab: MealPlanTab = .plan
    @State private var selectedRange: MealPlanRange = .week
    @State private var selectedDay = Date()
    @State private var isAddingMeal = false
    @State private var planningMeal: MealIdea?
    @State private var editingMeal: MealIdea?
    @State private var planningDate = Date()
    @State private var planningSlot: MealSlot = .dinner

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Meal plan section", selection: $selectedTab) {
                    ForEach(MealPlanTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 12)

                if selectedTab == .plan {
                    Picker("Range", selection: $selectedRange) {
                        ForEach(MealPlanRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                }

                ScrollView {
                    if selectedTab == .plan {
                        planContent
                    } else {
                        mealsContent
                    }
                }
            }
            .background(AppTheme.background)
            .navigationTitle("Meal Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAddingMeal = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add meal")
                }
            }
            .sheet(isPresented: $isAddingMeal) {
                MealEditorView()
            }
            .sheet(item: $editingMeal) { meal in
                MealEditorView(meal: meal)
            }
            .sheet(item: $planningMeal) { meal in
                PlanMealView(meal: meal, initialDate: planningDate, initialSlot: planningSlot)
            }
        }
    }

    private var planContent: some View {
        LazyVStack(spacing: 12) {
            if organizerStore.mealIdeas.isEmpty {
                ContentUnavailableView("No Meals Yet", systemImage: "fork.knife", description: Text("Add meals in the Meals tab, then plan them for breakfast, lunch, or dinner."))
                    .padding(.top, 80)
            } else {
                dayPicker

                ForEach(daysToShow, id: \.self) { day in
                    DayMealSection(day: day, meals: plannedMeals(on: day)) { slot in
                        planningDate = day
                        planningSlot = slot
                        selectedDay = day
                        selectedTab = .meals
                    } onDelete: { plannedMeal in
                        organizerStore.deletePlannedMeal(plannedMeal)
                    }
                }
            }
        }
        .padding(14)
    }

    private var mealsContent: some View {
        LazyVStack(spacing: 12) {
            if organizerStore.mealIdeas.isEmpty {
                ContentUnavailableView("No Saved Meals", systemImage: "fork.knife.circle", description: Text("Add meals once and reuse them while planning the week."))
                    .padding(.top, 80)
            } else {
                ForEach(organizerStore.mealIdeas) { meal in
                    MealIdeaCard(meal: meal) {
                        planningDate = selectedTab == .meals ? planningDate : selectedDay
                        planningMeal = meal
                    } onEdit: {
                        editingMeal = meal
                    } onDelete: {
                        organizerStore.deleteMealIdea(meal)
                    }
                }
            }
        }
        .padding(14)
    }

    private var dayPicker: some View {
        HStack(spacing: 10) {
            Button {
                selectedDay = Calendar.current.date(byAdding: .day, value: -dayStep, to: selectedDay) ?? selectedDay
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            VStack(spacing: 2) {
                Text(selectedRange == .day ? selectedDay.formatted(date: .complete, time: .omitted) : weekTitle)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(selectedRange.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Button {
                selectedDay = Calendar.current.date(byAdding: .day, value: dayStep, to: selectedDay) ?? selectedDay
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private var dayStep: Int {
        selectedRange == .day ? 1 : 7
    }

    private var daysToShow: [Date] {
        if selectedRange == .day {
            return [Calendar.current.startOfDay(for: selectedDay)]
        }

        let interval = Calendar.current.dateInterval(of: .weekOfYear, for: selectedDay)
        let start = interval?.start ?? Calendar.current.startOfDay(for: selectedDay)
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }

    private var weekTitle: String {
        guard let first = daysToShow.first, let last = daysToShow.last else { return "" }
        return "\(first.formatted(.dateTime.month(.abbreviated).day())) - \(last.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func plannedMeals(on day: Date) -> [PlannedMeal] {
        organizerStore.plannedMeals
            .filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
            .sorted { lhs, rhs in
                guard lhs.slot != rhs.slot else { return lhs.date < rhs.date }
                return MealSlot.allCases.firstIndex(of: lhs.slot) ?? 0 < MealSlot.allCases.firstIndex(of: rhs.slot) ?? 0
            }
    }
}

private enum MealPlanTab: String, CaseIterable, Identifiable {
    case plan
    case meals

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plan: "Plan"
        case .meals: "Meals"
        }
    }
}

private enum MealPlanRange: String, CaseIterable, Identifiable {
    case day
    case week

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        }
    }
}

private struct DayMealSection: View {
    @EnvironmentObject private var organizerStore: OrganizerStore
    let day: Date
    let meals: [PlannedMeal]
    let onPlanSlot: (MealSlot) -> Void
    let onDelete: (PlannedMeal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(day.formatted(date: .complete, time: .omitted))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 8) {
                ForEach(MealSlot.allCases) { slot in
                    MealSlotRow(slot: slot, plannedMeals: meals.filter { $0.slot == slot }, onPlan: { onPlanSlot(slot) }, onDelete: onDelete)
                }
            }
        }
        .padding(12)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct MealSlotRow: View {
    @EnvironmentObject private var organizerStore: OrganizerStore
    let slot: MealSlot
    let plannedMeals: [PlannedMeal]
    let onPlan: () -> Void
    let onDelete: (PlannedMeal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(slot.title, systemImage: slot.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.primary)

            if plannedMeals.isEmpty {
                Button(action: onPlan) {
                    Text("Not planned")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(AppTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            } else {
                ForEach(plannedMeals) { plannedMeal in
                    if let meal = organizerStore.mealIdea(for: plannedMeal) {
                        HStack(spacing: 10) {
                            Text(meal.name)
                                .font(.footnote)
                                .lineLimit(2)
                            Spacer()
                            Button(role: .destructive) {
                                onDelete(plannedMeal)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(AppTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }
}

private struct MealIdeaCard: View {
    let meal: MealIdea
    let onPlan: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "fork.knife.circle")
                    .font(.title2)
                    .foregroundStyle(AppTheme.primary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(meal.name)
                        .font(.footnote.weight(.semibold))
                    Text("\(meal.ingredients.count) ingredients")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    Button(action: onPlan) {
                        Label("Add to Plan", systemImage: "calendar.badge.plus")
                    }
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }

            if !meal.ingredients.isEmpty {
                Text(meal.ingredients.map(\.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlan)
        .onTapGesture(count: 2, perform: onEdit)
    }
}

private struct MealEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var organizerStore: OrganizerStore
    let meal: MealIdea?
    @State private var name: String
    @State private var notes: String
    @State private var ingredients: [MealIngredient]

    init(meal: MealIdea? = nil) {
        self.meal = meal
        _name = State(initialValue: meal?.name ?? "")
        _notes = State(initialValue: meal?.notes ?? "")
        let existing = meal?.ingredients ?? []
        _ingredients = State(initialValue: existing.isEmpty ? [MealIngredient(name: "")] : existing)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") {
                    TextField("Name", text: $name)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Ingredients") {
                    ForEach($ingredients) { $ingredient in
                        IngredientEditorRow(ingredient: $ingredient)
                    }
                    .onDelete { offsets in
                        ingredients.remove(atOffsets: offsets)
                    }

                    Button {
                        ingredients.append(MealIngredient(name: ""))
                    } label: {
                        Label("Add Ingredient", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle(meal == nil ? "New Meal" : "Edit Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let meal {
                            organizerStore.updateMealIdea(meal, name: name, ingredients: ingredients, notes: notes)
                        } else {
                            organizerStore.addMealIdea(name: name, ingredients: ingredients, notes: notes)
                        }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct IngredientEditorRow: View {
    @EnvironmentObject private var organizerStore: OrganizerStore
    @Binding var ingredient: MealIngredient

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Ingredient", text: $ingredient.name)

            Picker("Default Shop", selection: $ingredient.defaultShopID) {
                Text("Choose later").tag(Optional<UUID>.none)
                ForEach(organizerStore.shops) { shop in
                    Text(shop.name).tag(Optional(shop.id))
                }
            }
            .font(.caption)
        }
    }
}

private struct PlanMealView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var organizerStore: OrganizerStore
    let meal: MealIdea
    let initialDate: Date
    let initialSlot: MealSlot
    @State private var date: Date
    @State private var slot: MealSlot
    @State private var addIngredientsToShopping = true
    @State private var useOneShop = true
    @State private var selectedShopID: UUID?
    @State private var selectedIngredientIDs: Set<UUID> = []
    @State private var ingredientShopIDs: [UUID: UUID] = [:]

    init(meal: MealIdea, initialDate: Date, initialSlot: MealSlot = .dinner) {
        self.meal = meal
        self.initialDate = initialDate
        self.initialSlot = initialSlot
        _date = State(initialValue: initialDate)
        _slot = State(initialValue: initialSlot)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") {
                    Text(meal.name)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Slot", selection: $slot) {
                        ForEach(MealSlot.allCases) { slot in
                            Text(slot.title).tag(slot)
                        }
                    }
                }

                Section("Groceries") {
                    Toggle("Add ingredients to shopping", isOn: $addIngredientsToShopping)

                    if addIngredientsToShopping {
                        Toggle("Use one shop for all", isOn: $useOneShop)

                        if useOneShop {
                            Picker("Shop", selection: $selectedShopID) {
                                Text("Choose shop").tag(Optional<UUID>.none)
                                ForEach(organizerStore.shops) { shop in
                                    Text(shop.name).tag(Optional(shop.id))
                                }
                            }

                            ForEach(meal.ingredients) { ingredient in
                                Toggle(ingredient.name, isOn: ingredientSelectionBinding(for: ingredient))
                            }
                        } else {
                            ForEach(meal.ingredients) { ingredient in
                                VStack(alignment: .leading, spacing: 8) {
                                    Toggle(ingredient.name, isOn: ingredientSelectionBinding(for: ingredient))

                                    if selectedIngredientIDs.contains(ingredient.id) {
                                        Picker("Shop", selection: ingredientShopBinding(for: ingredient)) {
                                            Text("Choose shop").tag(Optional<UUID>.none)
                                            ForEach(organizerStore.shops) { shop in
                                                Text(shop.name).tag(Optional(shop.id))
                                            }
                                        }
                                        .font(.caption)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to Plan")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                selectedShopID = selectedShopID ?? firstDefaultShopID
                for ingredient in meal.ingredients {
                    selectedIngredientIDs.insert(ingredient.id)
                    ingredientShopIDs[ingredient.id] = ingredient.defaultShopID
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        organizerStore.planMeal(
                            meal,
                            on: date,
                            slot: slot,
                            ingredientShopOverrides: groceryAssignments,
                            addIngredientsToShopping: addIngredientsToShopping
                        )
                        dismiss()
                    }
                    .disabled(addIngredientsToShopping && !meal.ingredients.isEmpty && groceryAssignments.isEmpty)
                }
            }
        }
    }

    private var firstDefaultShopID: UUID? {
        meal.ingredients.compactMap(\.defaultShopID).first ?? organizerStore.shops.first?.id
    }

    private var groceryAssignments: [UUID: UUID] {
        if !addIngredientsToShopping {
            return [:]
        }

        if useOneShop {
            guard let selectedShopID else { return [:] }
            return Dictionary(uniqueKeysWithValues: meal.ingredients
                .filter { selectedIngredientIDs.contains($0.id) }
                .map { ($0.id, selectedShopID) })
        }

        return ingredientShopIDs.filter { _, shopID in
            organizerStore.shops.contains { $0.id == shopID }
        }
        .filter { ingredientID, _ in
            selectedIngredientIDs.contains(ingredientID)
        }
    }

    private func ingredientSelectionBinding(for ingredient: MealIngredient) -> Binding<Bool> {
        Binding(
            get: { selectedIngredientIDs.contains(ingredient.id) },
            set: { isSelected in
                if isSelected {
                    selectedIngredientIDs.insert(ingredient.id)
                    ingredientShopIDs[ingredient.id] = ingredientShopIDs[ingredient.id] ?? ingredient.defaultShopID ?? selectedShopID ?? organizerStore.shops.first?.id
                } else {
                    selectedIngredientIDs.remove(ingredient.id)
                }
            }
        )
    }

    private func ingredientShopBinding(for ingredient: MealIngredient) -> Binding<UUID?> {
        Binding(
            get: { ingredientShopIDs[ingredient.id] ?? ingredient.defaultShopID },
            set: { newValue in
                if let newValue {
                    ingredientShopIDs[ingredient.id] = newValue
                } else {
                    ingredientShopIDs.removeValue(forKey: ingredient.id)
                }
            }
        )
    }
}
