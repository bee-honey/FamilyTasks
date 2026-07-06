import SwiftUI

struct IdeaNotebookView: View {
    @EnvironmentObject private var organizerStore: OrganizerStore
    @State private var selectedTag = IdeaTagFilter.all
    @State private var searchText = ""
    @State private var showingAddIdea = false
    @State private var editingIdea: IdeaNote?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Tag", selection: $selectedTag) {
                        ForEach(tagFilters) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                }

                if filteredIdeas.isEmpty {
                    ContentUnavailableView(
                        "No Ideas Yet",
                        systemImage: "lightbulb",
                        description: Text("Save places, links, activities, and family finds here without dates or reminders.")
                    )
                    .listRowBackground(AppTheme.surface)
                } else {
                    Section("Ideas") {
                        ForEach(filteredIdeas) { idea in
                            IdeaNoteRow(idea: idea)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    editingIdea = idea
                                }
                        }
                        .onDelete(perform: deleteIdeas)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search ideas")
            .navigationTitle("Ideas")
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddIdea = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add idea")
                }
            }
            .sheet(isPresented: $showingAddIdea) {
                IdeaEditorView(mode: .add) { draft in
                    organizerStore.addIdea(draft)
                }
            }
            .sheet(item: $editingIdea) { idea in
                IdeaEditorView(mode: .edit(idea)) { draft in
                    organizerStore.updateIdea(idea, with: draft)
                }
            }
        }
    }

    private var allTags: [String] {
        IdeaNote.normalizedTags(organizerStore.ideaNotes.flatMap(\.tags))
    }

    private var tagFilters: [IdeaTagFilter] {
        [.all] + allTags.map { .tag($0) }
    }

    private var filteredIdeas: [IdeaNote] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return organizerStore.ideas(tag: selectedTag.tagValue)
            .filter { idea in
                guard !trimmedSearch.isEmpty else { return true }
                return idea.title.localizedCaseInsensitiveContains(trimmedSearch) ||
                    idea.notes.localizedCaseInsensitiveContains(trimmedSearch) ||
                    idea.link.localizedCaseInsensitiveContains(trimmedSearch) ||
                    idea.tags.contains { $0.localizedCaseInsensitiveContains(trimmedSearch) }
            }
    }

    private func deleteIdeas(at offsets: IndexSet) {
        for offset in offsets {
            guard filteredIdeas.indices.contains(offset) else { continue }
            organizerStore.deleteIdea(filteredIdeas[offset])
        }
    }
}

private struct IdeaNoteRow: View {
    let idea: IdeaNote

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(idea.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)
                Spacer()
                if idea.url != nil {
                    Image(systemName: "link")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                }
            }

            if !idea.notes.isEmpty {
                Text(idea.notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if let url = idea.url {
                Link(destination: url) {
                    Label(url.host() ?? idea.link, systemImage: "safari")
                        .font(.caption)
                        .lineLimit(1)
                }
            }

            if !idea.displayTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(idea.displayTags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(ideaTagColor(for: tag))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(ideaTagColor(for: tag).opacity(0.16), in: Capsule())
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(AppTheme.surface)
    }
}

private struct IdeaEditorView: View {
    enum Mode {
        case add
        case edit(IdeaNote)

        var title: String {
            switch self {
            case .add: "New Idea"
            case .edit: "Edit Idea"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var draft: IdeaDraft
    @State private var showingCustomTagField = false
    let mode: Mode
    let onSave: (IdeaDraft) -> Void

    init(mode: Mode, onSave: @escaping (IdeaDraft) -> Void) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .add:
            _draft = State(initialValue: IdeaDraft())
        case .edit(let idea):
            _draft = State(initialValue: IdeaDraft(note: idea))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Idea") {
                    TextField("Title", text: $draft.title)
                    TextField("Link", text: $draft.link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Tags") {
                    TagChipPicker(tags: tagChoices, selectedTags: $draft.tags) {
                        showingCustomTagField = true
                    }

                    if showingCustomTagField {
                        HStack {
                            TextField("Add tag", text: $draft.customTag)
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                                .onSubmit(addCustomTag)
                            Button("Add") {
                                addCustomTag()
                            }
                            .disabled(draft.customTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .navigationTitle(mode.title)
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var tagChoices: [String] {
        IdeaNote.normalizedTags(IdeaNote.suggestedTags + Array(draft.tags))
    }

    private func addCustomTag() {
        let trimmed = draft.customTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draft.tags.insert(trimmed)
        draft.customTag = ""
        showingCustomTagField = false
    }
}

private struct TagChipPicker: View {
    let tags: [String]
    @Binding var selectedTags: Set<String>
    let onAddTag: () -> Void

    var body: some View {
        FlowLayout(spacing: 8, rowSpacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Button {
                    toggle(tag)
                } label: {
                    Text(tag)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selectedTags.contains(tag) ? .white : ideaTagColor(for: tag))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(selectedTags.contains(tag) ? ideaTagColor(for: tag) : ideaTagColor(for: tag).opacity(0.16), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(selectedTags.contains(tag) ? "Remove \(tag) tag" : "Add \(tag) tag")
            }

            Button(action: onAddTag) {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.primary)
                    .frame(width: 30, height: 30)
                    .background(AppTheme.primarySoft, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add new tag")
        }
        .padding(.vertical, 4)
    }

    private func toggle(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

}


private func ideaTagColor(for tag: String) -> Color {
    let palette = AppTheme.avatarPalette + [AppTheme.warning, AppTheme.success, AppTheme.taskSchedule, AppTheme.taskDelegate, AppTheme.taskDo]
    let scalarTotal = tag.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    return palette[abs(scalarTotal) % palette.count]
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let rows = rows(in: width, subviews: subviews)
        return CGSize(width: width, height: rows.reduce(CGFloat(0)) { $0 + $1.height } + CGFloat(max(rows.count - 1, 0)) * rowSpacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(in: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for item in row.items {
                item.subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private func rows(in width: CGFloat, subviews: Subviews) -> [FlowRow] {
        guard !subviews.isEmpty else { return [] }
        var rows: [FlowRow] = []
        var currentItems: [FlowItem] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let nextWidth = currentItems.isEmpty ? size.width : currentWidth + spacing + size.width
            if !currentItems.isEmpty, nextWidth > width {
                rows.append(FlowRow(items: currentItems, height: currentHeight))
                currentItems = [FlowItem(subview: subview, size: size)]
                currentWidth = size.width
                currentHeight = size.height
            } else {
                currentItems.append(FlowItem(subview: subview, size: size))
                currentWidth = nextWidth
                currentHeight = max(currentHeight, size.height)
            }
        }

        if !currentItems.isEmpty {
            rows.append(FlowRow(items: currentItems, height: currentHeight))
        }
        return rows
    }

    private struct FlowItem {
        let subview: LayoutSubview
        let size: CGSize
    }

    private struct FlowRow {
        let items: [FlowItem]
        let height: CGFloat
    }
}

private enum IdeaTagFilter: Hashable, Identifiable {
    case all
    case tag(String)

    var id: String {
        switch self {
        case .all: "all"
        case .tag(let tag): "tag.\(tag)"
        }
    }

    var title: String {
        switch self {
        case .all: "All Tags"
        case .tag(let tag): tag
        }
    }

    var tagValue: String? {
        switch self {
        case .all: nil
        case .tag(let tag): tag
        }
    }
}
