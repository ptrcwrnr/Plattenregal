import SwiftUI
import AppKit
import ObjectiveC

/// The item at the top of a scrolled page, for `.scrollPosition(id:)`. An
/// object, not `@State` of the page: the scroll view writes it every time
/// another row reaches the top, and a state value would rebuild the whole
/// page with all its covers each time. Through Observation only views that
/// read `id` in their `body` follow it – usually none.
@Observable final class ScrollAnchor<ID: Hashable> {
    var id: ID?
}

extension View {
    /// `.scrollPosition(id:anchor: .top)` bound to `anchor` (see `scrollPosition(tracking:)`).
    /// The binding is made inside the modifier: making it reads `id`, and
    /// made in a grid's closure it tied that closure to every new top row.
    func scrollPosition<ID: Hashable>(_ anchor: ScrollAnchor<ID>) -> some View {
        modifier(AnchoredScrollPosition(anchor: anchor))
    }

    /// `.scrollPosition(id:anchor: .top)` in a modifier of its own. The
    /// scroll view reads the position where the modifier is built; built
    /// inline in a grid's closure, every new top row re-ran that closure –
    /// and with it every cover cell of the grid.
    func scrollPosition<ID: Hashable>(tracking position: Binding<ID?>) -> some View {
        modifier(TrackedScrollPosition(position: position))
    }
}

extension View {
    /// `onChange(of:)` for a value read from an observed object (e.g.
    /// `LibraryChanges`), read in a modifier of its own: read in a page's
    /// `body`, every change re-ran the whole page with all its cover cells –
    /// even when the handler had nothing to do.
    func onObservedChange<V: Equatable>(of value: @escaping () -> V, perform action: @escaping (V, V) -> Void) -> some View {
        modifier(ObservedChange(value: value, action: action))
    }

    /// `task(id:)` with the id read in a modifier of its own (see `onObservedChange`).
    func observedTask<ID: Equatable>(id: @escaping () -> ID, _ action: @escaping @MainActor () async -> Void) -> some View {
        modifier(ObservedTask(id: id, action: action))
    }
}

private struct ObservedChange<V: Equatable>: ViewModifier {
    let value: () -> V
    let action: (V, V) -> Void
    func body(content: Content) -> some View { content.onChange(of: value(), action) }
}

private struct ObservedTask<ID: Equatable>: ViewModifier {
    let id: () -> ID
    let action: @MainActor () async -> Void
    func body(content: Content) -> some View { content.task(id: id(), action) }
}

private struct AnchoredScrollPosition<ID: Hashable>: ViewModifier {
    let anchor: ScrollAnchor<ID>
    func body(content: Content) -> some View {
        content.scrollPosition(id: Bindable(anchor).id, anchor: .top)
    }
}

private struct TrackedScrollPosition<ID: Hashable>: ViewModifier {
    let position: Binding<ID?>
    func body(content: Content) -> some View {
        content.scrollPosition(id: position, anchor: .top)
    }
}
