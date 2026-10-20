import SwiftUI
import SwiftData
import AppKit

extension CollectionView {
    /// `animated`: records glide to their new place (search or section).
    /// Data refreshes (e.g. a Discogs sync) and the list layout update
    /// instantly — animating an NSTable diff of the whole collection would stutter.
    func rebuildBase(animated: Bool = false) {
        let analyticsIDs = analyticsFilter?.copyIDs
        // Only the current account: copies of an earlier one stay active in
        // the store (a sync only touches its own), matching the statistics.
        let owner = DiscogsAccount.current(in: accounts)?.username
        let matched = copies.filter { copy in
            (analyticsIDs == nil || analyticsIDs!.contains(copy.id)) &&
            copy.isInCurrentCollection(owner: owner)
        }
        base = order.apply(matched, scope: DisplaySettings.collectionOrderKey, alphabetical: SortingService.sortedByAlphabetSection,
                           key: { CollectionCoverGroup.identity(of: $0) },
                           added: { DiscogsDate.parse($0.discogsDateAdded) })
        shelfLabels = labelsCache.labels(for: shelves, style: labelStyle)
        labelsPending = false
        loaded = true
        applyQuery(animated: animated)
    }

    func refreshLabels() {
        guard activity.isActive else { labelsPending = true; return }
        labelsPending = false
        shelfLabels = labelsCache.labels(for: shelves, style: labelStyle)
    }

    func applyQuery(animated: Bool = false) {
        queryPending = false
        let words = SearchIndex<UUID>.words(query)
        let filtered: [RecordCopy]
        if words.isEmpty { filtered = base } else {
            let index = LibrarySearchIndexes.shared.collection(copies)
            filtered = base.filter { index.matches($0.id, words) }
        }
        let grouped = CollectionCoverGroup.make(from: filtered)
        let searchEnded = searching && words.isEmpty
        withAnimation(animated && layout == .grid ? AppStyle.layoutAnimation : nil) {
            items = filtered
            coverGroups = grouped
            searching = !words.isEmpty
            appliedQuery = words.isEmpty ? "" : query
        }
        // Back where the page was before the search – also when it was
        // cleared while this page was hidden.
        if searchEnded {
            scroll.id = scrollBeforeSearch ?? filtered.first?.id
            scrollBeforeSearch = nil
        }
        // A place filtered away isn't held on to.
        if let id = scroll.id, !filtered.contains(where: { $0.id == id }) { scroll.id = nil }
        normalizeGridScrollPosition(in: grouped)
    }

    func normalizeGridScrollPosition(in groups: [CollectionCoverGroup]) {
        guard layout == .grid, let id = scroll.id,
              let group = groups.first(where: { group in group.copies.contains { $0.id == id } })
        else { return }
        if id != group.primary.id { scroll.id = group.primary.id }
    }

    func placeLabel(for copy: RecordCopy) -> String {
        guard let shelf = copy.shelf else {
            return excludedIDs.contains(copy.id) ? String(localized: "Ohne Regalplatz") : "–"
        }
        if shelf.isReserved { return shelfLabels.prefix(for: shelf) + (shelf.name.isEmpty ? String(localized: "Gesperrtes Fach") : shelf.name) }
        return shelfLabels.prefix(for: shelf) + (shelfLabels[shelf.id] ?? "–")
    }

    /// Behind the page: the first few covers of the list.
    var ambientCovers: [String] {
        Array(items.lazy.compactMap { $0.release?.coverURL }.prefix(3))
    }

    /// The search ends: fade the hits out, show the whole list where it was
    /// before the search (see `applyQuery`), fade it in. Typing again
    /// meanwhile cancels this and brings the results back at once.
    func leaveSearch() async {
        withAnimation(AppStyle.searchExitFadeOut) { resultsHidden = true }
        try? await Task.sleep(for: .milliseconds(100))
        if !Task.isCancelled {
            applyQuery()
            // One layout pass for the jump, still invisible.
            try? await Task.sleep(for: .milliseconds(30))
        }
        withAnimation(AppStyle.searchExitFadeIn) { resultsHidden = false }
    }
}
