import SwiftUI

struct ShoppingView: View {
    @EnvironmentObject private var organizerStore: OrganizerStore
    /// Opened from Family rather than as a tab, so it needs the bar's back button.
    var showsNavigationBar = false
    @AppStorage("shopping.selectedShopID") private var selectedShopID = ""
    @State private var newItemName = ""
    @State private var showsAllUsualItems = false
    @State private var isAddingShop = false
    @State private var editingShop: Shop?
    @State private var shopToDelete: Shop?
    @State private var itemToMove: ShoppingItem?

    var body: some View {
        // Shown inside a tab's NavigationStack, or pushed from Family.
        Group {
            List {
                Section {
                    header
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 4))
                .listRowBackground(Color.clear)

                if let shop = selectedShop {
                    Section {
                        shopChips
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)

                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            addField(for: shop)
                            usualItems(for: shop)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                    .listRowBackground(Color.clear)

                    toBuySection(for: shop)
                    cartSection(for: shop)
                } else {
                    Section {
                        ContentUnavailableView {
                            Label("No Shops Yet", systemImage: "cart")
                        } description: {
                            Text("Add the shops you go to, then keep a list for each.")
                        } actions: {
                            Button("Add a Shop") { isAddingShop = true }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .contentMargins(.top, 0, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.background)
            .navigationTitle("Shopping")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(showsNavigationBar ? .automatic : .hidden, for: .navigationBar)
            .sheet(isPresented: $isAddingShop) {
                AddShopView()
            }
            .sheet(item: $editingShop) { shop in
                EditShopView(shop: shop)
            }
            .alert("Delete \(shopToDelete?.name ?? "shop")?", isPresented: Binding(
                get: { shopToDelete != nil },
                set: { if !$0 { shopToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let shopToDelete {
                        organizerStore.deleteShop(shopToDelete)
                    }
                }
            } message: {
                Text("This removes the shop and everything on its list.")
            }
            .confirmationDialog("Move to", isPresented: Binding(
                get: { itemToMove != nil },
                set: { if !$0 { itemToMove = nil } }
            ), presenting: itemToMove) { item in
                ForEach(organizerStore.shops.filter { $0.id != item.shopID }) { shop in
                    Button(shop.name) {
                        organizerStore.move(item, to: shop)
                    }
                }
            }
        }
    }

    private var selectedShop: Shop? {
        organizerStore.shops.first { $0.id.uuidString == selectedShopID } ?? organizerStore.shops.first
    }

    private func toBuy(at shop: Shop) -> [ShoppingItem] {
        organizerStore.items(for: shop).filter { $0.isNeeded && !$0.isPurchased }
    }

    private func inCart(at shop: Shop) -> [ShoppingItem] {
        organizerStore.items(for: shop).filter(\.isPurchased)
    }

    // MARK: Header and shops

    private var header: some View {
        let total = organizerStore.shoppingItems.filter { $0.isNeeded && !$0.isPurchased }.count
        let shopCount = organizerStore.shops.count
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(total) TO BUY · \(shopCount) \(shopCount == 1 ? "SHOP" : "SHOPS")")
                    .font(.footnote.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(AppTheme.primary)
                Text("Shopping")
                    .font(.title.weight(.bold))
            }
            Spacer()
            HStack(spacing: 10) {
                if let shop = selectedShop {
                    ShareLink(item: shareText(for: shop)) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                            .frame(width: 44, height: 44)
                            .background(AppTheme.surface, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(toBuy(at: shop).isEmpty)
                    .accessibilityLabel("Share \(shop.name) list")
                }
                Button {
                    isAddingShop = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.onPrimary)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.primary, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add shop")
            }
        }
    }

    /// One chip per shop with how much is needed there. Long-press a chip to rename,
    /// reorder or delete the shop.
    private var shopChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(organizerStore.shops) { shop in
                    let isSelected = shop.id == selectedShop?.id
                    let count = toBuy(at: shop).count
                    Button {
                        selectedShopID = shop.id.uuidString
                    } label: {
                        HStack(spacing: 6) {
                            Text(shop.name)
                            Text("\(count)")
                                .opacity(0.7)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? AppTheme.onPrimary : AppTheme.ink)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 38)
                        .background(isSelected ? AppTheme.primary : AppTheme.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(shop.name), \(count) to buy")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") { editingShop = shop }
                        Button("Move Left", systemImage: "arrow.left") { organizerStore.moveShopUp(shop) }
                            .disabled(organizerStore.shops.first?.id == shop.id)
                        Button("Move Right", systemImage: "arrow.right") { organizerStore.moveShopDown(shop) }
                            .disabled(organizerStore.shops.last?.id == shop.id)
                        Button("Delete Shop", systemImage: "trash", role: .destructive) { shopToDelete = shop }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: Adding items

    private func addField(for shop: Shop) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.headline)
                .foregroundStyle(AppTheme.primary)
            TextField("Add to \(shop.name)", text: $newItemName)
                .submitLabel(.done)
                .onSubmit { addItem(to: shop) }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func addItem(to shop: Shop) {
        organizerStore.addNeededItem(newItemName, to: shop)
        newItemName = ""
    }

    /// The shop's usual items not already on the list; tap one to add it.
    @ViewBuilder
    private func usualItems(for shop: Shop) -> some View {
        let needed = Set(toBuy(at: shop).map { WeeklyIngredient.key(for: $0.name) })
        let available = shop.usualItems.filter { !needed.contains(WeeklyIngredient.key(for: $0)) }
        if !available.isEmpty {
            let limit = 8
            let shown = showsAllUsualItems ? available : Array(available.prefix(limit))
            WrappingStack(spacing: 6) {
                ForEach(shown, id: \.self) { usual in
                    Button {
                        organizerStore.addNeededItem(usual, to: shop)
                    } label: {
                        Text("+ \(usual)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 32)
                            .overlay(Capsule().strokeBorder(AppTheme.surfaceMuted, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add \(usual)")
                    .contextMenu {
                        Button("Remove from Usually Buy", systemImage: "minus.circle", role: .destructive) {
                            organizerStore.deleteUsualItem(usual, from: shop)
                        }
                    }
                }
                if available.count > limit {
                    Button(showsAllUsualItems ? "Less" : "More…") {
                        withAnimation(.snappy) { showsAllUsualItems.toggle() }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.primary)
                    .frame(minHeight: 32)
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Lists

    @ViewBuilder
    private func toBuySection(for shop: Shop) -> some View {
        let items = toBuy(at: shop)
        let meals = mealsByIngredient
        Section {
            if items.isEmpty {
                Label("Nothing to buy at \(shop.name)", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .listRowBackground(AppTheme.surface)
            }
            ForEach(items) { item in
                ShoppingItemRow(item: item, forMeals: meals[WeeklyIngredient.key(for: item.name)] ?? []) {
                    organizerStore.togglePurchased(item)
                }
                .listRowBackground(AppTheme.surface)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        organizerStore.deleteShoppingItem(item)
                    }
                    if organizerStore.shops.count > 1 {
                        Button("Move", systemImage: "arrow.left.arrow.right") {
                            itemToMove = item
                        }
                        .tint(AppTheme.taskSchedule)
                    }
                }
                .contextMenu {
                    if organizerStore.shops.count > 1 {
                        Menu("Move To", systemImage: "arrow.left.arrow.right") {
                            ForEach(organizerStore.shops.filter { $0.id != item.shopID }) { other in
                                Button(other.name) { organizerStore.move(item, to: other) }
                            }
                        }
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        organizerStore.deleteShoppingItem(item)
                    }
                }
            }
        } header: {
            SectionTitle(text: "To buy · \(items.count)")
        }
    }

    @ViewBuilder
    private func cartSection(for shop: Shop) -> some View {
        let items = inCart(at: shop)
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    ShoppingItemRow(item: item, forMeals: []) {
                        organizerStore.togglePurchased(item)
                    }
                    .listRowBackground(AppTheme.surface)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            organizerStore.deleteShoppingItem(item)
                        }
                    }
                }
            } header: {
                HStack {
                    SectionTitle(text: "In the cart · \(items.count)")
                    Spacer()
                    Button("Done Shopping") {
                        withAnimation { organizerStore.closeTrip(for: shop) }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.primary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .background(AppTheme.primarySoft, in: Capsule())
                    .buttonStyle(.plain)
                    .textCase(nil)
                }
            }
        }
    }

    /// The meals planned this week that use each ingredient, for "For Chicken curry (Thu)".
    private var mealsByIngredient: [String: [String]] {
        guard let week = WeeklyIngredient.weekRange(containing: Date()) else { return [:] }
        let ingredients = organizerStore.weeklyIngredients(from: week.lowerBound, to: week.upperBound)
        return Dictionary(ingredients.map { ($0.id, $0.meals) }, uniquingKeysWith: { first, _ in first })
    }

    private func shareText(for shop: Shop) -> String {
        let bullets = toBuy(at: shop).map { "- \($0.name)" }.joined(separator: "\n")
        return "\(shop.name) shopping list\n\n\(bullets)"
    }
}

private struct ShoppingItemRow: View {
    let item: ShoppingItem
    let forMeals: [String]
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Group {
                    if item.isPurchased {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(AppTheme.onAvatar)
                            .frame(width: 26, height: 26)
                            .background(AppTheme.success, in: Circle())
                    } else {
                        Circle()
                            .strokeBorder(Color.secondary, lineWidth: 2)
                            .frame(width: 26, height: 26)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, -9)
            .accessibilityLabel(item.isPurchased ? "Put \(item.name) back on the list" : "Put \(item.name) in the cart")

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.body.weight(.semibold))
                    .strikethrough(item.isPurchased)
                    .foregroundStyle(item.isPurchased ? .secondary : .primary)
                if !forMeals.isEmpty {
                    Text("For \(forMeals.joined(separator: ", "))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

private struct AddShopView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var organizerStore: OrganizerStore
    @State private var shopName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Shop") {
                    TextField("Shop name", text: $shopName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(addShop)
                }
            }
            .navigationTitle("New Shop")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addShop() }
                        .disabled(trimmedShopName.isEmpty)
                }
            }
        }
    }

    private var trimmedShopName: String {
        shopName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addShop() {
        guard !trimmedShopName.isEmpty else { return }
        organizerStore.addShop(named: trimmedShopName)
        dismiss()
    }
}

private struct EditShopView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var organizerStore: OrganizerStore
    let shop: Shop
    @State private var shopName: String

    init(shop: Shop) {
        self.shop = shop
        _shopName = State(initialValue: shop.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Shop") {
                    TextField("Shop name", text: $shopName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(saveShop)
                }
            }
            .navigationTitle("Edit Shop")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveShop() }
                        .disabled(trimmedShopName.isEmpty)
                }
            }
        }
    }

    private var trimmedShopName: String {
        shopName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveShop() {
        guard !trimmedShopName.isEmpty else { return }
        organizerStore.updateShop(shop, name: trimmedShopName)
        dismiss()
    }
}
