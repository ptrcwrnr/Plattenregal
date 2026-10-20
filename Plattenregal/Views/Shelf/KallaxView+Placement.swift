import SwiftUI
import SwiftData

extension KallaxView {
    @ViewBuilder var undoToast: some View {
        if let entry = recentUnplace {
            HStack(spacing: AppStyle.rowSpacing) {
                Text("Aus Fach entfernt")
                // A shelf locked meanwhile takes no records, and a record marked
                // "Ohne Regalplatz" meanwhile stays out; nothing to undo then.
                if canUndo(entry) {
                    Button("Rückgängig", action: undoUnplace)
                        .appLinkButton()
                        .keyboardShortcut(searchFocused ? nil : KeyboardShortcut("z", modifiers: .command))
                }
            }
            .font(.callout)
            .padding(.horizontal, AppStyle.cardPadding)
            .padding(.vertical, AppStyle.itemSpacing)
            .appChipSurface(in: Capsule())
            .padding(.bottom, AppStyle.cardPadding)
            .transition(AppStyle.funnelTransition(from: .bottom))
            .task(id: entry.id) {
                try? await Task.sleep(for: .seconds(6))
                if recentUnplace?.id == entry.id {
                    withAnimation(AppStyle.standardAnimation) { recentUnplace = nil }
                }
            }
        }
    }

    func takePlacingRequest() {
        guard let id = requests.placing else { return }
        requests.placing = nil
        if let copy = allCopies.first(where: { $0.id == id }) { startPlacement(copy) }
    }

    func takeSortingInRequest() {
        guard requests.sortingIn else { return }
        requests.sortingIn = false
        placement = nil
        startAssignment(nil)
    }

    func startPlacement(_ copy: RecordCopy) {
        searchQuery = ""; focusCopy = nil; showsNameEditor = false
        var new = Placement(copy: copy, shelves: shelves)
        new.excluded = exclusions.contains { $0.copyID == copy.id }
        new.missing = missingIDs.contains(copy.id)
        withAnimation(AppStyle.standardAnimation) {
            placement = new
            if let shelf = new.spot?.shelf { highlight = shelf.id }
        }
        // A placed record is pulled out in the strip and selected in the table.
        if new.found && new.putAwayIn == nil {
            focusCopy = copy
            focusRevision += 1
        }
    }

    /// Records may change while the card is open (sync, edits in the table):
    /// recompute the spots, keeping the chosen shelf if it still fits. The
    /// card closes once the record was placed or taken out of its shelf.
    func refreshPlacement() {
        guard let current = placement else { return }
        let copy = current.copy
        guard !copy.isDeleted, copy.modelContext != nil, (copy.shelf != nil) == current.found else { placement = nil; return }
        var updated = Placement(copy: copy, shelves: shelves)
        updated.excluded = current.excluded
        updated.missing = missingIDs.contains(copy.id)
        if let shelfID = current.spot?.shelf.id, let index = updated.spots.firstIndex(where: { $0.shelf.id == shelfID }) {
            updated.chosen = index
        }
        placement = updated
        if let shelf = updated.spot?.shelf, highlight != shelf.id { highlight = shelf.id }
    }

    func choosePlacementSpot(_ index: Int) {
        guard let placement, placement.spots.indices.contains(index) else { return }
        self.placement?.chosen = index
        withAnimation(AppStyle.standardAnimation) { highlight = placement.spots[index].shelf.id }
    }

    func confirmPlacement() {
        guard let placement, let spot = placement.spot else { return }
        if placement.found {
            // Standing where it should: a "Gesucht" mark is settled.
            if placement.missing { setMissing(placement.copy, false) }
            withAnimation(AppStyle.standardAnimation) { self.placement = nil }
            return
        }
        do {
            try PositionService(context: context).move(placement.copy, to: spot.shelf, position: spot.position, found: true)
            withAnimation(AppStyle.standardAnimation) { self.placement = nil }
            focusCopy = placement.copy
            focusRevision += 1
        } catch { self.error = error.reportedMessage() }
    }

    func cancelPlacement() {
        withAnimation(AppStyle.standardAnimation) { placement = nil }
    }

    func unplace(_ copy: RecordCopy) {
        guard let shelf = copy.shelf else { return }
        let entry = UnplacedCopy(copy: copy, shelf: shelf, position: copy.positionInShelf)
        if focusCopy?.id == copy.id { focusCopy = nil }
        do {
            try PositionService(context: context).unplace(copy)
            withAnimation(AppStyle.standardAnimation) { recentUnplace = entry }
        } catch { self.error = error.reportedMessage() }
    }

    private func canUndo(_ entry: UnplacedCopy) -> Bool {
        // The compartment may be gone meanwhile (cabinet made smaller, backup
        // restored, reset); reading a deleted model would crash.
        !entry.copy.isDeleted && entry.copy.modelContext != nil
            && !entry.shelf.isDeleted && entry.shelf.modelContext != nil
            && entry.copy.shelf == nil && !entry.shelf.isReserved
            && !exclusions.contains { $0.copyID == entry.copy.id }
    }

    private func undoUnplace() {
        guard let entry = recentUnplace else { return }
        withAnimation(AppStyle.standardAnimation) { recentUnplace = nil }
        // Someone may have re-placed the copy meanwhile; don't yank it back.
        guard canUndo(entry) else { return }
        let position = min(max(entry.position, 1), entry.shelf.copies.count + 1)
        do { try PositionService(context: context).move(entry.copy, to: entry.shelf, position: position) }
        catch { self.error = error.reportedMessage() }
    }

    func delete(_ copy: RecordCopy) {
        // Records still in the Discogs collection leave via Discogs (see the table menu).
        guard !copy.isInCurrentCollection(owner: owner) else { return }
        // A deleted model must not stay referenced: reading it afterwards
        // (strip selection, undo toast, placement card) would crash.
        if focusCopy?.id == copy.id { focusCopy = nil }
        if recentUnplace?.copy.id == copy.id { recentUnplace = nil }
        if placement?.copy.id == copy.id { placement = nil }
        do { try PositionService(context: context).delete(copy) }
        catch { self.error = error.reportedMessage() }
    }
}
