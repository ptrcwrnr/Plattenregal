import SwiftUI
import SwiftData

// MARK: - Search

/// The matches of the shelf search (typed into the field in the toolbar),
/// floating over the rack like a popover so the page layout never shifts
/// while typing. Rows as in "Platte hinzufügen" (same height and cover),
/// the place in the shelf on the right; records without a shelf follow under
/// their own heading. Scrolls only when the window is too low for the list.
struct ShelfSearchResultsPanel: View {
    let matches: [RecordCopy]
    /// Records without a shelf; picking one shows where it belongs, picking
    /// a placed match shows where it stands.
    let unplaced: [RecordCopy]
    /// Matches beyond the listed ones.
    let hidden: Int
    let labels: ShelfLabels
    /// Copies marked "Vermisst".
    let missing: Set<UUID>
    let place: (RecordCopy) -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            results
            ScrollView { results }.scrollIndicators(.automatic)
        }
        .searchPanelSurface()
    }

    @ViewBuilder private var results: some View {
        if matches.isEmpty && unplaced.isEmpty {
            Text("Keine Treffer im Regal.")
                .font(.callout)
                .foregroundStyle(SearchPanelInk.muted)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(matches) { copy in
                    Button { place(copy) } label: {
                        SearchResultRow(copy: copy, labels: labels, missing: missing.contains(copy.id))
                    }
                    .buttonStyle(.plain)
                    .help("Zeigt, zwischen welchen Platten sie steht")
                }
                if !unplaced.isEmpty {
                    Text("Ohne Fach")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SearchPanelInk.muted)
                        .padding(.horizontal, 10)
                        .padding(.top, matches.isEmpty ? 4 : 12)
                        .padding(.bottom, 4)
                    ForEach(unplaced) { copy in
                        Button { place(copy) } label: {
                            SearchResultRow(copy: copy, labels: labels, missing: missing.contains(copy.id), placeable: true)
                        }
                        .buttonStyle(.plain)
                        .help("Zeigt, wo die Platte alphabetisch hingehört")
                    }
                }
                if hidden > 0 {
                    // In the accent like the sync capsule's second line (Klassisch: petrol).
                    Text("\(hidden) weitere Treffer – Suche genauer eingrenzen")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppStyle.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }
            }
            .padding(6)
        }
    }
}

/// Text colors of the panel: the design's ink in Klassisch, the system's in Modern.
private enum SearchPanelInk {
    static var ink: AnyShapeStyle { AppStyle.isAtelier ? AnyShapeStyle(AtelierPalette.ink) : AnyShapeStyle(.primary) }
    static var muted: AnyShapeStyle { AppStyle.isAtelier ? AnyShapeStyle(AtelierPalette.muted) : AnyShapeStyle(.secondary) }
}

private extension View {
    /// Klassisch: paper card like the popovers. Modern: glass tinted toward
    /// the window color like the popovers and the sync capsule, so the rack
    /// underneath doesn't run through the text.
    func searchPanelSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: AppStyle.surfaceRadius)
        return clipShape(shape)
            .background {
                if AppStyle.isAtelier {
                    shape.fill(AtelierPalette.surface)
                        .overlay(shape.strokeBorder(AtelierPalette.border, lineWidth: 1))
                }
            }
            .glassEffect(AppStyle.isAtelier ? .identity : .regular.tint(Color(nsColor: .windowBackgroundColor).opacity(0.65)), in: shape)
            .shadow(color: .black.opacity(AppStyle.isAtelier ? 0.1 : 0.15), radius: 14, y: 4)
    }
}

private struct SearchResultRow: View {
    let copy: RecordCopy
    let labels: ShelfLabels
    var missing = false
    var placeable = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: AppStyle.rowSpacing) {
            CoverView(url: copy.release?.coverURL, size: AssignmentCard<EmptyView>.coverSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(copy.release?.displayArtist ?? "—")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(SearchPanelInk.ink)
                HStack(spacing: 6) {
                    Text(copy.release?.displayTitle ?? "—")
                        .font(.caption)
                        .foregroundStyle(SearchPanelInk.muted)
                    if missing { MissingBadge() }
                }
            }
            .lineLimit(1)
            .opacity(missing ? 0.7 : 1)
            Spacer(minLength: AppStyle.itemSpacing)
            place
        }
        .padding(.horizontal, 8)
        .frame(height: AssignmentRowMetrics.height)
        .contentShape(Rectangle())
        .appHoverable(hovering, cornerRadius: 8)
        .onHover { hovering = $0 }
    }

    /// Where it stands, in two short lines instead of one cut-off one: the
    /// compartment, then cabinet and position. Without a shelf: the way to one.
    private var place: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if placeable || copy.shelf == nil {
                // "Ohne Fach" already heads the section.
                Text("Platz finden").font(.caption.weight(.medium)).foregroundStyle(AppStyle.accent)
            } else if let shelf = copy.shelf {
                let prefix = labels.prefix(for: shelf)
                if shelf.isReserved {
                    Text(shelf.name.isEmpty ? String(localized: "Gesperrtes Fach") : shelf.name)
                        .font(.caption.weight(.medium)).foregroundStyle(SearchPanelInk.ink)
                    if !prefix.isEmpty {
                        Text(prefix.trimmingCharacters(in: CharacterSet(charactersIn: " ·")))
                            .font(.caption2).foregroundStyle(SearchPanelInk.muted)
                    }
                } else {
                    Text(labels[shelf.id] ?? String(localized: "Leeres Fach"))
                        .font(.caption.weight(.medium)).foregroundStyle(SearchPanelInk.ink)
                    Text(prefix + String(localized: "Position \(copy.positionInShelf)"))
                        .font(.caption2.monospacedDigit()).foregroundStyle(SearchPanelInk.muted)
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}


// MARK: - Placement

/// What the shelf search found: placed records (listed with their location),
/// records without a shelf (offered for sorting in) and the shelves to keep
/// lit. `litShelfIDs == nil` while not searching, so nothing is dimmed.
struct ShelfSearchResults {
    static let placedLimit = 8
    static let unplacedLimit = 4
    var placed: [RecordCopy] = []
    var unplaced: [RecordCopy] = []
    /// Matches left out by the limits above.
    var hidden = 0
    var litShelfIDs: Set<UUID>? = nil
}

/// A record being sorted in: the spots it fits (one, or two at a shelf
/// boundary) and the one currently shown. For a record that already has a
/// shelf (`found`) the single spot is where it stands, to put it back there.
struct Placement {
    let copy: RecordCopy
    let found: Bool
    let spots: [AlphabeticalPlacement.Spot]
    var chosen = 0
    /// Marked "Nicht im Regal"; sorting it in lifts that.
    var excluded = false
    /// Marked "Vermisst"; sorting it in counts as found.
    var missing = false
    /// Name of the deactivated cabinet the record stands in: its shelf isn't
    /// on this page, so there is no spot to show.
    let putAwayIn: String?

    init(copy: RecordCopy, shelves: [Shelf]) {
        self.copy = copy
        found = copy.shelf != nil
        if let shelf = copy.shelf, !shelf.isInUse {
            putAwayIn = shelf.cabinet?.name ?? ""
            spots = []
            return
        }
        putAwayIn = nil
        spots = found
            ? AlphabeticalPlacement.current(for: copy, in: shelves).map { [$0] } ?? []
            : AlphabeticalPlacement.spots(for: copy, in: shelves)
    }
    var spot: AlphabeticalPlacement.Spot? { spots.indices.contains(chosen) ? spots[chosen] : nil }
}

/// Sits above the compartment that was picked for the record: what goes
/// where, between which two records, and — at a shelf boundary — the other
/// shelf that fits just as well, with how many records each already holds.
struct PlacementCard: View {
    let placement: Placement
    let labels: ShelfLabels
    /// Copies marked "Vermisst": no help as a landmark at the shelf.
    let missing: Set<UUID>
    let choose: (Int) -> Void
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        let release = placement.copy.release
        // Cover and text from the top; the buttons centered beside them.
        HStack(spacing: AppStyle.rowSpacing) {
            HStack(alignment: .top, spacing: AppStyle.rowSpacing) {
                CoverView(url: release?.coverURL, size: 52)
                VStack(alignment: .leading, spacing: AppStyle.tightSpacing) {
                    Text("\(placement.found ? String(localized: "Hier steht") : String(localized: "Einsortieren")): \(release?.displayArtist ?? "—") – \(release?.displayTitle ?? "—")")
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if placement.excluded && !placement.found {
                        Label("Steht auf „Nicht im Regal“ – beim Einsortieren wird das aufgehoben.", systemImage: "info.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if placement.missing && placement.putAwayIn == nil {
                        Label(placement.found
                              ? "Als vermisst markiert – hier sollte sie stehen."
                              : "Als vermisst markiert – beim Einsortieren gilt sie als gefunden.",
                              systemImage: "pause.circle")
                            .font(.callout)
                            .foregroundStyle(AppStyle.errorColor)
                    }
                    if let spot = placement.spot {
                        Text(location(spot))
                            .font(.callout)
                        // An empty shelf has no neighbours: no empty line then.
                        if spot.before != nil || spot.after != nil {
                            Text(neighbours(spot))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        ForEach(Array(placement.spots.enumerated()), id: \.element.id) { index, other in
                            if index != placement.chosen {
                                Button { choose(index) } label: {
                                    Text("Passt genauso \(other.position == 1 ? String(localized: "an den Anfang") : String(localized: "ans Ende")) von „\(name(other.shelf))“ (\(AppStyle.records(other.shelf.copies.count))) – dorthin wechseln")
                                }
                                .appLinkButton()
                                .font(.callout)
                                .padding(.top, 2)
                            }
                        }
                    } else if let cabinet = placement.putAwayIn {
                        Text("Steht im deaktivierten Regal „\(cabinet)“. Aktiviere es in den Einstellungen unter „Regale“, um sie hier zu sehen.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Es steht noch keine Platte im Regal, an der sich die Platte ausrichten könnte. Wähle ein Fach und füge sie dort über „+“ hinzu.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: AppStyle.itemSpacing)
            HStack(spacing: AppStyle.itemSpacing) {
                SecondaryButton(title: String(localized: "Abbrechen"), action: cancel)
                if placement.spot != nil {
                    PrimaryButton(title: placement.found ? String(localized: "Gefunden") : String(localized: "Hier einsortieren"), action: confirm)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(AppStyle.cardPadding)
        .accentGlassCard()
    }

    /// As chosen in the settings; shelves are never named by their internal number.
    private func name(_ shelf: Shelf) -> String { labels.prefix(for: shelf) + (labels[shelf.id] ?? String(localized: "Leeres Fach")) }

    private func location(_ spot: AlphabeticalPlacement.Spot) -> String {
        let count = spot.shelf.copies.count
        let place = spot.position == 1 ? String(localized: "ganz links") : spot.position > count ? String(localized: "ganz rechts") : String(localized: "Position \(spot.position)")
        return String(localized: "Fach „\(name(spot.shelf))“ · \(place) · \(AppStyle.records(count)) im Fach")
    }

    private func neighbours(_ spot: AlphabeticalPlacement.Spot) -> String {
        func title(_ copy: RecordCopy) -> String {
            let text = String(localized: "„\(copy.release?.displayArtist ?? "—") – \(copy.release?.displayTitle ?? "—")“")
            let note = missing.contains(copy.id) ? String(localized: " – vermisst") : ""
            guard let shelf = copy.shelf, shelf.id != spot.shelf.id else { return text + note }
            return text + String(localized: " (Fach „\(name(shelf))“\(note))")
        }
        switch (spot.before, spot.after) {
        case let (before?, after?): return String(localized: "Zwischen \(title(before)) und \(title(after))")
        case let (before?, nil): return String(localized: "Nach \(title(before))")
        case let (nil, after?): return String(localized: "Vor \(title(after))")
        case (nil, nil): return ""
        }
    }
}

struct UnplacedCopy {
    let id = UUID()
    let copy: RecordCopy
    let shelf: Shelf
    let position: Int
}
