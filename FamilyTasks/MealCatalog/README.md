# Meal Catalog

Ready-made meals the app suggests under **Meal Plan → Meals → Browse Recipes** and in the
meal picker. Each cuisine is one JSON file in this folder; the app bundles every `.json`
file here, so adding a cuisine is just adding a file.

Pull requests that fix a recipe, add dishes or add a cuisine are welcome.

## Adding or editing a dish

Edit the cuisine's file (for example `indian.json`) and add an entry to `meals`:

```json
{
  "id": "indian.masala-dosa",
  "name": "Masala Dosa",
  "category": "breakfast",
  "region": "South Indian",
  "area": "South Indian",
  "diet": "vegan",
  "glutenFree": true,
  "serving": "1 dosa with potato filling",
  "minutes": 30,
  "nutrition": { "calories": 350, "protein": 7, "carbs": 52, "fat": 12, "fiber": 4 },
  "goodSourceOf": ["Carbohydrates", "Vitamin B6", "Potassium"],
  "highlights": ["The fermented rice and urad dal batter is easy to digest."],
  "ingredients": ["Dosa batter", "Potatoes", "Onions", "Oil"]
}
```

| Field | Notes |
| --- | --- |
| `id` | `<cuisine id>.<kebab-case-name>`. Never change an existing id: people's saved meals point to it. |
| `name` | As people usually say it. |
| `category` | `breakfast` or `mainCourse` (main courses are offered for lunch and dinner). |
| `region` | Optional, such as "Kerala" or "Punjabi". |
| `area` | Optional wider area for the region filter: for Indian dishes, `South Indian`, `North Indian` or `West Indian`. Leave it out for dishes eaten everywhere. |
| `diet` | `vegan`, `vegetarian`, `eggetarian` or `nonVegetarian`, for the dish as usually made. |
| `glutenFree` | Whether its usual ingredients are gluten-free. Packaged asafoetida (hing) often contains wheat, so the app reminds people to check. |
| `serving` | What the nutrition numbers are for. |
| `minutes` | Rough total time, not counting soaking or fermenting overnight. |
| `nutrition` | Calories (kcal) and grams of protein, carbs, fat and fiber for one serving. |
| `goodSourceOf` | Up to four nutrients it's notably high in. |
| `highlights` | One or two short, factual sentences. No health claims. |
| `ingredients` | Shopping-list names, main ones only. They're added to the family's shopping list. |

## Adding a cuisine

Add a new file such as `italian.json` with `cuisine` (its display name), `id`, `about` and
`meals`. Every meal id starts with the cuisine's `id` and a dot.

## Nutrition

The numbers are estimates for a typical home-cooked serving, worked out from standard food
composition values (such as the Indian Food Composition Tables and USDA FoodData Central).
The app shows them as approximate. Real values change with the recipe, the oil and the
portion.

## Checks

`MealCatalogTests` runs over every file here: ids are unique and well formed, every field
is filled in, and calories are within 15% of 4 × protein + 4 × carbs + 9 × fat. Run the
tests before opening a pull request.
