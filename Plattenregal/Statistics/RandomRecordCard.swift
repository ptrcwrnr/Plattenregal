import SwiftUI
import SwiftData

// MARK: - Random pick

/// One random record from the collection, rerolled on demand: a large cover
/// on the first grid columns, details on the rest, the cover blurred behind.
struct RandomRecordCard: View {
    let copies: [RecordCopy]
    /// The same records by ID (`StatisticsViewModel.copiesByID`), so finding
    /// the pick doesn't walk the whole collection on every render.
    let copiesByID: [UUID: RecordCopy]
    /// `StatisticsViewModel.version`: the shelf labels are recomputed on it,
    /// not on every render.
    let version: Int
    let open: (RecordCopy) -> Void
    let showShelf: (RecordCopy) -> Void
    @Environment(\.statisticsColumns) private var columns
    @State private var labelsCache = ShelfLabelsCache()
    /// The labels of every compartment, worked out once per state of the
    /// shelves (see the `task` below), not for every pick: a new pick only
    /// needs its own compartment's. `nil` = to be worked out again.
    @State private var labels: ShelfLabels?
    /// Where the pick stands, read from the app's own records: the page's
    /// copies come from a reload, and sorting in doesn't reload the page.
    @State private var placement: (location: String, inShelf: Bool)?
    @Environment(\.modelContext) private var context
    @State private var width: CGFloat = 0
    /// Stored by ID and looked up in the current `copies`: each reload hands
    /// in new objects, and an old one must not stay on screen.
    @State private var pickID: UUID?
    @State private var rolls = 0
    /// Shared with the pages, fetched only when they change (see `LibraryRecords`).
    private var shelves: [Shelf] { LibraryRecords.of(context).shelves }
    private var exclusions: [OptimizationExclusion] { LibraryRecords.of(context).exclusions }
    @AppStorage(ShelfLabelStyle.key) private var labelStyle = ShelfLabelStyle.range
    /// Decides a compartment's first and last record, so its label too.
    @AppStorage(ShelfSecondaryOrder.key) private var secondaryOrder = ShelfSecondaryOrder.title
    /// Records sorted in on the shelf page change the labels; while the
    /// statistics aren't shown, the place is worked out once they are.
    @State private var activity = PageActivity()
    @State private var placementPending = false
    private var pick: RecordCopy? { pickID.flatMap { copiesByID[$0] } }

    private var coverSpan: Int { columns >= 5 ? 2 : 1 }

    var body: some View {
        Group {
            if let pick, let release = pick.release {
                let coverWidth = StatisticsLayout.span(coverSpan, of: columns, in: width)
                HStack(alignment: .top, spacing: StatisticsLayout.gutter) {
                    Button { open(pick) } label: {
                        CoverView(url: release.coverURL, size: nil)
                            .atelierRecordSleeve()
                            .frame(width: min(coverWidth, 380))
                            .shadow(color: .black.opacity(AppStyle.isAtelier ? 0 : 0.25), radius: 18, y: 8)
                    }
                    .buttonStyle(.plain)
                    .help("Details anzeigen")
                    .frame(width: coverWidth, alignment: .leading)
                    details(pick, release)
                }
                .id(pick.id)
                .transition(AppStyle.reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                                           removal: .move(edge: .leading).combined(with: .opacity)))
            } else {
                Text("Noch keine Platten zum Ziehen.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
        // Whenever the pick is gone (first load, or a sync removed it) and
        // there is something to pick — not only when the count changes.
        // Places change without a reload of the page (see `StatisticsView.affectsStatistics`).
        .task(id: [version, labelStyle.hashValue, secondaryOrder.hashValue, LibraryChanges.shared.placementsVersion, LibraryChanges.shared.shelvesVersion]) {
            labels = nil
            if pick == nil { pickID = copies.randomElement()?.id }
            guard activity.isActive else { placementPending = true; return }
            updatePlacement()
        }
        .onChange(of: pickID) { updatePlacement() }
        .trackPageActivity(activity) { active in
            if active && placementPending { updatePlacement() }
        }
    }

    private func details(_ pick: RecordCopy, _ release: Release) -> some View {
        VStack(alignment: .leading, spacing: StatisticsLayout.gutter) {
            VStack(alignment: .leading, spacing: AppStyle.tightSpacing) {
                Text("Heute aus deiner Sammlung").font(.caption.weight(.semibold)).foregroundStyle(AppStyle.accent)
                Text(release.displayArtist)
                    .font(.system(.largeTitle, design: AppStyle.figureDesign, weight: .bold))
                    .lineLimit(2)
                Text(release.displayTitle).font(.title2).foregroundStyle(.secondary).lineLimit(2)
            }
            // Same columns as the page grid to the right of the cover.
            LazyVGrid(columns: StatisticsLayout.columns(max(1, columns - coverSpan)), alignment: .leading, spacing: AppStyle.rowSpacing) {
                detail(String(localized: "Jahr"), release.year.map(String.init))
                detail(String(localized: "Label"), release.displayLabel)
                detail(String(localized: "Land"), release.country)
                detail(String(localized: "Format"), release.format)
                detail(String(localized: "Tracks"), release.tracks.isEmpty ? nil : "\(release.tracks.count)")
                detail(String(localized: "Fach"), placement?.location)
            }
            if !release.styles.isEmpty {
                HStack(spacing: AppStyle.itemSpacing) { ForEach(release.styles.prefix(4), id: \.self) { AppBadge(title: $0) } }
            }
            HStack(spacing: AppStyle.itemSpacing) {
                Button { reroll() } label: {
                    Label("Neue Platte ziehen", systemImage: "dice")
                        .symbolEffect(.bounce, value: rolls)
                        .foregroundStyle(AppStyle.accent)
                }
                .appGlassButton()
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .help(AppShortcuts.help(String(localized: "Neue Platte ziehen"), keys: "⇧⌘R"))
                SecondaryButton(title: placement?.inShelf != true ? String(localized: "Platz im Regal finden") : String(localized: "Im Regal zeigen")) { showShelf(pick) }
                SecondaryButton(title: String(localized: "Details")) { open(pick) }
            }
            .controlSize(.large)
        }
    }

    @ViewBuilder private func detail(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value.flatMap { $0.isEmpty ? nil : $0 } ?? "—").font(.callout.weight(.medium)).lineLimit(1)
        }
        .help(value ?? "")
    }

    private func updatePlacement() {
        placementPending = false
        guard let id = pickID,
              let copy = try? context.fetch(FetchDescriptor<RecordCopy>(predicate: #Predicate { $0.id == id })).first
        else { placement = nil; return }
        let current = labels ?? labelsCache.labels(for: shelves, style: labelStyle)
        labels = current
        placement = (ShelfRangeLabels.location(of: copy, labels: current, excluded: exclusions.contains { $0.copyID == id }),
                     copy.shelf != nil)
    }

    private func reroll() {
        rolls += 1
        // Drawn again until it's another record – about one draw, where
        // filtering out the current one read every record's ID (and `pick`,
        // read for each, walked the list once more: seconds for 2 000).
        var next = copies.randomElement()?.id
        while copies.count > 1, next == pickID { next = copies.randomElement()?.id }
        withAnimation(AppStyle.layoutAnimation ?? AppStyle.fadeAnimation) { pickID = next }
    }
}
