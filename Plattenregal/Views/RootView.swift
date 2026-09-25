import SwiftUI
import SwiftData

enum Destination: String, CaseIterable, Identifiable {
    case overview = "Übersicht"
    case shelf = "Regal"
    case statistics = "Statistik"
    var id: String { rawValue }
    /// ⌘1 … ⌘3, in the order of the switch in the toolbar.
    var shortcut: KeyEquivalent {
        switch self {
        case .overview: "1"
        case .shelf: "2"
        case .statistics: "3"
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
    /// "Im Regal anzeigen" from any page, for the shelf page.
    @State private var shelfRequests = ShelfRequests()
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
            .environment(\.searchRequests, searchRequests)
            // Names the window in the Fenster menu and Mission Control; the
            // toolbar shows the page switch instead of a title.
            .navigationTitle("Plattenregal")
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .principal) { PagePicker(selection: destination) }
                ToolbarItemGroup(placement: .primaryAction) {
                    SearchButton(selection: destination) { searchRequests.request() }
                    SettingsLink { Label("Einstellungen", systemImage: "gearshape") }
                        .help("Einstellungen (⌘,)")
                }
            }
            .background(pageShortcuts)
    }

    /// ⌘1 … ⌘3 switch pages, like the tabs of a browser window.
    private var pageShortcuts: some View {
        ForEach(Destination.allCases) { page in
            Button(page.rawValue) { destination.current = page }
                .keyboardShortcut(page.shortcut, modifiers: .command)
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
        case .overview: OverviewView(showShelf: showShelf)
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

/// The page switch in the toolbar.
private struct PagePicker: View {
    @Bindable var selection: PageSelection<Destination>
    var body: some View {
        Picker("Rubrik", selection: $selection.current) {
            ForEach(Destination.allCases) { Text($0.rawValue).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.large)
        .fixedSize()
    }
}

/// ⌘F: reveals the search of the page shown; off where there is none.
private struct SearchButton: View {
    let selection: PageSelection<Destination>
    let action: () -> Void
    var body: some View {
        Button(action: action) { Label("Suchen", systemImage: "magnifyingglass") }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(!selection.current.hasSearch)
            .help("Suchen (⌘F)")
    }
}

/// "Übersicht": collection and wantlist behind one
/// picker. Like the pages, every section is built once and kept alive (`PageStack`),
/// so switching keeps each section's data and scroll position.
struct OverviewView: View {
    @Environment(\.modelContext) private var context
    let showShelf: (RecordCopy) -> Void
    /// Starts on the section chosen in the settings (Collection or Wantlist).
    @State private var section = PageSelection<OverviewSection>(AppPreferences.shared.startPage.section)
    /// One search for all sections, so a hit can be followed from the
    /// collection to the wantlist and back.
    @State private var search = OverviewSearch()

    var body: some View {
        PageStack(pages: OverviewSection.allCases, selection: section) {
            content($0).appPageEnvironment(context)
        }
    }

    /// The objects themselves, not bindings: each section is built once and
    /// is its own hosting view (see `PageStack`); only Observation reaches it.
    @ViewBuilder private func content(_ item: OverviewSection) -> some View {
        switch item {
        case .collection: CollectionView(sections: section, search: search, showShelf: showShelf)
        case .wantlist: WantlistView(search: search, sections: section)
        }
    }
}

/// The search shared by the overview sections.
@Observable final class OverviewSearch {
    var query = ""
    /// Revealed by ⌘F (see `SearchReveal`).
    var isPresented = false
}

/// Picker in the header bar of every "Übersicht" section.
struct OverviewSectionPicker: View {
    @Bindable var selection: PageSelection<OverviewSection>
    var body: some View {
        Picker("Bereich", selection: $selection.current) {
            ForEach(OverviewSection.allCases) { Text($0.rawValue).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
        .help("Collection oder Wantlist anzeigen")
    }
}
