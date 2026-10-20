import SwiftUI

/// What other pages ask of the shelf page. An object, not a binding: pages
/// live in separate hosting views (see `PageStack`), and only Observation
/// reaches across.
@Observable final class ShelfRequests {
    /// A record to show: where it stands and between which records, or –
    /// without a shelf – where it belongs.
    var placing: UUID?
    /// The round button: every record without a shelf, each to its place.
    var sortingIn = false
}

/// What is typed into the search field in the toolbar while the shelf page is
/// shown (see `ToolbarSearchField`). An object, read by the page itself: the
/// page is built once (see `PageStack`).
@Observable final class ShelfSearch {
    var text = ""
}
