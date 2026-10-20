import SwiftUI
import SwiftData

extension ShelfContentsView {
    var table: some View {
        Table(tableItems, selection: selection, sortOrder: Binding(
            get: { sortOrder }, set: { session.tableSortOrder = $0 }
        )) {
            TableColumn("Pos.", value: \.position) { item in
                Text(String(item.position)).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 34, ideal: 40, max: 52)
            TableColumn("") { item in CoverView(url: item.copy.release?.coverURL, size: 20) }
                .width(24)
            TableColumn("Interpret", value: \.artist) { item in
                Text(item.artist).lineLimit(1).help(item.artist)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .popover(isPresented: quickEditBinding(item.id), arrowEdge: .trailing) {
                        quickEditor(item.copy)
                    }
            }
            .width(min: 120, ideal: 220)
            TableColumn("Titel", value: \.title) { item in
                HStack(spacing: AppStyle.itemSpacing) {
                    Text(item.title).lineLimit(1).help(item.title)
                    if item.missing {
                        MissingBadge()
                            .help("Beim Einsortieren nicht gefunden – Rechtsklick → „Wieder gefunden“, sobald sie auftaucht")
                    }
                    if item.forSale { SaleBadge() }
                    if item.sold {
                        StatusTag(text: String(localized: "Nicht in der Collection"), color: AppStyle.warningColor)
                            .help("Nicht (mehr) in deiner Discogs-Collection – per Rechtsklick aus dem Fach entfernen")
                    }
                }
            }
            .width(min: 120, ideal: 280)
            TableColumn("Jahr", value: \.year) { item in
                Text(item.year > 0 ? String(item.year) : "–").monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 40, ideal: 48, max: 60)
            TableColumn("Label", value: \.label) { item in
                Text(item.label.isEmpty ? "–" : item.label).lineLimit(1).foregroundStyle(.secondary).help(item.label)
            }
            .width(min: 80, ideal: 160)
            TableColumn("Genre", value: \.genre) { item in
                Text(item.genre.isEmpty ? "–" : item.genre).lineLimit(1).foregroundStyle(.secondary).help(item.genre)
            }
            .width(min: 80, ideal: 130)
        }
        .tableStyle(.inset)
        .background(QuietIconColumnHeaders())
        .background(TableRowClickToggle { selectLocally(nil) })
        .alternatingRowBackgrounds(.disabled)
        .scrollContentBackground(.hidden)
        // The last rows scroll clear of the round button.
        .contentMargins(.bottom, AppStyle.floatingClearance, for: .scrollContent)
        .contextMenu(forSelectionType: UUID.self) { _ in } primaryAction: { ids in
            if let id = ids.first, let copy = items.first(where: { $0.id == id })?.copy { activate(copy) }
        }
        .overlay(TableRowClicks(secondary: { row, point in
            guard tableItems.indices.contains(row) else { return }
            quickEditID = nil
            menuFor = (tableItems[row].id, point)
        }))
        .popover(isPresented: Binding(get: { menuFor != nil }, set: { if !$0 { menuFor = nil } }),
                 attachmentAnchor: .point(menuFor?.anchor ?? .center), arrowEdge: .trailing) {
            if let id = menuFor?.id, let copy = items.first(where: { $0.id == id })?.copy {
                actionMenu(copy)
            }
        }
        .background(ShelfTableScrollBridge(
            ids: tableItems.map(\.id),
            position: scrollPosition(for: .list),
            revealID: focusScroll?.layout == .list ? focusScroll?.copyID : nil,
            revealRequest: focusScroll?.layout == .list ? focusScroll?.requestID : nil
        ))
        .id(loadedShelfID)
        .appTableCard()
    }
}
