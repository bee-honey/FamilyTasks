import SwiftUI

/// The ready-made meals from the catalog, by type, to read about and add to the family's
/// meals. Pushed from Your Meals.
struct MealCatalogView: View {
    @EnvironmentObject private var organizerStore: OrganizerStore
    var catalog = MealCatalog.shared
    @State private var category: MealCategory = .breakfast
    @State private var vegetarianOnly = false
    /// One area, such as "South Indian", or nil for all.
    @State private var area: String?
    @State private var searchText = ""
    @State private var showingDish: CatalogMeal?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        ForEach(MealCategory.allCases) { choice in
                            ChoiceChip(title: choice.title, isSelected: category == choice) {
                                category = choice
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    if areas.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ChoiceChip(title: "All Regions", isSelected: area == nil) { area = nil }
                                ForEach(areas, id: \.self) { choice in
                                    ChoiceChip(title: choice, isSelected: area == choice) { area = choice }
                                }
                            }
                        }
                    }
                    Toggle(isOn: $vegetarianOnly) {
                        HStack(spacing: 8) {
                            DietMark(diet: .vegetarian)
                            Text("Vegetarian only")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))

            ForEach(catalog.cuisines) { cuisine in
                let dishes = dishes(in: cuisine)
                if !dishes.isEmpty {
                    Section {
                        ForEach(dishes) { dish in
                            Button {
                                showingDish = dish
                            } label: {
                                CatalogMealRow(dish: dish, isSaved: organizerStore.hasCatalogMeal(dish))
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(AppTheme.surface)
                        }
                    } header: {
                        SectionTitle(text: "\(cuisine.name) · \(dishes.count)")
                    } footer: {
                        Text(cuisine.about)
                    }
                }
            }

            if catalog.cuisines.allSatisfy({ dishes(in: $0).isEmpty }) {
                ContentUnavailableView.search(text: searchText)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(AppTheme.background)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Dish, ingredient or nutrient")
        .navigationTitle("Browse Recipes")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $showingDish) { dish in
            CatalogMealDetailView(dish: dish)
        }
    }

    /// Every area in the catalog, most dishes first.
    private var areas: [String] {
        let counts = Dictionary(grouping: catalog.meals.compactMap(\.area), by: { $0 }).mapValues(\.count)
        return counts.keys.sorted { (counts[$0] ?? 0, $1) > (counts[$1] ?? 0, $0) }
    }

    private func dishes(in cuisine: CatalogCuisine) -> [CatalogMeal] {
        cuisine.meals
            .filter { $0.category == category && (!vegetarianOnly || $0.diet.isVegetarian) && $0.matches(searchText) }
            .filter { area == nil || $0.area == area }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// A catalog dish in a list: its food mark, name, region and time, and calories and protein.
struct CatalogMealRow: View {
    let dish: CatalogMeal
    var isSaved = false

    var body: some View {
        HStack(spacing: 12) {
            DietMark(diet: dish.diet)
            VStack(alignment: .leading, spacing: 3) {
                Text(dish.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text("\(dish.nutritionSummary) · \(dish.detailLine)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isSaved {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.success)
                    .accessibilityLabel("In your meals")
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// One catalog dish in full: nutrition per serving, what it's a good source of, a note or
/// two, and its ingredients, with a button to add it to the family's meals.
struct CatalogMealDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var organizerStore: OrganizerStore
    let dish: CatalogMeal

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(dish.name)
                            .font(.title2.weight(.bold))
                        HStack(spacing: 8) {
                            DietMark(diet: dish.diet)
                            Text([dish.diet.title, dish.region, "\(dish.minutes) min"].compactMap { $0 }.joined(separator: " · "))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    EditorSection("Per Serving · \(dish.serving)") {
                        NutritionGrid(nutrition: dish.nutrition)
                        Text("Approximate, for a typical home-cooked serving.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if !dish.goodSourceOf.isEmpty {
                        EditorSection("Good Source Of") {
                            WrappingStack(spacing: 8) {
                                ForEach(dish.goodSourceOf, id: \.self) { nutrient in
                                    Text(nutrient)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.success)
                                        .padding(.horizontal, 12)
                                        .frame(minHeight: 32)
                                        .background(AppTheme.success.opacity(0.14), in: Capsule())
                                }
                            }
                        }
                    }

                    if !dish.highlights.isEmpty {
                        EditorSection("Good to Know") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(dish.highlights, id: \.self) { line in
                                    Label(line, systemImage: "leaf")
                                        .labelStyle(.tile(AppTheme.brightAccent))
                                        .font(.subheadline)
                                }
                                if dish.glutenFree {
                                    Label("Gluten-free ingredients. Check packaged spices like asafoetida, which can contain wheat.", systemImage: "checkmark.seal")
                                        .labelStyle(.tile(AppTheme.coolAccent))
                                        .font(.subheadline)
                                }
                            }
                        }
                    }

                    EditorSection("Ingredients") {
                        Text(dish.ingredients.joined(separator: ", "))
                            .font(.subheadline)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Text("Added to your meal, so Shop for Week can put them on the shopping list.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .background(AppTheme.background)
            .safeAreaInset(edge: .bottom) {
                addButton
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(AppTheme.background)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var addButton: some View {
        if organizerStore.hasCatalogMeal(dish) {
            PillButtonLabel(title: "In Your Meals", systemImage: "checkmark", fillsWidth: true)
                .accessibilityAddTraits(.isStaticText)
        } else {
            Button {
                organizerStore.addCatalogMeal(dish)
                ToastCenter.shared.show("\(dish.name) added to your meals")
                dismiss()
            } label: {
                PillButtonLabel(title: "Add to My Meals", systemImage: "plus", isProminent: true, fillsWidth: true)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Calories, protein, carbs, fat and fiber in a row of tiles.
struct NutritionGrid: View {
    let nutrition: CatalogMeal.Nutrition

    var body: some View {
        HStack(spacing: 8) {
            tile("\(nutrition.calories)", unit: "kcal", label: "Calories", tint: AppTheme.warmAccent)
            tile(number(nutrition.protein), unit: "g", label: "Protein", tint: AppTheme.primary)
            tile(number(nutrition.carbs), unit: "g", label: "Carbs", tint: AppTheme.goldAccent)
            tile(number(nutrition.fat), unit: "g", label: "Fat", tint: AppTheme.coolAccent)
            tile(number(nutrition.fiber), unit: "g", label: "Fiber", tint: AppTheme.brightAccent)
        }
    }

    private func number(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }

    private func tile(_ value: String, unit: String, label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.headline.monospacedDigit())
                Text(unit)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The square-and-dot food mark: green for vegetarian, brown for egg, red for meat and fish.
struct DietMark: View {
    let diet: CatalogMeal.Diet

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .strokeBorder(diet.markColor, lineWidth: 1.5)
            .frame(width: 16, height: 16)
            .overlay {
                Circle()
                    .fill(diet.markColor)
                    .frame(width: 7, height: 7)
            }
            .accessibilityLabel(diet.title)
    }
}
