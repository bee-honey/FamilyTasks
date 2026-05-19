import SwiftUI
import UniformTypeIdentifiers

struct ShoppingView: View {
    @EnvironmentObject private var organizerStore: OrganizerStore
    @State private var isAddingShop = false
    @State private var activeItemID: UUID?
    @State private var activeShopID: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(organizerStore.shops) { shop in
                        ShopSectionView(
                            shop: shop,
                            draggedItemID: $activeItemID,
                            draggedShopID: $activeShopID,
                            onMoveShopBefore: { movingID, targetID in
                                organizerStore.moveShop(id: movingID, before: targetID)
                            }
                        )
                    }
                }
                .padding(14)
            }
            .background(AppTheme.background)
            .navigationTitle("Shopping")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAddingShop = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingShop) {
                AddShopView()
            }
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

private struct ShopSectionView: View {
    @EnvironmentObject private var organizerStore: OrganizerStore
    let shop: Shop
    @Binding var draggedItemID: UUID?
    @Binding var draggedShopID: UUID?
    let onMoveShopBefore: (UUID, UUID) -> Void
    @State private var isExpanded = false
    @State private var newItemName = ""
    @State private var newUsualItemName = ""

    private var items: [ShoppingItem] {
        organizerStore.items(for: shop)
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(shop.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("\(items.filter { $0.isNeeded }.count) needed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "line.3.horizontal")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .onDrag {
                            draggedShopID = shop.id
                            return NSItemProvider(object: "shop:\(shop.id.uuidString)" as NSString)
                        }

                    ShareLink(item: shareText) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .disabled(neededItems.isEmpty)

                    Button {
                        organizerStore.closeTrip(for: shop)
                    } label: {
                        Label("Close", systemImage: "checkmark.circle")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!items.contains(where: \.isPurchased))
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 10) {
                    addItemRow
                    usualItems

                    if items.isEmpty {
                        ContentUnavailableView("No shopping items", systemImage: "cart", description: Text("Add items you need for this shop."))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    } else {
                        ForEach(items) { item in
                            ShoppingItemRow(item: item, shops: organizerStore.shops)
                                .onDrag {
                                    draggedItemID = item.id
                                    return NSItemProvider(object: item.id.uuidString as NSString)
                                }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14))
        .onDrop(of: [UTType.text], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
                let value = item as? Data
                let string = value.flatMap { String(data: $0, encoding: .utf8) } ?? item as? String
                guard let string else { return }
                Task { @MainActor in
                    if string.hasPrefix("shop:"),
                       let movingID = UUID(uuidString: String(string.dropFirst(5))) {
                        onMoveShopBefore(movingID, shop.id)
                    } else if let id = UUID(uuidString: string),
                              let movingItem = organizerStore.shoppingItems.first(where: { $0.id == id }) {
                        organizerStore.move(movingItem, to: shop)
                    }
                    draggedItemID = nil
                    draggedShopID = nil
                }
            }
            return true
        }
    }

    private var neededItems: [ShoppingItem] {
        items.filter { $0.isNeeded && !$0.isPurchased }
    }

    private var shareText: String {
        let bullets = neededItems.map { "- \($0.name)" }.joined(separator: "\n")
        return "\(shop.name) shopping list\n\n\(bullets)"
    }

    private var addItemRow: some View {
        HStack(spacing: 10) {
            TextField("Add item needed here", text: $newItemName)
                .submitLabel(.done)
                .onSubmit(addNeededItem)

            Button(action: addNeededItem) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .disabled(newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(10)
        .background(AppTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10))
    }

    private var usualItems: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Usually buy")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(shop.usualItems, id: \.self) { usualItem in
                        Button {
                            organizerStore.addNeededItem(usualItem, to: shop)
                        } label: {
                            Label(usualItem, systemImage: "plus")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(AppTheme.primarySoft, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                organizerStore.deleteUsualItem(usualItem, from: shop)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }

                    TextField("New usual", text: $newUsualItemName)
                        .font(.caption)
                        .frame(width: 110)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(AppTheme.surfaceMuted, in: Capsule())
                        .submitLabel(.done)
                        .onSubmit(addUsualItem)
                }
            }
        }
    }

    private func addNeededItem() {
        organizerStore.addNeededItem(newItemName, to: shop)
        newItemName = ""
    }

    private func addUsualItem() {
        organizerStore.addUsualItem(newUsualItemName, to: shop)
        newUsualItemName = ""
    }
}

private struct ShoppingItemRow: View {
    @EnvironmentObject private var organizerStore: OrganizerStore
    let item: ShoppingItem
    let shops: [Shop]

    var body: some View {
        HStack(spacing: 12) {
            Button {
                organizerStore.togglePurchased(item)
            } label: {
                Image(systemName: item.isPurchased ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isPurchased ? AppTheme.success : .secondary)
            }
            .buttonStyle(.plain)

            Text(item.name)
                .font(.footnote)
                .strikethrough(item.isPurchased)
                .foregroundStyle(item.isPurchased ? .secondary : .primary)

            Spacer()

            Menu {
                ForEach(shops.filter { $0.id != item.shopID }) { shop in
                    Button("Move to \(shop.name)") {
                        organizerStore.move(item, to: shop)
                    }
                }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                organizerStore.deleteShoppingItem(item)
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.destructive)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(AppTheme.surfaceMuted, in: RoundedRectangle(cornerRadius: 10))
    }
}
