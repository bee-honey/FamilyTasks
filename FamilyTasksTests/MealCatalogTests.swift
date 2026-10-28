import XCTest
@testable import FamilyTasks

/// Checks every cuisine file in FamilyTasks/MealCatalog, so a pull request that edits the
/// catalog can't ship a file the app would skip.
@MainActor
final class MealCatalogTests: XCTestCase {
    /// The MealCatalog folder in the source tree, next to this test folder.
    private var sourceFolder: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("FamilyTasks/MealCatalog")
    }

    private func sourceFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: sourceFolder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
    }

    func testEveryCatalogFileDecodes() throws {
        let files = try sourceFiles()
        XCTAssertFalse(files.isEmpty)
        for file in files {
            XCTAssertNoThrow(try MealCatalog.decode(Data(contentsOf: file)), file.lastPathComponent)
        }
    }

    func testEveryDishIsComplete() throws {
        var ids = Set<String>()
        for file in try sourceFiles() {
            let cuisine = try MealCatalog.decode(Data(contentsOf: file))
            XCTAssertFalse(cuisine.name.isEmpty, file.lastPathComponent)
            XCTAssertFalse(cuisine.meals.isEmpty, file.lastPathComponent)

            for dish in cuisine.meals {
                let label = "\(file.lastPathComponent): \(dish.id)"
                XCTAssertTrue(ids.insert(dish.id).inserted, "Duplicate id \(label)")
                XCTAssertTrue(dish.id.hasPrefix(cuisine.id + "."), "Id should start with \(cuisine.id). \(label)")
                XCTAssertNotNil(dish.id.range(of: #"^[a-z]+\.[a-z0-9]+(-[a-z0-9]+)*$"#, options: .regularExpression), "Id should be kebab-case: \(label)")
                XCTAssertFalse(dish.name.isEmpty, label)
                XCTAssertFalse(dish.serving.isEmpty, label)
                XCTAssertGreaterThan(dish.minutes, 0, label)
                XCTAssertFalse(dish.ingredients.isEmpty, label)
                XCTAssertFalse(dish.highlights.isEmpty, label)
                XCTAssertLessThanOrEqual(dish.goodSourceOf.count, 4, label)
            }
        }
    }

    /// Calories should agree with the macros (4 kcal per gram of protein and carbs, 9 per
    /// gram of fat), which catches most typos in the numbers.
    func testCaloriesMatchMacros() throws {
        for file in try sourceFiles() {
            for dish in try MealCatalog.decode(Data(contentsOf: file)).meals {
                let n = dish.nutrition
                let fromMacros = 4 * n.protein + 4 * n.carbs + 9 * n.fat
                let difference = abs(fromMacros - Double(n.calories)) / Double(n.calories)
                XCTAssertLessThanOrEqual(difference, 0.15, "\(dish.id): \(n.calories) kcal but macros add up to \(Int(fromMacros))")
                XCTAssertLessThanOrEqual(n.fiber, n.carbs, dish.id)
            }
        }
    }

    func testTheAppBundlesTheCatalog() throws {
        let bundled = MealCatalog.shared
        XCTAssertEqual(bundled.cuisines.count, try sourceFiles().count)
        XCTAssertTrue(bundled.meals.contains { $0.id == "indian.masala-dosa" })
        XCTAssertTrue(bundled.meals.contains { $0.category == .breakfast })
        XCTAssertTrue(bundled.meals.contains { $0.category == .mainCourse })
    }

    // MARK: Saving a dish

    func testAddingADishSavesItOnceWithItsIngredients() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OrganizerStore(directory: directory)
        let dosa = try XCTUnwrap(MealCatalog.shared.meal(id: "indian.masala-dosa"))

        let id = store.addCatalogMeal(dosa)
        XCTAssertEqual(store.addCatalogMeal(dosa), id)

        let saved = try XCTUnwrap(store.mealIdeas.first { $0.id == id })
        XCTAssertEqual(saved.catalogID, dosa.id)
        XCTAssertEqual(saved.category, .breakfast)
        XCTAssertEqual(saved.ingredients.map(\.name), dosa.ingredients)
        XCTAssertTrue(store.hasCatalogMeal(dosa))
    }

    func testAMealAlreadySavedByNameIsLinkedNotCopied() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OrganizerStore(directory: directory)
        store.addMealIdea(name: "rajma", category: .mainCourse, ingredients: [MealIngredient(name: "Rajma")], notes: "Grandma's way")
        let rajma = try XCTUnwrap(MealCatalog.shared.meal(id: "indian.rajma"))
        let before = store.mealIdeas.count

        let id = store.addCatalogMeal(rajma)

        XCTAssertEqual(store.mealIdeas.count, before)
        let linked = try XCTUnwrap(store.mealIdeas.first { $0.id == id })
        XCTAssertEqual(linked.catalogID, "indian.rajma")
        XCTAssertEqual(linked.notes, "Grandma's way")
    }
}
