import SwiftUI
import SwiftData

/// The search field at the right end of the toolbar, on the pages that have
/// one (not on the statistics). It ends flush with the covers below it: the
/// toolbar's own margin is topped up to the pages' (`toolbarSearchInset`).
/// ⌘F puts the cursor in it; Esc clears the query, a second Esc leaves it.
/// Collection and wantlist share one query (`LibrarySearch`), the shelf has
/// its own (`ShelfSearch`); the pages read them and filter themselves.
struct ToolbarSearchField: View {
    let selection: PageSelection<Destination>
    let library: LibrarySearch
    let shelf: ShelfSearch
    let requests: SearchRequests
    @FocusState private var focused: Bool

    var body: some View {
        let page = selection.current
        Group {
            if page.hasSearch {
                AppSearchField(placeholder: placeholder(for: page), text: text(for: page), focus: $focused, onToolbar: true)
                    .frame(width: AppStyle.toolbarSearchWidth)
                    .padding(.trailing, AppStyle.toolbarSearchInset)
                    .accessibilityLabel(String(localized: "Suchen"))
                    .transition(.opacity)
            }
        }
        .animation(AppStyle.fadeAnimation, value: page.hasSearch)
        .onChange(of: requests.count) {
            guard selection.current.hasSearch else { return }
            focused = true
        }
        .onChange(of: focused) { _, new in requests.fieldFocused = new }
        .onChange(of: page) { if !page.hasSearch { focused = false } }
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
