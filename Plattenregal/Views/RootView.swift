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
    /// Pages with a search that ⌘F reveals.
    var hasSearch: Bool { self != .statistics }
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
    /// ⌘F / the search button; see `SearchRequests`.
    @State private var searchRequests = SearchRequests()
    /// One search for collection and wantlist, so a hit can be followed from
    /// one to the other.
    @State private var search = LibrarySearch()
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

    /// No sidebar: the pages sit in a switch in the middle of the toolbar,
    /// grid/list on the right, all in the toolbar's Liquid Glass. Search has
    /// no button: ⌘F reveals it.
    /// The settings are where a Mac app has them: Plattenregal menu and ⌘,.
    private var library: some View {
        pages
            .environment(\.searchRequests, searchRequests)
            // Names the window in the Fenster menu and Mission Control; the
            // toolbar shows the page switch instead of a title.
            .navigationTitle("Plattenregal")
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .principal) { PagePicker(selection: destination) }
                ToolbarItem(placement: .primaryAction) { LayoutSwitch(selection: destination) }
            }
            .background(pageShortcuts)
            .background(GlobalShortcuts(selection: destination))
            .background { AmbientGlow() }
    }

    /// ⌘1 … ⌘4 switch pages, like the tabs of a browser window; ⌘F toggles
    /// the search of the page shown, where it has one.
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
            pageContent($0).appPageEnvironment(context)
        }
    }

    @ViewBuilder private func pageContent(_ page: Destination) -> some View {
        switch page {
        case .collection: CollectionView(pages: destination, search: search, showShelf: showShelf)
        case .wantlist: WantlistView(search: search, pages: destination)
        case .statistics: StatisticsView(model: statisticsModel, showShelf: showShelf)
        case .shelf: KallaxView(requests: shelfRequests)
        }
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

/// Grid or list for collection and wantlist; absent on the other pages.
private struct LayoutSwitch: View {
    let selection: PageSelection<Destination>
    @AppStorage(DisplaySettings.collectionLayoutKey) private var collectionLayout = OverviewLayout.grid
    @AppStorage(DisplaySettings.wantlistLayoutKey) private var wantlistLayout = OverviewLayout.grid
    var body: some View {
        switch selection.current {
        case .collection: OverviewLayoutPicker(selection: $collectionLayout.animation(AppStyle.fadeAnimation), glass: false)
        case .wantlist: OverviewLayoutPicker(selection: $wantlistLayout.animation(AppStyle.fadeAnimation), glass: false)
        case .shelf, .statistics: EmptyView()
        }
    }
}

/// The search shared by collection and wantlist. An object, read by the
/// pages themselves: each page is built once (see `PageStack`), and a binding
/// handed in would keep the value it had then.
@Observable final class LibrarySearch {
    var query = ""
    /// Revealed by ⌘F (see `SearchReveal`).
    var isPresented = false
}
