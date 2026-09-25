import SwiftUI
import SwiftData

enum Destination: String, CaseIterable, Identifiable {
    case overview = "Übersicht"
    case statistics = "Statistik"
    case shelf = "Regal"
    var id: String { rawValue }
    /// ⌘1 … ⌘3, in the order of the switch in the toolbar.
    var shortcut: KeyEquivalent {
        switch self {
        case .overview: "1"
        case .statistics: "2"
        case .shelf: "3"
        }
    }
    /// Pages with a search that ⌘F reveals.
    var hasSearch: Bool { self != .statistics }
}
/// The two views inside "Übersicht", switched from the picker in each page's header bar.
enum OverviewSection: String, CaseIterable, Identifiable {
    case collection = "Collection"
    case wantlist = "Wantlist"
    var id: String { rawValue }
}
private struct ActivePageKey: EnvironmentKey {
    static let defaultValue = true
}
private struct SearchRequestKey: EnvironmentKey {
    static let defaultValue = 0
}
extension EnvironmentValues {
    var isActivePage: Bool {
        get { self[ActivePageKey.self] }
        set { self[ActivePageKey.self] = newValue }
    }
    /// Counts ⌘F presses; the active page reveals its search on each change
    /// (see `SearchReveal`).
    var searchRequest: Int {
        get { self[SearchRequestKey.self] }
        set { self[SearchRequestKey.self] = newValue }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var destination: Destination = {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--preview-page=") }),
           let page = Destination(rawValue: String(raw.dropFirst("--preview-page=".count))) { return page }
        if ProcessInfo.processInfo.arguments.contains("--statistics-demo") { return .statistics }
        #endif
        return AppPreferences.shared.startPage.destination
    }()
    /// Bumped by ⌘F / the search button; see `EnvironmentValues.searchRequest`.
    @State private var searchRequest = 0
    @State private var highlight: UUID?
    /// A record without a shelf whose alphabetical place the shelf page should show.
    @State private var placing: UUID?
    // Loaded once here, alongside collection startup, so the Statistik page is
    // already populated the moment the user first navigates to it instead of
    // recomputing everything from scratch on every visit.
    @State private var statisticsModel = StatisticsViewModel()
    var body: some View {
        library
            .task { await statisticsModel.initialLoad(container: context.container) }
            // An interrupted first tracklist run (or due refreshes) continues on its own.
            .task { await DiscogsSyncService.shared.resumeTracklistsIfNeeded(container: context.container) }
            // Writes the export into the chosen folder when it is due.
            .task { ScheduledExport.shared.start(container: context.container) }
            .task { CoverCache.shared.pruneDisk() }
    }

    /// No sidebar: the three pages sit in a segmented switch in the middle of
    /// the toolbar (Liquid Glass); search and settings on the right.
    private var library: some View {
        pages
            .environment(\.searchRequest, searchRequest)
            // The window title (Fenster menu, Mission Control) names the page;
            // the switch already shows it, so the toolbar doesn't repeat it.
            .navigationTitle(destination.rawValue)
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .principal) { pagePicker }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { searchRequest += 1 } label: { Label("Suchen", systemImage: "magnifyingglass") }
                        .keyboardShortcut("f", modifiers: .command)
                        .disabled(!destination.hasSearch)
                        .help("Suchen (⌘F)")
                    SettingsLink { Label("Einstellungen", systemImage: "gearshape") }
                        .help("Einstellungen (⌘,)")
                }
            }
            .background(pageShortcuts)
    }

    private var pagePicker: some View {
        Picker("Rubrik", selection: $destination) {
            ForEach(Destination.allCases) { Text($0.rawValue).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.large)
        .fixedSize()
    }

    /// ⌘1 … ⌘3 switch pages, like the tabs of a browser window.
    private var pageShortcuts: some View {
        ForEach(Destination.allCases) { page in
            Button(page.rawValue) { destination = page }
                .keyboardShortcut(page.shortcut, modifiers: .command)
        }
        .opacity(0).frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    /// Every page is built once and kept alive; switching only changes which
    /// one is visible. Pages therefore keep their loaded data, sorting and
    /// scroll position, and switching pages is instant instead
    /// of rebuilding (and re-sorting the whole collection) on every visit.
    private var pages: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Destination.allCases) { page in
                let active = page == destination
                pageContent(page)
                    .environment(\.isActivePage, active)
                    .animation(AppStyle.fadeAnimation) { $0.opacity(active ? 1 : 0) }
                    .allowsHitTesting(active)
                    .disabled(!active)
                    .accessibilityHidden(!active)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private func pageContent(_ page: Destination) -> some View {
        switch page {
        case .overview: OverviewView(showShelf: showShelf)
        case .statistics: StatisticsView(model: statisticsModel, showShelf: showShelf)
        case .shelf: KallaxView(highlight: $highlight, placing: $placing)
        }
    }
    /// Opens the shelf page with the card for this record: where it stands
    /// and between which records, or — without a shelf — where it belongs.
    private func showShelf(_ copy: RecordCopy) {
        placing = copy.id
        destination = .shelf
    }
}

/// "Übersicht": collection and wantlist behind one
/// picker. Like the pages, every section is built once and kept alive,
/// so switching keeps each section's data and scroll position.
struct OverviewView: View {
    @Environment(\.isActivePage) private var isActivePage
    let showShelf: (RecordCopy) -> Void
    /// Starts on the section chosen in the settings (Collection or Wantlist).
    @State private var section: OverviewSection = AppPreferences.shared.startPage.section
    /// One search for all sections, so a hit can be followed from the
    /// collection to the wantlist and back.
    @State private var query = ""
    /// The search bar revealed by ⌘F, shared like the query.
    @State private var searchPresented = false
    // Deliberately session-only: returning to a section restores its place,
    // while every fresh app launch still starts at the top.
    @State private var scrollPositions: [OverviewSection: UUID] = [:]

    var body: some View {
        ZStack {
            ForEach(OverviewSection.allCases) { item in
                let active = item == section
                content(item)
                    .environment(\.isActivePage, isActivePage && active)
                    .opacity(active ? 1 : 0)
                    .animation(AppStyle.fadeAnimation, value: active)
                    .allowsHitTesting(active)
                    .disabled(!active)
                    .accessibilityHidden(!active)
            }
        }
    }

    @ViewBuilder private func content(_ item: OverviewSection) -> some View {
        switch item {
        case .collection:
            CollectionView(
                section: $section,
                query: $query,
                searchPresented: $searchPresented,
                showShelf: showShelf,
                scrollPosition: Binding(
                    get: { scrollPositions[item] },
                    set: { scrollPositions[item] = $0 }
                )
            )
            .id(item)
        case .wantlist: WantlistView(query: $query, searchPresented: $searchPresented, section: $section)
        }
    }
}

/// Picker in the header bar of every "Übersicht" section.
struct OverviewSectionPicker: View {
    @Binding var selection: OverviewSection
    var body: some View {
        Picker("Bereich", selection: $selection) {
            ForEach(OverviewSection.allCases) { Text($0.rawValue).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
        .help("Collection oder Wantlist anzeigen")
    }
}
