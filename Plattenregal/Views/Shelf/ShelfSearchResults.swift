import SwiftUI

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
    /// Copies marked "Gesucht".
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
                .padding(.horizontal, AppStyle.cardPadding)
                .padding(.vertical, AppStyle.rowSpacing)
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
                    Text("Noch nicht einsortiert")
                        .font(AppStyle.captionMark)
                        .foregroundStyle(SearchPanelInk.muted)
                        .padding(.horizontal, AppStyle.itemSpacing)
                        .padding(.top, matches.isEmpty ? AppStyle.tightSpacing : AppStyle.rowSpacing)
                        .padding(.bottom, AppStyle.tightSpacing)
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
                        .font(AppStyle.captionLabel)
                        .foregroundStyle(AppStyle.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, AppStyle.itemSpacing)
                        .padding(.bottom, AppStyle.tightSpacing)
                }
            }
            .padding(AppStyle.itemSpacing)
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
                        .overlay(shape.strokeBorder(AtelierPalette.border, lineWidth: AppStyle.borderWidth))
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
            VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
                Text(copy.release?.displayArtist ?? "—")
                    .font(AppStyle.rowTitle)
                    .foregroundStyle(SearchPanelInk.ink)
                HStack(spacing: AppStyle.itemSpacing) {
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
        .padding(.horizontal, AppStyle.itemSpacing)
        .frame(height: AssignmentRowMetrics.height)
        .contentShape(Rectangle())
        .appHoverable(hovering, cornerRadius: AppStyle.rowRadius)
        .onHover { hovering = $0 }
    }

    /// Where it stands, in two short lines instead of one cut-off one: the
    /// compartment, then cabinet and position. Without a shelf: the way to one.
    private var place: some View {
        VStack(alignment: .trailing, spacing: AppStyle.hairSpacing) {
            if placeable || copy.shelf == nil {
                // "Noch nicht einsortiert" already heads the section.
                Text("Platz finden").font(AppStyle.captionLabel).foregroundStyle(AppStyle.accent)
            } else if let shelf = copy.shelf {
                let prefix = labels.prefix(for: shelf)
                if shelf.isReserved {
                    Text(shelf.name.isEmpty ? String(localized: "Gesperrtes Fach") : shelf.name)
                        .font(AppStyle.captionLabel).foregroundStyle(SearchPanelInk.ink)
                    if !prefix.isEmpty {
                        Text(prefix.trimmingCharacters(in: CharacterSet(charactersIn: " ·")))
                            .font(.caption2).foregroundStyle(SearchPanelInk.muted)
                    }
                } else {
                    Text(labels[shelf.id] ?? String(localized: "Leeres Fach"))
                        .font(AppStyle.captionLabel).foregroundStyle(SearchPanelInk.ink)
                    Text(prefix + String(localized: "Position \(copy.positionInShelf)"))
                        .font(.caption2.monospacedDigit()).foregroundStyle(SearchPanelInk.muted)
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}


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
