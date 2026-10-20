import SwiftUI
import SwiftData

extension KallaxView {
    /// Runs only when the (debounced) query or the data changes, never in
    /// `body`: plain substring checks against the prebuilt index instead of
    /// Unicode-comparing every record's text, tracks included.
    func applySearch() {
        let words = SearchIndex<UUID>.words(searchQuery)
        guard !words.isEmpty else { searchResults = ShelfSearchResults(); return }
        if searchIndexStale {
            searchIndex = SearchIndex(allCopies, id: \.id, text: SortingService.searchText)
            searchIndexStale = false
        }
        let excluded = Set(exclusions.map(\.copyID))
        let owner = owner
        var placed: [RecordCopy] = [], unplaced: [RecordCopy] = []
        for copy in allCopies where searchIndex.matches(copy.id, words) {
            // Records in an inactive cabinet are put away: neither shown nor offered for placing.
            if let shelf = copy.shelf { if shelf.isInUse { placed.append(copy) } }
            // "Ohne Regalplatz" and records outside the current collection
            // aren't meant to be placed (same rule as "Platte hinzufügen").
            else if ShelfAssignmentPresentation.isCandidate(copy, owner: owner, excluding: excluded) { unplaced.append(copy) }
        }
        // Ties (two copies of one album) by ID, so rows don't swap while typing.
        func sorted(_ copies: [RecordCopy], _ limit: Int) -> [RecordCopy] {
            Array(SortingService.sorted(copies).prefix(limit))
        }
        searchResults = ShelfSearchResults(
            placed: sorted(placed, ShelfSearchResults.placedLimit),
            unplaced: sorted(unplaced, ShelfSearchResults.unplacedLimit),
            hidden: max(0, placed.count - ShelfSearchResults.placedLimit) + max(0, unplaced.count - ShelfSearchResults.unplacedLimit),
            litShelfIDs: Set(placed.compactMap { $0.shelf?.id })
        )
    }

    /// Only while the committed query has words, so a field of spaces lists nothing.
    @ViewBuilder var searchResultsPanel: some View {
        let typed = !SearchIndex<UUID>.words(search.text).isEmpty
        if typed && !SearchIndex<UUID>.words(searchQuery).isEmpty {
            ShelfSearchResultsPanel(
                matches: searchResults.placed,
                unplaced: searchResults.unplaced,
                hidden: searchResults.hidden,
                labels: rangeLabels,
                missing: missingIDs,
                place: startPlacement
            )
            // Still the previous query's matches while typing pauses.
            .opacity(searchQuery == search.text ? 1 : 0.6)
            .animation(AppStyle.quickAnimation, value: searchQuery == search.text)
            .frame(width: AppStyle.toolbarSearchWidth + 60)
            .padding(.trailing, AppStyle.pageMargin)
            .padding(.top, AppStyle.itemSpacing)
            .transition(.opacity)
        }
    }
}
