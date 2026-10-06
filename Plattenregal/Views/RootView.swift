import SwiftUI
import SwiftData

/// The pages of the main window, in the order of the switch in the toolbar.
enum Destination: String, CaseIterable, Identifiable {
    case collection = "Collection"
    case wantlist = "Wantlist"
    case shelf = "Regal"
    case statistics = "Statistik"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .collection: String(localized: "Collection")
        case .wantlist: String(localized: "Wantlist")
        case .shelf: String(localized: "Regal")
        case .statistics: String(localized: "Statistik")
        }
    }
    /// ⌘1 … ⌘4, in the order of the switch in the toolbar.
    var shortcut: KeyEquivalent {
        switch self {
        case .collection: "1"
        case .wantlist: "2"
        case .shelf: "3"
        case .statistics: "4"
        }
    }
    /// Pages with a search (⌘F opens it, see `FloatingControls`).
    var hasSearch: Bool { self != .statistics }
    /// Pages with grid and list (see `FloatingControls`).
    var hasLayoutSwitch: Bool { self == .collection || self == .wantlist }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    /// The page shown. An object, so a switch only updates what shows it (see
    /// `PageStack`), not this view with everything below it.
    @State private var destination = PageSelection<Destination>({
        #if DEBUG
        if let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--preview-page=") }),
           let page = Destination(rawValue: String(raw.dropFirst("--preview-page=".count))) { return page }
        if ProcessInfo.processInfo.arguments.contains("--statistics-demo") { return .statistics }
        #endif
        return AppPreferences.shared.startPage.destination
    }())
    /// ⌘F and the focus of the search field; see `SearchRequests`.
    @State private var searchRequests = SearchRequests()
    /// One search for collection and wantlist, so a hit can be followed from
    /// one to the other.
    @State private var search = {
        let search = LibrarySearch()
        search.query = Self.previewSearch
        return search
    }()
    /// What is typed into the search field while the shelf page is shown.
    @State private var shelfSearch = {
        let search = ShelfSearch()
        search.text = Self.previewSearch
        return search
    }()
    /// Debug only: screenshots with a search typed in (`--preview-search=…`).
    private static var previewSearch: String {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--preview-search=") }) {
            return String(raw.dropFirst("--preview-search=".count))
        }
        #endif
        return ""
    }
    /// "Im Regal anzeigen" from any page, for the shelf page.
    @State private var shelfRequests = ShelfRequests()
    // Loaded once here, alongside collection startup, so the Statistik page is
    // already populated the moment the user first navigates to it instead of
    // recomputing everything from scratch on every visit.
    @State private var statisticsModel = StatisticsViewModel()
    @State private var tour = AppTour.shared
    var body: some View {
        library
            // Over all pages; marked as seen however it closes.
            .appPanel(item: $tour.request, onDismiss: { AppTour.shared.markSeen() }) { _ in
                TourView { AppTour.shared.request = nil }
            }
            .onAppear { AppTour.shared.showOnFirstLaunch() }
            .task { await statisticsModel.initialLoad(container: context.container) }
            // An interrupted first tracklist run (or due refreshes) continues on its own.
            .task { await DiscogsSyncService.shared.resumeTracklistsIfNeeded(container: context.container) }
            // Writes the export into the chosen folder when it is due.
            .task { ScheduledExport.shared.start(container: context.container) }
            .task { CoverCache.shared.pruneDisk() }
    }

    /// No sidebar: only the page switch, centered in the toolbar, so the
    /// pages start right below it. Everything else – search, grid or list,
    /// sync, settings – fans out of the round button at the bottom right
    /// (see `FloatingControls`). ⌘F opens the search beside it. The settings
    /// are also where a Mac app has them: Plattenregal menu and ⌘,.
    private var library: some View {
        pages
            .environment(\.searchRequests, searchRequests)
            .overlay(alignment: .bottomTrailing) {
                FloatingControls(selection: destination, library: search, shelf: shelfSearch, requests: searchRequests) {
                    Task { await statisticsModel.refresh(container: context.container) }
                }
            }
            // Names the window in the Fenster menu and Mission Control; the
            // toolbar shows the page switch instead of a title.
            .navigationTitle("Plattenregal")
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .principal) { PagePicker(selection: destination).toolbarBar() }
                    // The bar brings its own background (see `toolbarBar`).
                    .sharedBackgroundVisibility(.hidden)
            }
            .background { SignatureToolbarAppearance() }
            .background(pageShortcuts)
            .background(GlobalShortcuts(selection: destination))
            .background { AmbientGlow() }
    }

    /// ⌘1 … ⌘4 switch pages, like the tabs of a browser window; ⌘F puts the
    /// cursor in the search field, where the page has one.
    private var pageShortcuts: some View {
        Group {
            ForEach(Destination.allCases) { page in
                Button(page.title) { destination.current = page }
                    .keyboardShortcut(page.shortcut, modifiers: .command)
            }
            Button("Suchen") { searchRequests.request() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(!destination.current.hasSearch)
        }
        .opacity(0).frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    /// Every page is built once and kept alive (see `PageStack`); switching
    /// only changes which one is visible. Pages therefore keep their loaded
    /// data, sorting and scroll position, and switching is instant instead of
    /// rebuilding (and re-sorting the whole collection) on every visit.
    private var pages: some View {
        PageStack(pages: Destination.allCases, selection: destination) {
            pageContent($0)
                // Room at the end of every page, so the last covers and rows
                // scroll clear of the floating button.
                .safeAreaPadding(.bottom, AppStyle.floatingClearance)
                .appPageEnvironment(context)
        }
    }

    @ViewBuilder private func pageContent(_ page: Destination) -> some View {
        switch page {
        case .collection: CollectionView(pages: destination, search: search, showShelf: showShelf)
        case .wantlist: WantlistView(search: search, pages: destination)
        case .statistics: StatisticsView(model: statisticsModel, showShelf: showShelf)
        case .shelf: KallaxView(requests: shelfRequests, search: shelfSearch)
        }
    }
    /// Opens the shelf page with the card for this record: where it stands
    /// and between which records, or — without a shelf — where it belongs.
    private func showShelf(_ copy: RecordCopy) {
        shelfRequests.placing = copy.id
        destination.current = .shelf
    }
}

/// The round button at the bottom right of the window. A click fans the
/// page's actions out around it on a quarter circle – search, grid or list,
/// sync (or refresh), settings – and closes them again; so does Esc, a click
/// beside them or choosing one. The search opens as a field to the left of
/// the button (also with ⌘F) and stays while a query is active, so no filter
/// works unseen; Esc clears the query, a second Esc closes the field.
/// Collection and wantlist share one query (`LibrarySearch`), the shelf has
/// its own (`ShelfSearch`); the pages read them and filter themselves.
private struct FloatingControls: View {
    let selection: PageSelection<Destination>
    let library: LibrarySearch
    let shelf: ShelfSearch
    let requests: SearchRequests
    let refreshStatistics: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.openSettings) private var openSettings
    @State private var sync = DiscogsSyncService.shared
    @AppStorage(DisplaySettings.collectionLayoutKey) private var collectionLayout = OverviewLayout.grid
    @AppStorage(DisplaySettings.wantlistLayoutKey) private var wantlistLayout = OverviewLayout.grid
    @FocusState private var focused: Bool
    /// The actions fanned out (debug: `--preview-actions` starts with them).
    @State private var expanded = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--preview-actions")
        #else
        false
        #endif
    }()
    /// The search field opened by its button or ⌘F.
    @State private var searchOpened = false

    private enum Action: Hashable { case search, layout, sync, settings }

    var body: some View {
        let page = selection.current
        let text = text(for: page)
        let searchShown = page.hasSearch && (searchOpened || !text.wrappedValue.isEmpty)
        ZStack(alignment: .bottomTrailing) {
            if expanded {
                // A click beside the actions closes them.
                Color.clear.contentShape(Rectangle())
                    .onTapGesture { collapse() }
                    .accessibilityHidden(true)
            }
            HStack(spacing: 12) {
                if searchShown {
                    searchField(page: page, text: text)
                        // Out of the way of the fanned-out actions.
                        .opacity(expanded ? 0 : 1)
                        .allowsHitTesting(!expanded)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                ZStack {
                    let actions = actions(for: page)
                    ForEach(Array(actions.enumerated()), id: \.element) { index, action in
                        actionButton(action, page: page)
                            .offset(expanded ? Self.offset(index, of: actions.count) : .zero)
                            .scaleEffect(expanded ? 1 : 0.3)
                            .opacity(expanded ? 1 : 0)
                            .allowsHitTesting(expanded)
                            .accessibilityHidden(!expanded)
                            .animation(AppStyle.reduceMotion ? .default : .spring(duration: 0.38, bounce: 0.25)
                                .delay(expanded ? Double(index) * 0.03 : 0), value: expanded)
                    }
                    mainButton
                }
            }
            .padding(AppStyle.floatingMargin)
            // Esc closes the fanned-out actions.
            .background {
                if expanded {
                    Button("") { collapse() }.keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true)
                }
            }
        }
        .animation(AppStyle.fadeAnimation, value: searchShown)
        .animation(AppStyle.quickAnimation, value: otherSection(for: page)?.count)
        .onChange(of: requests.count) {
            guard selection.current.hasSearch else { return }
            openSearch()
        }
        .onChange(of: focused) { _, new in
            requests.fieldFocused = new
            if !new && text.wrappedValue.isEmpty { closeSearch() }
        }
        .onChange(of: page) {
            collapse()
            // The shelf has its own query: the field stays only with one,
            // or while it has the cursor on a page with a search.
            if !page.hasSearch || (!focused && text.wrappedValue.isEmpty) { closeSearch() }
        }
    }

    // MARK: Main button and actions

    private var mainButton: some View {
        Button {
            withAnimation(AppStyle.reduceMotion ? .default : .spring(duration: 0.35, bounce: 0.2)) { expanded.toggle() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3.weight(.semibold))
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .foregroundStyle(AppStyle.isAtelier ? AnyShapeStyle(AtelierPalette.toolbarSelection) : AnyShapeStyle(.primary))
                .frame(width: AppStyle.floatingButtonSize, height: AppStyle.floatingButtonSize)
                .floatingCircle(prominent: true)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(expanded ? String(localized: "Aktionen schließen") : String(localized: "Aktionen"))
        .accessibilityLabel(String(localized: "Aktionen"))
        .accessibilityValue(expanded ? String(localized: "geöffnet") : "")
    }

    /// What the page offers, from the left (beside the search field) up to
    /// the top of the quarter circle.
    private func actions(for page: Destination) -> [Action] {
        var actions: [Action] = []
        if page.hasSearch { actions.append(.search) }
        if page.hasLayoutSwitch { actions.append(.layout) }
        if page != .shelf { actions.append(.sync) }
        actions.append(.settings)
        return actions
    }

    /// On a quarter circle from straight left to straight up of the button.
    private static func offset(_ index: Int, of count: Int) -> CGSize {
        let degrees = count == 1 ? 135 : 180 - Double(index) * 90 / Double(count - 1)
        let radians = degrees * .pi / 180
        let radius = AppStyle.floatingButtonSize + 34
        return CGSize(width: radius * cos(radians), height: -radius * sin(radians))
    }

    @ViewBuilder private func actionButton(_ action: Action, page: Destination) -> some View {
        switch action {
        case .search:
            item("magnifyingglass", String(localized: "Suchen"), help: String(localized: "Suchen (⌘F)")) { openSearch() }
        case .layout:
            let layout = layoutBinding(for: page)
            let next: OverviewLayout = layout?.wrappedValue == .grid ? .list : .grid
            item(next.systemImage, next == .list ? String(localized: "Als Liste anzeigen") : String(localized: "Als Raster anzeigen")) {
                layout?.wrappedValue = next
            }
        case .sync:
            let title = page == .statistics ? String(localized: "Aktualisieren") : String(localized: "Synchronisieren")
            item("arrow.clockwise", title, help: title + " (⌘R)") {
                switch page {
                case .collection: sync.start(.collection, container: context.container)
                case .wantlist: sync.start(.wantlist, container: context.container)
                case .statistics: refreshStatistics()
                case .shelf: break
                }
            }
            // Discogs is off in the demo; the statistics still recalculate.
            .disabled(sync.busy || (DemoMode.isActive && page != .statistics))
        case .settings:
            item("gearshape", String(localized: "Einstellungen"), help: String(localized: "Einstellungen (⌘,)")) { openSettings() }
        }
    }

    /// One of the fanned-out actions; choosing it closes the fan.
    private func item(_ systemImage: String, _ title: String, help: String? = nil, perform: @escaping () -> Void) -> some View {
        Button {
            collapse()
            perform()
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(AppStyle.isAtelier ? AnyShapeStyle(AtelierPalette.ink) : AnyShapeStyle(.primary))
                .frame(width: AppStyle.floatingItemSize, height: AppStyle.floatingItemSize)
                .floatingCircle(prominent: false)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help ?? title)
        .accessibilityLabel(title)
    }

    private func layoutBinding(for page: Destination) -> Binding<OverviewLayout>? {
        switch page {
        case .collection: $collectionLayout.animation(AppStyle.fadeAnimation)
        case .wantlist: $wantlistLayout.animation(AppStyle.fadeAnimation)
        case .shelf, .statistics: nil
        }
    }

    private func collapse() {
        guard expanded else { return }
        withAnimation(AppStyle.reduceMotion ? .default : .spring(duration: 0.3, bounce: 0.1)) { expanded = false }
    }

    // MARK: Search

    private func searchField(page: Destination, text: Binding<String>) -> some View {
        AppSearchField(placeholder: placeholder(for: page), text: text, focus: $focused,
                       accessory: otherSection(for: page).map { AnyView(otherButton($0)) })
            .frame(width: AppStyle.floatingSearchWidth)
            .accessibilityLabel(String(localized: "Suchen"))
    }

    private func openSearch() {
        withAnimation(AppStyle.fadeAnimation) { searchOpened = true }
        focused = true
    }

    private func closeSearch() {
        focused = false
        withAnimation(AppStyle.fadeAnimation) { searchOpened = false }
    }

    /// The other page's hits for the same query, one click away; quiet, like
    /// the placeholder, inside the field.
    private func otherButton(_ other: (page: Destination, count: Int)) -> some View {
        Button { selection.current = other.page } label: {
            Text("\(other.count.formatted()) in der \(other.page.title)")
                .font(.caption)
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Treffer in der \(other.page.title) anzeigen")
        .accessibilityLabel("\(other.count) Treffer in der \(other.page.title) anzeigen")
        .transition(.opacity)
    }

    private func text(for page: Destination) -> Binding<String> {
        page == .shelf ? Bindable(shelf).text : Bindable(library).query
    }

    private func placeholder(for page: Destination) -> String {
        switch page {
        case .collection: String(localized: "Collection durchsuchen")
        case .wantlist: String(localized: "Wantlist durchsuchen")
        case .shelf, .statistics: String(localized: "Platte im Regal suchen …")
        }
    }

    private func otherSection(for page: Destination) -> (page: Destination, count: Int)? {
        guard !library.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        switch page {
        case .collection: return library.wantlistMatches > 0 ? (.wantlist, library.wantlistMatches) : nil
        case .wantlist: return library.collectionMatches > 0 ? (.collection, library.collectionMatches) : nil
        case .shelf, .statistics: return nil
        }
    }
}

/// The shortcuts listed in `AppShortcuts` beyond page and search. A view of
/// its own, so following the sync and the layouts doesn't redraw `RootView`.
private struct GlobalShortcuts: View {
    let selection: PageSelection<Destination>
    @Environment(\.modelContext) private var context
    @State private var sync = DiscogsSyncService.shared
    @AppStorage(DisplaySettings.collectionLayoutKey) private var collectionLayout = OverviewLayout.grid
    @AppStorage(DisplaySettings.wantlistLayoutKey) private var wantlistLayout = OverviewLayout.grid
    @AppStorage(DisplaySettings.coverSizeKey) private var storedCoverSize = DisplaySettings.defaultCoverSize

    /// Grid or list of the page shown; nil on shelf and statistics.
    private var layout: Binding<OverviewLayout>? {
        switch selection.current {
        case .collection: $collectionLayout.animation(AppStyle.fadeAnimation)
        case .wantlist: $wantlistLayout.animation(AppStyle.fadeAnimation)
        case .shelf, .statistics: nil
        }
    }

    var body: some View {
        let coverSize = DisplaySettings.coverSize(storedCoverSize)
        let showsGrid = layout?.wrappedValue == .grid
        Group {
            Button("Alles mit Discogs synchronisieren") { sync.start(.all, container: context.container) }
                .keyboardShortcut(AppShortcuts.syncAll)
                .disabled(sync.busy || DemoMode.isActive)
            Button("Synchronisierung abbrechen") { sync.cancel() }
                .keyboardShortcut(AppShortcuts.cancelSync)
                .disabled(!sync.isRunning)
            Button("Raster") { layout?.wrappedValue = .grid }
                .keyboardShortcut(AppShortcuts.grid)
                .disabled(layout == nil)
            Button("Liste") { layout?.wrappedValue = .list }
                .keyboardShortcut(AppShortcuts.list)
                .disabled(layout == nil)
            Button("Cover größer") { storedCoverSize = DisplaySettings.coverSize(coverSize + AppShortcuts.coverStep) }
                .keyboardShortcut(AppShortcuts.largerCovers)
                .disabled(!showsGrid || coverSize >= DisplaySettings.coverSizeRange.upperBound)
            // ⌘= as well: on US keyboards "+" needs Shift.
            Button("Cover größer") { storedCoverSize = DisplaySettings.coverSize(coverSize + AppShortcuts.coverStep) }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(!showsGrid || coverSize >= DisplaySettings.coverSizeRange.upperBound)
            Button("Cover kleiner") { storedCoverSize = DisplaySettings.coverSize(coverSize - AppShortcuts.coverStep) }
                .keyboardShortcut(AppShortcuts.smallerCovers)
                .disabled(!showsGrid || coverSize <= DisplaySettings.coverSizeRange.lowerBound)
            Button("Cover in Standardgröße") { storedCoverSize = DisplaySettings.defaultCoverSize }
                .keyboardShortcut(AppShortcuts.defaultCovers)
                .disabled(!showsGrid || coverSize == DisplaySettings.defaultCoverSize)
        }
        .opacity(0).frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

/// The page switch in the toolbar.
private struct PagePicker: View {
    @Bindable var selection: PageSelection<Destination>
    var body: some View {
        GlassSegmentedPicker(selection: $selection.current, options: Destination.allCases, glass: false) {
            Text($0.title)
        }
        .accessibilityLabel("Rubrik")
    }
}

/// The search shared by collection and wantlist. An object, read by the
/// pages themselves: each page is built once (see `PageStack`), and a binding
/// handed in would keep the value it had then.
@Observable final class LibrarySearch {
    var query = ""
    /// Hits of `query` on the other page, for the button beside the search
    /// field: the collection counts the wantlist's, the wantlist the collection's.
    var wantlistMatches = 0
    var collectionMatches = 0
}
