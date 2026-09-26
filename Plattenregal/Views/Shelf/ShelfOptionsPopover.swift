import SwiftUI
import SwiftData

/// What the shelf page shows as locked while (un)locking animates.
///
/// Saving a shelf makes the whole shelf page recompute (statistics, range
/// labels over every copy); doing that mid-animation stutters. So the menu
/// only flips this small observable, which just the compartments read, and the
/// store is written once the animation is over. Afterwards the entry is
/// dropped and the compartment reads the (now equal) model value again.
@MainActor @Observable
final class ShelfLockPreview {
    private var overrides: [UUID: Bool] = [:]

    func isLocked(_ shelf: Shelf) -> Bool { overrides[shelf.id] ?? shelf.isReserved }
    func set(_ locked: Bool, for shelf: Shelf) { overrides[shelf.id] = locked }
    func clear(_ shelf: Shelf) { overrides[shelf.id] = nil }
}

/// Builds its content from a shelf's locked state as `ShelfLockPreview` sees
/// it. Only this small view observes the preview, so flipping the switch
/// re-renders just these bits, not the whole shelf page.
struct ShelfLockReader<Content: View>: View {
    let shelf: Shelf
    let preview: ShelfLockPreview
    @ViewBuilder let content: (Bool) -> Content

    var body: some View {
        let locked = preview.isLocked(shelf)
        content(locked)
            .animation(AppStyle.standardAnimation, value: locked)
    }
}

/// "Namen ändern …" in a locked compartment's menu: the name shown on it
/// instead of the range (e.g. "Plattenspieler"). Saved on Return and when
/// the popover closes.
struct ShelfNamePopover: View {
    let shelf: Shelf
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    // Seeded up front, not in onAppear, so the popover opens in its final state.
    @State private var name: String
    @State private var error: String?
    @FocusState private var focused: Bool

    init(shelf: Shelf) {
        self.shelf = shelf
        _name = State(initialValue: shelf.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.itemSpacing) {
            Text("Name des gesperrten Fachs").font(.callout.weight(.medium))
            AppSearchField(placeholder: "z. B. Plattenspieler", text: $name, onSubmit: { if save() { dismiss() } }, focus: $focused)
            Text(error ?? "Erscheint im Regal anstelle von „Gesperrt“.")
                .font(.caption)
                .foregroundStyle(error == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(AppStyle.errorColor))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppStyle.cardPadding)
        .frame(width: 280)
        .onAppear { focused = true }
        // Closing by clicking elsewhere can't show a failure any more; it is
        // in the protocol, and the old name stays.
        .onDisappear { _ = save() }
    }

    /// `false` when saving failed; Return then keeps the popover open with
    /// the message instead of closing over it.
    @discardableResult private func save() -> Bool {
        // Removed meanwhile (cabinet resized or backup restored in the settings).
        guard !shelf.isDeleted, shelf.modelContext != nil, shelf.isReserved else { return true }
        let newName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard newName != shelf.name else { return true }
        do { try PositionService(context: context).configure(shelf, name: newName, isReserved: true); error = nil; return true }
        catch { self.error = error.reportedMessage(); return false }
    }
}
