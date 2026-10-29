import SwiftUI

struct MealPlanView: View {
    @EnvironmentObject private var organizerStore: OrganizerStore
    var isPushed = false
    @State private var selectedDay = Date()
    @State private var choosingSlot: SlotChoice?
    @State private var isShoppingForWeek = false
    @State private var isGenerating = false
    @AppStorage(IngredientsOnHand.storageKey) private var ingredientsOnHand = Data()

    /// An empty slot being filled.
    struct SlotChoice: Identifiable {
        let day: Date
        let slot: MealSlot
        var id: String { "\(day.timeIntervalSince1970)-\(slot.rawValue)" }
    }

    var body: some View {
        // Shown inside a tab's NavigationStack, or pushed from Family.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ScreenHeader(eyebrow: weekTitle, title: "Meal Plan") {
                    NavigationLink {
                        MealLibraryView()
                    } label: {
                        PillButtonLabel(title: "Meals", systemImage: "book")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)

                if organizerStore.mealIdeas.isEmpty {
                    ContentUnavailableView {
                        Label("No Meals Yet", systemImage: "fork.knife")
                    } description: {
                        Text("Add the meals your family makes, then plan them for breakfast, lunch or dinner.")
                    } actions: {
                        NavigationLink {
                            MealLibraryView()
                        } label: {
                            PillButtonLabel(title: "Add Your Meals", systemImage: "plus", isProminent: true)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 60)
                } else {
                    weekSwitcher

                    HStack(spacing: 10) {
                        if !generationDays.isEmpty {
                            Button {
                                isGenerating = true
                            } label: {
                                PillButtonLabel(title: "Generate", systemImage: "wand.and.stars", isProminent: true)
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            isShoppingForWeek = true
                        } label: {
                            PillButtonLabel(title: "Shop for Week", systemImage: "cart", badge: weekIngredientsToBuy, fillsWidth: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(weekIngredientsToBuy > 0 ? "\(shopForWeekTitle), \(weekIngredientsToBuy) to buy" : shopForWeekTitle)
                    }

                    WeeklyMealPlanGrid(days: daysToShow) { day, slot in
                        plannedMeals(on: day, slot: slot)
                    } mealForPlannedMeal: { plannedMeal in
                        organizerStore.mealIdea(for: plannedMeal)
                    } onPlanSlot: { day, slot in
                        choosingSlot = SlotChoice(day: day, slot: slot)
                    } onDelete: { plannedMeal in
                        organizerStore.deletePlannedMeal(plannedMeal)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .background(AppTheme.background)
        .mainScreenNavigationBar(title: "Meal Plan", isPushed: isPushed)
        .sheet(item: $choosingSlot) { choice in
            ChooseMealView(
                category: MealPlanGenerator.category(for: choice.slot),
                title: "\(choice.day.formatted(.dateTime.weekday(.wide))) \(choice.slot.title)"
            ) { mealID in
                plan(mealID, on: choice.day, slot: choice.slot)
            }
        }
        .sheet(isPresented: $isGenerating) {
            GenerateMealPlanView(days: generationDays) { added in
                ToastCenter.shared.show(
                    "Added \(added) \(added == 1 ? "meal" : "meals") to the plan",
                    actionTitle: "Shop for Week"
                ) {
                    isShoppingForWeek = true
                }
            }
        }
        .sheet(isPresented: $isShoppingForWeek) {
            WeeklyShoppingView(title: shopForWeekTitle, range: shoppingRange)
        }
    }

    private func plan(_ mealID: UUID, on day: Date, slot: MealSlot) {
        let noon = Calendar.current.startOfDay(for: day).addingTimeInterval(12 * 3_600)
        organizerStore.planMeals([(mealID, noon, slot)])
        let name = organizerStore.mealIdeas.first { $0.id == mealID }?.name ?? "Meal"
        ToastCenter.shared.show("\(name) added to \(day.formatted(.dateTime.weekday(.abbreviated))) \(slot.title.lowercased())")
    }

    /// "‹ This Week ›" to move between weeks.
    private var weekSwitcher: some View {
        HStack(spacing: 6) {
            weekArrow("chevron.left", label: "Previous week", offset: -7)
            Text(weekRelativeTitle)
                .font(.headline)
                .frame(minWidth: 110)
            weekArrow("chevron.right", label: "Next week", offset: 7)
            Spacer()
            if !Calendar.current.isDate(selectedDay, equalTo: Date(), toGranularity: .weekOfYear) {
                Button("Back to This Week") { selectedDay = Date() }
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    /// The days a generated plan fills: the week shown, from today on.
    private var generationDays: [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        return daysToShow.filter { $0 >= today }
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

    /// Ingredients for the shown week that are not on the shopping list yet, leaving out
    /// the ones the family said they have.
    private var weekIngredientsToBuy: Int {
        guard let range = shoppingRange else { return 0 }
        let onHand = IngredientsOnHand.keys(in: ingredientsOnHand, weekStart: range.lowerBound)
        return organizerStore.weeklyIngredients(from: range.lowerBound, to: range.upperBound)
            .filter { !$0.isAlreadyNeeded && !onHand.contains($0.id) }
            .count
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
                Label(slot.title, systemImage: slot.systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(slot.courseColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(slot.courseColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                        .strokeBorder(slot.courseColor.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
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
                                .background(slot.courseColor.opacity(isToday ? 0.3 : 0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(slot.courseColor)
                                        .frame(width: 3)
                                        .padding(.vertical, 10)
                                }
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
                    Text(subtitle)
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

    /// "350 kcal · 7 g protein · 8 ingredients" for catalog meals, else the ingredient count.
    private var subtitle: String {
        let ingredients = "\(meal.ingredients.count) ingredients"
        guard let dish = MealCatalog.shared.meal(for: meal) else { return ingredients }
        return "\(dish.nutritionSummary) · \(ingredients)"
    }
}

struct MealEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var organizerStore: OrganizerStore
    let meal: MealIdea?
    @State private var name: String
    @State private var category: MealCategory
    @State private var notes: String
    @State private var ingredients: [MealIngredient]
    @State private var timesPerWeek: Int
    @State private var suggestInGeneratedPlans: Bool

    init(meal: MealIdea? = nil, initialCategory: MealCategory = .mainCourse) {
        self.meal = meal
        _name = State(initialValue: meal?.name ?? "")
        _category = State(initialValue: meal?.category ?? initialCategory)
        _notes = State(initialValue: meal?.notes ?? "")
        let existing = meal?.ingredients ?? []
        _ingredients = State(initialValue: existing.isEmpty ? [MealIngredient(name: "")] : existing)
        _timesPerWeek = State(initialValue: meal?.timesPerWeek ?? 1)
        _suggestInGeneratedPlans = State(initialValue: !(meal?.skipInGeneratedPlans ?? false))
    }

    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("What's the meal?", text: $name, axis: .vertical)
                            .font(.title2.weight(.bold))
                            .focused($isNameFocused)
                        TextField("Add notes or a recipe link", text: $notes, axis: .vertical)
                            .foregroundStyle(.secondary)
                            .lineLimit(1...5)
                    }

                    EditorSection("Type") {
                        WrappingStack(spacing: 8) {
                            ForEach(MealCategory.allCases) { choice in
                                ChoiceChip(title: choice.title, isSelected: category == choice) {
                                    category = choice
                                }
                            }
                        }
                    }

                    if meal == nil, !recipeSuggestions.isEmpty {
                        EditorSection(name.trimmingCharacters(in: .whitespaces).isEmpty ? "Or Pick a Recipe" : "Matching Recipes") {
                            recipeSuggestionsCard
                            Text("Adds the recipe with its ingredients and nutrition.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let dish = meal.flatMap(MealCatalog.shared.meal(for:)) {
                        EditorSection("Nutrition · \(dish.serving)") {
                            NutritionGrid(nutrition: dish.nutrition)
                            Text("Approximate, from the \(dish.name) recipe in Browse Recipes.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    EditorSection("Ingredients") {
                        ingredientsCard
                        Text("Shop for This Week adds these to the shopping list, at each one's shop.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    EditorSection("Generated Plans") {
                        VStack(spacing: 0) {
                            Toggle(isOn: $suggestInGeneratedPlans) {
                                Label("Suggest in Generated Plans", systemImage: "wand.and.stars")
                                    .labelStyle(.tile(AppTheme.primary))
                            }
                            .padding(12)
                            if suggestInGeneratedPlans {
                                Divider().padding(.leading, 56)
                                Stepper(value: $timesPerWeek, in: 1...7) {
                                    Label(timesPerWeek == 1 ? "Once a week" : "Up to \(timesPerWeek) times a week", systemImage: "repeat")
                                        .labelStyle(.tile(AppTheme.coolAccent))
                                }
                                .padding(12)
                            }
                        }
                        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Text("Meals that can repeat let a generated plan fill the week with fewer meals. Turn suggestions off for meals that are out of season.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let meal {
                        EditorDeleteButton(title: "Delete Meal", message: "It's taken off the plan and removed for everyone in the family.") {
                            organizerStore.deleteMealIdea(meal)
                            dismiss()
                        }
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.background)
            .navigationTitle(meal == nil ? "New Meal" : "Edit Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(meal == nil ? "Add" : "Save") {
                        if let meal {
                            organizerStore.updateMealIdea(meal, name: name, category: category, ingredients: ingredients, notes: notes, timesPerWeek: timesPerWeek, skipInGeneratedPlans: !suggestInGeneratedPlans)
                        } else {
                            organizerStore.addMealIdea(name: name, category: category, ingredients: ingredients, notes: notes, timesPerWeek: timesPerWeek, skipInGeneratedPlans: !suggestInGeneratedPlans)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if meal == nil { isNameFocused = true }
            }
        }
    }

    /// Catalog dishes of this type that aren't saved yet, matching what's typed, so a
    /// common dish doesn't have to be entered by hand.
    private var recipeSuggestions: [CatalogMeal] {
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return MealCatalog.shared.meals
            .filter { $0.category == category && !organizerStore.hasCatalogMeal($0) }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.ingredients.contains { $0.localizedCaseInsensitiveContains(query) } }
            .sorted { lhs, rhs in
                // Names that start with what's typed come first.
                let lhsPrefix = !query.isEmpty && lhs.name.lowercased().hasPrefix(query.lowercased())
                let rhsPrefix = !query.isEmpty && rhs.name.lowercased().hasPrefix(query.lowercased())
                if lhsPrefix != rhsPrefix { return lhsPrefix }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .prefix(4)
            .map { $0 }
    }

    private var recipeSuggestionsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(recipeSuggestions.enumerated()), id: \.element.id) { index, dish in
                if index > 0 {
                    Divider().padding(.leading, 40)
                }
                Button {
                    organizerStore.addCatalogMeal(dish)
                    ToastCenter.shared.show("\(dish.name) added to your meals")
                    dismiss()
                } label: {
                    HStack {
                        CatalogMealRow(dish: dish)
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(AppTheme.primary)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Adds it to your meals")
            }
        }
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var ingredientsCard: some View {
        VStack(spacing: 0) {
            ForEach($ingredients) { $ingredient in
                IngredientEditorRow(ingredient: $ingredient) {
                    ingredients.removeAll { $0.id == ingredient.id }
                }
                Divider().padding(.leading, 12)
            }

            Button {
                ingredients.append(MealIngredient(name: ""))
            } label: {
                Label("Add Ingredient", systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.primary)
        }
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// An ingredient's name, the shop it's usually bought at, and a button to remove it.
private struct IngredientEditorRow: View {
    @EnvironmentObject private var organizerStore: OrganizerStore
    @Binding var ingredient: MealIngredient
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Ingredient", text: $ingredient.name)

            Menu {
                Picker("Shop", selection: $ingredient.defaultShopID) {
                    Text("Choose later").tag(Optional<UUID>.none)
                    ForEach(organizerStore.shops) { shop in
                        Text(shop.name).tag(Optional(shop.id))
                    }
                }
            } label: {
                Label(shopName ?? "Shop", systemImage: "storefront")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(shopName == nil ? Color.secondary : AppTheme.coolAccent)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 30)
                    .background((shopName == nil ? Color.secondary : AppTheme.coolAccent).opacity(0.14), in: Capsule())
            }
            .accessibilityLabel("Shop for \(ingredient.name.isEmpty ? "ingredient" : ingredient.name)")

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove ingredient")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
    }

    private var shopName: String? {
        ingredient.defaultShopID.flatMap { id in organizerStore.shops.first { $0.id == id }?.name }
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
                        if addIngredientsToShopping && !meal.ingredients.isEmpty {
                            ToastCenter.shared.show("\(meal.name) planned, ingredients added to Shopping", actionTitle: "View") {
                                AppNavigator.shared.open(.section(.shopping))
                            }
                        } else {
                            ToastCenter.shared.show("\(meal.name) added to \(date.formatted(.dateTime.weekday(.abbreviated))) \(slot.title.lowercased())")
                        }
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

    @AppStorage(IngredientsOnHand.storageKey) private var ingredientsOnHand = Data()

    @State private var ingredients: [WeeklyIngredient] = []
    @State private var selectedIDs: Set<String> = []
    @State private var shopIDs: [String: UUID] = [:]
    /// Ingredients unticked earlier this week because the family has them.
    @State private var onHandIDs: Set<String> = []

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
                    let rows = toBuy.filter { shopIDs[$0.id] == shop.id && !onHandIDs.contains($0.id) }
                    if !rows.isEmpty {
                        Section {
                            ForEach(rows) { ingredientRow($0) }
                        } header: {
                            Text(shop.name)
                        } footer: {
                            if shop.id == firstShopWithRows {
                                Text("Untick anything you already have; it won't be offered again this week.")
                            }
                        }
                    }
                }

                let haveIt = toBuy.filter { onHandIDs.contains($0.id) }
                if !haveIt.isEmpty {
                    Section {
                        ForEach(haveIt) { ingredientRow($0) }
                    } header: {
                        Text("You Have These")
                    } footer: {
                        Text("Tick any you need to buy after all.")
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
                        let count = itemsToAdd.count
                        rememberOnHand()
                        organizerStore.addNeededItems(itemsToAdd)
                        dismiss()
                        guard count > 0 else { return }
                        ToastCenter.shared.show(
                            "\(count) \(count == 1 ? "item" : "items") added to Shopping",
                            systemImage: "cart.fill.badge.plus",
                            actionTitle: "View"
                        ) {
                            AppNavigator.shared.open(.section(.shopping))
                        }
                    }
                    .disabled(ingredients.isEmpty)
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

    /// "Done" when nothing is ticked, so unticking everything still saves what's on hand.
    private var addTitle: String {
        itemsToAdd.isEmpty ? "Done" : "Add \(itemsToAdd.count)"
    }

    private var firstShopWithRows: UUID? {
        organizerStore.shops.first { shop in
            toBuy.contains { shopIDs[$0.id] == shop.id && !onHandIDs.contains($0.id) }
        }?.id
    }

    private func load() {
        guard let range else { return }
        ingredients = organizerStore.weeklyIngredients(from: range.lowerBound, to: range.upperBound)
        onHandIDs = IngredientsOnHand.keys(in: ingredientsOnHand, weekStart: range.lowerBound)
        let fallbackShopID = organizerStore.shops.first?.id
        for ingredient in ingredients {
            shopIDs[ingredient.id] = ingredient.shopID ?? fallbackShopID
            if !ingredient.isAlreadyNeeded && !onHandIDs.contains(ingredient.id) {
                selectedIDs.insert(ingredient.id)
            }
        }
    }

    /// Every ingredient left unticked that isn't already on the list is one the family has.
    private func rememberOnHand() {
        guard let range else { return }
        let onHand = Set(toBuy.map(\.id)).subtracting(selectedIDs)
        ingredientsOnHand = IngredientsOnHand.setting(onHand, in: ingredientsOnHand, weekStart: range.lowerBound)
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

/// The cart button with how many of the week's ingredients are not on the list yet.
/// iOS 26 draws toolbar buttons in glass that clips anything outside them, so there the
/// system toolbar badge is used; earlier versions draw the count on the icon.
extension MealSlot {
    /// Each course's color in the meal plan, so breakfast, lunch and dinner read as columns.
    var courseColor: Color {
        switch self {
        case .breakfast: AppTheme.goldAccent
        case .lunch: AppTheme.brightAccent
        case .dinner: AppTheme.coolAccent
        }
    }
}

/// Every saved meal, by type, to plan, edit or add to. Pushed from Meal Plan.
struct MealLibraryView: View {
    @EnvironmentObject private var organizerStore: OrganizerStore
    @State private var category: MealCategory = .breakfast
    @State private var searchText = ""
    @State private var isAddingMeal = false
    @State private var planningMeal: MealIdea?
    @State private var editingMeal: MealIdea?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                NavigationLink {
                    MealCatalogView()
                } label: {
                    HStack(spacing: 12) {
                        IconTile(systemImage: "book.pages", tint: AppTheme.brightAccent, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Browse Recipes")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                            Text(catalogSummary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(12)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    ForEach(MealCategory.allCases) { choice in
                        ChoiceChip(title: choice.title, isSelected: category == choice) {
                            category = choice
                        }
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search meals or ingredients", text: $searchText)
                        .textInputAutocapitalization(.words)
                }
                .padding(12)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if meals.isEmpty {
                    ContentUnavailableView {
                        Label(searchText.isEmpty ? "No \(category.title) Meals" : "No Matches", systemImage: "fork.knife.circle")
                    } description: {
                        Text(searchText.isEmpty ? "Add meals once and reuse them every week." : "Try another search.")
                    } actions: {
                        Button("Add \(category.title) Meal") { isAddingMeal = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 40)
                } else {
                    ForEach(meals) { meal in
                        MealIdeaCard(meal: meal) {
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
        .scrollDismissesKeyboard(.interactively)
        .background(AppTheme.background)
        .navigationTitle("Your Meals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Meal", systemImage: "plus") { isAddingMeal = true }
                    .labelStyle(.titleAndIcon)
            }
        }
        .sheet(isPresented: $isAddingMeal) {
            MealEditorView(initialCategory: category)
        }
        .sheet(item: $editingMeal) { meal in
            MealEditorView(meal: meal)
        }
        .sheet(item: $planningMeal) { meal in
            PlanMealView(meal: meal, initialDate: Date(), initialSlot: meal.category == .breakfast ? .breakfast : .dinner)
        }
    }

    /// "48 Indian dishes with nutrition"
    private var catalogSummary: String {
        let catalog = MealCatalog.shared
        let names = ListFormatter.localizedString(byJoining: catalog.cuisines.map(\.name))
        return "\(catalog.meals.count) \(names) dishes with nutrition"
    }

    private var meals: [MealIdea] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return organizerStore.mealIdeas
            .filter { $0.category == category }
            .filter { meal in
                query.isEmpty
                || meal.name.localizedCaseInsensitiveContains(query)
                || meal.ingredients.contains { $0.name.localizedCaseInsensitiveContains(query) }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
