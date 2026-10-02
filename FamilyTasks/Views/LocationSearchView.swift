import MapKit
import SwiftUI

/// Finds a place with Apple Maps search, or keeps what was typed. Searching doesn't need
/// location permission.
struct LocationSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (TaskLocation) -> Void
    @StateObject private var search = PlaceSearch()
    @State private var isResolving = false
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search places or addresses", text: $search.query)
                            .focused($isFieldFocused)
                            .submitLabel(.search)
                            .autocorrectionDisabled()
                    }
                }

                let typed = search.query.trimmingCharacters(in: .whitespacesAndNewlines)
                if !typed.isEmpty {
                    Section {
                        Button {
                            choose(TaskLocation(name: typed))
                        } label: {
                            Label("Use “\(typed)”", systemImage: "text.cursor")
                        }
                    }
                }

                if !search.results.isEmpty {
                    Section("Places") {
                        ForEach(search.results, id: \.self) { result in
                            Button {
                                resolve(result)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title)
                                        .foregroundStyle(AppTheme.ink)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .disabled(isResolving)
                        }
                    }
                }
            }
            .labelStyle(.tile(AppTheme.coolAccent))
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Add Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if isResolving {
                    ToolbarItem(placement: .confirmationAction) {
                        ProgressView()
                    }
                }
            }
            .onAppear { isFieldFocused = true }
        }
    }

    private func choose(_ location: TaskLocation) {
        onPick(location)
        dismiss()
    }

    /// Looks the suggestion up for its address and coordinates.
    private func resolve(_ completion: MKLocalSearchCompletion) {
        isResolving = true
        Task {
            let fallback = TaskLocation(name: completion.title, address: completion.subtitle.isEmpty ? nil : completion.subtitle)
            do {
                let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start()
                if let item = response.mapItems.first {
                    let coordinate = item.placemark.coordinate
                    choose(TaskLocation(
                        name: item.name ?? completion.title,
                        address: fallback.address ?? item.placemark.title,
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude
                    ))
                } else {
                    choose(fallback)
                }
            } catch {
                // Offline or not found: keep the name and address shown in the suggestion.
                choose(fallback)
            }
            isResolving = false
        }
    }
}

/// Apple Maps search suggestions for what's typed so far. MapKit calls the delegate on the
/// main thread, which the preconcurrency conformance checks at runtime.
@MainActor
private final class PlaceSearch: NSObject, ObservableObject, @preconcurrency MKLocalSearchCompleterDelegate {
    @Published var query = "" {
        didSet { completer.queryFragment = query }
    }
    @Published private(set) var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = Array(completer.results.prefix(12))
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }
}
