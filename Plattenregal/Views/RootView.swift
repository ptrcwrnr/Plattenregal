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
    var body: some View {
        library
            // Over all pages, in the middle of the window; marked as seen however it closes.
            .appPanel(item: $welcome.request, alignment: .center, onDismiss: { AppWelcome.shared.markSeen() }) { _ in
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

    /// No sidebar: the page switch centered in the toolbar, the search at
    /// its right end (⌘F), so the pages start right below it. On collection
    /// and wantlist grid or list, sync and settings fan out of the round
    /// button at the bottom right (see `FloatingControls`). The settings are
    /// also where a Mac app has them: Plattenregal menu and ⌘,.
    private var library: some View {
        pages
            .environment(\.searchRequests, searchRequests)
            .overlay(alignment: .bottomTrailing) { FloatingControls(selection: destination) }
            // Names the window in the Fenster menu and Mission Control; the
            // toolbar shows the page switch instead of a title.
            .navigationTitle("Plattenregal")
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .principal) { PagePicker(selection: destination).toolbarBar() }
                    // The bar brings its own background (see `toolbarBar`).
                    .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .primaryAction) {
                    ToolbarSearchField(selection: destination, library: search, shelf: shelfSearch, requests: searchRequests)
                }
                // Brings its own capsule (see `searchBarChrome`).
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
                // Room at the end of the pages with the floating button, so
                // the last covers and rows scroll clear of it.
                .safeAreaPadding(.bottom, $0.hasActions ? AppStyle.floatingClearance : 0)
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

/// The round button at the bottom right of the window, only on collection
/// and wantlist. A click fans the page's actions out around it on a quarter
/// circle – grid or list, sync, settings – and closes them again; so does
/// Esc, a click beside them or choosing one.
private struct FloatingControls: View {
    let selection: PageSelection<Destination>
    @Environment(\.modelContext) private var context
    @Environment(\.openSettings) private var openSettings
    @State private var sync = DiscogsSyncService.shared
    @AppStorage(DisplaySettings.collectionLayoutKey) private var collectionLayout = OverviewLayout.grid
    @AppStorage(DisplaySettings.wantlistLayoutKey) private var wantlistLayout = OverviewLayout.grid
    /// The actions fanned out (debug: `--preview-actions` starts with them).
    @State private var expanded = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--preview-actions")
        #else
        false
        #endif
    }()

    private enum Action: Hashable, CaseIterable { case layout, sync, settings }

    var body: some View {
        let page = selection.current
        ZStack {
            if page.hasActions {
                controls(page: page).transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(AppStyle.quickAnimation, value: page.hasActions)
        .onChange(of: page) { collapse() }
    }

    private func controls(page: Destination) -> some View {
        let actions = Action.allCases
        return ZStack {
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
        // A click anywhere beside the button and the actions – page,
        // list, toolbar – closes them.
        .background {
            if expanded {
                OutsideClickWatcher(spots: [.zero] + actions.indices.map { Self.offset($0, of: actions.count) }) { collapse() }
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

    /// On a quarter circle from straight left to straight up of the button.
    private static func offset(_ index: Int, of count: Int) -> CGSize {
        let degrees = count == 1 ? 135 : 180 - Double(index) * 90 / Double(count - 1)
        let radians = degrees * .pi / 180
        let radius = AppStyle.floatingButtonSize + 34
        return CGSize(width: radius * cos(radians), height: -radius * sin(radians))
    }

    @ViewBuilder private func actionButton(_ action: Action, page: Destination) -> some View {
        switch action {
        case .layout:
            let layout = layoutBinding(for: page)
            let next: OverviewLayout = layout?.wrappedValue == .grid ? .list : .grid
            item(next.systemImage, next == .list ? String(localized: "Als Liste anzeigen") : String(localized: "Als Raster anzeigen")) {
                layout?.wrappedValue = next
            }
        case .sync:
            let title = String(localized: "Synchronisieren")
            item("arrow.clockwise", title, help: title + " (⌘R)") {
                sync.start(page == .wantlist ? .wantlist : .collection, container: context.container)
            }
            // Discogs is off in the demo.
            .disabled(sync.busy || DemoMode.isActive)
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
}

/// The search field at the right end of the toolbar, on the pages that have
/// one (not on the statistics). It ends flush with the covers below it: the
/// toolbar's own margin is topped up to the pages' (`toolbarSearchInset`).
/// ⌘F puts the cursor in it; Esc clears the query, a second Esc leaves it.
/// Collection and wantlist share one query (`LibrarySearch`), the shelf has
/// its own (`ShelfSearch`); the pages read them and filter themselves.
private struct ToolbarSearchField: View {
    let selection: PageSelection<Destination>
    let library: LibrarySearch
    let shelf: ShelfSearch
    let requests: SearchRequests
    @FocusState private var focused: Bool

    var body: some View {
        let page = selection.current
        Group {
            if page.hasSearch {
                AppSearchField(placeholder: placeholder(for: page), text: text(for: page), focus: $focused, onToolbar: true)
                    .frame(width: AppStyle.toolbarSearchWidth)
                    .padding(.trailing, AppStyle.toolbarSearchInset)
                    .accessibilityLabel(String(localized: "Suchen"))
                    .transition(.opacity)
            }
        }
        .animation(AppStyle.fadeAnimation, value: page.hasSearch)
        .onChange(of: requests.count) {
            guard selection.current.hasSearch else { return }
            focused = true
        }
        .onChange(of: focused) { _, new in requests.fieldFocused = new }
        .onChange(of: page) { if !page.hasSearch { focused = false } }
    }

    private func text(for page: Destination) -> Binding<String> {
        page == .shelf ? Bindable(shelf).text : Bindable(library).query
    }

    private func placeholder(for page: Destination) -> String {
        switch page {
        case .collection: String(localized: "Collection durchsuchen")
        case .wantlist: String(localized: "Wantlist durchsuchen")
        case .shelf, .statistics: String(localized: "Regal durchsuchen")
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

/// The search shared by collection and wantlist. An object, read by the
/// pages themselves: each page is built once (see `PageStack`), and a binding
/// handed in would keep the value it had then.
@Observable final class LibrarySearch {
    var query = ""
}

/// Watches the window's clicks while the actions are fanned out and reports
/// one that misses the button and every action. It watches instead of
/// catching, so the click still reaches what is under it – a list, the
/// toolbar, a cover – the same as beside an open menu.
private struct OutsideClickWatcher: NSViewRepresentable {
    /// The centers of the button and the actions, relative to the button's.
    let spots: [CGSize]
    let outside: () -> Void

    func makeNSView(context: Context) -> Watcher { Watcher() }
    func updateNSView(_ view: Watcher, context: Context) {
        view.spots = spots
        view.outside = outside
    }
    static func dismantleNSView(_ view: Watcher, coordinator: ()) { view.stop() }

    final class Watcher: NSView {
        var spots: [CGSize] = []
        var outside: (() -> Void)?
        private var monitor: Any?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                let p = self.convert(event.locationInWindow, from: nil)
                let reach = AppStyle.floatingButtonSize / 2 + 4
                let hit = self.spots.contains { spot in
                    hypot(p.x - (self.bounds.midX + spot.width), p.y - (self.bounds.midY + spot.height)) <= reach
                }
                if !hit { self.outside?() }
                return event
            }
        }
        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
