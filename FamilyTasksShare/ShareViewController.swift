import SwiftUI
import UIKit

/// The share sheet's "Family Tasks" option: saves a link from YouTube, Instagram, X, Maps
/// or anywhere else to the family's Ideas, with its title and picture.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareIdeaModel { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        } onCancel: { [weak self] in
            self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        }
        let host = UIHostingController(rootView: ShareIdeaView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        Task { await model.load(from: items) }
    }
}

@MainActor
final class ShareIdeaModel: ObservableObject {
    @Published var draft = IdeaDraft()
    @Published var isLoading = true
    @Published var isSaved = false
    @Published var errorMessage: String?
    private var kindWasChosen = false
    private let onDone: () -> Void
    let onCancel: () -> Void

    init(onDone: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onDone = onDone
        self.onCancel = onCancel
    }

    func load(from items: [NSExtensionItem]) async {
        var url: URL?
        var texts: [String] = []
        for item in items {
            if let text = item.attributedContentText?.string, !text.isEmpty { texts.append(text) }
            for provider in item.attachments ?? [] {
                if url == nil, provider.canLoadObject(ofClass: URL.self), let found = await Self.loadURL(from: provider), !found.isFileURL {
                    url = found
                } else if provider.canLoadObject(ofClass: String.self), let text = await Self.loadText(from: provider) {
                    texts.append(text)
                }
            }
        }

        // Text often carries the link too, plus a name: "Balboa Park\nhttps://maps.app.goo.gl/…".
        let shared = SharedLinkText.split(texts.joined(separator: "\n"))
        url = url ?? shared.url
        let lines = shared.rest.split(separator: "\n").map(String.init)
        let textTitle = lines.first.map { $0.count > 120 ? String($0.prefix(119)) + "…" : $0 } ?? ""

        draft.link = url?.absoluteString ?? ""
        draft.title = textTitle
        if lines.count > 1 { draft.notes = lines.dropFirst().joined(separator: "\n") }
        if let url {
            let preview = await LinkPreview.fetch(url)
            // A page's own title beats the text an app sends along with the link.
            if !preview.title.isEmpty { draft.title = "" }
            draft.apply(preview)
            if draft.title.isEmpty { draft.title = textTitle }
            if !kindWasChosen {
                draft.kind = IdeaKind.guess(link: url, text: [draft.title, preview.summary, shared.rest].joined(separator: " "))
            }
            if draft.kind == .place, draft.location.isEmpty, lines.count > 1 {
                draft.location = lines[1]
            }
        } else if !kindWasChosen {
            draft.kind = IdeaKind.guess(link: nil, text: shared.rest)
        }
        isLoading = false
    }

    func choose(_ kind: IdeaKind) {
        draft.kind = kind
        kindWasChosen = true
    }

    func save() {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        guard let inbox = IdeaInbox.shared else {
            errorMessage = "Couldn't reach Family Tasks. Open the app once, then try again."
            return
        }
        var idea = IdeaNote(title: title)
        idea.notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        idea.link = draft.link.trimmingCharacters(in: .whitespacesAndNewlines)
        idea.kind = draft.kind
        idea.location = draft.kind == .place ? draft.location.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        idea.latitude = idea.location.isEmpty ? nil : draft.latitude
        idea.longitude = idea.location.isEmpty ? nil : draft.longitude
        idea.imageURL = draft.imageURL
        idea.siteName = draft.siteName
        do {
            try inbox.add(idea)
        } catch {
            errorMessage = "Couldn't save: \(error.localizedDescription)"
            return
        }
        withAnimation { isSaved = true }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            onDone()
        }
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                continuation.resume(returning: text)
            }
        }
    }
}

struct ShareIdeaView: View {
    @ObservedObject var model: ShareIdeaModel
    @FocusState private var focusedField: Field?

    private enum Field { case title, notes, location }

    var body: some View {
        NavigationStack {
            Form {
                if model.isLoading {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Getting the details…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    if model.isSaved {
                        Section {
                            Label("Saved to Ideas", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.green)
                        }
                    }
                    preview
                    Section {
                        TextField("What's the idea?", text: $model.draft.title, axis: .vertical)
                            .font(.headline)
                            .focused($focusedField, equals: .title)
                        TextField("Why save it? Who'd love it?", text: $model.draft.notes, axis: .vertical)
                            .lineLimit(1...5)
                            .focused($focusedField, equals: .notes)
                    }
                    Section("Kind") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(IdeaKind.allCases) { kind in
                                    kindChip(kind)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        if model.draft.kind == .place {
                            TextField("Place or address", text: $model.draft.location)
                                .textInputAutocapitalization(.words)
                                .focused($focusedField, equals: .location)
                        }
                    }
                    if let error = model.errorMessage {
                        Section {
                            Text(error)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("Save to Ideas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: model.onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { model.save() }
                        .fontWeight(.semibold)
                        .disabled(model.isLoading || model.isSaved || model.draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let image = URL(string: model.draft.imageURL), !model.draft.imageURL.isEmpty {
            Section {
                AsyncImage(url: image) { phase in
                    if let picture = phase.image {
                        picture.resizable().scaledToFill()
                    } else {
                        Color.secondary.opacity(0.15)
                    }
                }
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipped()
                .listRowInsets(EdgeInsets())
            } footer: {
                if !model.draft.siteName.isEmpty {
                    Text("From \(model.draft.siteName)")
                }
            }
        } else if let host = URL(string: model.draft.link)?.host() {
            Section {
                Label(host, systemImage: "link")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func kindChip(_ kind: IdeaKind) -> some View {
        let isSelected = model.draft.kind == kind
        return Button {
            model.choose(kind)
        } label: {
            Label(kind.title, systemImage: kind.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(isSelected ? Color.accentColor : Color.accentColor.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
