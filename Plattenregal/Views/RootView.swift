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
    /// Pages with a search field in the toolbar (⌘F puts the cursor in it).
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
    /// ⌘F and the focus of the search field; see `SearchRequests`.
    @State private var searchRequests = SearchRequests()
    /// One search for collection and wantlist, so a hit can be followed from
    /// one to the other.
    @State private var search = LibrarySearch()
    /// What is typed into the search field while the shelf page is shown.
    @State private var shelfSearch = ShelfSearch()
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
    /// grid/list and the search field on the right, all in the toolbar, so
    /// the pages start right below it. ⌘F puts the cursor in the field.
    /// The settings are where a Mac app has them: Plattenregal menu and ⌘,.
    private var library: some View {
        pages
            .environment(\.searchRequests, searchRequests)
            // Names the window in the Fenster menu and Mission Control; the
            // toolbar shows the page switch instead of a title.
            .navigationTitle("Plattenregal")
            .toolbar(removing: .title)
            .toolbar {
                // Only in Atelier, so the current design gets no empty items.
                if AppStyle.isAtelier {
                    ToolbarItem(placement: .navigation) { AtelierBrand() }
                        .sharedBackgroundVisibility(.hidden)
                }
                ToolbarItem(placement: .principal) { PagePicker(selection: destination) }
                    .sharedBackgroundVisibility(AppStyle.isAtelier ? .hidden : .automatic)
                ToolbarItem(placement: .primaryAction) { LayoutSwitch(selection: destination) }
                    .sharedBackgroundVisibility(AppStyle.isAtelier ? .hidden : .automatic)
                // Brings its own capsule, like the search bars on the pages did.
                ToolbarItem(placement: .primaryAction) {
                    ToolbarSearchField(selection: destination, library: search, shelf: shelfSearch, requests: searchRequests)
                }
                .sharedBackgroundVisibility(.hidden)
                // Atelier: sync and settings at the right end of its toolbar.
                if AppStyle.isAtelier {
                    ToolbarItem(placement: .primaryAction) {
                        AtelierSyncButton(selection: destination) {
                            Task { await statisticsModel.refresh(container: context.container) }
                        }
                    }
                    .sharedBackgroundVisibility(.hidden)
                    ToolbarItem(placement: .primaryAction) {
                        SettingsLink { Image(systemName: "gearshape").accessibilityLabel(String(localized: "Einstellungen")) }
                            .foregroundStyle(Color.white.opacity(0.85))
                            .help(String(localized: "Einstellungen (⌘,)"))
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
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
            pageContent($0).appPageEnvironment(context)
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

private struct AtelierBrand: View {
    var body: some View {
        HStack(spacing: 7) {
            if let icon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: icon).resizable().frame(width: 28, height: 28)
            }
            Text("Plattenregal").font(.callout.weight(.semibold)).foregroundStyle(.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Plattenregal")
    }
}

/// Sync (collection, wantlist) or refresh (statistics) as a button in the
/// toolbar, only in Atelier; the same as ⌘R or pulling the page down.
private struct AtelierSyncButton: View {
    let selection: PageSelection<Destination>
    let refreshStatistics: () -> Void
    @Environment(\.modelContext) private var context
    @State private var sync = DiscogsSyncService.shared
    var body: some View {
        let page = selection.current
        if page != .shelf {
            let title = page == .statistics ? String(localized: "Aktualisieren") : String(localized: "Synchronisieren")
            Button {
                switch page {
                case .collection: sync.start(.collection, container: context.container)
                case .wantlist: sync.start(.wantlist, container: context.container)
                case .statistics: refreshStatistics()
                case .shelf: break
                }
            } label: {
                Image(systemName: "arrow.clockwise").accessibilityLabel(title)
            }
            .foregroundStyle(Color.white.opacity(0.85))
            .help(title + " (⌘R)")
            // Discogs is off in the demo; the statistics still recalculate.
            .disabled(sync.busy || (DemoMode.isActive && page != .statistics))
        }
    }
}

/// The search field in the toolbar, always there on the pages that have a
/// search (not on the statistics). Collection and wantlist share one query
/// (`LibrarySearch`), the shelf has its own (`ShelfSearch`); the pages read
/// them and filter themselves. ⌘F puts the cursor in it; Esc clears it, a
/// second Esc leaves it.
private struct ToolbarSearchField: View {
    let selection: PageSelection<Destination>
    let library: LibrarySearch
    let shelf: ShelfSearch
    let requests: SearchRequests
    @FocusState private var focused: Bool

    var body: some View {
        let page = selection.current
        HStack(spacing: AppStyle.itemSpacing) {
            if let other = otherSection(for: page) {
                // The other page's hits for the same query, one click away.
                Button { selection.current = other.page } label: {
                    Text("\(other.count.formatted()) in der \(other.page.title)")
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .appGlassButton()
                .fixedSize()
                .help("Treffer in der \(other.page.title) anzeigen")
                .accessibilityLabel("\(other.count) Treffer in der \(other.page.title) anzeigen")
                .transition(.opacity)
            }
            if page.hasSearch {
                AppSearchField(placeholder: placeholder(for: page), text: text(for: page), focus: $focused)
                    .frame(width: AppStyle.toolbarSearchWidth)
                    .accessibilityLabel(String(localized: "Suchen"))
            }
        }
        .animation(AppStyle.quickAnimation, value: otherSection(for: page)?.count)
        .onChange(of: requests.count) {
            guard selection.current.hasSearch else { return }
            focused = true
        }
        .onChange(of: focused) { _, new in requests.fieldFocused = new }
        // The statistics have no field: it must not keep the focus there.
        .onChange(of: page) { _, new in if !new.hasSearch { focused = false } }
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
    /// Hits of `query` on the other page, for the button beside the search
    /// field: the collection counts the wantlist's, the wantlist the collection's.
    var wantlistMatches = 0
    var collectionMatches = 0
}
