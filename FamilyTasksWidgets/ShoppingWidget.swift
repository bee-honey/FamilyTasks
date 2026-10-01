import SwiftUI
import WidgetKit

struct ShoppingEntry: TimelineEntry {
    let date: Date
    /// Nil when there are no shops yet.
    let shop: WidgetSnapshot.ShopRow?

    static let sample = ShoppingEntry(
        date: Date(),
        shop: WidgetSnapshot.ShopRow(
            id: UUID(),
            name: "Grocery",
            items: ["Milk", "Bread", "Apples"].map { WidgetSnapshot.ItemRow(id: UUID(), name: $0) }
        )
    )
}

struct ShoppingProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ShoppingEntry {
        .sample
    }

    func snapshot(for configuration: SelectShopIntent, in context: Context) async -> ShoppingEntry {
        context.isPreview ? .sample : entry(for: configuration)
    }

    /// The app reloads the widget whenever the list changes, so no refresh schedule is needed.
    func timeline(for configuration: SelectShopIntent, in context: Context) async -> Timeline<ShoppingEntry> {
        Timeline(entries: [entry(for: configuration)], policy: .never)
    }

    /// The chosen shop, or until one is chosen, the first shop with something on its list.
    private func entry(for configuration: SelectShopIntent) -> ShoppingEntry {
        let shops = WidgetStorage.shared?.loadSnapshot().shops ?? []
        let chosen = configuration.shop.flatMap { selected in shops.first { $0.id.uuidString == selected.id } }
        let shop = chosen ?? shops.first { !$0.items.isEmpty } ?? shops.first
        return ShoppingEntry(date: Date(), shop: shop)
    }
}

struct ShoppingWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "FamilyTasksShopping", intent: SelectShopIntent.self, provider: ShoppingProvider()) { entry in
            ShoppingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Shopping List")
        .description("What's needed at one shop. Tap a circle when it's in the cart.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

struct ShoppingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ShoppingEntry

    var body: some View {
        if let shop = entry.shop {
            switch family {
            case .accessoryInline:
                Text(shop.items.isEmpty ? "\(shop.name): nothing needed" : "\(shop.items.count) needed at \(shop.name)")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(shop.name) · \(shop.items.count)")
                        .font(.headline)
                        .lineLimit(1)
                    if shop.items.isEmpty {
                        Text("Nothing needed")
                    } else {
                        Text(shop.items.prefix(3).map(\.name).joined(separator: ", "))
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                list(for: shop)
            }
        } else {
            Text("Add a shop in Family Tasks")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func list(for shop: WidgetSnapshot.ShopRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(shop.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if !shop.items.isEmpty {
                    Text("\(shop.items.count)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }

            if shop.items.isEmpty {
                Spacer()
                Label("Nothing needed", systemImage: "cart")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(shop.items.prefix(maxRows)) { item in
                    HStack(spacing: 6) {
                        Button(intent: PurchaseItemIntent(itemID: item.id)) {
                            Image(systemName: "circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        Text(item.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                if shop.items.count > maxRows {
                    Text("+\(shop.items.count - maxRows) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var maxRows: Int {
        switch family {
        case .systemSmall, .systemMedium: 3
        default: 9
        }
    }
}

#Preview("Shopping", as: .systemSmall) {
    ShoppingWidget()
} timeline: {
    ShoppingEntry.sample
    ShoppingEntry(date: Date(), shop: WidgetSnapshot.ShopRow(id: UUID(), name: "Hardware", items: []))
}
