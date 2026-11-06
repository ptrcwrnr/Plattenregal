import SwiftUI
import SwiftData

/// One opening of "Sortierung prüfen" for a compartment.
struct ShelfSortCheckRequest: Identifiable {
    let id = UUID()
    let shelf: Shelf
}

/// "Sortierung prüfen" from a compartment's menu: checks its stored order
/// and, where records are out of place, lists the moves at the shelf one by
/// one – each only refers to records that already stand right. Once they
/// are done, "Reihenfolge übernehmen" stores the new order.
///
/// Laid out for the shelf in front of you: a quiet head with the order as a
/// menu, the compartment as a strip from left to right with the records to
/// move, then the moves themselves – where to take a record out, where it
/// goes – and the buttons at the foot, as on the placement card.
struct ShelfSortCheckView: View {
    let shelf: Shelf
    let rangeLabel: String?
    /// Closes the panel once the new order is saved: left open, it would
    /// only say "Alles in Ordnung", and the next click on the shelf page
    /// would merely close it instead of reaching a compartment. Also
    /// "Schließen" and "Fertig".
    let close: () -> Void
    @Environment(\.modelContext) private var context
    @AppStorage(ShelfSecondaryOrder.key) private var savedOrder = ShelfSecondaryOrder.title
    @State private var order = ShelfSecondaryOrder.current
    /// Steps ticked off at the shelf.
    @State private var done: Set<UUID> = []
    @State private var error: String?

    /// The panel's width: a move's target ("hinter Artist – Title") on one line.
    private static let width: CGFloat = 560
    /// The list of moves scrolls beyond this; the head and foot stay.
    private static let listMaxHeight: CGFloat = 360

    private var gone: Bool { shelf.isDeleted || shelf.modelContext == nil }

    var body: some View {
        // A sync may be removing records meanwhile: never read a deleted one.
        let copies = gone ? [] : PositionService.inShelfOrder(shelf.copies.filter { !$0.isDeleted && $0.modelContext != nil })
        let steps = ShelfSortCheck.steps(copies, by: order)
        VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
            // Nothing to move: the order only matters once another was chosen
            // (to go back or keep it), so the menu stays then.
            header(count: copies.count, unsorted: !steps.isEmpty, showsOrder: !steps.isEmpty || order != savedOrder)
            if steps.isEmpty {
                inOrder(count: copies.count)
            } else {
                moves(steps, in: copies)
            }
            if let error { AppBanner(message: error, kind: .error).transition(AppStyle.funnelTransition()) }
            footer(steps)
        }
        .padding(AppStyle.pagePadding)
        .frame(width: Self.width)
        .animation(AppStyle.standardAnimation, value: order)
        .animation(AppStyle.standardAnimation, value: error)
        // Another order is another list of moves.
        .onChange(of: order) { done = []; logCheck() }
        .onAppear {
            logCheck()
            #if DEBUG
            // Screenshots: --preview-sortcheck-done=N ticks off the first N moves.
            if let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--preview-sortcheck-done=") }),
               let count = Int(raw.dropFirst("--preview-sortcheck-done=".count)) {
                done = Set(steps.prefix(count).map(\.id))
            }
            #endif
        }
    }

    /// Title and compartment; the order for one artist's records as a menu
    /// beside them – set once, rarely changed, so it no longer takes a row
    /// of its own above the result.
    private func header(count: Int, unsorted: Bool, showsOrder: Bool) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.tightSpacing) {
            HStack(alignment: .top, spacing: AppStyle.rowSpacing) {
                VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
                    Text("Sortierung prüfen").font(AppStyle.dialogTitle)
                    Text("\(rangeLabel.map { String(localized: "Fach „\($0)“") } ?? String(localized: "Dieses Fach")) · \(AppStyle.records(count))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: AppStyle.itemSpacing)
                if showsOrder {
                    GlassMenuPicker(title: String(localized: "Bei gleichem Interpreten nach"), selection: $order,
                                    current: Self.orderTitle(order)) {
                        ForEach(ShelfSecondaryOrder.allCases) { Text(Self.orderTitle($0)).tag($0) }
                    }
                    .help("Immer nach Interpret; bei gleichem Interpreten nach Titel, Jahr oder Label")
                    .transition(.opacity)
                }
            }
            // Said where it arises instead of next to the button.
            if order != savedOrder && unsorted {
                Text("Übernimmt „\(order.title)“ auch für Platzsuche und Hinzufügen in allen Fächern.")
                    .font(.caption).foregroundStyle(AppStyle.accent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.opacity)
            }
        }
    }

    /// "Interpret, dann Titel": the whole order in the menu's few words.
    private static func orderTitle(_ order: ShelfSecondaryOrder) -> String {
        String(localized: "Interpret, dann \(order.title)")
    }

    /// Nothing to move: the strip of the compartment with the check in its
    /// middle – the same strip that marks the moves otherwise. Too few
    /// records for a check: one sentence. With another order chosen, the
    /// offer to keep it.
    private func inOrder(count: Int) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
            if count < 2 {
                Text("Zu wenige Platten, um etwas zu prüfen.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ShelfOrderStrip(count: count, marks: [], inOrder: true)
            }
            if order != savedOrder {
                HStack(spacing: AppStyle.rowSpacing) {
                    Text("Beim Einsortieren gilt bisher „\(savedOrder.title)“.").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    SecondaryButton(title: String(localized: "„\(order.title)“ übernehmen")) {
                        AppLog.info("Regal", "Bei gleichem Interpreten jetzt nach \(order.title) statt \(savedOrder.title) (aus „Sortierung prüfen“)")
                        savedOrder = order
                    }
                }
            }
        }
    }

    /// The strip of the compartment and the list of moves – the numbers and
    /// ticks of the list say what is left, no count above it.
    private func moves(_ steps: [ShelfSortCheck.Step], in copies: [RecordCopy]) -> some View {
        let current = steps.first { !done.contains($0.id) }?.id
        return VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
            ShelfOrderStrip(count: copies.count, marks: ShelfOrderStrip.marks(for: steps, in: copies, done: done, current: current))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Divider()
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                        SortStepRow(number: index + 1, step: step, done: done.contains(step.id), current: step.id == current) {
                            if done.contains(step.id) { done.remove(step.id) } else { done.insert(step.id) }
                        }
                        Divider()
                    }
                }
            }
            .frame(maxHeight: Self.listMaxHeight)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// As on the placement card: a way out, and the action – quiet while
    /// moves are open, the main one once all are ticked off (saving early
    /// stays possible). Nothing to move: only "Fertig".
    private func footer(_ steps: [ShelfSortCheck.Step]) -> some View {
        let complete = steps.allSatisfy { done.contains($0.id) }
        return HStack(spacing: AppStyle.itemSpacing) {
            Spacer(minLength: 0)
            if steps.isEmpty {
                PrimaryButton(title: String(localized: "Fertig"), action: close)
                    .keyboardShortcut(.defaultAction)
            } else {
                SecondaryButton(title: String(localized: "Schließen"), action: close)
                if complete {
                    PrimaryButton(title: String(localized: "Reihenfolge übernehmen")) { apply() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    SecondaryButton(title: String(localized: "Reihenfolge übernehmen")) { apply() }
                }
            }
        }
        .animation(AppStyle.standardAnimation, value: complete)
    }

    /// For the protocol: which compartment was checked, by what, and the result.
    private func logCheck() {
        guard !gone else { return }
        let copies = PositionService.inShelfOrder(shelf.copies.filter { !$0.isDeleted && $0.modelContext != nil })
        let count = ShelfSortCheck.steps(copies, by: order).count
        AppLog.info("Regal", "Sortierung geprüft: \(PositionService.name(shelf)), Interpret, dann \(order.title) – "
                    + (count == 0 ? String(localized: "alles in Ordnung") : String(localized: "\(count) von \(copies.count) Platten umzustellen")))
    }

    private func apply() {
        guard !gone else { return }
        do {
            try PositionService(context: context).sortAlphabetically(shelf, by: order)
            if savedOrder != order {
                AppLog.info("Regal", "Bei gleichem Interpreten jetzt nach \(order.title) statt \(savedOrder.title) (aus „Sortierung prüfen“)")
            }
            savedOrder = order
            done = []
            error = nil
            close()
        } catch { self.error = error.reportedMessage() }
    }
}

/// One move: the record with its cover, then what to do at the shelf –
/// take it out at its place, put it behind the record shown (or at the very
/// front, before it). The next open move carries "Als Nächstes" like the
/// next record in "Noch nicht einsortiert"; a click ticks a move off.
private struct SortStepRow: View {
    let number: Int
    let step: ShelfSortCheck.Step
    let done: Bool
    /// The next open move.
    let current: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        let release = step.copy.release
        Button(action: toggle) {
            HStack(spacing: AppStyle.rowSpacing) {
                StepNumber(number: number, done: done, prominent: current)
                CoverView(url: release?.shownCoverURL, size: 40)
                VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
                    Text("\(release?.displayArtist ?? "—") – \(release?.displayTitle ?? "—")")
                        .font(AppStyle.rowTitle).lineLimit(1).truncationMode(.middle)
                    // What matters at the shelf, in the text's own color;
                    // only where it stands now is muted.
                    HStack(spacing: AppStyle.tightSpacing) {
                        Text("Platz \(step.position) herausnehmen").monospacedDigit().foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").font(AppStyle.indicatorSymbol).foregroundStyle(.secondary)
                        if let neighbour = step.before ?? step.after {
                            // Cut at the end: the artist in bold is what you look for.
                            Text(target(neighbour)).lineLimit(1).truncationMode(.tail)
                        }
                    }
                    .font(.callout)
                }
                Spacer(minLength: 0)
                if current { StatusTag(text: String(localized: "Als Nächstes"), color: AppStyle.accent) }
            }
            .padding(.horizontal, AppStyle.itemSpacing)
            .padding(.vertical, AppStyle.itemSpacing)
            .frame(minHeight: AssignmentRowMetrics.height)
            .opacity(done ? 0.45 : 1)
            .contentShape(Rectangle())
            .appHoverable(hovering, cornerRadius: AppStyle.rowRadius)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(AppStyle.quickAnimation, value: done)
        .animation(AppStyle.standardAnimation, value: current)
        .help(done ? "Doch noch nicht umgestellt" : "Als umgestellt abhaken")
        .accessibilityAddTraits(done ? .isSelected : [])
    }

    /// "hinter **Artist** – Title" (or "ganz vorn, vor …"): the artist in bold.
    private func target(_ neighbour: RecordCopy) -> AttributedString {
        var artist = AttributedString(neighbour.release?.displayArtist ?? "—")
        artist.inlinePresentationIntent = .stronglyEmphasized
        return AttributedString((step.before == nil ? String(localized: "ganz vorn, vor") : String(localized: "hinter")) + " ")
            + artist + AttributedString(" – \(neighbour.release?.displayTitle ?? "—")")
    }
}

/// The compartment from left to right, one tick per place, as you stand in
/// front of it: where the records to move stand now, and for the next move
/// also where it goes – joined by an arc. Moves ticked off show at their
/// new place. Gives the rough direction at the shelf ("far right") before
/// the exact place in the list. All in order (`inOrder`): the check in the
/// middle instead of marks. As tall as a row of the moves below.
private struct ShelfOrderStrip: View {
    /// One record to move: its place now (0-based) and the gap it goes into
    /// (0 = before the first record, `count` = behind the last one).
    struct Mark: Equatable {
        let from: Int
        let gap: Int
        let done: Bool
        let current: Bool
    }

    let count: Int
    let marks: [Mark]
    var inOrder = false

    // Drawn geometry of the strip itself.
    private static let inset: CGFloat = 6
    /// Room above the marks for the arc of the next move.
    private static let arcRoom: CGFloat = 14
    private static let tickHeight: CGFloat = 8
    /// Below this width per place the ticks would merge into a gray band.
    private static let minimumTickSpacing: CGFloat = 3

    /// Places from the current order: `copies` as they stand, the moves in
    /// the order of their target places (`ShelfSortCheck.steps`).
    static func marks(for steps: [ShelfSortCheck.Step], in copies: [RecordCopy], done: Set<UUID>, current: UUID?) -> [Mark] {
        let index = Dictionary(copies.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        return steps.compactMap { step in
            guard let from = index[step.copy.id] else { return nil }
            let gap = step.before.flatMap { index[$0.id] }.map { $0 + 1 } ?? step.after.flatMap { index[$0.id] } ?? 0
            return Mark(from: from, gap: gap, done: done.contains(step.id), current: step.id == current)
        }
    }

    var body: some View {
        Canvas { context, size in draw(in: &context, size: size) }
            .frame(height: AssignmentRowMetrics.height)
            .overlay {
                if inOrder {
                    Image(systemName: "checkmark.circle.fill")
                        .font(AppStyle.statusSymbol)
                        .foregroundStyle(AppStyle.successColor)
                        // Lifted off the ticks behind it.
                        .background(Circle().fill(.background).padding(-AppStyle.hairSpacing))
                }
            }
            .background(RoundedRectangle(cornerRadius: AppStyle.rowRadius).fill(AppStyle.hoverBackground))
            .overlay(RoundedRectangle(cornerRadius: AppStyle.rowRadius).strokeBorder(AppStyle.borderColor, lineWidth: AppStyle.borderWidth))
            .animation(AppStyle.standardAnimation, value: marks)
            // The list below says the same in words.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(inOrder
                ? String(localized: "Alle \(count) Platten stehen in der richtigen Reihenfolge.")
                : String(localized: "Fach mit \(count) Plätzen von links nach rechts, \(marks.filter { !$0.done }.count) Platten zum Umstellen markiert"))
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        guard count > 0 else { return }
        let width = size.width - 2 * Self.inset
        let slot = width / CGFloat(count)
        let top = Self.inset + Self.arcRoom, bottom = size.height - Self.inset
        func center(_ place: Int) -> CGFloat { Self.inset + (CGFloat(place) + 0.5) * slot }
        func edge(_ gap: Int) -> CGFloat { Self.inset + CGFloat(min(max(gap, 0), count)) * slot }
        func bar(at x: CGFloat, width barWidth: CGFloat, from y: CGFloat = top) -> Path {
            Path(roundedRect: CGRect(x: x - barWidth / 2, y: y, width: barWidth, height: bottom - y), cornerRadius: barWidth / 2)
        }
        let markWidth = min(max(slot - 1, 2), 4)

        // Every place a short tick at the foot, while they stay apart.
        if slot >= Self.minimumTickSpacing {
            var ticks = Path()
            for place in 1..<count {
                let x = edge(place)
                ticks.move(to: CGPoint(x: x, y: bottom - Self.tickHeight))
                ticks.addLine(to: CGPoint(x: x, y: bottom))
            }
            context.stroke(ticks, with: .color(AppStyle.borderColor), lineWidth: AppStyle.hairlineWidth * 2)
        }
        // Open moves where they stand, quiet; done ones at their new place.
        for mark in marks where !mark.current {
            if mark.done {
                context.fill(bar(at: edge(mark.gap), width: 2), with: .color(AppStyle.successColor))
            } else {
                context.fill(bar(at: center(mark.from), width: markWidth), with: .style(.secondary.opacity(0.6)))
            }
        }
        // The next move: where it stands, where it goes and the arc between.
        if let mark = marks.first(where: \.current) {
            let from = center(mark.from), to = edge(mark.gap)
            var arc = Path()
            arc.move(to: CGPoint(x: from, y: top))
            arc.addQuadCurve(to: CGPoint(x: to, y: top), control: CGPoint(x: (from + to) / 2, y: Self.inset - Self.arcRoom / 2))
            context.stroke(arc, with: .color(AppStyle.accent), style: StrokeStyle(lineWidth: AppStyle.selectionLineWidth, lineCap: .round))
            context.fill(bar(at: to, width: 2), with: .color(AppStyle.accent.opacity(0.6)))
            context.fill(bar(at: from, width: max(markWidth, 3)), with: .color(AppStyle.accent))
        }
    }
}
