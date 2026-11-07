import SwiftUI
import SwiftData

/// "+" in the compartment header: pick records that don't have a shelf yet.
/// Records marked "Gesucht" aren't offered; the settings list them.
/// A glass panel over the page, closed by a click beside it or Esc: the
/// target compartment on a glass card, below it one row per record – the
/// cover as large as in the compartment's grid, beside it across the panel
/// the record and, larger, where it goes. A click adds it. No title – the card says what
/// the panel is for. All state is in the session.
struct ShelfAssignmentView: View {
    @Bindable var session: ShelfAssignmentSession
    let owner: String?
    let rangeLabel: String?
    /// All shelf names, for the rows that belong elsewhere.
    let labels: ShelfLabels
    /// Every mark in the rack; a record released in the settings returns to the list.
    var missingIDs: Set<UUID> = []
    /// Off in the settings: no "Auf die Suchliste setzen", marked records are listed like the rest.
    var missingEnabled = true
    /// Opens the settings on "Listen".
    var openMissing: () -> Void = {}
    @Environment(\.modelContext) private var context

    static let listWidth: CGFloat = 660

    var body: some View {
        addColumn
            .frame(width: Self.listWidth, height: 640)
            .onChange(of: missingIDs) { _, ids in session.syncMissing(ids) }
    }

    private var addColumn: some View {
        // Records marked "Gesucht" wait in the settings, not here.
        let items = missingEnabled ? session.visible.filter { !session.missing.contains($0.id) } : session.visible
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                targetCard
                if let error = session.error {
                    AppBanner(message: error, kind: .error)
                        .transition(AppStyle.funnelTransition())
                }
            }
            .padding(.horizontal, AppStyle.pagePadding)
            .padding(.top, AppStyle.pagePadding)
            ZStack {
                ShelfAssignmentGrid(items: items, missingEnabled: missingEnabled,
                                    rackWide: session.isRackWide,
                                    belongsElsewhere: session.belongsElsewhere,
                                    toggleMissing: { [session, context] copy in session.toggleMissing(copy, in: context) },
                                    hover: { [session] copy, hovering in session.hover(copy, hovering) },
                                    location: location) { [session, context] copy in
                    session.add(copy, in: context)
                }
                if session.loaded && items.isEmpty {
                    if pausedCount > 0 {
                        AppEmptyState(String(localized: "Nur noch gesuchte Platten"), systemImage: "checkmark.circle",
                                      description: Text("Alle übrigen noch nicht einsortierten Platten stehen auf der Suchliste. In den Einstellungen unter „Listen“ markierst du sie als gefunden."),
                                      actionTitle: String(localized: "Suchliste …"), action: openMissing)
                    } else {
                        AppEmptyState(String(localized: "Alles einsortiert"), systemImage: "checkmark.circle",
                                      description: Text("Jede Platte der Sammlung liegt bereits in einem Fach."))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(AppStyle.standardAnimation, value: session.error)
        .onAppear { session.load(context, owner: owner, labels: labels) }
    }

    /// Where the records go, like "Standort" on the detail card: the shelf,
    /// and – for the row under the pointer, else the last one added – the
    /// two records it goes between. The count of additions on the right.
    private var targetCard: some View {
        AssignmentCard(title: session.isRackWide ? String(localized: "Noch nicht einsortiert")
                           : rangeLabel.map { String(localized: "Fach „\($0)“") } ?? String(localized: "Dieses Fach"),
                       detail: detail) {
            if session.addedCount > 0 {
                Label(session.isRackWide ? "\(session.addedCount) einsortiert" : "\(session.addedCount) hinzugefügt", systemImage: "checkmark")
                    .font(AppStyle.rowTitle)
                    .foregroundStyle(AppStyle.accent)
                    .contentTransition(.numericText())
                    .fixedSize()
                    .transition(.opacity)
            }
        }
        .animation(AppStyle.standardAnimation, value: session.addedCount)
        .animation(AppStyle.quickAnimation, value: session.hoveredID)
    }

    private var detail: String {
        if let copy = session.hovered {
            let artist = String(localized: "„\(copy.release?.displayArtist ?? "—")“")
            if session.isRackWide {
                guard let spot = session.spot(for: copy) else { return String(localized: "\(artist) – noch steht keine Platte im Regal") }
                return String(localized: "\(artist) in „\(name(spot.shelf))“ \(place(spot))")
            }
            if let other = session.belongsElsewhere[copy.id] { return String(localized: "\(artist) gehört in „\(other)“") }
            if let spot = session.spot(for: copy) { return String(localized: "\(artist) \(place(spot))") }
        }
        if let copy = session.lastAddedHere, let spot = session.placed(copy) {
            let artist = copy.release?.displayArtist ?? "—"
            if session.isRackWide { return String(localized: "Zuletzt „\(artist)“ in „\(name(spot.shelf))“ \(place(spot))") }
            return String(localized: "Zuletzt „\(artist)“ \(place(spot))")
        }
        return String(localized: "Jede Platte kommt an ihre alphabetische Stelle")
    }

    /// "zwischen „Air“ und „Björk“", "vor „Air“", "nach „Zappa“", "als erste Platte".
    private func place(_ spot: AlphabeticalPlacement.Spot) -> String {
        func name(_ copy: RecordCopy) -> String { String(localized: "„\(copy.release?.displayArtist ?? "—")“") }
        switch (spot.before, spot.after) {
        case let (before?, after?): return String(localized: "zwischen \(name(before)) und \(name(after))")
        case let (nil, after?): return String(localized: "ganz vorn, vor \(name(after))")
        case let (before?, nil): return String(localized: "ans Ende, nach \(name(before))")
        case (nil, nil): return String(localized: "als erste Platte")
        }
    }

    /// For a record's row: the compartment it goes to, the position there
    /// and the records it would stand between.
    private func location(for copy: RecordCopy) -> AssignmentLocation? {
        session.place(for: copy).map { spot in
            AssignmentLocation(shelf: labels.prefix(for: spot.shelf) + name(spot.shelf), position: spot.position, neighbours: place(spot))
        }
    }

    /// Just the compartment: the row below names the cabinet too, and the
    /// card has one line.
    private func name(_ shelf: Shelf) -> String { labels[shelf.id] ?? shelf.numberText }

    private var pausedCount: Int {
        guard missingEnabled else { return 0 }
        return session.candidates.filter { session.missing.contains($0.id) }.count
    }
}

/// Where a record without a shelf would stand, as its row tells it.
struct AssignmentLocation {
    /// Cabinet (when there are several) and compartment.
    let shelf: String
    let position: Int
    /// "zwischen „Air“ und „Björk“".
    let neighbours: String
}

/// The candidates, one row each. An added (or marked) record fades out and
/// the rest move up, so the next one lands under the pointer.
private struct ShelfAssignmentGrid: View {
    let items: [RecordCopy]
    let missingEnabled: Bool
    let rackWide: Bool
    let belongsElsewhere: [UUID: String]
    let toggleMissing: (RecordCopy) -> Void
    let hover: (RecordCopy, Bool) -> Void
    /// Where each record would stand (see `ShelfAssignmentSession.place`).
    let location: (RecordCopy) -> AssignmentLocation?
    let add: (RecordCopy) -> Void
    /// The row whose right-click menu is open, and where it was clicked.
    @State private var menuFor: (id: UUID, anchor: UnitPoint)?
    @State private var clicks = GridSecondaryClicks<UUID>()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: CoverGrid.spacing) {
                ForEach(items) { copy in
                    ShelfAssignmentRow(copy: copy, location: location(copy),
                                       elsewhere: !rackWide && belongsElsewhere[copy.id] != nil,
                                       rackWide: rackWide,
                                       hover: { hover(copy, $0) }) { add(copy) }
                        .gridSecondaryClickCell(copy.id, in: clicks)
                        .popover(isPresented: Binding(get: { menuFor?.id == copy.id }, set: { if !$0, menuFor?.id == copy.id { menuFor = nil } }),
                                 attachmentAnchor: .point(menuFor?.anchor ?? .center), arrowEdge: .trailing) {
                            AppMenu(dismiss: { menuFor = nil }) {
                                Button(rackWide ? "Einsortieren" : "Zum Fach hinzufügen") { add(copy) }
                                if missingEnabled {
                                    Button("Auf die Suchliste setzen") { toggleMissing(copy) }
                                }
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .gridSecondaryClickGrid(clicks)
            .padding(.horizontal, AppStyle.pagePadding)
            .padding(.top, AppStyle.rowSpacing)
            .padding(.bottom, AppStyle.pagePadding)
            .animation(AppStyle.layoutAnimation, value: items.map(\.id))
        }
        .onGridSecondaryClick(clicks) { id, point in menuFor = (id, point) }
        .scrollIndicators(.automatic)
    }
}

/// One candidate across the panel: the cover as large as in a compartment's
/// grid, beside it the record's caption and – larger – where it goes:
/// compartment, position and the records it would stand between. A click
/// adds it; a right-click offers the search list.
private struct ShelfAssignmentRow: View {
    let copy: RecordCopy
    /// Where it would stand in the compartment it belongs to.
    let location: AssignmentLocation?
    /// "Platte hinzufügen": belongs in another shelf than the open one.
    let elsewhere: Bool
    let rackWide: Bool
    let hover: (Bool) -> Void
    let add: () -> Void
    @State private var hovering = false

    var body: some View {
        let artist = copy.release?.displayArtist ?? "—"
        let title = copy.release?.displayTitle ?? "—"
        Button(action: add) {
            HStack(alignment: .center, spacing: AppStyle.sectionSpacing) {
                CoverView(url: copy.release?.shownCoverURL, size: AssignmentRowMetrics.largeCoverSize)
                    .atelierRecordSleeve()
                VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                    // The same caption as in the compartment, Collection and Wantlist.
                    RecordCaption(release: copy.release)
                    place
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(AppStyle.itemSpacing)
            .contentShape(Rectangle())
            .appHoverable(hovering, cornerRadius: AppStyle.cardRadius + AppStyle.itemSpacing)
        }
        .buttonStyle(.plain)
        // The hover surface reaches out, so covers stay flush with the card above.
        .padding(-AppStyle.itemSpacing)
        .help(help)
        .accessibilityLabel(rackWide ? String(localized: "\(artist) – \(title) einsortieren") : String(localized: "\(artist) – \(title) ins Fach hinzufügen"))
        .onHover { hovering = $0; hover($0) }
    }

    /// Where it goes, the largest text of the row.
    @ViewBuilder private var place: some View {
        if let location {
            VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
                Text(elsewhere ? String(localized: "Gehört in „\(location.shelf)“") : location.shelf)
                    .font(AppStyle.sectionTitle)
                    .foregroundStyle(elsewhere ? AnyShapeStyle(.secondary) : AnyShapeStyle(AppStyle.accent))
                Text("Position \(location.position) · \(location.neighbours)")
                    .font(.callout).monospacedDigit().foregroundStyle(.secondary)
            }
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Es steht noch keine Platte im Regal, an der sich die Platte ausrichten könnte. Wähle ein Fach und füge sie dort über „+“ hinzu.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var help: String {
        if rackWide {
            return location == nil ? "" : String(localized: "Klick: hier einsortieren. Rechtsklick: weitere Aktionen.")
        }
        if elsewhere { return String(localized: "Klick: trotzdem in dieses Fach hinzufügen. Rechtsklick: weitere Aktionen.") }
        return String(localized: "Klick: an ihrer alphabetischen Stelle ins Fach hinzufügen. Rechtsklick: weitere Aktionen.")
    }
}
