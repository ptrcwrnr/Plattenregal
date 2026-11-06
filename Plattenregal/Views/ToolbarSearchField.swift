import SwiftUI

/// The search in the toolbar, at the end of the page switch's bar: a line,
/// then the magnifying glass, which opens into the field (see
/// `AppSearchField`). A click on the glass or ⌘F opens it with the cursor in
/// it, springing open (`AppStyle.openAnimation`, the glass bounces once);
/// it closes calmly when it loses the focus with nothing typed (Esc clears
/// the query, a second Esc leaves it). A query keeps it open, also across a
/// page switch; opened or closed by a query alone (another page, the shelf
/// clearing its query after a match was picked, the clear button) it moves
/// calmly, without spring or bounce. On the statistics, which has no search,
/// line and glass fade out in the beat of the page switch while the whole bar
/// narrows calmly (`AppStyle.layoutAnimation`) and stays centered; back on a
/// page with search it widens again and they fade in.
/// Collection and wantlist share one query (`LibrarySearch`), the shelf has
/// its own (`ShelfSearch`); the pages read them and filter themselves.
struct ToolbarSearchField: View {
    let selection: PageSelection<Destination>
    let library: LibrarySearch
    let shelf: ShelfSearch
    let requests: SearchRequests
    @FocusState private var focused: Bool
    /// The page whose search the field shows: on the statistics, which has
    /// none, it keeps the last one while it folds away.
    @State private var fieldPage: Destination = .collection
    /// Opened by the glass or ⌘F, until the field loses the focus.
    @State private var opened = false
    /// What the bar shows. Follows `opened` and the query in an animation
    /// (see `follow`), so the bar never changes its width in a jump.
    @State private var shownOpen = false
    /// Bounces the glass, on opening by the glass or ⌘F only.
    @State private var bounces = 0
    /// Whether line and glass take room in the bar. Follows the page in a
    /// transaction of its own (see `body`), so the whole bar – its
    /// background and its place in the middle of the toolbar – changes its
    /// width smoothly instead of only this part of it.
    @State private var searchShown = true

    var body: some View {
        let page = selection.current
        let shown = page.hasSearch ? page : fieldPage
        let text = text(for: shown)
        let open = opened || !text.wrappedValue.isEmpty
        // Always in the bar, only folded away on the statistics: taken out
        // and put back, the toolbar was laid out anew and jumped.
        HStack(spacing: 0) {
            ControlSeparator()
            AppSearchField(placeholder: placeholder(for: shown), text: text, focus: $focused, open: shownOpen, onOpen: openField, bounce: bounces)
        }
        // The fade in the beat of the page switch, only for the opacity …
        .opacity(page.hasSearch ? 1 : 0)
        .animation(page.hasSearch ? AppStyle.pageInAnimation : AppStyle.pageOutAnimation, value: page.hasSearch)
        // … the width calmly with the whole bar (see `searchShown`).
        .frame(width: searchShown ? nil : 0, alignment: .leading)
        .clipped()
        .allowsHitTesting(page.hasSearch)
        .disabled(!page.hasSearch)
        .accessibilityHidden(!page.hasSearch)
        .onChange(of: requests.count) {
            guard selection.current.hasSearch else { return }
            openField()
        }
        .onChange(of: focused) { _, new in
            requests.fieldFocused = new
            if !new { opened = false }
        }
        .onChange(of: open, initial: true) { old, new in follow(new, animated: old != new) }
        .onChange(of: page.hasSearch, initial: true) { old, new in
            if old == new { searchShown = new } else { withAnimation(AppStyle.layoutAnimation) { searchShown = new } }
        }
        .onChange(of: page, initial: true) {
            if page.hasSearch { fieldPage = page } else { focused = false }
        }
    }

    /// Opens the field and puts the cursor in it, in a spring the whole bar
    /// follows. The text field only exists once open, so the focus follows
    /// in the next update.
    private func openField() {
        opened = true
        if !shownOpen {
            if !AppStyle.reduceMotion { bounces += 1 }
            withAnimation(AppStyle.openAnimation) { shownOpen = true }
        }
        Task { @MainActor in focused = true }
    }

    /// Every other change: calm. Already shown as it should be after
    /// `openField`, so that one keeps its spring.
    private func follow(_ open: Bool, animated: Bool) {
        guard shownOpen != open else { return }
        if animated {
            withAnimation(AppStyle.closeAnimation) { shownOpen = open }
        } else {
            shownOpen = open
        }
    }

    private func text(for page: Destination) -> Binding<String> {
        page == .shelf ? Bindable(shelf).text : Bindable(library).query
    }

    /// Names the page by its name, the user's own if given (`PageNames`).
    /// The statistics has no search; while its page fades in, the shelf's shows.
    private func placeholder(for page: Destination) -> String {
        String(localized: "\(page == .statistics ? Destination.shelf.title : page.title) durchsuchen")
    }
}

/// The search shared by collection and wantlist. An object, read by the
/// pages themselves: each page is built once (see `PageStack`), and a binding
/// handed in would keep the value it had then.
@Observable final class LibrarySearch {
    var query = ""
}
