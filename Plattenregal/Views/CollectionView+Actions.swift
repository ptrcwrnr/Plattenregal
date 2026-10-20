import SwiftUI
import SwiftData
import AppKit

extension CollectionView {
    // No "Löschen" here: every record shown comes from the Discogs collection,
    // and the next sync would bring a locally deleted copy back as a new one
    // (without its shelf place). Records leave via Discogs; "Ohne Regalplatz"
    // keeps one off the shelf.

    /// "Ohne Regalplatz" / "Wieder einsortieren", depending on whether all
    /// of the given copies are already kept out of the shelves.
    @ViewBuilder private func exclusionButton(for selectedCopies: [RecordCopy]) -> some View {
        let allExcluded = !selectedCopies.isEmpty && selectedCopies.allSatisfy { excludedIDs.contains($0.id) }
        Button(allExcluded ? "Wieder einsortieren" : "Ohne Regalplatz") {
            perform { try PositionService(context: context).setExcluded(selectedCopies, !allExcluded) }
        }
    }

    @ViewBuilder func gridContextMenu(_ group: CollectionCoverGroup) -> some View {
        if group.copies.count > 1 {
            ForEach(Array(group.copies.enumerated()), id: \.element.id) { index, copy in
                let excluded = excludedIDs.contains(copy.id)
                AppMenuSection(title: String(localized: "Exemplar \(index + 1) · \(ShelfRangeLabels.location(of: copy, labels: shelfLabels, excluded: excluded))"))
                actions(copy)
            }
        } else {
            actions(group.primary)
        }
    }

    @ViewBuilder func tableContextMenu(_ id: UUID, items: [RecordCopy]) -> some View {
        if let copy = items.first(where: { $0.id == id }) {
            actions(copy)
        }
    }

    /// A click on a cover: its popover – unless that very popover was just
    /// closed by this click.
    func showQuickLook(_ copy: RecordCopy) {
        let justClosed = quickLookDismissed.map { $0.id == copy.id && Date().timeIntervalSince($0.at) < 0.4 } ?? false
        if !justClosed { quickLook = copy.id }
    }

    func contextMenuBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { contextMenu?.id == id },
            set: { if !$0, contextMenu?.id == id { contextMenu = nil } }
        )
    }

    func quickLookBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { quickLook == id },
            set: { presented in
                guard !presented, quickLook == id else { return }
                quickLook = nil
                quickLookDismissed = (id, Date())
            }
        )
    }

    /// Above the content, right under the toolbar: the grid's covers start
    /// one `CoverGrid.spacing` below it in both designs (see `CoverGrid.topSpace`).
    var topSpace: CGFloat { layout == .grid ? CoverGrid.topSpace : AppStyle.pagePadding }

    /// In the window the page has no header bar: page switch, grid/list and
    /// search are in the toolbar. The statistics panel has no toolbar, so
    /// there its title sits beside the layout switch — but no search: it is
    /// only for looking.
    var showsControls: Bool { pages == nil }

    func collectionControls(items: [RecordCopy]) -> some View {
        HStack(spacing: AppStyle.rowSpacing) {
            if let analyticsFilter {
                // Title and count, like the shelf's detail header.
                HStack(alignment: .firstTextBaseline, spacing: AppStyle.rowSpacing) {
                    Text(analyticsFilter.name).font(AppStyle.dialogTitle).lineLimit(1)
                    Text(AppStyle.records(items.count)).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Spacer(minLength: AppStyle.rowSpacing)
            OverviewLayoutPicker(selection: $layout.animation(AppStyle.fadeAnimation))
        }
        .frame(height: AppStyle.searchBarHeight)
    }
    @ViewBuilder private func actions(_ copy: RecordCopy) -> some View {
        Button(copy.shelf == nil ? "Platz im Regal finden" : "Im Regal anzeigen") { showShelf(copy) }
        if let url = copy.release?.sourceURL {
            Button("Auf Discogs öffnen") { openURL(url) }
        }
        exclusionButton(for: [copy])
        if missingEnabled { missingButton(for: copy) }
        if saleEnabled { saleButton(for: copy) }
    }
    /// Marks the copy "Gesucht" (settings tab "Listen") or found again.
    /// Not offered for one kept out of the shelves ("Ohne Regalplatz"): there
    /// is nothing to look for, `setExcluded` lifts the mark for the same
    /// reason, and the settings wouldn't list it.
    @ViewBuilder private func missingButton(for copy: RecordCopy) -> some View {
        let missing = records.missingMarks.contains { $0.copyID == copy.id }
        if missing || !excludedIDs.contains(copy.id) {
            Button(missing ? "Wieder gefunden" : "Auf die Suchliste setzen") {
                perform { try PositionService(context: context).setMissing([copy], !missing) }
            }
        }
    }
    /// Puts the copy on the "Verkauf" list (settings tab "Listen") or takes it off.
    @ViewBuilder private func saleButton(for copy: RecordCopy) -> some View {
        let forSale = records.saleMarks.contains { $0.copyID == copy.id }
        Button(forSale ? "Nicht mehr verkaufen" : "Zum Verkauf vormerken") {
            perform { try PositionService(context: context).setForSale([copy], !forSale) }
        }
    }
    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { self.error = error.reportedMessage() }
    }
}
