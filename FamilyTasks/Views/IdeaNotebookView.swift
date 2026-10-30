import SwiftUI

/// The family's someday list: places to go, food to cook, things to do or watch, often
/// saved straight from another app's share sheet. Each can be marked done and rated, or
/// turned into a trip plan, a meal or a task when the time comes.
struct IdeaNotebookView: View {
    @EnvironmentObject private var organizerStore: OrganizerStore
    var isPushed = false
    @AppStorage("ideas.shareTipDismissed") private var shareTipDismissed = false
    @State private var kindFilter: IdeaKind?
    @State private var showsDone = false
    @State private var searchText = ""
    @State private var showingAddIdea = false
    @State private var openIdeaID: UUID?

    var body: some View {
        // Shown inside a tab's NavigationStack, or pushed from Family.
        List {
            Section {
                ScreenHeader(eyebrow: eyebrow, title: "Ideas") {
                    HeaderAddButton(accessibilityLabel: "Add idea") { showingAddIdea = true }
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 4))
            .listRowBackground(Color.clear)

            if !shareTipDismissed {
                Section {
                    ShareTipCard { withAnimation { shareTipDismissed = true } }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                .listRowBackground(Color.clear)
            }

            if !organizerStore.ideaNotes.isEmpty {
                Section {
                    filters
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                .listRowBackground(Color.clear)
            }

            if filteredIdeas.isEmpty {
                ContentUnavailableView(emptyTitle, systemImage: kindFilter?.systemImage ?? "lightbulb", description: Text(emptyMessage))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(filteredIdeas) { idea in
                        Button {
                            openIdeaID = idea.id
                        } label: {
                            IdeaCard(idea: idea)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(AppTheme.surface)
                        .swipeActions(edge: .leading) {
                            Button(idea.isDone ? "To Try" : idea.kind.doneTitle, systemImage: idea.isDone ? "arrow.uturn.backward" : "checkmark") {
                                organizerStore.setIdeaDone(idea, !idea.isDone)
                            }
                            .tint(AppTheme.success)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                organizerStore.deleteIdea(idea)
                            }
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        // Header at the same height on every tab.
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .background(AppTheme.background)
        .mainScreenNavigationBar(title: "Ideas", isPushed: isPushed)
        .navigationDestination(item: $openIdeaID) { ideaID in
            IdeaDetailView(ideaID: ideaID).backButton("Ideas")
        }
        .sheet(isPresented: $showingAddIdea) {
            IdeaEditorView(mode: .add) { draft in
                organizerStore.addIdea(draft)
            }
        }
        .task(id: ideasMissingPreviews.map(\.id)) {
            await IdeaPreviewFiller.fill(ideasMissingPreviews, store: organizerStore)
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search ideas", text: $searchText)
            }
            .padding(12)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Picker("Show", selection: $showsDone) {
                Text("To Try · \(organizerStore.ideaNotes.filter { !$0.isDone }.count)").tag(false)
                Text("Done · \(organizerStore.ideaNotes.filter(\.isDone).count)").tag(true)
            }
            .pickerStyle(.segmented)

            if usedKinds.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ChoiceChip(title: "All", isSelected: kindFilter == nil) { kindFilter = nil }
                        ForEach(usedKinds) { kind in
                            ChoiceChip(title: kind.pluralTitle, isSelected: kindFilter == kind) {
                                kindFilter = kindFilter == kind ? nil : kind
                            }
                        }
                    }
                }
            }
        }
    }

    private var eyebrow: String {
        let toTry = organizerStore.ideaNotes.filter { !$0.isDone }.count
        let done = organizerStore.ideaNotes.count - toTry
        if organizerStore.ideaNotes.isEmpty { return "Someday list" }
        return done == 0 ? "\(toTry) to try" : "\(toTry) to try · \(done) done"
    }

    private var usedKinds: [IdeaKind] {
        IdeaKind.allCases.filter { kind in organizerStore.ideaNotes.contains { $0.kind == kind } }
    }

    private var filteredIdeas: [IdeaNote] {
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return organizerStore.ideaNotes
            .filter { $0.isDone == showsDone }
            .filter { kindFilter == nil || $0.kind == kindFilter }
            .filter { idea in
                guard !search.isEmpty else { return true }
                return [idea.title, idea.notes, idea.link, idea.location, idea.siteName, idea.doneNote]
                    .contains { $0.localizedCaseInsensitiveContains(search) }
                    || idea.tags.contains { $0.localizedCaseInsensitiveContains(search) }
            }
            .sorted { lhs, rhs in
                showsDone ? (lhs.doneAt ?? lhs.updatedAt) > (rhs.doneAt ?? rhs.updatedAt) : lhs.createdAt > rhs.createdAt
            }
    }

    /// Links saved without a picture yet, such as ones shared while offline.
    private var ideasMissingPreviews: [IdeaNote] {
        organizerStore.ideaNotes.filter { $0.url != nil && $0.imageURL.isEmpty && $0.siteName.isEmpty }
    }

    private var emptyTitle: String {
        if organizerStore.ideaNotes.isEmpty { return "No Ideas Yet" }
        if !searchText.isEmpty { return "No Matches" }
        return showsDone ? "Nothing Done Yet" : "All Done"
    }

    private var emptyMessage: String {
        if organizerStore.ideaNotes.isEmpty {
            return "Save places to visit, food to cook and things to do. Share them from YouTube, Instagram, X, Maps or Safari, or tap + to add one."
        }
        if !searchText.isEmpty { return "Try another search." }
        return showsDone ? "Mark an idea done once you've been, cooked it or watched it, and rate how it went." : "Everything on the list has been tried. Time to save some more."
    }
}

/// Explains saving from other apps until dismissed.
private struct ShareTipCard: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(systemImage: "square.and.arrow.up", tint: AppTheme.coolAccent, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text("Save from any app")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text("Seen a place or recipe on YouTube, Instagram or X? Tap Share, then Family Tasks. (Not listed? Tap More in the app row.)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.surfaceMuted, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss tip")
        }
        .padding(14)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct IdeaCard: View {
    let idea: IdeaNote

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IdeaThumbnail(idea: idea, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(idea.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text("\(Image(systemName: idea.kind.systemImage)) \(detailLine)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ideaKindTint(idea.kind))
                    .lineLimit(1)
                if idea.isDone, let rating = idea.rating {
                    StarRatingView(rating: rating, size: 11)
                }
                let note = idea.isDone && !idea.doneNote.isEmpty ? idea.doneNote : idea.notes
                if !note.isEmpty {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if !idea.addedBy.isEmpty {
                    Text("Saved by \(Assignee.memberName(for: idea.addedBy))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var detailLine: String {
        if idea.isDone, let doneAt = idea.doneAt {
            return "\(idea.kind.doneTitle) \(doneAt.formatted(.dateTime.month(.abbreviated).day()))"
        }
        if idea.kind == .place, !idea.location.isEmpty, idea.location != idea.title {
            return idea.location
        }
        return idea.sourceName ?? idea.kind.title
    }
}

/// The link's picture, or the kind's icon.
struct IdeaThumbnail: View {
    let idea: IdeaNote
    let size: CGFloat
    var height: CGFloat?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: min(size, height ?? size) * 0.2, style: .continuous)
        Group {
            if let image = idea.image {
                AsyncImage(url: image) { phase in
                    if let picture = phase.image {
                        picture.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: height ?? size)
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            ideaKindTint(idea.kind).opacity(0.16)
            Image(systemName: idea.kind.systemImage)
                .font(.system(size: min(size, height ?? size) * 0.4, weight: .semibold))
                .foregroundStyle(ideaKindTint(idea.kind))
        }
    }
}

struct StarRatingView: View {
    let rating: Int
    var size: CGFloat = 14
    var onChange: ((Int?) -> Void)?

    var body: some View {
        HStack(spacing: size * 0.3) {
            ForEach(1...5, id: \.self) { star in
                let image = Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(star <= rating ? AppTheme.goldAccent : Color.secondary.opacity(0.5))
                if let onChange {
                    Button {
                        onChange(star == rating ? nil : star)
                    } label: {
                        image.frame(minWidth: 36, minHeight: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(star) \(star == 1 ? "star" : "stars")")
                    .accessibilityAddTraits(star == rating ? .isSelected : [])
                } else {
                    image
                }
            }
        }
        .accessibilityElement(children: onChange == nil ? .ignore : .contain)
        .accessibilityLabel(onChange == nil ? "\(rating) of 5 stars" : "Rating")
    }
}

func ideaKindTint(_ kind: IdeaKind) -> Color {
    switch kind {
    case .place: AppTheme.coolAccent
    case .food: AppTheme.brightAccent
    case .activity: AppTheme.warmAccent
    case .watch: AppTheme.taskDelegate
    case .other: AppTheme.goldAccent
    }
}

/// Looks up pictures for links saved without one, once per app run.
@MainActor
enum IdeaPreviewFiller {
    private static var tried = Set<UUID>()

    static func fill(_ ideas: [IdeaNote], store: OrganizerStore) async {
        for idea in ideas.prefix(6) where !tried.contains(idea.id) {
            tried.insert(idea.id)
            guard let url = idea.url else { continue }
            let preview = await LinkPreview.fetch(url)
            guard !Task.isCancelled else { return }
            if !preview.isEmpty { store.applyPreview(preview, to: idea.id) }
        }
    }
}

// MARK: Detail

/// One idea: its picture and link, what it can become (a trip plan, a meal, a task), and
/// how it went once done.
private struct IdeaDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var organizerStore: OrganizerStore
    @EnvironmentObject private var tripStore: TripStore
    let ideaID: UUID

    @State private var isEditing = false
    @State private var isAddingToTrip = false
    @State private var taskDraft: IdeaTaskDraft?
    @State private var doneNote = ""

    var body: some View {
        Group {
            if let idea = organizerStore.ideaNotes.first(where: { $0.id == ideaID }) {
                content(idea)
            } else {
                ContentUnavailableView("Idea Deleted", systemImage: "lightbulb", description: Text("Someone in the family deleted this idea."))
            }
        }
        .background(AppTheme.background)
    }

    private func content(_ idea: IdeaNote) -> some View {
        List {
            Section {
                header(idea)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 4, trailing: 4))
            .listRowBackground(Color.clear)

            Section {
                actions(idea)
            } header: {
                SectionTitle(text: "Make It Happen")
            }
            .listRowBackground(AppTheme.surface)

            doneSection(idea)

            if !idea.displayTags.isEmpty {
                Section {
                    FlowLayout(spacing: 6, rowSpacing: 6) {
                        ForEach(idea.displayTags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ideaTagColor(for: tag))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(ideaTagColor(for: tag).opacity(0.16), in: Capsule())
                        }
                    }
                } header: {
                    SectionTitle(text: "Tags")
                }
                .listRowBackground(AppTheme.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(idea.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ShareLink(item: shareText(idea)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                Button("Edit", systemImage: "pencil") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            IdeaEditorView(mode: .edit(idea)) { draft in
                organizerStore.updateIdea(idea, with: draft)
            } onDelete: {
                organizerStore.deleteIdea(idea)
                dismiss()
            }
        }
        .sheet(isPresented: $isAddingToTrip) {
            AddIdeaToTripView(idea: idea)
        }
        .sheet(item: $taskDraft) { draft in
            TaskEditorView(mode: .prefilled(draft.draft, due: .weekend))
        }
        .onAppear { doneNote = idea.doneNote }
    }

    private func header(_ idea: IdeaNote) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if idea.image != nil {
                GeometryReader { proxy in
                    IdeaThumbnail(idea: idea, size: proxy.size.width, height: 200)
                }
                .frame(height: 200)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("\(Image(systemName: idea.kind.systemImage)) \(idea.kind.title.uppercased())")
                    .font(.footnote.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(ideaKindTint(idea.kind))
                Text(idea.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                    .accessibilityAddTraits(.isHeader)
                if !idea.addedBy.isEmpty {
                    Text("Saved by \(Assignee.memberName(for: idea.addedBy)) · \(idea.createdAt.formatted(.dateTime.month(.abbreviated).day().year()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let url = idea.url {
                Button {
                    openURL(url)
                } label: {
                    Label("Open \(idea.sourceName ?? "Link")", systemImage: "arrow.up.right.square")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
            }
            if !idea.notes.isEmpty {
                Text(idea.notes)
                    .font(.subheadline)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private func actions(_ idea: IdeaNote) -> some View {
        switch idea.kind {
        case .place:
            Menu {
                MapsMenuItems(query: idea.mapQuery)
            } label: {
                actionLabel("Open in Maps", detail: idea.location.isEmpty ? nil : idea.location, systemImage: "map")
            }
            if !tripStore.upcomingTrips.isEmpty {
                Button {
                    isAddingToTrip = true
                } label: {
                    actionLabel("Add to a Trip", detail: "Put it on a day of an upcoming trip", systemImage: "suitcase.rolling")
                }
            }
        case .food:
            if isInYourMeals(idea) {
                actionLabel("In Your Meals", detail: "Plan it from the Meal Plan", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    addToMeals(idea)
                } label: {
                    actionLabel("Add to Your Meals", detail: "So it can go on the meal plan", systemImage: "fork.knife")
                }
            }
        case .activity, .watch, .other:
            EmptyView()
        }
        Button {
            taskDraft = IdeaTaskDraft(idea: idea)
        } label: {
            actionLabel("Schedule It", detail: "Make it a task with a day and reminder", systemImage: "calendar.badge.plus")
        }
    }

    private func actionLabel(_ title: String, detail: String?, systemImage: String) -> some View {
        HStack(spacing: 12) {
            IconTile(systemImage: systemImage, tint: AppTheme.primary, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func doneSection(_ idea: IdeaNote) -> some View {
        Section {
            if let doneAt = idea.doneAt {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(idea.kind.doneTitle) \(doneAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.success)
                    StarRatingView(rating: idea.rating ?? 0, size: 22) { stars in
                        organizerStore.rateIdea(idea, stars: stars)
                    }
                }
                TextField("How was it? Worth going back?", text: $doneNote, axis: .vertical)
                    .lineLimit(1...5)
                    .onSubmit { organizerStore.setIdeaDoneNote(idea, doneNote) }
                    .onChange(of: doneNote) { _, note in
                        organizerStore.setIdeaDoneNote(idea, note)
                    }
                Button("Move Back to To Try", systemImage: "arrow.uturn.backward") {
                    organizerStore.setIdeaDone(idea, false)
                }
                .font(.subheadline)
            } else {
                Button {
                    organizerStore.setIdeaDone(idea, true)
                } label: {
                    Label(idea.kind.markDoneTitle, systemImage: "checkmark.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.onPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(AppTheme.success, in: Capsule())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            }
        } header: {
            if idea.isDone { SectionTitle(text: "How It Went") }
        }
        .listRowBackground(AppTheme.surface)
    }

    private func isInYourMeals(_ idea: IdeaNote) -> Bool {
        organizerStore.mealIdeas.contains { $0.name.caseInsensitiveCompare(idea.title) == .orderedSame }
    }

    private func addToMeals(_ idea: IdeaNote) {
        let notes = [idea.notes, idea.link].filter { !$0.isEmpty }.joined(separator: "\n")
        organizerStore.addMealIdea(name: idea.title, category: .mainCourse, ingredients: [], notes: notes)
        ToastCenter.shared.show("Added \(idea.title) to Your Meals", systemImage: "fork.knife", actionTitle: "Meal Plan") {
            AppNavigator.shared.open(.section(.mealPlan))
        }
    }

    private func shareText(_ idea: IdeaNote) -> String {
        [idea.title, idea.kind == .place ? idea.location : "", idea.notes, idea.link]
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { lines, line in if !lines.contains(line) { lines.append(line) } }
            .joined(separator: "\n")
    }
}

/// A task started from an idea: "Visit Balboa Park", with the link in its notes.
private struct IdeaTaskDraft: Identifiable {
    let id = UUID()
    let draft: TaskDraft

    init(idea: IdeaNote) {
        var draft = TaskDraft()
        switch idea.kind {
        case .place: draft.title = "Visit \(idea.title)"
        case .food: draft.title = "Cook \(idea.title)"
        case .watch: draft.title = "Watch \(idea.title)"
        case .activity, .other: draft.title = idea.title
        }
        draft.notes = [idea.notes, idea.link].filter { !$0.isEmpty }.joined(separator: "\n")
        draft.isUrgent = false
        draft.isImportant = true
        if idea.kind == .place, !idea.location.isEmpty {
            draft.location = TaskLocation(name: idea.location, latitude: idea.latitude, longitude: idea.longitude)
        }
        self.draft = draft
    }
}

/// Puts a place on one day of an upcoming trip's plan.
private struct AddIdeaToTripView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tripStore: TripStore
    let idea: IdeaNote

    @State private var tripID: UUID?
    @State private var day: Date?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Trip", selection: $tripID) {
                        ForEach(tripStore.upcomingTrips) { trip in
                            Text(trip.displayName).tag(Optional(trip.id))
                        }
                    }
                    if let trip = selectedTrip {
                        Picker("Day", selection: $day) {
                            ForEach(Array(trip.days().enumerated()), id: \.element) { index, tripDay in
                                Text("Day \(index + 1) · \(tripDay.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))").tag(Optional(tripDay))
                            }
                        }
                    }
                } footer: {
                    Text("“\(idea.title)” goes on that day's plan as an any-time plan. Set a time from the trip.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Add to a Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }
                        .fontWeight(.semibold)
                        .disabled(selectedTrip == nil || day == nil)
                }
            }
            .onAppear {
                guard tripID == nil, let first = tripStore.upcomingTrips.first else { return }
                tripID = first.id
                day = first.days().first
            }
            .onChange(of: tripID) { _, _ in
                if let trip = selectedTrip, !(day.map { trip.days().contains($0) } ?? false) {
                    day = trip.days().first
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var selectedTrip: Trip? {
        tripID.flatMap(tripStore.trip(id:))
    }

    private func add() {
        guard let trip = selectedTrip, let day else { return }
        tripStore.addActivity(TripActivity(
            tripID: trip.id,
            title: idea.title,
            date: day,
            location: idea.location.isEmpty ? idea.title : idea.location,
            notes: [idea.notes, idea.link].filter { !$0.isEmpty }.joined(separator: "\n")
        ))
        ToastCenter.shared.show("Added to \(trip.displayName)", systemImage: "suitcase.rolling")
        dismiss()
    }
}

// MARK: Editor

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
    @State private var isFetchingPreview = false
    @State private var lookedUpLink: String
    @State private var kindWasChosen: Bool
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isLocationFocused: Bool
    @StateObject private var placeSearch = TripPlaceSearch()
    let mode: Mode
    let onSave: (IdeaDraft) -> Void
    let onDelete: (() -> Void)?

    init(mode: Mode, onSave: @escaping (IdeaDraft) -> Void, onDelete: (() -> Void)? = nil) {
        self.mode = mode
        self.onSave = onSave
        self.onDelete = onDelete
        switch mode {
        case .add:
            _draft = State(initialValue: IdeaDraft())
            _lookedUpLink = State(initialValue: "")
            _kindWasChosen = State(initialValue: false)
        case .edit(let idea):
            _draft = State(initialValue: IdeaDraft(note: idea))
            _lookedUpLink = State(initialValue: idea.link)
            _kindWasChosen = State(initialValue: true)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    linkSection

                    VStack(alignment: .leading, spacing: 8) {
                        TextField("What's the idea?", text: $draft.title, axis: .vertical)
                            .font(.title2.weight(.bold))
                            .focused($isTitleFocused)
                        TextField("Why save it? Who'd love it?", text: $draft.notes, axis: .vertical)
                            .foregroundStyle(.secondary)
                            .lineLimit(1...8)
                    }

                    EditorSection("Kind") {
                        FlowLayout(spacing: 8, rowSpacing: 8) {
                            ForEach(IdeaKind.allCases) { kind in
                                Button {
                                    draft.kind = kind
                                    kindWasChosen = true
                                } label: {
                                    Label(kind.title, systemImage: kind.systemImage)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(draft.kind == kind ? AppTheme.onAvatar : ideaKindTint(kind))
                                        .padding(.horizontal, 14)
                                        .frame(minHeight: 36)
                                        .background(draft.kind == kind ? ideaKindTint(kind) : ideaKindTint(kind).opacity(0.16), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(draft.kind == kind ? .isSelected : [])
                            }
                        }
                    }

                    if draft.kind == .place {
                        placeSection
                    }

                    EditorSection("Tags") {
                        TagChipPicker(tags: tagChoices, selectedTags: $draft.tags) {
                            showingCustomTagField = true
                        }

                        if showingCustomTagField {
                            HStack {
                                TextField("New tag", text: $draft.customTag)
                                    .textInputAutocapitalization(.words)
                                    .submitLabel(.done)
                                    .onSubmit(addCustomTag)
                                Button("Add") {
                                    addCustomTag()
                                }
                                .fontWeight(.semibold)
                                .disabled(draft.customTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            .padding(12)
                            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }

                    if let onDelete {
                        EditorDeleteButton(title: "Delete Idea", message: "It's removed for everyone in the family.") {
                            onDelete()
                            dismiss()
                        }
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppTheme.background)
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isAdding ? "Add" : "Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task(id: draft.link) { await lookUpLink() }
        }
    }

    private var linkSection: some View {
        EditorSection("Link") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    IconTile(systemImage: "link", tint: AppTheme.coolAccent, size: 36)
                    TextField("Paste a YouTube, Instagram or map link", text: $draft.link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if isFetchingPreview {
                        ProgressView()
                    } else if draft.link.isEmpty {
                        PasteButton(payloadType: String.self) { strings in
                            guard let text = strings.first else { return }
                            Task { @MainActor in paste(text) }
                        }
                        .labelStyle(.iconOnly)
                        .buttonBorderShape(.capsule)
                    }
                }
                .padding(10)
                .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if !draft.imageURL.isEmpty || !draft.siteName.isEmpty {
                    HStack(spacing: 10) {
                        IdeaThumbnail(idea: IdeaNote(title: draft.title, kind: draft.kind, imageURL: draft.imageURL), size: 44)
                        Text(draft.siteName.isEmpty ? "Preview found" : "From \(draft.siteName)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Remove Picture") {
                            draft.imageURL = ""
                        }
                        .font(.footnote)
                        .disabled(draft.imageURL.isEmpty)
                    }
                }
            }
        }
    }

    private var placeSection: some View {
        EditorSection("Where") {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    IconTile(systemImage: "mappin.and.ellipse", tint: AppTheme.coolAccent, size: 36)
                    TextField("Place or address", text: $draft.location)
                        .textInputAutocapitalization(.words)
                        .focused($isLocationFocused)
                        .onChange(of: draft.location) { _, text in
                            if isLocationFocused {
                                draft.latitude = nil
                                draft.longitude = nil
                                placeSearch.search(text)
                            }
                        }
                }
                .padding(10)
                if isLocationFocused {
                    ForEach(placeSearch.suggestions) { suggestion in
                        Divider().padding(.leading, 56)
                        Button {
                            draft.location = suggestion.subtitle.isEmpty ? suggestion.title : "\(suggestion.title), \(suggestion.subtitle)"
                            if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { draft.title = suggestion.title }
                            placeSearch.clear()
                            isLocationFocused = false
                        } label: {
                            PlaceSuggestionRow(suggestion: suggestion)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    /// Pasted text may be a bare link or a post with a link in it.
    private func paste(_ text: String) {
        let (url, rest) = SharedLinkText.split(text)
        if let url {
            draft.link = url.absoluteString
            if draft.title.isEmpty, let firstLine = rest.split(separator: "\n").first {
                draft.title = String(firstLine)
            }
        } else if draft.title.isEmpty {
            draft.title = rest
        }
    }

    /// Fills in the title, picture and kind from a newly entered link.
    private func lookUpLink() async {
        let link = draft.link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard link != lookedUpLink, let url = IdeaNote(title: "", link: link).url, url.host()?.contains(".") == true else { return }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        isFetchingPreview = true
        let preview = await LinkPreview.fetch(url)
        isFetchingPreview = false
        guard !Task.isCancelled else { return }
        lookedUpLink = link
        // A different link brings its own picture.
        draft.imageURL = ""
        draft.siteName = ""
        draft.apply(preview)
        if !kindWasChosen {
            draft.kind = IdeaKind.guess(link: url, text: [preview.title, preview.summary].joined(separator: " "))
        }
    }

    private var isAdding: Bool {
        if case .add = mode { return true }
        return false
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
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selectedTags.contains(tag) ? AppTheme.onAvatar : ideaTagColor(for: tag))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(selectedTags.contains(tag) ? ideaTagColor(for: tag) : ideaTagColor(for: tag).opacity(0.16), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(selectedTags.contains(tag) ? "Remove \(tag) tag" : "Add \(tag) tag")
            }

            Button(action: onAddTag) {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.primary)
                    .frame(width: 36, height: 36)
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
