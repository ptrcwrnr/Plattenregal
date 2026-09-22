import SwiftUI
import SwiftData
import AppKit

struct CollectionView: View {
    @Environment(\.isActivePage) private var isActivePage
    @Environment(\.modelContext) private var context
    @Query private var copies: [RecordCopy]
    @Query(sort: \DiscogsFolder.folderID) private var folders: [DiscogsFolder]
    @Query(sort: \Shelf.number) private var shelves: [Shelf]
    @State private var folderKey = "discogs"
    @State private var sync = DiscogsSyncService.shared
    let mode: Destination
    let query: String
    let showShelf: (RecordCopy) -> Void
    var analyticsFilter: StatisticGroup? = nil
    @Binding private var savedScrollPosition: UUID?
    @State private var scrollPosition: UUID?
    @AppStorage("collectionLayout") private var layout = "grid"
    @AppStorage("coverSize") private var coverSize = 155.0
    @State private var sort: RecordSort = .artistAZ
    @State private var selection: Set<UUID> = []
    @State private var selectionAnchor: UUID?
    @State private var cardFrames: [UUID: CGRect] = [:]
    @State private var dragRectangle: CGRect?
    @State private var dragBaseSelection: Set<UUID> = []
    @State private var opened: RecordCopy?
    @State private var editing: RecordCopy?
    @State private var deleting: RecordCopy?
    @State private var adding = false
    @State private var error: String?

    init(
        mode: Destination,
        query: String,
        showShelf: @escaping (RecordCopy) -> Void,
        analyticsFilter: StatisticGroup? = nil,
        scrollPosition: Binding<UUID?> = .constant(nil)
    ) {
        self.mode = mode
        self.query = query
        self.showShelf = showShelf
        self.analyticsFilter = analyticsFilter
        _savedScrollPosition = scrollPosition
        _scrollPosition = State(initialValue: scrollPosition.wrappedValue)
    }

    // Cached so that unrelated re-renders (e.g. the card-frame tracking below,
    // which updates as the lazy grid scrolls) don't force this filter/sort pass
    // to redo its work on every frame — that repeated O(n log n) work over the
    // full collection was the source of the scroll and navigation stutter.
    @State private var items: [RecordCopy] = []
    // Cached alongside `items`: building this (Unicode folding per artist name)
    // for the whole collection on every body evaluation was the extra cost that
    // made "Sammlung" (which shows the alphabet index) noticeably
    // choppier than views that don't, like "Zuletzt hinzugefügt".
    @State private var alphabetIndex: [String: UUID] = [:]

    private func recomputeItems() {
        let analyticsIDs = analyticsFilter?.copyIDs
        let selectedFolder = folders.first { $0.key == folderKey }
        let recentCutoff = Date().addingTimeInterval(-30 * 86400)
        let matched = copies.filter { copy in
            (analyticsIDs == nil || analyticsIDs!.contains(copy.id)) &&
            (folderKey == "discogs" ? copy.discogsActive == true : selectedFolder.map { $0.owner == copy.discogsOwner && copy.discogsActive == true && ($0.folderID == 0 || $0.folderID == copy.discogsFolderID) } == true) &&
            (mode != .recent || copy.dateAdded > recentCutoff) &&
            SortingService.matches(copy, query: query)
        }
        items = mode == .recent ? matched.sorted { $0.dateAdded > $1.dateAdded } : SortingService.sorted(matched, by: sort)
        alphabetIndex = showsAlphabetIndex ? alphabetAnchors(for: items) : [:]
    }
    var body: some View {
        let visibleIDs = items.map(\.id)
        VStack(spacing: 0) {
            collectionControls(count: items.count, items: items)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, AppStyle.pagePadding)
                .padding(.vertical, 12)
            if sync.busy || !sync.status.isEmpty || sync.error != nil || sync.summary != nil {
                DiscogsSyncStatusView()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24).padding(.bottom, 12)
            }
            Group {
            if items.isEmpty {
                AppEmptyState(query.isEmpty ? "Noch keine Schallplatten" : "Keine Treffer",
                    systemImage: query.isEmpty ? "opticaldisc" : "magnifyingglass",
                    description: Text(query.isEmpty ? "Füge deine erste Platte manuell oder über Discogs hinzu." : "Versuche einen anderen Titel, Interpreten oder ein Label."))
            } else {
                ZStack(alignment: .trailing) {
                    if layout == "grid" {
                        ScrollView {
                            ZStack(alignment: .topLeading) {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: coverSize + 20), alignment: .top)], spacing: 26) {
                                    ForEach(items) { copy in
                                        // A plain Button reacts on mouseUp immediately; layering the
                                        // double-click as a second, independent gesture (rather than a
                                        // second onTapGesture) avoids SwiftUI's single/double-tap
                                        // disambiguation delay that made selecting feel sluggish.
                                        Button {
                                            select(copy, in: items)
                                        } label: {
                                            RecordCard(
                                                copy: copy,
                                                coverSize: coverSize,
                                                selected: selection.contains(copy.id)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .id(copy.id)
                                        .background {
                                            GeometryReader { proxy in
                                                Color.clear.preference(
                                                    key: RecordCardFrameKey.self,
                                                    value: [copy.id: proxy.frame(in: .named("collectionGrid"))]
                                                )
                                            }
                                        }
                                        .simultaneousGesture(TapGesture(count: 2).onEnded { opened = copy })
                                        .contextMenu { gridContextMenu(copy, items: items) }
                                        .help("Klicken zum Markieren · Doppelklicken zum Öffnen · ⌘-Klick für Einzelauswahl")
                                    }
                                }
                                .scrollTargetLayout()
                                if let dragRectangle {
                                    Rectangle()
                                        .fill(Color.accentColor.opacity(0.12))
                                        .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1))
                                        .frame(width: dragRectangle.width, height: dragRectangle.height)
                                        .offset(x: dragRectangle.minX, y: dragRectangle.minY)
                                        .allowsHitTesting(false)
                                }
                            }
                            .padding(AppStyle.pagePadding)
                            .padding(.trailing, showsAlphabetIndex ? 24 : 0)
                            .coordinateSpace(name: "collectionGrid")
                            .onPreferenceChange(RecordCardFrameKey.self) { frames in
                                // Only needed for the rubber-band drag selection below. The lazy
                                // grid republishes this for every card that mounts while scrolling,
                                // so writing it unconditionally turned plain scrolling into a
                                // constant stream of full-view re-renders. Outside an active drag,
                                // stale frames are harmless — the next drag's first tick refreshes
                                // them from the then-current layout before any hit-testing happens.
                                guard dragRectangle != nil || cardFrames.isEmpty else { return }
                                if cardFrames != frames { cardFrames = frames }
                            }
                            .simultaneousGesture(gridSelectionGesture)
                        }
                        .scrollPosition(id: $scrollPosition, anchor: .top)
                    } else {
                        Table(items, selection: $selection) {
                            TableColumn("Interpret") { copy in
                                VStack(alignment: .leading) {
                                    Text(copy.release?.displayArtist ?? "—")
                                }
                            }.width(min: 130, ideal: 170)
                            TableColumn("Titel") { Text($0.release?.displayTitle ?? "—") }.width(min: 150, ideal: 210)
                            TableColumn("Jahr") { copy in Text(copy.release?.year.map(String.init) ?? "—") }.width(55)
                            TableColumn("Label") { Text($0.release?.label ?? "") }
                            TableColumn("Genre") { Text($0.release?.genres.joined(separator: ", ") ?? "") }
                            TableColumn("Fach") { Text($0.shelf?.title ?? "—") }.width(min: 80, ideal: 130)
                            TableColumn("Position") { Text(String($0.positionInShelf)) }.width(60)
                        }
                        .contextMenu(forSelectionType: UUID.self) { ids in
                            tableContextMenu(ids, items: items)
                        } primaryAction: { ids in
                            if ids.count == 1 { opened = copies.first(where: { ids.contains($0.id) }) }
                        }
                        .overlay {
                            CollectionTableScrollBridge(
                                position: $scrollPosition,
                                itemIDs: items.map(\.id)
                            )
                            .allowsHitTesting(false)
                        }
                    }

                    if showsAlphabetIndex {
                        AlphabetIndex(
                            availableSymbols: Set(alphabetIndex.keys),
                            action: { navigateToLetter($0, anchors: alphabetIndex) }
                        )
                        .padding(.trailing, 8)
                    }
                }
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        
        .toolbar { ToolbarItem { if isActivePage { Button { adding = true } label: { Label("Hinzufügen", systemImage: "plus") }.keyboardShortcut("n") } } }
        .sheet(isPresented: $adding) { RecordEditor() }
        .sheet(item: $opened) { copy in RecordDetailView(copy: copy) { showShelf(copy); opened = nil } }
        .sheet(item: $editing) { RecordEditor(copy: $0) }
        .confirmationDialog("Dieses Exemplar löschen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Exemplar löschen", role: .destructive) {
                if let copy = deleting { perform { try PositionService(context: context).delete(copy) } }; deleting = nil
            }
        } message: { Text("Die verbleibenden Platten im Fach rücken in der Positionsliste auf.") }
        .alert("Änderung nicht gespeichert", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .onChange(of: visibleIDs) { _, visibleIDs in
            selection.formIntersection(Set(visibleIDs))
            if let scrollPosition, !visibleIDs.contains(scrollPosition) {
                self.scrollPosition = nil
            }
        }
        .task { recomputeItems() }
        .onChange(of: copies) { _, _ in recomputeItems() }
        .onChange(of: folders) { _, _ in recomputeItems() }
        .onChange(of: folderKey) { _, _ in recomputeItems() }
        .onChange(of: mode) { _, _ in recomputeItems() }
        .onChange(of: query) { _, _ in recomputeItems() }
        .onChange(of: sort) { _, _ in recomputeItems() }
        .onAppear {
            if scrollPosition == nil { scrollPosition = savedScrollPosition }
        }
        .onDisappear {
            // Keep fast, per-frame scroll state inside this page. Writing every
            // visible item back into RootView would rebuild the complete
            // NavigationSplitView continuously while the user scrolls.
            savedScrollPosition = scrollPosition
        }
    }

    private var showsAlphabetIndex: Bool {
        mode != .recent && (sort == .artistAZ || sort == .artistZA)
    }

    private func alphabetAnchors(for items: [RecordCopy]) -> [String: UUID] {
        items.reduce(into: [:]) { result, copy in
            let symbol = SortingService.alphabetSection(for: copy.release?.displayArtist ?? "")
            if result[symbol] == nil { result[symbol] = copy.id }
        }
    }

    private func navigateToLetter(_ symbol: String, anchors: [String: UUID]) {
        guard let id = anchors[symbol] else { return }
        withAnimation(.easeOut(duration: 0.2)) { scrollPosition = id }
    }

    @ViewBuilder private func bulkMenus(for ids: Set<UUID>, items: [RecordCopy]) -> some View {
        let selectedCopies = items.filter { ids.contains($0.id) }
        Menu {
            ForEach(shelves) { shelf in
                Button(shelf.title) { assign(selectedCopies, to: shelf) }
                    .disabled(!canAssign(selectedCopies, to: shelf))
            }
        } label: {
            Label("Fach zuweisen", systemImage: "square.grid.3x3")
        }
    }

    @ViewBuilder private func gridContextMenu(_ copy: RecordCopy, items: [RecordCopy]) -> some View {
        if selection.contains(copy.id), selection.count > 1 {
            bulkMenus(for: selection, items: items)
        } else {
            actions(copy)
        }
    }

    @ViewBuilder private func tableContextMenu(_ ids: Set<UUID>, items: [RecordCopy]) -> some View {
        if ids.count > 1 {
            bulkMenus(for: ids, items: items)
        } else if let copy = items.first(where: { ids.contains($0.id) }) {
            actions(copy)
        }
    }

    private func canAssign(_ selectedCopies: [RecordCopy], to shelf: Shelf) -> Bool {
        let alreadyThere = selectedCopies.filter { $0.shelf?.id == shelf.id }.count
        let free = shelf.capacity - shelf.copies.count
        return selectedCopies.count - alreadyThere <= free
    }

    private func assign(_ selectedCopies: [RecordCopy], to shelf: Shelf) {
        perform {
            try PositionService(context: context).assign(selectedCopies, to: shelf)
            selection.removeAll()
        }
    }

    private func select(_ copy: RecordCopy, in items: [RecordCopy]) {
        let modifiers = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
        if modifiers.contains(.shift), let anchor = selectionAnchor,
           let start = items.firstIndex(where: { $0.id == anchor }),
           let end = items.firstIndex(where: { $0.id == copy.id }) {
            let range = min(start, end)...max(start, end)
            let ids = Set(range.map { items[$0].id })
            if modifiers.contains(.command) { selection.formUnion(ids) }
            else { selection = ids }
        } else if modifiers.contains(.command) {
            if selection.contains(copy.id) { selection.remove(copy.id) }
            else { selection.insert(copy.id) }
            selectionAnchor = copy.id
        } else if selection == [copy.id] {
            selection = []
            selectionAnchor = nil
        } else {
            selection = [copy.id]
            selectionAnchor = copy.id
        }
    }

    private var gridSelectionGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("collectionGrid"))
            .onChanged { value in
                if dragRectangle == nil {
                    let modifiers = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
                    dragBaseSelection = modifiers.contains(.command) ? selection : []
                }
                let rectangle = selectionRectangle(from: value.startLocation, to: value.location)
                dragRectangle = rectangle
                let hitIDs = Set(cardFrames.compactMap { id, frame in frame.intersects(rectangle) ? id : nil })
                selection = dragBaseSelection.union(hitIDs)
            }
            .onEnded { _ in
                dragRectangle = nil
                dragBaseSelection = []
                selectionAnchor = selection.first
            }
    }

    private func selectionRectangle(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    // A single, intrinsically sized control surface. Only the collection below expands.
    // The selection/shelf-assignment controls are always rendered here (just disabled
    // when nothing is selected) so this bar never grows or shrinks as the user clicks
    // records — it stays a fixed one- or two-line header.
    private func collectionControls(count: Int, items: [RecordCopy]) -> some View {
        controlLayout(count: count, items: items).appControlSurface()
    }
    private func controlLayout(count: Int, items: [RecordCopy]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                folderPicker
                itemCount(count)
                selectionControls(items: items)
                Spacer(minLength: 12)
                displayOptions
                syncButtons
            }
            VStack(spacing: 14) {
                HStack(spacing: 16) {
                    folderPicker
                    Spacer(minLength: 12)
                    syncButtons
                }
                HStack(spacing: 16) {
                    itemCount(count)
                    selectionControls(items: items)
                    Spacer(minLength: 12)
                    displayOptions
                }
            }
        }
        .controlSize(.regular)
        .padding(16)
    }
    private func selectionControls(items: [RecordCopy]) -> some View {
        let selectedCopies = items.filter { selection.contains($0.id) }
        return HStack(spacing: 10) {
            Divider().frame(height: 16)
            Label("\(selection.count)", systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(selection.isEmpty ? .secondary : Color.accentColor)
                .help("⌘-Klick oder mit gedrückter Maustaste über weitere Cover ziehen, um mehrere auszuwählen")
            Menu {
                ForEach(shelves) { shelf in
                    Button(shelf.title) { assign(selectedCopies, to: shelf) }
                        .disabled(!canAssign(selectedCopies, to: shelf))
                }
            } label: {
                Label("Fach zuweisen", systemImage: "square.grid.3x3")
            }
            .disabled(selection.isEmpty)
            .help(selection.isEmpty ? "Wähle Schallplatten aus, um sie einem Fach zuzuweisen" : "Ausgewählte Schallplatten einem Fach zuweisen")
            Button { selection.removeAll() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(selection.isEmpty)
                .opacity(selection.isEmpty ? 0.35 : 1)
                .help("Auswahl aufheben")
        }
        .fixedSize()
        .animation(.easeOut(duration: 0.15), value: selection.count)
    }
    private var folderPicker: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder").foregroundStyle(.secondary)
            Picker("Discogs-Ordner", selection: $folderKey) {
                Text("Gesamter Bestand").tag("discogs")
                ForEach(folders.filter { $0.name != "Uncategorized" && $0.name != "All" }) { Text($0.name).tag($0.key) }
            }
            .labelsHidden()
            .frame(minWidth: 190, idealWidth: 240, maxWidth: 300, alignment: .leading)
            .help("Sammlung oder Discogs-Ordner auswählen")
        }
    }
    private func itemCount(_ count: Int) -> some View {
        Text(count == 1 ? "1 Schallplatte" : "\(count) Schallplatten")
            .font(.callout).foregroundStyle(.secondary)
            .monospacedDigit().fixedSize()
    }
    private var displayOptions: some View {
        HStack(spacing: 12) {
            if mode != .recent {
                Picker("Sortierung", selection: $sort) {
                    ForEach(RecordSort.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().frame(width: 185)
                .help("Sortierung der Schallplatten")
            }
            Picker("Darstellung", selection: $layout) {
                Label("Raster", systemImage: "square.grid.2x2").tag("grid")
                Label("Liste", systemImage: "list.bullet").tag("list")
            }
            .labelStyle(.iconOnly).labelsHidden()
            .pickerStyle(.segmented).frame(width: 80)
            .help("Zwischen Raster und Liste wechseln")
        }.fixedSize()
    }
    private var syncButtons: some View {
        HStack(spacing: 12) {
            if let folder = folders.first(where: { $0.key == folderKey }) {
                Button {
                    sync.start(.folder(folder.folderID), container: context.container, expectedOwner: folder.owner)
                } label: { Label("Ordner", systemImage: "arrow.triangle.2.circlepath") }
                    .help("Ausgewählten Discogs-Ordner synchronisieren")
            }
            Button { sync.start(.collection, container: context.container) } label: {
                Label("Collection synchronisieren", systemImage: "arrow.clockwise")
            }
        }
        .buttonStyle(.borderless).disabled(sync.busy).fixedSize()
    }
    @ViewBuilder private func actions(_ copy: RecordCopy) -> some View {
        Button("Öffnen") { opened = copy }
        if let id = copy.release?.discogsID {
            Button("Veröffentlichung aktualisieren") { sync.start(.release(id), container: context.container) }.disabled(sync.busy)
        }
        Button("Im Regal anzeigen") { showShelf(copy) }
        Button("Bearbeiten") { editing = copy }
        Button("In anderes Fach verschieben") { editing = copy }
        Divider(); Button("Löschen", role: .destructive) { deleting = copy }
    }
    private func perform(_ action: () throws -> Void) { do { try action() } catch { self.error = error.localizedDescription } }
}
struct RecordCard: View {
    let copy: RecordCopy
    var coverSize: Double = 155
    var selected = false
    @State private var hovering = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverView(url: copy.release?.coverURL, size: coverSize)
            HStack {
                Text(copy.release?.displayArtist ?? "Unbekannt").font(.headline).lineLimit(1).frame(minHeight: 20, alignment: .leading)
            }
            Text(copy.release?.displayTitle ?? "—").lineLimit(2, reservesSpace: true).foregroundStyle(.secondary)
            Text("Hinzugefügt am \(copy.dateAdded.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(6)
        .frame(width: coverSize + 12, alignment: .leading)
        .background(selected ? Color.accentColor.opacity(0.12) : hovering ? Color.primary.opacity(0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2)
        }
        .overlay(alignment: .topTrailing) {
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.accentColor)
                    .padding(10)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

private struct RecordCardFrameKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct AlphabetIndex: View {
    let availableSymbols: Set<String>
    let action: (String) -> Void
    @State private var hoveredSymbol: String?

    private var symbols: [String] { SortingService.alphabetNavigationSymbols }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(symbols.enumerated()), id: \.element) { index, symbol in
                let available = availableSymbols.contains(symbol)
                let scale = magnification(at: index)
                Button { action(symbol) } label: {
                    Text(symbol)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .frame(width: 16, height: 13)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(available ? Color.accentColor : Color.secondary.opacity(0.35))
                .disabled(!available)
                .scaleEffect(scale)
                .zIndex(scale)
                .animation(.spring(response: 0.22, dampingFraction: 0.6), value: hoveredSymbol)
                .onHover { isHovering in
                    guard available else { return }
                    if isHovering { hoveredSymbol = symbol }
                    else if hoveredSymbol == symbol { hoveredSymbol = nil }
                }
                .help(available ? "Zu \(symbol) springen" : "Keine Einträge unter \(symbol)")
                .accessibilityLabel(available ? "Zu Buchstabe \(symbol) springen" : "Keine Einträge unter Buchstabe \(symbol)")
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 2)
        .appGlassSurface(cornerRadius: 9)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Alphabetische Navigation")
    }

    // Dock-style magnification: the hovered letter grows most, with a quick falloff
    // over its immediate neighbors so the effect reads as a smooth ripple.
    private func magnification(at index: Int) -> CGFloat {
        guard let hoveredSymbol, let hoveredIndex = symbols.firstIndex(of: hoveredSymbol) else { return 1 }
        switch abs(index - hoveredIndex) {
        case 0: return 1.7
        case 1: return 1.32
        case 2: return 1.12
        default: return 1
        }
    }
}

/// SwiftUI's `Table` does not expose its visible row as a binding on macOS 14.
/// This zero-opacity overlay observes the underlying table scroll view so the
/// same session-only restoration and alphabet jumps work in list layout too.
private struct CollectionTableScrollBridge: NSViewRepresentable {
    @Binding var position: UUID?
    let itemIDs: [UUID]

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onMoveToWindow = { [weak coordinator = context.coordinator, weak view] in
            guard let view else { return }
            DispatchQueue.main.async { coordinator?.connect(from: view) }
        }
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        context.coordinator.parent = self
        DispatchQueue.main.async { [weak coordinator = context.coordinator, weak nsView] in
            guard let nsView else { return }
            coordinator?.connect(from: nsView)
            coordinator?.restoreIfNeeded()
        }
    }

    final class ProbeView: NSView {
        var onMoveToWindow: (() -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onMoveToWindow?()
        }
    }

    @MainActor final class Coordinator {
        var parent: CollectionTableScrollBridge
        private weak var tableView: NSTableView?
        private weak var clipView: NSClipView?
        private var observer: NSObjectProtocol?
        private var lastVisibleID: UUID?

        init(parent: CollectionTableScrollBridge) { self.parent = parent }

        isolated deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }

        func connect(from probe: NSView) {
            guard let window = probe.window, let contentView = window.contentView else { return }
            let probeCenter = probe.convert(NSPoint(x: probe.bounds.midX, y: probe.bounds.midY), to: nil)
            let candidate = allSubviews(of: contentView, matching: NSTableView.self)
                .filter { table in
                    guard let scrollView = table.enclosingScrollView else { return false }
                    return scrollView.convert(scrollView.bounds, to: nil).contains(probeCenter)
                }
                .min { lhs, rhs in
                    lhs.convert(lhs.visibleRect, to: nil).width < rhs.convert(rhs.visibleRect, to: nil).width
                }
            guard let candidate, candidate !== tableView,
                  let clipView = candidate.enclosingScrollView?.contentView else { return }

            if let observer { NotificationCenter.default.removeObserver(observer) }
            tableView = candidate
            self.clipView = clipView
            clipView.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.recordVisibleRow() }
            }
            restoreIfNeeded()
        }

        func restoreIfNeeded() {
            guard let target = parent.position,
                  target != lastVisibleID,
                  let row = parent.itemIDs.firstIndex(of: target),
                  let tableView,
                  let clipView else { return }
            let rowRect = tableView.rect(ofRow: row)
            clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: rowRect.minY))
            tableView.enclosingScrollView?.reflectScrolledClipView(clipView)
            lastVisibleID = target
        }

        private func recordVisibleRow() {
            guard let tableView else { return }
            let rows = tableView.rows(in: tableView.visibleRect)
            guard rows.location != NSNotFound, rows.location < parent.itemIDs.count else { return }
            let id = parent.itemIDs[rows.location]
            guard id != lastVisibleID else { return }
            lastVisibleID = id
            DispatchQueue.main.async { [weak self] in
                guard let self, self.parent.position != id else { return }
                self.parent.position = id
            }
        }

        private func allSubviews<T: NSView>(of root: NSView, matching type: T.Type) -> [T] {
            root.subviews.reduce(into: root as? T == nil ? [] : [root as! T]) { result, view in
                result.append(contentsOf: allSubviews(of: view, matching: type))
            }
        }
    }
}
