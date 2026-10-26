import SwiftUI

/// The search in the toolbar, at the end of the page switch's bar: a line,
/// then the magnifying glass, which opens into the field (see
/// `AppSearchField`). A click on the glass or ⌘F opens it with the cursor in
/// it; it closes again when it loses the focus with nothing typed (Esc
/// clears the query, a second Esc leaves it). A query keeps it open, also
/// across a page switch. On the statistics, which has no search, line and
/// glass fold away in the beat of the page switch.
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

    var body: some View {
        let page = selection.current
        let shown = page.hasSearch ? page : fieldPage
        let text = text(for: shown)
        let open = opened || !text.wrappedValue.isEmpty
        // Always in the bar, only folded away on the statistics: taken out
        // and put back, the toolbar was laid out anew and jumped.
        HStack(spacing: 0) {
            ControlSeparator()
            AppSearchField(placeholder: placeholder(for: shown), text: text, focus: $focused, open: open, onOpen: openField)
        }
        .frame(width: page.hasSearch ? nil : 0, alignment: .leading)
        .clipped()
        .opacity(page.hasSearch ? 1 : 0)
        .animation(page.hasSearch ? AppStyle.pageInAnimation : AppStyle.pageOutAnimation, value: page.hasSearch)
        .allowsHitTesting(page.hasSearch)
        .disabled(!page.hasSearch)
        .accessibilityHidden(!page.hasSearch)
        .onChange(of: requests.count) {
            guard selection.current.hasSearch else { return }
            openField()
        }
        .onChange(of: focused) { _, new in
            requests.fieldFocused = new
            if !new && opened { withAnimation(AppStyle.searchCloseAnimation) { opened = false } }
        }
        .onChange(of: page, initial: true) {
            if page.hasSearch { fieldPage = page } else { focused = false }
        }
    }

    /// Opens the field and puts the cursor in it, in a spring the whole bar
    /// follows. The text field only exists once open, so the focus follows
    /// in the next update.
    private func openField() {
        if !opened { withAnimation(AppStyle.searchOpenAnimation) { opened = true } }
        Task { @MainActor in focused = true }
    }

    private func text(for page: Destination) -> Binding<String> {
        page == .shelf ? Bindable(shelf).text : Bindable(library).query
    }

    private func placeholder(for page: Destination) -> String {
        switch page {
        case .collection: String(localized: "Collection durchsuchen")
        case .wantlist: String(localized: "Wantlist durchsuchen")
        case .shelf, .statistics: String(localized: "Regal durchsuchen")
        }
    }
}

/// The search shared by collection and wantlist. An object, read by the
/// pages themselves: each page is built once (see `PageStack`), and a binding
/// handed in would keep the value it had then.
@Observable final class LibrarySearch {
    var query = ""
}
