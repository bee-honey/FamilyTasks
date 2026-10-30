import SwiftUI

/// The header every main screen starts with, like Today's: a small colored line over a big
/// title, and the screen's actions on the right.
struct ScreenHeader<Actions: View>: View {
    let eyebrow: String
    let title: String
    @ViewBuilder let actions: Actions

    init(eyebrow: String, title: String, @ViewBuilder actions: () -> Actions = { EmptyView() }) {
        self.eyebrow = eyebrow
        self.title = title
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow.uppercased())
                    .font(.footnote.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(AppTheme.primary)
                    .lineLimit(1)
                Text(title)
                    .font(.title.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                actions
            }
        }
    }
}

/// The round "+" in a screen header.
struct HeaderAddButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HeaderAddLabel()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// The look of the header "+", for use as a Menu's label.
struct HeaderAddLabel: View {
    var body: some View {
        Image(systemName: "plus")
            .font(.title3.weight(.bold))
            .foregroundStyle(AppTheme.onPrimary)
            .frame(width: 44, height: 44)
            .background(AppTheme.primary, in: Circle())
    }
}

/// A labeled action, so nothing in a header is an icon you have to guess.
struct PillButtonLabel: View {
    let title: String
    let systemImage: String
    var badge = 0
    var isProminent = false
    var fillsWidth = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(1)
            if badge > 0 {
                Text("\(badge)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isProminent ? AppTheme.primary : AppTheme.onPrimary)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(isProminent ? AppTheme.onPrimary : AppTheme.primary, in: Capsule())
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(isProminent ? AppTheme.onPrimary : AppTheme.ink)
        .padding(.horizontal, 14)
        .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 44)
        .background(isProminent ? AppTheme.primary : AppTheme.surface, in: Capsule())
    }
}

extension View {
    /// A main screen draws its own header. As a tab it hides the system bar; pushed from
    /// Family it keeps the bar for the back button, without repeating the title.
    func mainScreenNavigationBar(title: String, isPushed: Bool) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(isPushed ? .visible : .hidden, for: .navigationBar)
            .toolbar {
                if isPushed {
                    ToolbarItem(placement: .principal) {
                        Color.clear.frame(width: 1, height: 1)
                    }
                }
            }
    }
}

extension View {
    /// The back button names the screen it goes back to ("‹ More"), where iOS would
    /// otherwise show only a chevron.
    func backButton(_ title: String) -> some View {
        modifier(NamedBackButton(title: title))
    }
}

private struct NamedBackButton: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    let title: String

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .fontWeight(.semibold)
                            Text(title)
                        }
                    }
                    .accessibilityLabel("Back to \(title)")
                }
            }
    }
}

/// Hiding the system back button also turns off swipe-to-go-back; this keeps it.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}

// MARK: Confirmations

/// A short message after an action that changes another screen ("12 items added to
/// Shopping"), with an optional button to go there.
struct Toast: Identifiable {
    let id = UUID()
    let message: String
    let systemImage: String
    let actionTitle: String?
    let action: (@MainActor () -> Void)?
}

@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    @Published private(set) var current: Toast?

    func show(_ message: String, systemImage: String = "checkmark.circle.fill", actionTitle: String? = nil, action: (@MainActor () -> Void)? = nil) {
        let toast = Toast(message: message, systemImage: systemImage, actionTitle: actionTitle, action: action)
        withAnimation(.spring(duration: 0.35)) { current = toast }
        Task {
            try? await Task.sleep(for: .seconds(action == nil ? 3 : 5))
            if current?.id == toast.id { dismiss() }
        }
    }

    func dismiss() {
        withAnimation(.easeOut(duration: 0.25)) { current = nil }
    }
}

struct ToastView: View {
    let toast: Toast
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.systemImage)
                .font(.title3)
                .foregroundStyle(AppTheme.success)
            Text(toast.message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let title = toast.actionTitle, let action = toast.action {
                Button(title) {
                    onDismiss()
                    action()
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: Going to a section

/// Opens a section wherever it lives: its tab if it has one, otherwise inside More.
@MainActor
final class AppNavigator: ObservableObject {
    static let shared = AppNavigator()

    @Published var request: FamilyDestination?

    func open(_ destination: FamilyDestination) {
        request = destination
    }
}

/// Everything the More tab can open.
enum FamilyDestination: Hashable {
    case section(TabSection)
}

/// The red Delete at the bottom of an editor, so deleting doesn't depend on knowing to swipe.
struct EditorDeleteButton: View {
    let title: String
    let message: String
    let action: () -> Void
    @State private var isConfirming = false

    var body: some View {
        Button(role: .destructive) {
            isConfirming = true
        } label: {
            Label(title, systemImage: "trash")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(AppTheme.destructive.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.destructive)
        .confirmationDialog(title + "?", isPresented: $isConfirming, titleVisibility: .visible) {
            Button(title, role: .destructive, action: action)
        } message: {
            Text(message)
        }
    }
}
