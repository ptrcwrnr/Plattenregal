import SwiftUI
import SwiftData

/// One opening of the "Verlauf" panel.
struct ShelfHistoryRequest: Identifiable {
    let id = UUID()
}

/// "Verlauf" beside the round button of the shelf page: what was sorted in,
/// moved or taken out, newest first and by day. "Rückgängig" puts a record
/// back where it stood before (see `PositionService.undo`); the panel stays
/// open, so several changes can be taken back one after the other.
struct ShelfHistoryView: View {
    let labels: ShelfLabels
    @Environment(\.modelContext) private var context
    @Query(sort: \ShelfHistoryEntry.date, order: .reverse) private var entries: [ShelfHistoryEntry]
    @State private var error: String?
    /// Changes taken back since the panel opened, counted on the card.
    @State private var undoneCount = 0

    static let width: CGFloat = 660
    static let height: CGFloat = 640

    var body: some View {
        let records = LibraryRecords.of(context)
        let copies = Dictionary(records.copies.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let shelves = Dictionary(records.shelves.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // The shelf a record stands in is read from it directly: it changes
        // with every move, which the query alone wouldn't see.
        let blockers = ShelfHistory.blockers(entries, copies: copies, shelves: shelves,
                                             excluded: Set(records.exclusions.map(\.copyID)))
        // Built like "Platte hinzufügen": a card saying what the panel is for,
        // below it one large row per change – cover, caption, and larger,
        // what happened.
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                AssignmentCard(systemImage: "clock.arrow.circlepath", title: String(localized: "Verlauf"),
                               detail: String(localized: "„Rückgängig“ stellt eine Platte wieder dorthin, wo sie vorher stand")) {
                    if undoneCount > 0 {
                        AssignmentTally(count: undoneCount, one: String(localized: "Änderung rückgängig"),
                                        many: String(localized: "Änderungen rückgängig"))
                            .transition(.opacity)
                    }
                }
                .animation(AppStyle.standardAnimation, value: undoneCount)
                if let error {
                    AppBanner(message: error, kind: .error)
                        .transition(AppStyle.funnelTransition())
                }
            }
            .padding(.horizontal, AppStyle.pagePadding)
            .padding(.top, AppStyle.pagePadding)
            if entries.isEmpty {
                AppEmptyState(String(localized: "Noch nichts im Verlauf"), systemImage: "clock.arrow.circlepath",
                              description: Text("Sobald du Platten einsortierst, verschiebst oder aus einem Fach nimmst, stehen sie hier – und lassen sich rückgängig machen."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: CoverGrid.spacing) {
                        ForEach(Self.days(entries), id: \.day) { group in
                            VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                                Text(Self.title(of: group.day))
                                    .font(AppStyle.captionMark)
                                    .foregroundStyle(.secondary)
                                ForEach(group.entries) { entry in
                                    ShelfHistoryRow(entry: entry, copy: copies[entry.copyID],
                                                    what: what(entry, shelves: shelves), blocker: blockers[entry.id]) {
                                        undo(entry)
                                    }
                                    .padding(.bottom, AppStyle.itemSpacing)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppStyle.pagePadding)
                    .padding(.top, AppStyle.sectionSpacing)
                    .padding(.bottom, AppStyle.pagePadding)
                }
                .scrollIndicators(.automatic)
            }
        }
        .frame(width: Self.width, height: Self.height, alignment: .top)
        .animation(AppStyle.standardAnimation, value: error)
    }

    private func undo(_ entry: ShelfHistoryEntry) {
        do {
            try PositionService(context: context).undo(entry)
            error = nil
            undoneCount += 1
        } catch { self.error = error.reportedMessage() }
    }

    /// What happened, in two lines: where to, and the position.
    private func what(_ entry: ShelfHistoryEntry, shelves: [UUID: Shelf]) -> (headline: String, detail: String) {
        let from = name(entry.fromShelfID, fallback: entry.fromName, shelves: shelves)
        let to = name(entry.toShelfID, fallback: entry.toName, shelves: shelves)
        switch ShelfHistory.kind(of: entry) {
        case .sortedIn:
            return (String(localized: "Einsortiert in „\(to)“"), String(localized: "Position \(entry.toPosition)"))
        case .takenOut:
            return (String(localized: "Herausgenommen aus „\(from)“"), String(localized: "Stand an Position \(entry.fromPosition)"))
        case .moved where entry.fromShelfID == entry.toShelfID:
            return (String(localized: "Umgestellt in „\(to)“"), String(localized: "Position \(entry.fromPosition) → \(entry.toPosition)"))
        case .moved:
            return (String(localized: "Von „\(from)“ nach „\(to)“"), String(localized: "Position \(entry.toPosition)"))
        }
    }

    /// The compartment as the shelf page names it now; the name at the time
    /// once it is gone.
    private func name(_ id: UUID?, fallback: String, shelves: [UUID: Shelf]) -> String {
        guard let id, let shelf = shelves[id], !shelf.isDeleted, shelf.modelContext != nil else { return fallback }
        return labels.prefix(for: shelf) + (labels[shelf.id] ?? shelf.numberText)
    }

    private struct Day { let day: Date; let entries: [ShelfHistoryEntry] }

    /// Entries are newest first, so each day is one run.
    private static func days(_ entries: [ShelfHistoryEntry]) -> [Day] {
        let calendar = Calendar.current
        var result: [Day] = []
        var current: (day: Date, entries: [ShelfHistoryEntry])?
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            if current?.day == day { current?.entries.append(entry); continue }
            if let current { result.append(Day(day: current.day, entries: current.entries)) }
            current = (day, [entry])
        }
        if let current { result.append(Day(day: current.day, entries: current.entries)) }
        return result
    }

    private static func title(of day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return String(localized: "Heute") }
        if calendar.isDateInYesterday(day) { return String(localized: "Gestern") }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }
}

/// One change, as large as a row of "Platte hinzufügen": the cover as in a
/// compartment's grid, beside it the record's caption, larger what happened
/// (accent while it can be undone), when and where, and "Rückgängig" – or a
/// tag saying why that isn't possible.
private struct ShelfHistoryRow: View {
    let entry: ShelfHistoryEntry
    /// `nil` once the record left the collection.
    let copy: RecordCopy?
    let what: (headline: String, detail: String)
    let blocker: ShelfHistory.Blocker?
    let undo: () -> Void

    var body: some View {
        let release = copy.flatMap { $0.isDeleted || $0.modelContext == nil ? nil : $0.release }
        HStack(alignment: .center, spacing: AppStyle.sectionSpacing) {
            CoverView(url: release?.shownCoverURL, size: AssignmentRowMetrics.largeCoverSize)
                .atelierRecordSleeve()
            VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                // The same caption as in the compartment, Collection and Wantlist.
                RecordCaption(release: release, fallbackArtist: entry.artist, fallbackTitle: entry.title)
                VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
                    Text(what.headline)
                        .font(AppStyle.sectionTitle)
                        .foregroundStyle(blocker == nil ? AnyShapeStyle(AppStyle.accent) : AnyShapeStyle(.secondary))
                    Text("\(entry.date.formatted(date: .omitted, time: .shortened)) · \(what.detail)")
                        .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                }
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                action
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(entry.undoneAt == nil ? 1 : 0.55)
        .animation(AppStyle.standardAnimation, value: blocker)
    }

    @ViewBuilder private var action: some View {
        if let blocker {
            // Plain text in the button's place: no tag.
            Text(blocker.title)
                .font(AppStyle.captionLabel)
                .foregroundStyle(.secondary)
                .fixedSize()
                .help(blocker.message)
                .transition(.opacity)
        } else {
            SecondaryButton(title: String(localized: "Rückgängig"), action: undo)
                .help(ShelfHistory.kind(of: entry) == .sortedIn
                      ? String(localized: "Nimmt die Platte wieder aus dem Fach – sie steht dann wieder unter „Noch nicht einsortiert“.")
                      : String(localized: "Stellt die Platte wieder an ihren vorigen Platz."))
                .transition(.opacity)
        }
    }
}
