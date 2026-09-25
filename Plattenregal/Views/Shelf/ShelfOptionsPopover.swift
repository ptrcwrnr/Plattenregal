import SwiftUI
import SwiftData

/// What the shelf page shows as locked while the options popover is open.
///
/// Saving a shelf makes the whole shelf page recompute (statistics, range
/// labels over every copy); doing that mid-animation stutters. So the switch
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

/// Options of the selected compartment: locking it for records, with an
/// optional name that only appears while locked.
///
/// Fixed size on purpose: the name row and the hint share one slot and
/// crossfade, because a resizing NSPopover fights SwiftUI's animation.
struct ShelfOptionsPopover: View {
    let shelf: Shelf
    let preview: ShelfLockPreview
    @Environment(\.modelContext) private var context
    // Seeded up front, not in onAppear, so the popover opens in its final state.
    @State private var isLocked: Bool
    @State private var name: String
    @State private var error: String?
    @FocusState private var nameFocused: Bool

    /// Slightly longer than the animation, so the save lands after it.
    private static let saveDelay: Duration = .milliseconds(350)

    init(shelf: Shelf, preview: ShelfLockPreview) {
        self.shelf = shelf
        self.preview = preview
        _isLocked = State(initialValue: shelf.isReserved)
        _name = State(initialValue: shelf.name)
    }

    private var canLock: Bool { shelf.isReserved || shelf.copies.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: lockBinding) {
                Text("Fach sperren")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.switch)
            .disabled(!canLock)
            ZStack(alignment: .leading) {
                nameRow
                    .opacity(isLocked ? 1 : 0)
                    .offset(y: isLocked || AppStyle.reduceMotion ? 0 : -6)
                    .allowsHitTesting(isLocked)
                hint
                    .opacity(isLocked ? 0 : 1)
                    .offset(y: !isLocked || AppStyle.reduceMotion ? 0 : 6)
                    .allowsHitTesting(false)
            }
            .frame(height: AppStyle.controlHeight)
        }
        .padding(AppStyle.cardPadding)
        .frame(width: 280)
        // Persist once the switch has settled; a quick double flip cancels
        // the pending save and only the final state is written.
        .task(id: isLocked) {
            guard isLocked != shelf.isReserved else { return preview.clear(shelf) }
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            save()
        }
        .onDisappear(perform: save)
    }

    /// The switch animates the popover and the compartment behind it in one
    /// transaction; nothing is saved here.
    private var lockBinding: Binding<Bool> {
        Binding(
            get: { isLocked },
            set: { locked in
                withAnimation(AppStyle.standardAnimation) {
                    isLocked = locked
                    preview.set(locked, for: shelf)
                    error = nil
                }
                if locked { nameFocused = true }
            }
        )
    }

    private var nameRow: some View {
        HStack(spacing: AppStyle.itemSpacing) {
            Text("Name:").foregroundStyle(.secondary)
            TextField("Name", text: $name, prompt: Text(""))
                .labelsHidden()
                .textFieldStyle(.plain)
                .focused($nameFocused)
                .onSubmit(save)
                .padding(.horizontal, 8)
                .frame(height: AppStyle.controlHeight)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var hint: some View {
        Text(hintText)
            .font(.caption)
            .foregroundStyle(error == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(AppStyle.errorColor))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var hintText: String {
        if let error { return error }
        if !canLock { return "Nur leere Fächer können gesperrt werden." }
        return "In ein gesperrtes Fach können keine Platten gelegt werden."
    }

    /// Writes the popover's state to the store without animation: the page
    /// already shows it via `preview`, so nothing should move again.
    private func save() {
        // Removed meanwhile (cabinet resized or backup restored in the settings).
        guard !shelf.isDeleted, shelf.modelContext != nil else { return }
        let newName = isLocked ? name.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        guard shelf.isReserved != isLocked || shelf.name != newName else {
            preview.clear(shelf)
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            do {
                try PositionService(context: context).configure(shelf, name: newName, isReserved: isLocked)
                preview.clear(shelf)
            } catch {
                // Back to what is stored; the hint slot shows why.
                withAnimation(AppStyle.standardAnimation) {
                    isLocked = shelf.isReserved
                    preview.clear(shelf)
                    self.error = error.reportedMessage()
                }
            }
        }
    }
}
