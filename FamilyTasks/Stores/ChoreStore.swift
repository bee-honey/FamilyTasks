import Foundation

@MainActor
final class ChoreStore: ObservableObject {
    /// The app-wide store, shared with family sharing so there is only one copy in memory.
    static let shared = ChoreStore()

    @Published private(set) var kids: [KidProfile] = [] {
        didSet { recordRemovals(from: oldValue, to: kids); save() }
    }
    @Published private(set) var chores: [Chore] = [] {
        didSet { recordRemovals(from: oldValue, to: chores); save() }
    }
    @Published private(set) var completions: [ChoreCompletion] = [] {
        didSet { recordRemovals(from: oldValue, to: completions); save() }
    }
    @Published private(set) var payouts: [ChorePayout] = [] {
        didSet { recordRemovals(from: oldValue, to: payouts); save() }
    }
    @Published private(set) var settings = ChoreSettings() {
        didSet { save() }
    }

    private let storageURL: URL
    private var isLoading = false
    private var isApplyingSharedData = false

    init(directory: URL? = nil) {
        storageURL = (directory ?? URL.documentsDirectory).appendingPathComponent("family-chores.json")
        load()
    }

    // MARK: Kids

    func addKid(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        kids.append(KidProfile(name: trimmed))
    }

    func renameKid(_ kid: KidProfile, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = kids.firstIndex(where: { $0.id == kid.id }) else { return }
        kids[index].name = trimmed
        kids[index].updatedAt = Date()
    }

    /// Removes the kid, their chore assignments and their points history.
    func deleteKid(_ kid: KidProfile) {
        let now = Date()
        chores = chores.map { chore in
            guard chore.kidIDs.contains(kid.id) else { return chore }
            var changed = chore
            changed.kidIDs.removeAll { $0 == kid.id }
            changed.updatedAt = now
            return changed
        }
        completions.removeAll { $0.kidID == kid.id }
        payouts.removeAll { $0.kidID == kid.id }
        kids.removeAll { $0.id == kid.id }
    }

    // MARK: Chores

    func addChore(title: String, points: Int, frequency: RecurrenceFrequency, kidIDs: [UUID]) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        chores.append(Chore(title: trimmed, points: max(points, 1), frequency: frequency, kidIDs: kidIDs))
    }

    func updateChore(_ chore: Chore, title: String, points: Int, frequency: RecurrenceFrequency, kidIDs: [UUID]) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = chores.firstIndex(where: { $0.id == chore.id }) else { return }
        var changed = chores[index]
        changed.title = trimmed
        changed.points = max(points, 1)
        changed.frequency = frequency
        changed.kidIDs = kidIDs
        changed.updatedAt = Date()
        chores[index] = changed
    }

    /// Deleting a chore keeps the points already earned for it.
    func deleteChore(_ chore: Chore) {
        chores.removeAll { $0.id == chore.id }
        completions.removeAll { $0.choreID == chore.id && $0.status == .waitingForApproval }
    }

    func status(of chore: Chore, for kid: KidProfile, now: Date = Date()) -> ChoreStatus {
        ChoreMath.status(of: chore, for: kid.id, completions: completions, now: now)
    }

    func chores(for kid: KidProfile) -> [Chore] {
        chores.filter { $0.kidIDs.contains(kid.id) }
    }

    // MARK: Completing and approving

    /// Marks a chore done for a kid; it earns points once a parent approves it.
    func markDone(_ chore: Chore, for kid: KidProfile, at date: Date = Date()) {
        guard status(of: chore, for: kid, now: date) == .toDo else { return }
        completions.append(ChoreCompletion(
            choreID: chore.id,
            kidID: kid.id,
            choreTitle: chore.title,
            points: chore.points,
            markedBy: Self.currentProfileEmail(),
            completedAt: date,
            updatedAt: date
        ))
    }

    func approve(_ completion: ChoreCompletion, at date: Date = Date()) {
        guard let index = completions.firstIndex(where: { $0.id == completion.id }),
              completions[index].status == .waitingForApproval else { return }
        var changed = completions[index]
        changed.status = .approved
        changed.approvedBy = Self.currentProfileEmail()
        changed.approvedAt = date
        changed.updatedAt = date
        completions[index] = changed
    }

    /// "Not done": the chore goes back on the kid's list with no points.
    func reject(_ completion: ChoreCompletion) {
        completions.removeAll { $0.id == completion.id }
    }

    var waitingForApproval: [ChoreCompletion] {
        completions
            .filter { $0.status == .waitingForApproval }
            .sorted { $0.completedAt < $1.completedAt }
    }

    // MARK: Points

    func balance(for kid: KidProfile) -> Int {
        ChoreMath.balance(for: kid.id, completions: completions, payouts: payouts)
    }

    func payOut(_ points: Int, to kid: KidProfile) {
        guard points > 0 else { return }
        payouts.append(ChorePayout(kidID: kid.id, points: points, paidBy: Self.currentProfileEmail()))
    }

    func setPointsPerCurrencyUnit(_ points: Int) {
        guard points > 0, points != settings.pointsPerCurrencyUnit else { return }
        settings = ChoreSettings(pointsPerCurrencyUnit: points, updatedAt: Date())
    }

    // MARK: Family sharing

    func exportPayload() -> ChoresPayload {
        ChoresPayload(kids: kids, chores: chores, completions: completions, payouts: payouts, settings: settings)
    }

    /// Only assigns what changed, so a sync with nothing new does not rewrite files or redraw views.
    func applySharedData(_ payload: ChoresPayload) {
        isApplyingSharedData = true
        if kids != payload.kids { kids = payload.kids }
        if chores != payload.chores { chores = payload.chores }
        if completions != payload.completions { completions = payload.completions }
        if payouts != payload.payouts { payouts = payload.payouts }
        if settings != payload.settings { settings = payload.settings }
        isApplyingSharedData = false
    }

    // MARK: Storage

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        guard let payload = try? JSONDecoder().decode(ChoresPayload.self, from: data) else {
            PersistenceBackup.preserveUnreadableFile(at: storageURL)
            return
        }
        isLoading = true
        kids = payload.kids
        chores = payload.chores
        completions = payload.completions
        payouts = payload.payouts
        settings = payload.settings
        isLoading = false
    }

    private func save() {
        guard !isLoading else { return }
        guard let data = try? JSONEncoder().encode(exportPayload()) else { return }
        try? data.write(to: storageURL, options: [.atomic])
        if !isApplyingSharedData {
            NotificationCenter.default.post(name: .familyDataDidChange, object: self)
        }
    }

    private func recordRemovals<Item: SyncMergeable>(from oldItems: [Item], to newItems: [Item]) {
        guard !isApplyingSharedData, !isLoading else { return }
        SyncLedger.shared.recordRemovals(from: oldItems, to: newItems)
    }

    private static func currentProfileEmail() -> String {
        (UserDefaults.standard.string(forKey: "profile.email") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
