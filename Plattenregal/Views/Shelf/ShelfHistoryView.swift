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
        VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
            VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
                Text("Verlauf").font(AppStyle.dialogTitle)
                Text("Einsortiert, verschoben, herausgenommen – „Rückgängig“ stellt die Platte wieder dorthin, wo sie vorher stand.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppStyle.pagePadding)
            .padding(.top, AppStyle.pagePadding)
            if let error {
                AppBanner(message: error, kind: .error)
                    .padding(.horizontal, AppStyle.pagePadding)
                    .transition(AppStyle.funnelTransition())
            }
            if entries.isEmpty {
                AppEmptyState(String(localized: "Noch nichts im Verlauf"), systemImage: "clock.arrow.circlepath",
                              description: Text("Sobald du Platten einsortierst, verschiebst oder aus einem Fach nimmst, stehen sie hier – und lassen sich rückgängig machen."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Self.days(entries), id: \.day) { group in
                            Text(Self.title(of: group.day))
                                .font(AppStyle.captionMark)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, AppStyle.itemSpacing)
                                .padding(.top, AppStyle.rowSpacing)
                                .padding(.bottom, AppStyle.tightSpacing)
                            ForEach(group.entries) { entry in
                                ShelfHistoryRow(entry: entry, copy: copies[entry.copyID],
                                                what: what(entry, shelves: shelves), blocker: blockers[entry.id]) {
                                    undo(entry)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppStyle.cardPadding)
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

/// One change: the record as in the shelf search (same cover and height),
/// what happened and when, and "Rückgängig" – or why that isn't possible.
private struct ShelfHistoryRow: View {
    let entry: ShelfHistoryEntry
    /// `nil` once the record left the collection.
    let copy: RecordCopy?
    let what: (headline: String, detail: String)
    let blocker: ShelfHistory.Blocker?
    let undo: () -> Void
    @State private var hovering = false

    var body: some View {
        let release = copy.flatMap { $0.isDeleted || $0.modelContext == nil ? nil : $0.release }
        HStack(spacing: AppStyle.rowSpacing) {
            CoverView(url: release?.coverURL, size: AssignmentCard<EmptyView>.coverSize)
            VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
                Text(release?.displayArtist ?? entry.artist).font(AppStyle.rowTitle)
                Text(release?.displayTitle ?? entry.title).font(.caption).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: AppStyle.hairSpacing) {
                Text(what.headline).font(AppStyle.captionLabel)
                Text("\(entry.date.formatted(date: .omitted, time: .shortened)) · \(what.detail)")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .truncationMode(.middle)
            .layoutPriority(1)
            action
                .frame(width: Self.actionWidth, alignment: .trailing)
        }
        .padding(.horizontal, AppStyle.itemSpacing)
        .frame(height: AssignmentRowMetrics.height)
        .opacity(entry.undoneAt == nil ? 1 : 0.55)
        .appHoverable(hovering, cornerRadius: AppStyle.rowRadius)
        .onHover { hovering = $0 }
        .animation(AppStyle.standardAnimation, value: blocker)
    }

    /// Room for the longest status, so the columns stay put when one changes.
    private static let actionWidth: CGFloat = 132

    @ViewBuilder private var action: some View {
        if let blocker {
            Text(blocker.title)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .help(blocker.message)
                .transition(.opacity)
        } else {
            Button("Rückgängig", action: undo)
                .appLinkButton()
                .font(.callout)
                .help(ShelfHistory.kind(of: entry) == .sortedIn
                      ? String(localized: "Nimmt die Platte wieder aus dem Fach – sie steht dann wieder unter „Noch nicht einsortiert“.")
                      : String(localized: "Stellt die Platte wieder an ihren vorigen Platz."))
                .transition(.opacity)
        }
    }
}
