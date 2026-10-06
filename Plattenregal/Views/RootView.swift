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
    /// Pages with grid and list in the toolbar.
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

    /// No sidebar: every control sits in one bar in the middle of the
    /// toolbar (see `MainToolbar`), so the pages start right below it. ⌘F
    /// puts the cursor in the search field. The settings are where a Mac app
    /// has them: Plattenregal menu and ⌘,.
    private var library: some View {
        pages
            .environment(\.searchRequests, searchRequests)
            // Names the window in the Fenster menu and Mission Control; the
            // toolbar shows the bar instead of a title.
            .navigationTitle("Plattenregal")
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    MainToolbar(selection: destination, library: search, shelf: shelfSearch, requests: searchRequests) {
                        Task { await statisticsModel.refresh(container: context.container) }
                    }
                }
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

/// All controls of the main window in one bar, centered in the toolbar:
/// page switch, grid/list, search and, in Klassisch, sync and settings.
/// Controls a page doesn't have leave the bar, which then ends earlier: it is
/// laid out from the left in the width of the fullest page (search closed),
/// so the page switch keeps its place and never moves under the pointer.
/// An opened search widens the bar to both sides.
private struct MainToolbar: View {
    let selection: PageSelection<Destination>
    let library: LibrarySearch
    let shelf: ShelfSearch
    let requests: SearchRequests
    let refreshStatistics: () -> Void

    var body: some View {
        let page = selection.current
        ZStack(alignment: .leading) {
            // Reserves the width of the fullest page, search closed.
            MainToolbarSizer().hidden()
            HStack(spacing: 0) {
                PagePicker(selection: selection)
                if page.hasLayoutSwitch {
                    ToolbarBarDivider()
                    LayoutSwitch(selection: selection)
                }
                if page.hasSearch {
                    ToolbarBarDivider()
                    ToolbarSearchField(selection: selection, library: library, shelf: shelf, requests: requests)
                }
                if AppStyle.isAtelier {
                    ToolbarBarDivider()
                    AtelierSyncButton(selection: selection, refreshStatistics: refreshStatistics)
                    SettingsLink { ToolbarBarIcon(systemImage: "gearshape", label: String(localized: "Einstellungen")) }
                        .buttonStyle(.plain)
                        .help(String(localized: "Einstellungen (⌘,)"))
                }
            }
            .toolbarBar()
        }
        .animation(AppStyle.quickAnimation, value: page)
    }
}

/// `MainToolbar` with every control a page can have, only for its width.
private struct MainToolbarSizer: View {
    var body: some View {
        HStack(spacing: 0) {
            GlassSegmentedPicker(selection: .constant(Destination.collection), options: Destination.allCases, glass: false) { Text($0.title) }
            ToolbarBarDivider()
            OverviewLayoutPicker(selection: .constant(.grid), glass: false)
            ToolbarBarDivider()
            ToolbarBarIcon(systemImage: "magnifyingglass", label: "")
            if AppStyle.isAtelier {
                ToolbarBarDivider()
                ToolbarBarIcon(systemImage: "arrow.clockwise", label: "")
                ToolbarBarIcon(systemImage: "gearshape", label: "")
            }
        }
        .toolbarBar()
        .accessibilityHidden(true)
    }
}

/// A faint line between the groups of the toolbar's bar.
private struct ToolbarBarDivider: View {
    var body: some View {
        Rectangle()
            .fill(AppStyle.isAtelier ? Color.white.opacity(0.18) : Color.primary.opacity(0.12))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 3)
    }
}

/// An icon button's label in the toolbar's bar, as wide as it is high.
private struct ToolbarBarIcon: View {
    static let width = AppStyle.toolbarBarHeight + 4
    let systemImage: String
    let label: String
    var body: some View {
        Image(systemName: systemImage)
            .foregroundStyle(AppStyle.isAtelier ? AnyShapeStyle(Color.white.opacity(0.85)) : AnyShapeStyle(.secondary))
            .frame(width: Self.width, height: AppStyle.toolbarBarHeight)
            .contentShape(Rectangle())
            .accessibilityLabel(label)
    }
}

/// Sync (collection, wantlist) or refresh (statistics) as a button in the
/// toolbar, only in Klassisch; the same as ⌘R or pulling the page down.
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
                ToolbarBarIcon(systemImage: "arrow.clockwise", label: title)
            }
            .buttonStyle(.plain)
            .help(title + " (⌘R)")
            // Discogs is off in the demo; the statistics still recalculate.
            .disabled(sync.busy || (DemoMode.isActive && page != .statistics))
        }
    }
}

/// The search in the toolbar's bar, on the pages that have one (not on the
/// statistics): a magnifying glass that opens into a field. A click on it or
/// ⌘F opens it with the cursor inside; it closes again when it loses the
/// focus empty, or on Esc in the empty field. While a query is active it stays
/// open, so no filter works unseen. Collection and wantlist share one query
/// (`LibrarySearch`), the shelf has its own (`ShelfSearch`); the pages read
/// them and filter themselves. Esc clears the query, a second Esc closes.
private struct ToolbarSearchField: View {
    let selection: PageSelection<Destination>
    let library: LibrarySearch
    let shelf: ShelfSearch
    let requests: SearchRequests
    @FocusState private var focused: Bool
    /// Opened by the magnifying glass or ⌘F.
    @State private var opened = false

    var body: some View {
        let page = selection.current
        let text = text(for: page)
        let open = opened || !text.wrappedValue.isEmpty
        HStack(spacing: 0) {
            Button {
                if open && text.wrappedValue.isEmpty {
                    close()
                } else if open {
                    focused = true
                } else {
                    withAnimation(AppStyle.fadeAnimation) { opened = true }
                    focused = true
                }
            } label: {
                ToolbarBarIcon(systemImage: "magnifyingglass", label: String(localized: "Suchen"))
            }
            .buttonStyle(.plain)
            .help(String(localized: "Suchen (⌘F)"))
            HStack(spacing: 6) {
                TextField(placeholder(for: page), text: text)
                    .textFieldStyle(.plain)
                    .noTextAutoFill()
                    .focused($focused)
                    .foregroundStyle(AppStyle.isAtelier ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
                    .onKeyPress(.escape) {
                        if !text.wrappedValue.isEmpty { text.wrappedValue = ""; return .handled }
                        focused = false
                        return .handled
                    }
                if let other = otherSection(for: page) { otherButton(other) }
                if !text.wrappedValue.isEmpty {
                    Button { text.wrappedValue = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Suche löschen"))
                }
            }
            .padding(.trailing, 10)
            // Closed, the field is there but has no width: ⌘F can put the
            // cursor in it right away while it opens.
            .frame(width: open ? AppStyle.toolbarSearchWidth - ToolbarBarIcon.width : 0, alignment: .leading)
            .clipped()
            .opacity(open ? 1 : 0)
            .allowsHitTesting(open)
            .accessibilityHidden(!open)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Suchen"))
        .animation(AppStyle.quickAnimation, value: otherSection(for: page)?.count)
        .onChange(of: requests.count) {
            guard selection.current.hasSearch else { return }
            withAnimation(AppStyle.fadeAnimation) { opened = true }
            focused = true
        }
        .onChange(of: focused) { _, new in
            requests.fieldFocused = new
            if new { withAnimation(AppStyle.fadeAnimation) { opened = true } }
            else if text.wrappedValue.isEmpty { close() }
        }
        // The shelf has its own query: its page opens only with one of its own.
        .onChange(of: page) { if !focused && text.wrappedValue.isEmpty { close() } }
        // Leaves the bar on the statistics, which have no search; the
        // focus goes with it.
        .onDisappear { requests.fieldFocused = false; opened = false }
    }

    private func close() {
        focused = false
        withAnimation(AppStyle.fadeAnimation) { opened = false }
    }

    /// The other page's hits for the same query, one click away; inside the
    /// field, so the bar keeps its width.
    private func otherButton(_ other: (page: Destination, count: Int)) -> some View {
        Button { selection.current = other.page } label: {
            // Quiet, like the placeholder: a hint, not a call to action.
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

/// Grid or list for collection and wantlist (see `hasLayoutSwitch`).
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
