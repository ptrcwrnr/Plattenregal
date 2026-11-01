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
    /// Pages with the search field in the toolbar (⌘F, see `ToolbarSearchField`).
    var hasSearch: Bool { self != .statistics }
    /// Pages with grid and list, and with the round button of actions at the
    /// bottom right (see `FloatingControls`).
    var hasActions: Bool { self == .collection || self == .wantlist }
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
    @State private var welcome = AppWelcome.shared
    /// A record picked in the widget „Platte des Tages“ opens here (`pendingCopy`).
    @State private var quickSearch = ShelfQuickSearch.shared
    var body: some View {
        library
            .onAppear { takeQuickSearchRequest() }
            .onChange(of: quickSearch.pendingCopy) { takeQuickSearchRequest() }
            // Over all pages, in the middle of the window; marked as seen however it closes.
            .appPanel(item: $welcome.request, alignment: .center, onDismiss: { _ in AppWelcome.shared.markSeen() }) { _ in
                WelcomeView { AppWelcome.shared.request = nil }
            }
            .onAppear { AppWelcome.shared.showOnFirstLaunch() }
            .task { await statisticsModel.initialLoad(container: context.container) }
            // An interrupted first tracklist run (or due refreshes) continues on its own.
            .task { await DiscogsSyncService.shared.resumeTracklistsIfNeeded(container: context.container) }
            // Writes the export into the chosen folder when it is due.
            .task { ScheduledExport.shared.start(container: context.container) }
            .task { CoverCache.shared.pruneDisk() }
    }

    /// No sidebar: one bar centered in the toolbar, the page switch and the
    /// search behind its magnifying glass (⌘F), so the pages start right
    /// below it. On collection
    /// and wantlist grid or list, sync and settings fan out of the round
    /// button at the bottom right (see `FloatingControls`). The settings are
    /// also where a Mac app has them: Plattenregal menu and ⌘,.
    private var library: some View {
        pages
            .environment(\.searchRequests, searchRequests)
            .overlay(alignment: .bottomTrailing) { FloatingControls(selection: destination, shelfRequests: shelfRequests) }
            // Names the window in the Fenster menu and Mission Control; the
            // toolbar shows the page switch instead of a title.
            .navigationTitle("Plattenregal")
            .toolbar(removing: .title)
            .toolbar {
                // One bar: the page switch, then the search, which opens
                // from its magnifying glass (see `ToolbarSearchField`).
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 0) {
                        PagePicker(selection: destination)
                        ToolbarSearchField(selection: destination, library: search, shelf: shelfSearch, requests: searchRequests)
                    }
                    .toolbarBar()
                }
                // The bar brings its own background (see `toolbarBar`).
                .sharedBackgroundVisibility(.hidden)
            }
            .background { SignatureToolbarAppearance() }
            .background(pageShortcuts)
            .background(GlobalShortcuts(selection: destination))
            .background { AmbientGlow() }
            #if DEBUG
            // Recording a page switch without clicking: --preview-switch=Statistik
            // switches there 3 s after launch.
            .task {
                guard let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--preview-switch=") }),
                      let page = Destination(rawValue: String(raw.dropFirst("--preview-switch=".count))) else { return }
                try? await Task.sleep(for: .seconds(3))
                destination.current = page
            }
            // Recording full screen: --preview-fullscreen enters it after
            // launch (a window restored in full screen stays there). macOS
            // ignores the request while another app is in front, so it
            // activates first and tries again for up to 12 s – each time
            // after the transition (well under 3 s) has run.
            .task {
                guard ProcessInfo.processInfo.arguments.contains("--preview-fullscreen") else { return }
                for _ in 0..<4 {
                    try? await Task.sleep(for: .seconds(3))
                    guard let window = NSApp.windows.first(where: { $0.isVisible && $0.toolbar != nil }) else { continue }
                    if window.styleMask.contains(.fullScreen) { return }
                    NSApp.activate()
                    window.makeKeyAndOrderFront(nil)
                    window.toggleFullScreen(nil)
                }
            }
            #endif
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
                // Room at the end of the pages with the floating button, so
                // the last covers and rows scroll clear of it.
                .safeAreaPadding(.bottom, $0.hasActions ? AppStyle.floatingClearance : 0)
                .appPageEnvironment(context)
        }
        // The stack reaches up to the window's top edge, so each page's own
        // hosting view knows the toolbar as its safe area: pages still start
        // below the bar, but a scroll view can run on beneath it
        // (`scrollsUnderToolbar`, Modern).
        .ignoresSafeArea(.container, edges: .top)
    }

    @ViewBuilder private func pageContent(_ page: Destination) -> some View {
        switch page {
        case .collection: CollectionView(pages: destination, search: search, showShelf: showShelf)
        case .wantlist: WantlistView(search: search)
        case .statistics: StatisticsView(model: statisticsModel, showShelf: showShelf)
        case .shelf: KallaxView(requests: shelfRequests, search: shelfSearch)
        }
    }
    /// A record picked in the widget: the shelf page with its card.
    private func takeQuickSearchRequest() {
        guard let id = quickSearch.pendingCopy else { return }
        quickSearch.pendingCopy = nil
        shelfRequests.placing = id
        destination.current = .shelf
    }
    /// Opens the shelf page with the card for this record: where it stands
    /// and between which records, or — without a shelf — where it belongs.
    private func showShelf(_ copy: RecordCopy) {
        shelfRequests.placing = copy.id
        destination.current = .shelf
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
            Button("Cover größer") { storedCoverSize = DisplaySettings.coverSize(coverSize, offset: 1) }
                .keyboardShortcut(AppShortcuts.largerCovers)
                .disabled(!showsGrid || coverSize == DisplaySettings.coverSizes.last)
            // ⌘= as well: on US keyboards "+" needs Shift.
            Button("Cover größer") { storedCoverSize = DisplaySettings.coverSize(coverSize, offset: 1) }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(!showsGrid || coverSize == DisplaySettings.coverSizes.last)
            Button("Cover kleiner") { storedCoverSize = DisplaySettings.coverSize(coverSize, offset: -1) }
                .keyboardShortcut(AppShortcuts.smallerCovers)
                .disabled(!showsGrid || coverSize == DisplaySettings.coverSizes.first)
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
