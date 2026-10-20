import SwiftUI
import SwiftData

extension KallaxView {
    func forgetCopies() {
        closingAssignment = nil; assignment = nil; sortCheck = nil
        focusCopy = nil; placement = nil; recentUnplace = nil
        pendingDelete = nil; confirmRemoveSold = false
    }

    func setMissing(_ copy: RecordCopy, _ missing: Bool) {
        do { try PositionService(context: context).setMissing([copy], missing) }
        catch { self.error = error.reportedMessage() }
    }

    func removeSoldFromShelves() {
        let sold = soldInShelves
        if let focus = focusCopy, sold.contains(where: { $0.id == focus.id }) { focusCopy = nil }
        // One transaction: a failure halfway must not leave some sold records
        // out and others still in, with gaps in between.
        do { try PositionService(context: context).unplace(sold) }
        catch { self.error = error.reportedMessage() }
    }

    @ViewBuilder var shelfDetail: some View {
        if let shown = detailShelf {
            // The contents own their grid/list switch.
            VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                if let placement {
                    PlacementCard(
                        placement: placement,
                        labels: rangeLabels,
                        missing: missingIDs,
                        choose: choosePlacementSpot,
                        confirm: confirmPlacement,
                        cancel: cancelPlacement
                    )
                    .transition(AppStyle.funnelTransition())
                }
                // One slot: an animated switch between an empty and a filled
                // compartment crossfades instead of stacking both for a moment.
                ZStack(alignment: .topLeading) {
                if shown.isReserved || shown.copies.isEmpty {
                    ShelfLockReader(shelf: shown, preview: lockPreview) { locked in
                        if locked {
                            detailNote(String(localized: "Gesperrtes Fach – nicht für Platten vorgesehen. Per Rechtsklick auf das Fach kannst du es entsperren."))
                        } else {
                            HStack(spacing: AppStyle.itemSpacing) {
                                detailNote(String(localized: "Noch keine Platten in diesem Fach."))
                                Button("Platte hinzufügen") { startAssignment(shown) }
                                    .appLinkButton()
                            }
                        }
                    }
                } else {
                    ShelfContentsView(
                        shelf: shown,
                        session: contentsSession,
                        owner: owner,
                        missing: missingIDs,
                        focusCopy: focusCopy,
                        focusRevision: focusRevision,
                        select: { copy in
                            if let copy { if focusCopy?.id != copy.id { focusCopy = copy } } else { deselect() }
                        },
                        placed: showPlaced,
                        find: startPlacement,
                        unplace: unplace,
                        delete: { pendingDelete = $0 },
                        setMissing: setMissing
                    )
                }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .popover(isPresented: $showsNameEditor, arrowEdge: .top) {
                // Fresh state per shelf: a name seeded for one shelf must
                // never be saved onto another.
                ShelfNamePopover(shelf: shown).id(shown.id)
            }
        } else {
            detailNote(String(localized: "Wähle ein Fach im Regal oder suche oben nach einer Platte."))
        }
    }

    private func detailNote(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The compartment's right-click menu (an `AppMenu`, like the collection's).
    @ViewBuilder func shelfMenu(for shelf: Shelf) -> some View {
        let locked = lockPreview.isLocked(shelf)
        Button("Platte hinzufügen") { selectShelf(shelf); startAssignment(shelf) }
            .disabled(locked)
        Button("Sortierung prüfen") { selectShelf(shelf); sortCheck = ShelfSortCheckRequest(shelf: shelf) }
            .disabled(locked || shelf.copies.count < 2)
        if locked {
            Button("Namen ändern …") { selectShelf(shelf); showsNameEditor = true }
            Button("Fach entsperren") { setLocked(shelf, false) }
        } else {
            Button("Fach sperren") { setLocked(shelf, true) }
                .disabled(!shelf.copies.isEmpty)
        }
    }

    /// Shows the new state at once via `lockPreview` and saves once the
    /// compartment has faded over: saving makes the page recompute, which
    /// would stutter mid-animation. Unlocking drops the name as well.
    private func setLocked(_ shelf: Shelf, _ locked: Bool) {
        withAnimation(AppStyle.standardAnimation) { lockPreview.set(locked, for: shelf) }
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !shelf.isDeleted, shelf.modelContext != nil else { return lockPreview.clear(shelf) }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                do { try PositionService(context: context).configure(shelf, name: locked ? shelf.name : "", isReserved: locked) }
                catch { self.error = error.reportedMessage() }
                lockPreview.clear(shelf)
            }
        }
    }

    /// New records go to their alphabetical place in the compartment –
    /// without one (the round button), each to its place in the rack.
    func startAssignment(_ shelf: Shelf?) {
        let session = ShelfAssignmentSession(shelf: shelf)
        closingAssignment = session
        assignment = session
    }

    func selectShelf(_ shelf: Shelf) {
        searchQuery = ""; focusCopy = nil
        // Picking the other fitting shelf switches the spot; any other shelf ends the placement.
        if let placement {
            if let index = placement.spots.firstIndex(where: { $0.shelf.id == shelf.id }) {
                self.placement?.chosen = index
            } else {
                cancelPlacement()
            }
        }
        if highlight != shelf.id { showsNameEditor = false }
        withAnimation(AppStyle.standardAnimation) { highlight = shelf.id }
    }

    /// After a copy's place changed from the compartment contents: follow it
    /// to its new shelf, or drop the focus when it left the shelves altogether.
    func showPlaced(_ copy: RecordCopy) {
        guard let shelf = copy.shelf else {
            if focusCopy?.id == copy.id { focusCopy = nil }
            return
        }
        if highlight != shelf.id { withAnimation(AppStyle.standardAnimation) { highlight = shelf.id } }
        focusCopy = copy
        focusRevision += 1
    }

    // Lets go of the picked record; the shelf itself stays selected.
    func deselect() {
        guard focusCopy != nil else { return }
        focusCopy = nil
    }

    /// There is always a selected shelf: the start of the first cabinet, or the
    /// first occupied compartment of any other one if that cabinet is empty.
    /// An existing valid selection (e.g. "im Regal zeigen") is kept.
    func ensureShelfSelected() {
        if let highlight, shelves.contains(where: { $0.id == highlight }) { return }
        highlight = activeCabinets.first.flatMap { cabinet in
            shelves.first { $0.cabinet?.id == cabinet.id && Self.holdsRecords($0) }
        }?.id
            ?? shelves.first(where: Self.holdsRecords)?.id
            ?? shelves.first?.id
    }

    /// Where a cabinet is entered, the same for every way in (app start,
    /// switching cabinets): its first compartment with records in reading
    /// order – where the app starts the alphabet – else its first one. How the
    /// real rack is filled doesn't matter here.
    func startShelf(in cabinet: Cabinet) -> Shelf? {
        let own = shelves.filter { $0.cabinet?.id == cabinet.id }
        return own.first(where: Self.holdsRecords) ?? own.first
    }

    private static func holdsRecords(_ shelf: Shelf) -> Bool { !shelf.isReserved && !shelf.copies.isEmpty }
}
