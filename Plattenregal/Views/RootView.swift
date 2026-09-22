import SwiftUI
import SwiftData

enum Destination: String, CaseIterable, Identifiable {
    case all = "Sammlung"
    case wantlist = "Wantlist"
    case statistics = "Statistik"
    case recent = "Zuletzt"
    case shelf = "Regal"
    case discogs = "Suche"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .statistics: "chart.bar.xaxis"
        case .wantlist: "heart.text.clipboard"
        case .all: "square.stack"
        case .recent: "clock"
        case .shelf: "square.grid.3x3"
        case .discogs: "magnifyingglass"
        }
    }
}
private struct ActivePageKey: EnvironmentKey {
    static let defaultValue = true
}
extension EnvironmentValues {
    var isActivePage: Bool {
        get { self[ActivePageKey.self] }
        set { self[ActivePageKey.self] = newValue }
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var releases: [Release]
    @State private var destination: Destination? = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--statistics-demo") { return .statistics }
        if let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--preview-page=") }),
           let page = Destination(rawValue: String(raw.dropFirst("--preview-page=".count))) { return page }
        #endif
        return .all
    }()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var query = ""
    @State private var highlight: UUID?
    // Deliberately session-only: returning to a collection page restores its place,
    // while every fresh app launch still starts at the top.
    @State private var collectionScrollPositions: [Destination: UUID] = [:]
    @State private var refresh = MetadataRefreshService()
    // Loaded once here, alongside collection startup, so the Statistik page is
    // already populated the moment the user first navigates to it instead of
    // recomputing everything from scratch on every visit.
    @State private var statisticsModel = StatisticsViewModel()
    var body: some View {
        library
            .task { await statisticsModel.initialLoad(container: context.container) }
    }

    private var library: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $destination) {
                nav([.all, .wantlist, .statistics, .recent])
                nav([.shelf])
                nav([.discogs])
            }
            .navigationTitle("Plattenregal")
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(min: 190, ideal: 225)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("4 Spalten · 3 Reihen", systemImage: "square.grid.3x3").font(.caption).foregroundStyle(.secondary)
                    SettingsLink { Label("Einstellungen", systemImage: "gearshape") }.buttonStyle(.plain)
                }.padding().frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            GeometryReader { geometry in
                Group {
                    if supportsGlobalSearch {
                        detailContent(size: geometry.size)
                            .searchable(text: $query, prompt: "Sammlung durchsuchen")
                    } else {
                        detailContent(size: geometry.size)
                    }
                }
            }
            .navigationTitle(query.isEmpty ? activePage.rawValue : "Suchergebnisse")
        }
        .toolbar {
            if #available(macOS 26.0, *) {
                ToolbarItem(placement: .navigation) { sidebarButton }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .navigation) { sidebarButton }
            }
        }
        .onChange(of: destination) { _, page in
            if !supportsGlobalSearch(page) { query = "" }
        }
    }

    private func detailContent(size: CGSize) -> some View {
        VStack(spacing: 0) {
            if let error = refresh.error {
                AppBanner(message: error, kind: .warning, actionTitle: "Erneut versuchen", action: { refreshNow() }, onDismiss: { refresh.error = nil })
                    .padding(.horizontal, AppStyle.pagePadding)
                    .padding(.top, AppStyle.itemSpacing)
            }
            pageContent(activePage)
                .environment(\.isActivePage, true)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var supportsGlobalSearch: Bool { supportsGlobalSearch(destination) }
    private func supportsGlobalSearch(_ page: Destination?) -> Bool {
        page == .all || page == .recent
    }

    private var sidebarButton: some View {
        IconButton(
            systemImage: "sidebar.left",
            help: columnVisibility == .detailOnly ? "Seitenleiste einblenden" : "Seitenleiste ausblenden"
        ) {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        }
        .accessibilityLabel("Seitenleiste umschalten")
    }
    private var activePage: Destination { query.isEmpty ? destination ?? .all : .all }
    @ViewBuilder private func pageContent(_ page: Destination) -> some View {
        switch page {
        case .all, .recent:
            // .all/.recent share this one switch case, so without an explicit
            // id SwiftUI treats them as the same view identity and keeps one CollectionView's
            // @State (cached items, card geometry, scroll position, selection …) alive across
            // mode switches. That let state built up for one page keep affecting another
            // (e.g. a stale, gated card-frame cache making a later page feel choppy again).
            // Forcing a distinct id per page gives each its own, fully isolated state.
            CollectionView(
                mode: page,
                query: page == .all ? query : "",
                showShelf: showShelf,
                scrollPosition: Binding(
                    get: { collectionScrollPositions[page] },
                    set: { collectionScrollPositions[page] = $0 }
                )
            )
            .id(page)
        case .statistics: StatisticsView(model: statisticsModel, showShelf: showShelf)
        case .wantlist: WantlistView()
        case .shelf: KallaxView(highlight: $highlight)
        case .discogs: DiscogsSearchView()
        }
    }
    private func nav(_ items: [Destination]) -> some View {
        ForEach(items) { item in Label(item.rawValue, systemImage: item.symbol).tag(item) }
    }
    private func showShelf(_ copy: RecordCopy) {
        query = ""; highlight = copy.shelf?.id; destination = .shelf
    }
    private func refreshNow() { Task { await refresh.refresh(releases, context: context) } }
}
