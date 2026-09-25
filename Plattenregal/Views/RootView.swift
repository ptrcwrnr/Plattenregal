import SwiftUI
import SwiftData

enum Destination: String, CaseIterable, Identifiable {
    case overview = "Übersicht"
    case statistics = "Statistik"
    case shelf = "Regal"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "square.stack"
        case .statistics: "chart.bar.xaxis"
        case .shelf: "square.grid.3x3"
        }
    }
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
private struct GridReferenceWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}
extension EnvironmentValues {
    var isActivePage: Bool {
        get { self[ActivePageKey.self] }
        set { self[ActivePageKey.self] = newValue }
    }
    /// Width a page would have *with the sidebar shown*. Cover grids derive
    /// their column count from it, so toggling the sidebar keeps the columns
    /// and only scales the covers; `nil` (e.g. in sheets) = use the own width.
    var gridReferenceWidth: CGFloat? {
        get { self[GridReferenceWidthKey.self] }
        set { self[GridReferenceWidthKey.self] = newValue }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var releases: [Release]
    @State private var destination: Destination? = {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--preview-page=") }),
           let page = Destination(rawValue: String(raw.dropFirst("--preview-page=".count))) { return page }
        if ProcessInfo.processInfo.arguments.contains("--statistics-demo") { return .statistics }
        #endif
        return AppPreferences.shared.startPage.destination
    }()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var windowWidth: CGFloat = 0
    @State private var highlight: UUID?
    /// A record without a shelf whose alphabetical place the shelf page should show.
    @State private var placing: UUID?
    @State private var refresh = MetadataRefreshService()
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

    /// Matches `navigationSplitViewColumnWidth(ideal:)` below.
    private static let sidebarWidth: CGFloat = 225

    private var library: some View {
        // The window width doesn't change when the sidebar toggles — unlike the
        // detail width, which AppKit only updates at the end of the slide.
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $destination) {
                nav([.overview, .statistics])
                nav([.shelf])
            }
            .navigationTitle("Plattenregal")
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(min: 190, ideal: Self.sidebarWidth)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    SettingsLink { Label("Einstellungen", systemImage: "gearshape") }.buttonStyle(.plain)
                }.padding().frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            GeometryReader { geometry in
                detailContent(size: geometry.size)
            }
            .environment(\.gridReferenceWidth, windowWidth > 0 ? windowWidth - Self.sidebarWidth : nil)
            .navigationTitle(activePage.rawValue)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) { sidebarButton }
                .sharedBackgroundVisibility(.hidden)
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { windowWidth = $0 }
    }

    private func detailContent(size: CGSize) -> some View {
        VStack(spacing: 0) {
            if let error = refresh.error {
                AppBanner(message: error, kind: .warning, actionTitle: "Erneut versuchen", action: { refreshNow() }, onDismiss: { refresh.error = nil })
                    .padding(.horizontal, AppStyle.pagePadding)
                    .padding(.top, AppStyle.itemSpacing)
                    .transition(AppStyle.funnelTransition())
            }
            // Every page is built once and kept alive; switching only changes which
            // one is visible. Pages therefore keep their loaded data, sorting and
            // scroll position, and clicking through the sidebar is instant instead
            // of rebuilding (and re-sorting the whole collection) on every visit.
            ZStack {
                ForEach(Destination.allCases) { page in
                    let active = page == activePage
                    pageContent(page)
                        .environment(\.isActivePage, active)
                        .animation(AppStyle.fadeAnimation) { $0.opacity(active ? 1 : 0) }
                        .allowsHitTesting(active)
                        .disabled(!active)
                        .accessibilityHidden(!active)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .animation(AppStyle.standardAnimation, value: refresh.error)
    }

    private var sidebarButton: some View {
        IconButton(
            systemImage: "sidebar.left",
            help: columnVisibility == .detailOnly ? "Seitenleiste einblenden" : "Seitenleiste ausblenden"
        ) {
            withAnimation(AppStyle.layoutAnimation) {
                columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
            }
        }
        .accessibilityLabel("Seitenleiste umschalten")
    }
    private var activePage: Destination { destination ?? .overview }
    @ViewBuilder private func pageContent(_ page: Destination) -> some View {
        switch page {
        case .overview: OverviewView(showShelf: showShelf)
        case .statistics: StatisticsView(model: statisticsModel, showShelf: showShelf)
        case .shelf: KallaxView(highlight: $highlight, placing: $placing)
        }
    }
    private func nav(_ items: [Destination]) -> some View {
        ForEach(items) { item in Label(item.rawValue, systemImage: item.symbol).tag(item) }
    }
    /// Opens the shelf page with the card for this record: where it stands
    /// and between which records, or — without a shelf — where it belongs.
    private func showShelf(_ copy: RecordCopy) {
        placing = copy.id
        destination = .shelf
    }
    private func refreshNow() { Task { await refresh.refresh(releases, context: context) } }
}

/// "Übersicht": collection and wantlist behind one
/// picker. Like the sidebar pages, every section is built once and kept alive,
/// so switching keeps each section's data and scroll position.
struct OverviewView: View {
    @Environment(\.isActivePage) private var isActivePage
    let showShelf: (RecordCopy) -> Void
    /// Starts on the section chosen in the settings (Collection or Wantlist).
    @State private var section: OverviewSection = AppPreferences.shared.startPage.section
    /// One search for all sections, so a hit can be followed from the
    /// collection to the wantlist and back.
    @State private var query = ""
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
                showShelf: showShelf,
                scrollPosition: Binding(
                    get: { scrollPositions[item] },
                    set: { scrollPositions[item] = $0 }
                )
            )
            .id(item)
        case .wantlist: WantlistView(query: $query, section: $section)
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
