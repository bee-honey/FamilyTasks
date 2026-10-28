import SwiftUI

/// Ready-made meals, one cuisine per JSON file in the app's MealCatalog folder (see its
/// README). People add one to their own meals to plan it; the copy keeps `catalogID` so
/// its nutrition can still be shown.
struct MealCatalog {
    var cuisines: [CatalogCuisine]

    static let folderName = "MealCatalog"
    static let shared = MealCatalog.bundled()

    var meals: [CatalogMeal] { cuisines.flatMap(\.meals) }

    func meal(id: String?) -> CatalogMeal? {
        guard let id else { return nil }
        return meals.first { $0.id == id }
    }

    /// The catalog dish a saved meal came from: by its link, else by the same name and type.
    func meal(for idea: MealIdea) -> CatalogMeal? {
        meal(id: idea.catalogID) ?? meals.first {
            $0.category == idea.category && $0.name.caseInsensitiveCompare(idea.name) == .orderedSame
        }
    }

    /// Every cuisine file in `directory`, in name order. A file that doesn't decode is
    /// skipped, so one bad file can't empty the catalog (the tests catch it instead).
    static func load(from directory: URL) -> MealCatalog {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let cuisines = files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decode(Data(contentsOf: $0)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return MealCatalog(cuisines: cuisines)
    }

    static func decode(_ data: Data) throws -> CatalogCuisine {
        try JSONDecoder().decode(CatalogCuisine.self, from: data)
    }

    private static func bundled() -> MealCatalog {
        guard let directory = Bundle.main.url(forResource: folderName, withExtension: nil) else {
            return MealCatalog(cuisines: [])
        }
        return load(from: directory)
    }
}

struct CatalogCuisine: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var about: String
    var meals: [CatalogMeal]

    private enum CodingKeys: String, CodingKey {
        case id
        case name = "cuisine"
        case about
        case meals
    }
}

struct CatalogMeal: Codable, Identifiable, Equatable, Hashable {
    enum Diet: String, Codable, CaseIterable {
        case vegan
        case vegetarian
        case eggetarian
        case nonVegetarian

        var title: String {
            switch self {
            case .vegan: "Vegan"
            case .vegetarian: "Vegetarian"
            case .eggetarian: "Contains egg"
            case .nonVegetarian: "Non-vegetarian"
            }
        }

        /// The square-and-dot food mark used on Indian packaging: green for vegetarian, brown
        /// for egg, red for meat and fish.
        var markColor: Color {
            switch self {
            case .vegan, .vegetarian: Color(red: 0.13, green: 0.55, blue: 0.27)
            case .eggetarian: Color(red: 0.62, green: 0.42, blue: 0.16)
            case .nonVegetarian: Color(red: 0.72, green: 0.16, blue: 0.16)
            }
        }

        var isVegetarian: Bool { self == .vegan || self == .vegetarian }
    }

    struct Nutrition: Codable, Equatable, Hashable {
        var calories: Int
        var protein: Double
        var carbs: Double
        var fat: Double
        var fiber: Double
    }

    var id: String
    var name: String
    var category: MealCategory
    var region: String?
    var diet: Diet
    var glutenFree: Bool
    var serving: String
    var minutes: Int
    var nutrition: Nutrition
    var goodSourceOf: [String]
    var highlights: [String]
    var ingredients: [String]

    /// "350 kcal · 7 g protein"
    var nutritionSummary: String {
        "\(nutrition.calories) kcal · \(Self.grams(nutrition.protein)) protein"
    }

    /// "South Indian · 30 min"
    var detailLine: String {
        [region, "\(minutes) min"].compactMap { $0 }.joined(separator: " · ")
    }

    static func grams(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value)) g" : String(format: "%.1f g", value)
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return name.localizedCaseInsensitiveContains(query)
            || (region?.localizedCaseInsensitiveContains(query) ?? false)
            || ingredients.contains { $0.localizedCaseInsensitiveContains(query) }
            || goodSourceOf.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}
