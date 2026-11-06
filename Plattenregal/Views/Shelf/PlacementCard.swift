import SwiftUI

/// A record being sorted in: the spots it fits (one, or two at a shelf
/// boundary) and the one currently shown. For a record that already has a
/// shelf (`found`) the single spot is where it stands, to put it back there.
struct Placement {
    let copy: RecordCopy
    let found: Bool
    let spots: [AlphabeticalPlacement.Spot]
    var chosen = 0
    /// Marked "Ohne Regalplatz"; sorting it in lifts that.
    var excluded = false
    /// Marked "Gesucht"; sorting it in counts as found.
    var missing = false
    /// Name of the deactivated cabinet the record stands in: its shelf isn't
    /// on this page, so there is no spot to show.
    let putAwayIn: String?

    /// `openShelf` and `cabinet`: where the page stands. A record without a
    /// shelf is sorted into the cabinet shown (`AlphabeticalPlacement.spots`);
    /// at a boundary between two of its compartments the open one comes
    /// first (see `AlphabeticalPlacement.preferredIndex`).
    init(copy: RecordCopy, shelves: [Shelf], openShelf: UUID? = nil, cabinet: UUID? = nil) {
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
            : AlphabeticalPlacement.spots(for: copy, in: shelves, cabinet: cabinet)
        chosen = AlphabeticalPlacement.preferredIndex(spots, for: copy, openShelf: openShelf, cabinet: cabinet)
    }
    var spot: AlphabeticalPlacement.Spot? { spots.indices.contains(chosen) ? spots[chosen] : nil }
}

/// Sits above the compartment that was picked for the record: what goes
/// where, between which two records, and — at a shelf boundary — the other
/// shelf that fits just as well, with how many records each already holds.
struct PlacementCard: View {
    let placement: Placement
    let labels: ShelfLabels
    /// Copies marked "Gesucht": no help as a landmark at the shelf.
    let missing: Set<UUID>
    let choose: (Int) -> Void
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        let release = placement.copy.release
        // Cover and text from the top; the buttons centered beside them.
        HStack(spacing: AppStyle.rowSpacing) {
            HStack(alignment: .top, spacing: AppStyle.rowSpacing) {
                CoverView(url: release?.shownCoverURL, size: 52)
                VStack(alignment: .leading, spacing: AppStyle.tightSpacing) {
                    Text("\(placement.found ? String(localized: "Hier steht") : String(localized: "Einsortieren")): \(release?.displayArtist ?? "—") – \(release?.displayTitle ?? "—")")
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if placement.excluded && !placement.found {
                        Label("Steht auf „Ohne Regalplatz“ – beim Einsortieren wird das aufgehoben.", systemImage: "info.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if placement.missing && placement.putAwayIn == nil {
                        Label(placement.found
                              ? "Steht auf der Suchliste – hier sollte sie stehen."
                              : "Steht auf der Suchliste – beim Einsortieren gilt sie als gefunden.",
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
                                .padding(.top, AppStyle.hairSpacing)
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
            let note = missing.contains(copy.id) ? String(localized: " – gesucht") : ""
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
    /// Undone through the history, so the entry is marked and no new one is written.
    let entry: ShelfHistoryEntry
}
