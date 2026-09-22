import SwiftUI
import SwiftData

struct KallaxView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Shelf.number) private var shelves: [Shelf]
    @Query private var allCopies: [RecordCopy]
    @Query private var shelfCustomizations: [ShelfCustomization]
    @Binding var highlight: UUID?
    @State private var configured: Shelf?
    @State private var editCopy: RecordCopy?
    @State private var assigningToShelf: Shelf?
    // Forces a fresh ShelfAssignmentView (and its @Query) on every presentation,
    // even when the same shelf is reopened right after assigning a copy — otherwise
    // SwiftUI can keep the sheet's prior state across a quick dismiss/re-present,
    // showing an already-assigned copy as available again.
    @State private var assignmentToken = UUID()
    @State private var pendingUnplace: RecordCopy?
    @State private var pendingDelete: RecordCopy?
    @State private var sortingShelf: Shelf?
    @State private var error: String?

    // Search inside the shelf view. `focusCopy` is the exact match the user clicked
    // (persists until search is cleared); `previewCopy` is a hover-only preview that
    // reverts the instant the mouse leaves. `focusIsFromSearch` tracks whether the
    // current `highlight` was set by search so clearing it can cleanly return to
    // the unfocused overview.
    @State private var searchQuery = ""
    @State private var focusCopy: RecordCopy?
    @State private var previewCopy: RecordCopy?
    @State private var focusIsFromSearch = false

    // Recomputed only when the underlying placement/style data actually changes
    // (see `statsSignature`), not on every keystroke or unrelated re-render.
    @State private var shelfStats: [UUID: ShelfStatistics] = [:]

    private var committedShelf: Shelf? { shelves.first { $0.id == highlight } }
    // The shelf actually shown on the right: a hover preview temporarily takes
    // over so moving through search results live-updates the whole detail pane,
    // then reverts to whatever is actually selected once the hover ends.
    private var detailShelf: Shelf? { previewCopy?.shelf ?? committedShelf }
    private var activeCopy: RecordCopy? { previewCopy ?? focusCopy }

    private var statsSignature: Int {
        var hasher = Hasher()
        for copy in allCopies {
            hasher.combine(copy.shelf?.id)
            hasher.combine(copy.positionInShelf)
            hasher.combine(copy.release?.primaryStyle)
        }
        for shelf in shelves { hasher.combine(shelf.capacity) }
        return hasher.finalize()
    }

    private var searchMatches: [RecordCopy] {
        guard !searchQuery.isEmpty else { return [] }
        return Array(
            allCopies
                .filter { $0.shelf != nil && SortingService.matches($0, query: searchQuery) }
                .sorted {
                    let left = ($0.release?.displayArtist ?? "") + "\t" + ($0.release?.displayTitle ?? "")
                    let right = ($1.release?.displayArtist ?? "") + "\t" + ($1.release?.displayTitle ?? "")
                    return left.localizedStandardCompare(right) == .orderedAscending
                }
                .prefix(8)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
            AppPageHeading(title: "Alles hat seinen Platz.", subtitle: "KALLAX · 3 × 4 Fächer")
                .padding(.horizontal, AppStyle.pagePadding)
                .padding(.top, AppStyle.pagePadding)
            GeometryReader { geometry in
                HSplitView {
                    ScrollView {
                        VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                            ShelfSearchField(
                                query: $searchQuery,
                                matches: searchMatches,
                                focusCopy: focusCopy,
                                onSelect: focusOnSearchResult,
                                onPreview: previewSearchResult,
                                onClear: clearSearch
                            )
                            ShelfOverviewStrip(copies: allCopies, shelves: shelves)
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: ShelfGeometry.columns),
                                spacing: 12
                            ) {
                                ForEach(shelves) { shelf in
                                    Button { selectShelf(shelf) } label: {
                                        ShelfCard(
                                            shelf: shelf,
                                            stats: shelfStats[shelf.id] ?? ShelfStatistics(shelf: shelf),
                                            selected: detailShelf?.id == shelf.id,
                                            dimmed: activeCopy != nil && activeCopy?.shelf?.id != shelf.id
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu { shelfMenu(for: shelf) }
                                }
                            }
                        }
                        .padding(AppStyle.pagePadding)
                    }
                    .frame(minWidth: 560, idealWidth: 690)
                    .frame(height: geometry.size.height)

                    shelfDetail
                        .frame(minWidth: 390, idealWidth: 470)
                        .frame(height: geometry.size.height)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .task(id: statsSignature) {
            shelfStats = Dictionary(uniqueKeysWithValues: shelves.map { ($0.id, ShelfStatistics(shelf: $0)) })
        }
        .sheet(item: $configured) { ShelfEditor(shelf: $0) }
        .sheet(item: $editCopy) { RecordEditor(copy: $0) }
        .sheet(item: $assigningToShelf) { ShelfAssignmentView(shelf: $0).id(assignmentToken) }
        .confirmationDialog(
            "Platte aus dem Fach entfernen?",
            isPresented: Binding(get: { pendingUnplace != nil }, set: { if !$0 { pendingUnplace = nil } })
        ) {
            Button("Aus KALLAX entfernen", role: .destructive) {
                if let copy = pendingUnplace { unplace(copy) }
                pendingUnplace = nil
            }
            Button("Abbrechen", role: .cancel) { pendingUnplace = nil }
        } message: {
            Text("Das Exemplar bleibt in deiner Sammlung und kann später wieder einem Fach zugeordnet werden.")
        }
        .confirmationDialog(
            "Exemplar endgültig aus der Sammlung löschen?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
        ) {
            Button("Aus Sammlung löschen", role: .destructive) {
                if let copy = pendingDelete { delete(copy) }
                pendingDelete = nil
            }
            Button("Abbrechen", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Diese Aktion entfernt das Exemplar samt deinen lokalen Exemplardaten. Sie kann nicht rückgängig gemacht werden.")
        }
        .confirmationDialog(
            "Physische Reihenfolge ändern?",
            isPresented: Binding(get: { sortingShelf != nil }, set: { if !$0 { sortingShelf = nil } })
        ) {
            Button("Fach alphabetisch sortieren") {
                if let shelf = sortingShelf {
                    do { try PositionService(context: context).sort(shelf, by: .artistAZ) }
                    catch { self.error = error.localizedDescription }
                }
                sortingShelf = nil
            }
        } message: {
            Text("Die gespeicherten Positionen dieses Fachs ändern sich. Stelle die Platten anschließend auch im Regal in diese Reihenfolge.")
        }
        .alert(
            "Änderung nicht möglich",
            isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
        ) { Button("OK") {} } message: { Text(error ?? "") }
    }

    @ViewBuilder private var shelfDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let shown = detailShelf {
                let stats = shelfStats[shown.id] ?? ShelfStatistics(shelf: shown)
                let stripCopy = [previewCopy, focusCopy].compactMap { $0 }.first { $0.shelf?.id == shown.id }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(shown.title).font(AppStyle.dialogTitle)
                                Text("· \(stats.count)/\(stats.capacity) · \(stats.occupancyPercent) %")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            if !infoText(for: shown).isEmpty {
                                Text(infoText(for: shown))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Button { assignmentToken = UUID(); assigningToShelf = shown } label: {
                            Image(systemName: "plus")
                        }
                        .help("Platte aus der Sammlung hinzufügen")
                        .disabled(shown.copies.count >= shown.capacity)
                        Button { configured = shown } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .help("Fach bearbeiten")
                    }
                    .appGlassButton()
                    ShelfStyleBreakdown(stats: stats)
                    ShelfPositionStrip(stats: stats, focusCopy: stripCopy)
                }
                .padding(.horizontal, AppStyle.pagePadding)
                .padding(.top, AppStyle.pagePadding)
                .padding(.bottom, AppStyle.cardPadding)
                Divider()
                if shown.copies.isEmpty {
                    AppEmptyState(
                        "Hier ist noch Platz",
                        systemImage: "opticaldisc",
                        description: Text("Noch keine Platten in diesem Fach."),
                        actionTitle: "Platte hinzufügen",
                        action: { assignmentToken = UUID(); assigningToShelf = shown }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ShelfCopyList(
                        shelf: shown,
                        focusCopy: focusCopy,
                        open: { copy in focusCopy = copy },
                        edit: { editCopy = $0 },
                        unplace: { pendingUnplace = $0 },
                        delete: { pendingDelete = $0 },
                        preview: { previewCopy = $0 }
                    )
                }
            } else {
                VStack(spacing: 0) {
                    AppEmptyState(
                        "Fach auswählen",
                        systemImage: "square.grid.3x3",
                        description: Text("Wähle ein Fach oder suche oben nach einer Platte.")
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder private func shelfMenu(for shelf: Shelf) -> some View {
        Button("Inhalt anzeigen") { selectShelf(shelf) }
        Button("Vorhandenes Exemplar zuweisen …") { assignmentToken = UUID(); assigningToShelf = shelf }
            .disabled(shelf.copies.count >= shelf.capacity)
        Divider()
        Button("Name, Infotext und Kapazität") { configured = shelf }
        Button("Alphabetisch sortieren …") { sortingShelf = shelf }
            .disabled(shelf.copies.count < 2)
    }

    private func selectShelf(_ shelf: Shelf) {
        searchQuery = ""; focusCopy = nil; previewCopy = nil; focusIsFromSearch = false
        withAnimation(.easeInOut(duration: 0.25)) { highlight = shelf.id }
    }

    private func previewSearchResult(_ copy: RecordCopy?) {
        previewCopy = copy
    }

    private func focusOnSearchResult(_ copy: RecordCopy) {
        previewCopy = nil
        focusCopy = copy
        focusIsFromSearch = true
        withAnimation(.easeInOut(duration: 0.35)) { highlight = copy.shelf?.id }
    }

    private func clearSearch() {
        searchQuery = ""
        focusCopy = nil
        previewCopy = nil
        if focusIsFromSearch {
            withAnimation(.easeInOut(duration: 0.25)) { highlight = nil }
            focusIsFromSearch = false
        }
    }

    private func unplace(_ copy: RecordCopy) {
        do { try PositionService(context: context).unplace(copy) }
        catch { self.error = error.localizedDescription }
    }

    private func delete(_ copy: RecordCopy) {
        do { try PositionService(context: context).delete(copy) }
        catch { self.error = error.localizedDescription }
    }

    private func infoText(for shelf: Shelf) -> String {
        shelfCustomizations.first { $0.shelfID == shelf.id }?.infoText ?? ""
    }
}

// MARK: - Search

private struct ShelfSearchField: View {
    @Binding var query: String
    let matches: [RecordCopy]
    let focusCopy: RecordCopy?
    let onSelect: (RecordCopy) -> Void
    let onPreview: (RecordCopy?) -> Void
    let onClear: () -> Void
    @FocusState private var focused: Bool
    @State private var hoveredID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Platte im Regal suchen …", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                if !query.isEmpty {
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .appGlassSurface(cornerRadius: AppStyle.surfaceRadius)

            if !query.isEmpty && focusCopy == nil {
                if matches.isEmpty {
                    Text("Keine Treffer im Regal.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(matches) { copy in
                            Button { onSelect(copy) } label: {
                                SearchResultRow(copy: copy)
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                if hovering {
                                    hoveredID = copy.id
                                    onPreview(copy)
                                } else if hoveredID == copy.id {
                                    hoveredID = nil
                                    onPreview(nil)
                                }
                            }
                            .background(hoveredID == copy.id ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(6)
                    .appGlassSurface(cornerRadius: AppStyle.surfaceRadius)
                    .onDisappear { onPreview(nil) }
                }
            }
        }
    }
}

private struct SearchResultRow: View {
    let copy: RecordCopy
    var body: some View {
        HStack(spacing: 10) {
            CoverView(url: copy.release?.coverURL, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(copy.release?.displayArtist ?? "—").font(.callout).lineLimit(1)
                Text(copy.release?.displayTitle ?? "—").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(copy.location)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }
}

/// Always-present, compact strip: an abstracted row of record spines standing
/// left to right, matching how the physical copies sit in the shelf. With no
/// search focus it just reads as a quiet texture; once a copy is matched, its
/// spine pops up in accent color so the position reads at a glance. Keeping
/// the same slot on screen in both states avoids the layout jumping around
/// as a search starts or clears.
private struct ShelfPositionStrip: View {
    let stats: ShelfStatistics
    let focusCopy: RecordCopy?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            RecordRackStrip(count: stats.count, highlightPosition: focusCopy?.positionInShelf)
            Group {
                if let focusCopy {
                    Text("Position \(focusCopy.positionInShelf) von \(stats.count) · \(focusCopy.release?.displayArtist ?? "—") – \(focusCopy.release?.displayTitle ?? "—")")
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text(stats.count == 0 ? "Noch leer" : "\(stats.count) Platten")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .lineLimit(1)
            .animation(nil, value: focusCopy?.id)
        }
    }
}

private struct RecordRackStrip: View {
    let count: Int
    let highlightPosition: Int?

    var body: some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(1...max(count, 1), id: \.self) { position in
                let isTarget = position == highlightPosition
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isTarget ? Color.accentColor : Color.primary.opacity(0.12))
                    .frame(maxWidth: .infinity)
                    .frame(height: isTarget ? 22 : 12)
                    .shadow(color: isTarget ? Color.accentColor.opacity(0.35) : .clear, radius: 2, y: 1)
            }
        }
        .frame(height: 24, alignment: .bottom)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: highlightPosition)
    }
}

// MARK: - Overview strip

private struct ShelfOverviewStrip: View {
    let copies: [RecordCopy]
    let shelves: [Shelf]

    var body: some View {
        HStack(spacing: 10) {
            metric("Einsortiert", value: "\(copies.filter { $0.shelf != nil }.count)", symbol: "checkmark.circle")
            metric("Ohne Fach", value: "\(copies.filter { $0.shelf == nil }.count)", symbol: "tray")
            metric("Freie Plätze", value: "\(max(0, shelves.reduce(0) { $0 + $1.capacity } - copies.filter { $0.shelf != nil }.count))", symbol: "square.grid.3x3")
        }
    }

    private func metric(_ title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.headline.monospacedDigit())
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appGlassSurface(cornerRadius: AppStyle.surfaceRadius)
    }
}

// MARK: - Shelf card

struct ShelfCard: View {
    let shelf: Shelf
    let stats: ShelfStatistics
    var selected = false
    var dimmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(shelf.title).font(.headline).lineLimit(1)
                Spacer()
                if selected { Image(systemName: "location.fill").foregroundStyle(Color.accentColor) }
            }
            Spacer(minLength: 0)
            Text("\(stats.count) / \(stats.capacity)").font(.title3.monospacedDigit())
            ShelfFillGauge(fraction: stats.occupancyFraction, level: stats.fillLevel)
        }
        .padding(AppStyle.cardPadding)
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .leading)
        .background(selected ? Color.accentColor.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 16))
        .appGlassSurface(cornerRadius: 16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2 : 1))
        .opacity(dimmed ? 0.4 : 1)
        .scaleEffect(dimmed ? 0.98 : 1)
        .animation(.easeInOut(duration: 0.25), value: dimmed)
        .animation(.easeInOut(duration: 0.2), value: selected)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(shelf.title), \(stats.count) von \(stats.capacity) Platten, \(stats.occupancyPercent) Prozent belegt")
    }
}

/// Slim capsule gauge that stays low-key for ordinary fill levels and only
/// reads as "more urgent" once a shelf is nearly or fully at capacity.
private struct ShelfFillGauge: View {
    let fraction: Double
    let level: ShelfStatistics.FillLevel

    private var tint: Color {
        switch level {
        case .low: return Color.accentColor.opacity(0.55)
        case .medium: return Color.accentColor.opacity(0.8)
        case .high: return Color.accentColor
        case .full: return Color.orange
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(tint)
                    .frame(width: max(3, geometry.size.width * fraction))
            }
        }
        .frame(height: 6)
        .animation(.easeInOut(duration: 0.3), value: fraction)
    }
}

// MARK: - Style breakdown

private struct ShelfStyleBreakdown: View {
    let stats: ShelfStatistics

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform").foregroundStyle(.secondary)
            StyleBadge(text: stats.dominantStyleLabel, prominent: true)
            if stats.styleShares.count > 1 {
                ForEach(stats.styleShares.dropFirst().prefix(3)) { share in
                    StyleBadge(text: "\(share.style) \(Int((share.fraction * 100).rounded())) %")
                }
            }
        }
        .lineLimit(1)
    }
}

/// One consistent look for every style label in the shelf view — the shelf
/// card's dominant style, the header breakdown, and each record's style in
/// the copy list all use this instead of ad hoc text or capsule styling.
struct StyleBadge: View {
    let text: String
    var prominent = false

    var body: some View {
        Text(text)
            .font(.caption2.weight(prominent ? .semibold : .regular))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(prominent ? Color.accentColor : .secondary)
            .background(prominent ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06), in: Capsule())
    }
}

// MARK: - Copy list in the shelf detail pane

/// Owns its own cached, sorted snapshot of the shelf's copies so scrolling
/// stays smooth — mirroring `CollectionView`'s item cache, this recomputes
/// only when the shelf's contents actually change (see `signature`), not on
/// every unrelated re-render of the surrounding page (e.g. a search hover).
private struct ShelfCopyList: View {
    @Environment(\.modelContext) private var context
    let shelf: Shelf
    let focusCopy: RecordCopy?
    let open: (RecordCopy) -> Void
    let edit: (RecordCopy) -> Void
    let unplace: (RecordCopy) -> Void
    let delete: (RecordCopy) -> Void
    let preview: (RecordCopy?) -> Void

    @State private var items: [RecordCopy] = []
    @State private var hoveredID: UUID?

    private var signature: Int {
        var hasher = Hasher()
        hasher.combine(shelf.id)
        for copy in shelf.copies { hasher.combine(copy.id); hasher.combine(copy.positionInShelf) }
        return hasher.finalize()
    }

    var body: some View {
        ScrollViewReader { proxy in
            List(items) { copy in
                ShelfCopyRow(
                    copy: copy,
                    isFocused: copy.id == focusCopy?.id,
                    open: { open(copy) },
                    edit: { edit(copy) },
                    unplace: { unplace(copy) },
                    delete: { delete(copy) }
                )
                .id(copy.id)
                .onHover { hovering in
                    if hovering {
                        hoveredID = copy.id
                        preview(copy)
                    } else if hoveredID == copy.id {
                        hoveredID = nil
                        preview(nil)
                    }
                }
            }
            .contentMargins(.horizontal, AppStyle.pagePadding, for: .scrollContent)
            .contentMargins(.bottom, 32, for: .scrollContent)
            .task(id: signature) {
                items = PositionService(context: context).ordered(shelf)
                if let id = focusCopy?.id { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: focusCopy?.id) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
            .onDisappear { preview(nil) }
        }
    }
}

private struct ShelfCopyRow: View {
    let copy: RecordCopy
    let isFocused: Bool
    let open: () -> Void
    let edit: () -> Void
    let unplace: () -> Void
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: open) {
                HStack(spacing: 12) {
                    Text(String(copy.positionInShelf))
                        .font(.callout.monospacedDigit().weight(.semibold))
                        .foregroundStyle(isFocused ? Color.white : .secondary)
                        .frame(width: 30, height: 22)
                        .background(isFocused ? Color.accentColor : Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    CoverView(url: copy.release?.coverURL, size: 42)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(copy.release?.displayArtist ?? "—").font(.headline)
                        HStack(spacing: 6) {
                            Text(copy.release?.displayTitle ?? "—").foregroundStyle(.secondary)
                            if let year = copy.release?.year {
                                Text("· \(String(year))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if let style = copy.release?.primaryStyle, !style.isEmpty {
                            Text(style).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            Menu {
                Button("Details öffnen", action: open)
                Button("Position / Exemplar bearbeiten", action: edit)
                Divider()
                Button("Aus KALLAX entfernen", action: unplace)
                Button("Aus Sammlung löschen", role: .destructive, action: delete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .appGlassButton()
            .fixedSize()
        }
        .listRowBackground(isFocused ? Color.accentColor.opacity(0.12) : hovering ? Color.primary.opacity(0.04) : Color.clear)
        .contextMenu {
            Button("Details öffnen", action: open)
            Button("Position / Exemplar bearbeiten", action: edit)
            Button("Aus KALLAX entfernen", action: unplace)
            Divider()
            Button("Aus Sammlung löschen", role: .destructive, action: delete)
        }
    }
}

struct ShelfEditor: View {
    let shelf: Shelf
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var shelfCustomizations: [ShelfCustomization]
    @State private var title = ""
    @State private var infoText = ""
    @State private var capacity = 90
    @State private var error: String?

    var body: some View {
        Form {
            Text("Fach \(shelf.number) bearbeiten").font(AppStyle.dialogTitle)
            TextField("Name des Fachs", text: $title, prompt: Text("Fach \(shelf.number)"))
            TextField("Infotext", text: $infoText, axis: .vertical)
                .lineLimit(2...4)
            TextField("Kapazität", value: $capacity, format: .number)
            Text("Aktuell \(shelf.copies.count) Platten").foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Abbrechen") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Speichern") {
                    do {
                        try PositionService(context: context).configure(
                            shelf,
                            title: title,
                            infoText: infoText,
                            capacity: capacity
                        )
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(AppStyle.pagePadding)
        .frame(width: 480)
        .onAppear {
            title = shelf.name
            infoText = shelfCustomizations.first { $0.shelfID == shelf.id }?.infoText ?? ""
            capacity = shelf.capacity
        }
    }
}

private struct ShelfAssignmentView: View {
    let shelf: Shelf
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var copies: [RecordCopy]
    @State private var query = ""
    @State private var error: String?

    private var availableCopies: [RecordCopy] {
        ShelfAssignmentPresentation.availableCopies(copies, for: shelf, matching: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Exemplar zu \(shelf.title)").font(AppStyle.dialogTitle)
                    Text("Noch \(max(0, shelf.capacity - shelf.copies.count)) freie Plätze")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Fertig") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(AppStyle.pagePadding)
            Divider()
            if let error {
                Text(error).foregroundStyle(.red).padding(.horizontal, AppStyle.pagePadding).padding(.top, 10)
            }
            if availableCopies.isEmpty {
                AppEmptyState(
                    query.isEmpty ? "Keine weiteren Exemplare" : "Keine Treffer",
                    systemImage: "tray",
                    description: Text(query.isEmpty ? "Alle vorhandenen Exemplare liegen bereits in diesem Fach." : "Versuche einen anderen Suchbegriff.")
                )
            } else {
                List(availableCopies) { copy in
                    HStack(spacing: 12) {
                        CoverView(url: copy.release?.coverURL, size: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(copy.release?.displayArtist ?? "—").font(.headline)
                            Text(copy.release?.displayTitle ?? "—").foregroundStyle(.secondary)
                            Text(labelName(for: copy)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Einordnen") { assign(copy) }
                            .buttonStyle(.borderedProminent)
                            .disabled(shelf.copies.count >= shelf.capacity)
                    }
                    .padding(.vertical, 3)
                }
                .searchable(text: $query, prompt: "Vorhandene Sammlung durchsuchen")
            }
        }
        .frame(width: 700, height: 720)
    }

    private func labelName(for copy: RecordCopy) -> String {
        guard let release = copy.release else { return "Label unbekannt" }
        if let data = release.basicInformation,
           let basic = try? JSONDecoder().decode(DiscogsBasicInformation.self, from: data) {
            var seen: Set<String> = []
            let names = (basic.labels ?? [])
                .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && seen.insert($0).inserted }
            if !names.isEmpty { return names.joined(separator: ", ") }
        }
        let label = release.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? "Label unbekannt" : label
    }

    private func assign(_ copy: RecordCopy) {
        do {
            let service = PositionService(context: context)
            let position = service.ordered(shelf, excluding: copy.id).count + 1
            try service.move(copy, to: shelf, position: position)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

enum ShelfAssignmentPresentation {
    @MainActor static func availableCopies(
        _ copies: [RecordCopy],
        for shelf: Shelf,
        matching query: String
    ) -> [RecordCopy] {
        // Read only the copy → shelf side of the relationship: it's the one directly
        // written by PositionService.move/assign. The inverse `shelf.copies` collection
        // is derived by SwiftData and can still reflect the previous state for one
        // update cycle, which used to let an already assigned copy reappear here.
        return copies
            .filter { $0.shelf?.id != shelf.id }
            .filter { query.isEmpty || SortingService.matches($0, query: query) }
            .sorted {
                if ($0.shelf == nil) != ($1.shelf == nil) { return $0.shelf == nil }
                let left = ($0.release?.displayArtist ?? "") + "\t" + ($0.release?.displayTitle ?? "")
                let right = ($1.release?.displayArtist ?? "") + "\t" + ($1.release?.displayTitle ?? "")
                return left.localizedStandardCompare(right) == .orderedAscending
            }
    }
}
