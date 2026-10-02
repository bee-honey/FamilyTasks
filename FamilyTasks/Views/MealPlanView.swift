import SwiftUI

struct MealPlanView: View {
    @EnvironmentObject private var organizerStore: OrganizerStore
    @State private var selectedTab: MealPlanTab = .plan
    @State private var selectedMealCategory: MealCategory = .breakfast
    @State private var mealSearchText = ""
    @State private var selectedDay = Date()
    @State private var isAddingMeal = false
    @State private var planningMeal: MealIdea?
    @State private var editingMeal: MealIdea?
    @State private var planningDate = Date()
    @State private var planningSlot: MealSlot = .dinner
    @State private var isShoppingForWeek = false

    var body: some View {
        // Shown inside a tab's NavigationStack.
        Group {
            VStack(spacing: 0) {
                if selectedTab == .meals {
                    Picker("Meal type", selection: $selectedMealCategory) {
                        ForEach(MealCategory.allCases) { category in
                            Text(category.title).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search meals", text: $mealSearchText)
                            .textInputAutocapitalization(.words)
                    }
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 12))
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
            .navigationTitle(selectedTab == .plan ? "Meal Plan" : "Meals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selectedTab == .plan {
                    ToolbarItem(placement: .topBarTrailing) {
                        let toBuy = weekIngredientsToBuy
                        Button {
                            isShoppingForWeek = true
                        } label: {
                            Image(systemName: "cart")
                                .overlay(alignment: .topTrailing) {
                                    if toBuy > 0 {
                                        Text("\(toBuy)")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.black)
                                            .padding(.horizontal, 4)
                                            .frame(minWidth: 16, minHeight: 16)
                                            .background(AppTheme.warning, in: Capsule())
                                            .offset(x: 10, y: -8)
                                    }
                                }
                        }
                        .accessibilityLabel(toBuy > 0 ? "\(shopForWeekTitle), \(toBuy) to buy" : shopForWeekTitle)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        selectedTab = selectedTab == .plan ? .meals : .plan
                    } label: {
                        Label(selectedTab == .plan ? "Meals" : "Plan", systemImage: selectedTab == .plan ? "book" : "calendar")
                            .labelStyle(.titleAndIcon)
                    }
                }
                if selectedTab == .meals {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isAddingMeal = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add meal")
                    }
                }
            }
            .sheet(isPresented: $isAddingMeal) {
                MealEditorView(initialCategory: selectedMealCategory)
            }
            .sheet(item: $editingMeal) { meal in
                MealEditorView(meal: meal)
            }
            .sheet(item: $planningMeal) { meal in
                PlanMealView(meal: meal, initialDate: planningDate, initialSlot: planningSlot)
            }
            .sheet(isPresented: $isShoppingForWeek) {
                WeeklyShoppingView(title: shopForWeekTitle, range: shoppingRange)
            }
        }
    }

    private var planContent: some View {
        LazyVStack(spacing: 12) {
            if organizerStore.mealIdeas.isEmpty {
                ContentUnavailableView("No Meals Yet", systemImage: "fork.knife", description: Text("Tap Meals to add the meals you make, then plan them for breakfast, lunch, or dinner."))
                    .padding(.top, 80)
            } else {
                weekHeader

                if daysToShow.contains(where: { Calendar.current.isDateInToday($0) }) {
                    TonightCard(dinners: plannedMeals(on: Date(), slot: .dinner)) {
                        planSlot(day: Date(), slot: .dinner)
                    }
                }

                WeeklyMealPlanGrid(days: daysToShow) { day, slot in
                    plannedMeals(on: day, slot: slot)
                } mealForPlannedMeal: { plannedMeal in
                    organizerStore.mealIdea(for: plannedMeal)
                } onPlanSlot: { day, slot in
                    planSlot(day: day, slot: slot)
                } onDelete: { plannedMeal in
                    organizerStore.deletePlannedMeal(plannedMeal)
                }
            }
        }
        .padding(14)
    }

    /// Opens the meal library on the right category, ready to plan `slot` on `day`.
    private func planSlot(day: Date, slot: MealSlot) {
        planningDate = day
        planningSlot = slot
        selectedMealCategory = mealCategory(for: slot)
        selectedDay = day
        selectedTab = .meals
    }

    /// "SEP 27 – OCT 3 / This week" with small arrows to change week.
    private var weekHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(weekTitle.uppercased())
                    .font(.footnote.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(AppTheme.primary)
                Text(weekRelativeTitle)
                    .font(.title2.weight(.bold))
            }
            Spacer()
            HStack(spacing: 6) {
                weekArrow("chevron.left", label: "Previous week", offset: -7)
                weekArrow("chevron.right", label: "Next week", offset: 7)
            }
        }
        .padding(.horizontal, 4)
    }

    private func weekArrow(_ systemImage: String, label: String, offset: Int) -> some View {
        Button {
            selectedDay = Calendar.current.date(byAdding: .day, value: offset, to: selectedDay) ?? selectedDay
        } label: {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(AppTheme.surface, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var weekRelativeTitle: String {
        let calendar = Calendar.current
        guard let shown = calendar.dateInterval(of: .weekOfYear, for: selectedDay)?.start,
              let current = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return "Week" }
        let weeks = calendar.dateComponents([.weekOfYear], from: current, to: shown).weekOfYear ?? 0
        switch weeks {
        case 0: return "This Week"
        case 1: return "Next Week"
        case -1: return "Last Week"
        default: return weeks > 0 ? "In \(weeks) Weeks" : "\(-weeks) Weeks Ago"
        }
    }

    /// Ingredients for the shown week that are not on the shopping list yet.
    private var weekIngredientsToBuy: Int {
        guard let range = shoppingRange else { return 0 }
        return organizerStore.weeklyIngredients(from: range.lowerBound, to: range.upperBound)
            .filter { !$0.isAlreadyNeeded }
            .count
    }

    private var mealsContent: some View {
        LazyVStack(spacing: 12) {
            if organizerStore.mealIdeas.isEmpty {
                ContentUnavailableView("No Saved Meals", systemImage: "fork.knife.circle", description: Text("Add meals once and reuse them while planning the week."))
                    .padding(.top, 80)
            } else if filteredMealIdeas.isEmpty {
                ContentUnavailableView("No Matches", systemImage: "magnifyingglass", description: Text("Try another search or add a \(selectedMealCategory.title.lowercased()) meal."))
                    .padding(.top, 80)
            } else {
                ForEach(filteredMealIdeas) { meal in
                    MealIdeaCard(meal: meal) {
                        planningDate = selectedTab == .meals ? planningDate : selectedDay
                        planningMeal = meal
                        selectedTab = .plan
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

    private var daysToShow: [Date] {
        let interval = Calendar.current.dateInterval(of: .weekOfYear, for: selectedDay)
        let start = interval?.start ?? Calendar.current.startOfDay(for: selectedDay)
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }

    private var shoppingRange: Range<Date>? {
        WeeklyIngredient.weekRange(containing: selectedDay)
    }

    private var shopForWeekTitle: String {
        guard let first = daysToShow.first, let last = daysToShow.last else { return "Shop for This Week" }
        let today = Date()
        if today >= first && today < (Calendar.current.date(byAdding: .day, value: 1, to: last) ?? last) {
            return "Shop for This Week"
        }
        return "Shop for Week of \(first.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var weekTitle: String {
        guard let first = daysToShow.first, let last = daysToShow.last else { return "" }
        return "\(first.formatted(.dateTime.month(.abbreviated).day())) - \(last.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func plannedMeals(on day: Date, slot: MealSlot) -> [PlannedMeal] {
        organizerStore.plannedMeals
            .filter { Calendar.current.isDate($0.date, inSameDayAs: day) && $0.slot == slot }
            .sorted { $0.date < $1.date }
    }

    private var filteredMealIdeas: [MealIdea] {
        let query = mealSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return organizerStore.mealIdeas
            .filter { $0.category == selectedMealCategory }
            .filter { meal in
                query.isEmpty
                || meal.name.localizedCaseInsensitiveContains(query)
                || meal.ingredients.contains { $0.name.localizedCaseInsensitiveContains(query) }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func mealCategory(for slot: MealSlot) -> MealCategory {
        switch slot {
        case .breakfast:
            return .breakfast
        case .lunch, .dinner:
            return .mainCourse
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

private struct WeeklyMealPlanGrid: View {
    let days: [Date]
    let plannedMeals: (Date, MealSlot) -> [PlannedMeal]
    let mealForPlannedMeal: (PlannedMeal) -> MealIdea?
    let onPlanSlot: (Date, MealSlot) -> Void
    let onDelete: (PlannedMeal) -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerRow

            ForEach(days, id: \.self) { day in
                let isToday = Calendar.current.isDateInToday(day)
                let isPast = day < Calendar.current.startOfDay(for: Date())
                HStack(alignment: .top, spacing: 6) {
                    DayColumn(day: day, isToday: isToday)
                        .frame(width: 58, alignment: .leading)
                        .padding(.top, 6)

                    ForEach(MealSlot.allCases) { slot in
                        MealPlanGridCell(
                            day: day,
                            slot: slot,
                            plannedMeals: plannedMeals(day, slot),
                            mealForPlannedMeal: mealForPlannedMeal,
                            isToday: isToday,
                            onPlan: { onPlanSlot(day, slot) },
                            onDelete: onDelete
                        )
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .padding(6)
                .background(isToday ? AppTheme.primarySoft : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .opacity(isPast ? 0.5 : 1)
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 4)
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Color.clear
                .frame(width: 58, height: 1)

            ForEach(MealSlot.allCases) { slot in
                Text(slot.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
    }
}

private struct DayColumn: View {
    let day: Date
    var isToday = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(day.formatted(.dateTime.weekday(.abbreviated)))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isToday ? AppTheme.primary : AppTheme.ink)
            Text(day.formatted(.dateTime.month(.abbreviated).day()))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MealPlanGridCell: View {
    let day: Date
    let slot: MealSlot
    let plannedMeals: [PlannedMeal]
    let mealForPlannedMeal: (PlannedMeal) -> MealIdea?
    var isToday = false
    let onPlan: () -> Void
    let onDelete: (PlannedMeal) -> Void

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            if plannedMeals.isEmpty {
                Button(action: onPlan) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AppTheme.surfaceMuted, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add meal for \(slot.title) on \(day.formatted(date: .abbreviated, time: .omitted))")
            } else {
                ForEach(plannedMeals) { plannedMeal in
                    if let meal = mealForPlannedMeal(plannedMeal) {
                        Menu {
                            Button(action: onPlan) {
                                Label("Add Another", systemImage: "plus.circle")
                            }
                            Button(role: .destructive) {
                                onDelete(plannedMeal)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        } label: {
                            Text(meal.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                .padding(.horizontal, 8)
                                .background(isToday ? AppTheme.surface : AppTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(slot.title): \(meal.name)")
                        .accessibilityHint("Add another or remove")
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

                HStack(spacing: 14) {
                    Button(action: onPlan) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.headline)
                            .foregroundStyle(AppTheme.primary)
                            .frame(width: 36, height: 36)
                            .background(AppTheme.surfaceMuted, in: Circle())
                    }
                    .frame(width: 44, height: 44)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(meal.name) to meal plan")

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
                            .frame(width: 44, height: 44)
                    }
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
    }
}

private struct MealEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var organizerStore: OrganizerStore
    let meal: MealIdea?
    @State private var name: String
    @State private var category: MealCategory
    @State private var notes: String
    @State private var ingredients: [MealIngredient]

    init(meal: MealIdea? = nil, initialCategory: MealCategory = .mainCourse) {
        self.meal = meal
        _name = State(initialValue: meal?.name ?? "")
        _category = State(initialValue: meal?.category ?? initialCategory)
        _notes = State(initialValue: meal?.notes ?? "")
        let existing = meal?.ingredients ?? []
        _ingredients = State(initialValue: existing.isEmpty ? [MealIngredient(name: "")] : existing)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Meal") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $category) {
                        ForEach(MealCategory.allCases) { category in
                            Text(category.title).tag(category)
                        }
                    }
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
                            organizerStore.updateMealIdea(meal, name: name, category: category, ingredients: ingredients, notes: notes)
                        } else {
                            organizerStore.addMealIdea(name: name, category: category, ingredients: ingredients, notes: notes)
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
    @State private var addIngredientsToShopping = false
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

/// Every ingredient for the week's planned meals, combined and grouped by shop, to add
/// to the shopping list in one go.
private struct WeeklyShoppingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var organizerStore: OrganizerStore
    let title: String
    let range: Range<Date>?

    @State private var ingredients: [WeeklyIngredient] = []
    @State private var selectedIDs: Set<String> = []
    @State private var shopIDs: [String: UUID] = [:]

    var body: some View {
        NavigationStack {
            List {
                if ingredients.isEmpty {
                    ContentUnavailableView("Nothing to Buy", systemImage: "fork.knife", description: Text(emptyMessage))
                        .listRowBackground(Color.clear)
                } else if organizerStore.shops.isEmpty {
                    ContentUnavailableView("No Shops Yet", systemImage: "cart", description: Text("Add a shop in Shopping first."))
                        .listRowBackground(Color.clear)
                }

                ForEach(organizerStore.shops) { shop in
                    let rows = toBuy.filter { shopIDs[$0.id] == shop.id }
                    if !rows.isEmpty {
                        Section(shop.name) {
                            ForEach(rows) { ingredientRow($0) }
                        }
                    }
                }

                let onList = ingredients.filter(\.isAlreadyNeeded)
                if !onList.isEmpty {
                    Section {
                        ForEach(onList) { ingredientRow($0) }
                    } header: {
                        Text("Already on Your List")
                    } footer: {
                        Text("Tick any you need more of.")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(addTitle) {
                        organizerStore.addNeededItems(itemsToAdd)
                        dismiss()
                    }
                    .disabled(itemsToAdd.isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var emptyMessage: String {
        guard let range else { return "" }
        let plannedThisWeek = organizerStore.plannedMeals.contains { range.contains($0.date) }
        return plannedThisWeek
            ? "The meals planned for this week don't have ingredients yet. Add them to the meals in the Meals tab."
            : "No meals are planned for this week yet."
    }

    private var toBuy: [WeeklyIngredient] {
        ingredients.filter { !$0.isAlreadyNeeded }
    }

    private var itemsToAdd: [(name: String, shopID: UUID)] {
        ingredients.compactMap { ingredient in
            guard selectedIDs.contains(ingredient.id), let shopID = shopIDs[ingredient.id] else { return nil }
            return (ingredient.name, shopID)
        }
    }

    private var addTitle: String {
        itemsToAdd.isEmpty ? "Add" : "Add \(itemsToAdd.count)"
    }

    private func load() {
        guard let range else { return }
        ingredients = organizerStore.weeklyIngredients(from: range.lowerBound, to: range.upperBound)
        let fallbackShopID = organizerStore.shops.first?.id
        for ingredient in ingredients {
            shopIDs[ingredient.id] = ingredient.shopID ?? fallbackShopID
            if !ingredient.isAlreadyNeeded {
                selectedIDs.insert(ingredient.id)
            }
        }
    }

    private func ingredientRow(_ ingredient: WeeklyIngredient) -> some View {
        let isSelected = selectedIDs.contains(ingredient.id)
        return HStack(spacing: 10) {
            Button {
                if isSelected {
                    selectedIDs.remove(ingredient.id)
                } else {
                    selectedIDs.insert(ingredient.id)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? AppTheme.success : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ingredient.name)
                            .foregroundStyle(.primary)
                        Text(ingredient.meals.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Spacer(minLength: 8)

            Menu {
                ForEach(organizerStore.shops) { shop in
                    Button(shop.name) {
                        shopIDs[ingredient.id] = shop.id
                        selectedIDs.insert(ingredient.id)
                    }
                }
            } label: {
                Text(shopName(for: ingredient))
                    .font(.caption)
                    .lineLimit(1)
            }
        }
    }

    private func shopName(for ingredient: WeeklyIngredient) -> String {
        organizerStore.shops.first { $0.id == shopIDs[ingredient.id] }?.name ?? "Choose Shop"
    }
}

/// Tonight's dinner, its ingredients and whether they are on the shopping list.
private struct TonightCard: View {
    @EnvironmentObject private var organizerStore: OrganizerStore
    let dinners: [PlannedMeal]
    let onPlanDinner: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TONIGHT")
                .font(.footnote.weight(.bold))
                .tracking(1)
                .foregroundStyle(AppTheme.avatarPalette[2])

            if let dinner = dinners.first, let meal = organizerStore.mealIdea(for: dinner) {
                let ingredients = dinners.flatMap { organizerStore.ingredients(for: $0) }
                let missing = ingredients.filter { !$0.isAlreadyNeeded }

                VStack(alignment: .leading, spacing: 2) {
                    Text(meal.name)
                        .font(.title2.weight(.bold))
                    if dinners.count > 1 {
                        Text("and \(dinners.count - 1) more")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if !ingredients.isEmpty {
                    FlowChips(ingredients: ingredients)
                }

                if !missing.isEmpty {
                    Button {
                        let fallbackShopID = organizerStore.shops.first?.id
                        organizerStore.addNeededItems(missing.compactMap { ingredient in
                            (ingredient.shopID ?? fallbackShopID).map { (ingredient.name, $0) }
                        })
                    } label: {
                        Text("Add \(missing.count) to shopping")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.avatarPalette[2])
                    .foregroundStyle(.black)
                    .disabled(organizerStore.shops.isEmpty)
                } else if !ingredients.isEmpty {
                    Label("Everything is on your list", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.success)
                }
            } else {
                Text("Nothing planned for dinner")
                    .font(.title3.weight(.semibold))
                Button(action: onPlanDinner) {
                    Text("Plan dinner")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Ingredient chips that wrap onto new lines; ones not on the list are highlighted.
private struct FlowChips: View {
    let ingredients: [WeeklyIngredient]

    var body: some View {
        WrappingStack(spacing: 6) {
            ForEach(ingredients) { ingredient in
                HStack(spacing: 4) {
                    if ingredient.isAlreadyNeeded {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.success)
                    }
                    Text(ingredient.name)
                }
                .font(.footnote)
                .foregroundStyle(ingredient.isAlreadyNeeded ? AppTheme.ink : AppTheme.warning)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppTheme.surfaceMuted, in: Capsule())
                .accessibilityLabel(ingredient.isAlreadyNeeded ? "\(ingredient.name), on your list" : "\(ingredient.name), not on your list")
            }
        }
    }
}

/// Lays children out left to right, wrapping to a new line when the row is full.
private struct WrappingStack: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
