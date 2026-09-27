import SwiftUI
import SwiftData

// MARK: - Search

/// Slim search field; matches float over the rack like a popover so the page
/// layout never shifts while typing.
struct ShelfSearchField: View {
    /// Committed query, updated after a short pause in typing so the page
    /// behind the field isn't rebuilt on every keystroke.
    @Binding var query: String
    var focused: FocusState<Bool>.Binding
    let matches: [RecordCopy]
    /// Records without a shelf; picking one shows where it belongs, picking
    /// a placed match shows where it stands.
    let unplaced: [RecordCopy]
    /// Matches beyond the listed ones.
    let hidden: Int
    let labels: ShelfLabels
    /// Copies marked "Vermisst".
    let missing: Set<UUID>
    let onClear: () -> Void
    let place: (RecordCopy) -> Void
    @State private var text = ""

    /// Only words count: a field of spaces searches nothing.
    private static func hasWords(_ value: String) -> Bool { !SearchIndex<UUID>.words(value).isEmpty }

    private func clear() {
        text = ""
        onClear()
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Platte im Regal suchen …", text: $text)
                .textFieldStyle(.plain)
                .noTextAutoFill()
                .focused(focused)
                // Esc clears the query; with an empty field it gives up the
                // focus, which hides the search bar again (see `SearchReveal`).
                .onExitCommand { if text.isEmpty { focused.wrappedValue = false } else { clear() } }
            if !text.isEmpty {
                Button(action: clear) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.callout)
        .searchBarChrome()
        .overlay(alignment: .topLeading) {
            if Self.hasWords(text) && Self.hasWords(query) {
                results.offset(y: AppStyle.searchBarHeight + 6)
                    // Still the previous query's matches while typing pauses.
                    .opacity(query == text ? 1 : 0.6)
                    .animation(AppStyle.quickAnimation, value: query == text)
            }
        }
        .task(id: text) {
            // Clearing is immediate; typing waits for a short pause.
            if !text.isEmpty {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
            }
            if query != text { query = text }
        }
        // Cleared from outside (picking a shelf or a result).
        .onChange(of: query) { _, new in if new.isEmpty { text = "" } }
    }

    @ViewBuilder private var results: some View {
        Group {
            if matches.isEmpty && unplaced.isEmpty {
                Text("Keine Treffer im Regal.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(matches) { copy in
                        Button { place(copy) } label: {
                            SearchResultRow(copy: copy, labels: labels, missing: missing.contains(copy.id))
                        }
                        .buttonStyle(.plain)
                        .help("Zeigt, zwischen welchen Platten sie steht")
                    }
                    if !unplaced.isEmpty {
                        if !matches.isEmpty { Divider().padding(.vertical, 3) }
                        ForEach(unplaced) { copy in
                            Button { place(copy) } label: {
                                SearchResultRow(copy: copy, labels: labels, missing: missing.contains(copy.id), placeable: true)
                            }
                            .buttonStyle(.plain)
                            .help("Zeigt, wo die Platte alphabetisch hingehört")
                        }
                    }
                    if hidden > 0 {
                        Text("\(hidden) weitere Treffer – Suche genauer eingrenzen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                    }
                }
                .padding(5)
            }
        }
        // Same glass as the system popovers in the overview.
        .appGlassSurface(cornerRadius: 12)
    }
}

private struct SearchResultRow: View {
    let copy: RecordCopy
    let labels: ShelfLabels
    var missing = false
    var placeable = false
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 10) {
            CoverView(url: copy.release?.coverURL, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(copy.release?.displayArtist ?? "—").font(.callout).lineLimit(1)
                HStack(spacing: 6) {
                    Text(copy.release?.displayTitle ?? "—").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if missing { MissingBadge() }
                }
            }
            Spacer(minLength: 8)
            Text(placeable ? "Ohne Fach · Platz finden" : ShelfRangeLabels.location(of: copy, labels: labels))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .appHoverable(hovering, cornerRadius: 8)
        .onHover { hovering = $0 }
    }
}

/// Full-width strip of the selected compartment: an abstracted row of record
/// spines standing left to right, matching how the physical copies sit in the
/// shelf. Clicking a spine pulls it out; the line underneath carries both the
/// selection and the genre legend so the colors are explained right where
/// they're used.
struct ShelfPositionStrip: View {
    let stats: ShelfStatistics
    let slots: Int
    let palette: StylePalette
    let selectedCopy: RecordCopy?
    /// 1-based index of `selectedCopy` among the drawn spines.
    let selectedSlot: Int?
    /// Where a record being sorted in would go; drawn as a marker between spines.
    var insertionPosition: Int? = nil
    /// 1-based spines marked "Vermisst"; drawn as an outline.
    var missingSlots: Set<Int> = []
    /// The records in spine order, for the cover shown on hover.
    let copies: [RecordCopy]
    let select: (Int) -> Void

    /// The spine under the pointer (1-based), once the cover is shown.
    @State private var hoveredSlot: Int?
    /// The cover appears only after the pointer rested a moment, so passing
    /// over the strip on the way to the table doesn't flash it; from then on
    /// it follows the pointer at once, until it leaves the strip.
    @State private var armed = false
    @State private var arming: Task<Void, Never>?
    /// Where the pointer is while the delay runs.
    @State private var pendingSlot: Int?
    @State private var rackWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SpineRack(
                styles: stats.spineStyles,
                slots: slots,
                palette: palette,
                selectedPosition: selectedSlot,
                insertionPosition: insertionPosition,
                missingPositions: missingSlots,
                selectable: true,
                onSelect: select
            )
            .frame(height: 46)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { rackWidth = $0 }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hover(at: point.x)
                case .ended:
                    arming?.cancel(); arming = nil
                    armed = false; hoveredSlot = nil
                }
            }
            .overlay { hoverCover }
            HStack(spacing: AppStyle.rowSpacing) {
                Group {
                    if let insertionPosition {
                        Text("Neue Platte an Position \(insertionPosition) · \(AppStyle.records(stats.count)) im Fach")
                            .foregroundStyle(AppStyle.accent)
                    } else if let copy = selectedCopy {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(palette.color(for: copy.release?.primaryStyle ?? "", solid: true))
                                .frame(width: 7, height: 7)
                            Text("Position \(selectedSlot ?? copy.positionInShelf) von \(stats.count) · \(copy.release?.displayArtist ?? "—") – \(copy.release?.displayTitle ?? "—")")
                                .foregroundStyle(.primary)
                            if let slot = selectedSlot, missingSlots.contains(slot) { MissingBadge() }
                        }
                    } else {
                        // The count is in the header right above.
                        Text("Von links nach rechts"
                             + (missingSlots.isEmpty ? "" : " · \(missingSlots.count) vermisst"))
                    }
                }
                .lineLimit(1)
                .truncationMode(.tail)
                Spacer(minLength: AppStyle.rowSpacing)
                ShelfStyleLegend(stats: stats, palette: palette)
                    .layoutPriority(-1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var layout: SpineLayout { SpineLayout(width: rackWidth, slots: max(slots, stats.spineStyles.count, 1)) }

    private func hover(at x: CGFloat) {
        guard rackWidth > 0 else { return }
        let index = layout.index(at: x)
        let slot = copies.indices.contains(index) ? index + 1 : nil
        if armed { hoveredSlot = slot; return }
        guard arming == nil else { pendingSlot = slot; return }
        pendingSlot = slot
        arming = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            armed = true
            hoveredSlot = pendingSlot
            arming = nil
        }
    }
    /// The hovered record's cover on a small glass card beside its spine, on
    /// whichever side has room. Purely visual: clicks reach the spines.
    private var hoverCover: some View {
        GeometryReader { geometry in
            if let slot = hoveredSlot, copies.indices.contains(slot - 1) {
                let card: CGFloat = 52
                let spine = layout.midX(slot - 1)
                let offset = max(layout.pitch, 3) + 8 + card / 2
                let x = spine + offset + card / 2 <= geometry.size.width ? spine + offset : spine - offset
                CoverView(url: copies[slot - 1].release?.coverURL, size: card - 8)
                    .padding(4)
                    .glassEffect(.regular, in: .rect(cornerRadius: 10))
                    .position(x: x, y: geometry.size.height - card / 2)
                    .transition(AppStyle.reduceMotion ? .opacity : .scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
        .animation(AppStyle.quickAnimation, value: hoveredSlot)
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
        HStack(alignment: .top, spacing: AppStyle.rowSpacing) {
            CoverView(url: release?.coverURL, size: 52)
            VStack(alignment: .leading, spacing: AppStyle.tightSpacing) {
                Text("\(placement.found ? "Hier steht" : "Einsortieren"): \(release?.displayArtist ?? "—") – \(release?.displayTitle ?? "—")")
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
                                Text("Passt genauso \(other.position == 1 ? "an den Anfang" : "ans Ende") von „\(name(other.shelf))“ (\(AppStyle.records(other.shelf.copies.count))) – dorthin wechseln")
                            }
                            .buttonStyle(.link)
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
            Spacer(minLength: AppStyle.itemSpacing)
            HStack(spacing: AppStyle.itemSpacing) {
                SecondaryButton(title: "Abbrechen", action: cancel)
                if placement.spot != nil {
                    PrimaryButton(title: placement.found ? "Gefunden" : "Hier einsortieren", action: confirm)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(AppStyle.cardPadding)
        .accentGlassCard()
    }

    /// As chosen in the settings; shelves are never named by their internal number.
    private func name(_ shelf: Shelf) -> String { labels.prefix(for: shelf) + (labels[shelf.id] ?? "Leeres Fach") }

    private func location(_ spot: AlphabeticalPlacement.Spot) -> String {
        let count = spot.shelf.copies.count
        let place = spot.position == 1 ? "ganz links" : spot.position > count ? "ganz rechts" : "Position \(spot.position)"
        return "Fach „\(name(spot.shelf))“ · \(place) · \(AppStyle.records(count)) im Fach"
    }

    private func neighbours(_ spot: AlphabeticalPlacement.Spot) -> String {
        func title(_ copy: RecordCopy) -> String {
            let text = "„\(copy.release?.displayArtist ?? "—") – \(copy.release?.displayTitle ?? "—")“"
            let note = missing.contains(copy.id) ? " – vermisst" : ""
            guard let shelf = copy.shelf, shelf.id != spot.shelf.id else { return text + note }
            return text + " (Fach „\(name(shelf))“\(note))"
        }
        switch (spot.before, spot.after) {
        case let (before?, after?): return "Zwischen \(title(before)) und \(title(after))"
        case let (before?, nil): return "Nach \(title(before))"
        case let (nil, after?): return "Vor \(title(after))"
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
