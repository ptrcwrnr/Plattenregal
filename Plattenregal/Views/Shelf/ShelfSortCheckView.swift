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
    /// "Schließen".
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
    /// stays possible). Nothing to move: only "Schließen".
    private func footer(_ steps: [ShelfSortCheck.Step]) -> some View {
        let complete = steps.allSatisfy { done.contains($0.id) }
        return HStack(spacing: AppStyle.itemSpacing) {
            Spacer(minLength: 0)
            // "Schließen" in both states, the same button; with nothing to
            // move ↩ closes too.
            if steps.isEmpty {
                SecondaryButton(title: String(localized: "Schließen"), action: close)
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
/// front, before it). The next open move shows by its number in the accent
/// (and by the arc in the strip above), without a tag of its own; a click
/// ticks a move off.
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
            }
            .padding(.horizontal, AppStyle.itemSpacing)
            .padding(.vertical, AppStyle.itemSpacing)
            .frame(minHeight: AssignmentRowMetrics.height)
            .opacity(done ? AppStyle.dimmedOpacity : 1)
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
/// also where it goes – the two light up one after the other, from here to
/// there (`MoveGlow`). Moves ticked off show at their new place. Gives the
/// rough direction at the shelf ("far right") before the exact place in the
/// list. All in order (`inOrder`): the check in the middle instead of marks.
/// As tall as a row of the moves below.
private struct ShelfOrderStrip: View {
    /// One record to move: its place now (0-based) and the gap it goes into
    /// (0 = before the first record, `count` = behind the last one).
    struct Mark: Hashable {
        let from: Int
        let gap: Int
        let done: Bool
        let current: Bool
    }

    let count: Int
    let marks: [Mark]
    var inOrder = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The next move rests while the window is in the background …
    @Environment(\.appearsActive) private var appearsActive
    /// … or the shelf page behind another one (see `PageStack`).
    @Environment(\.pageVisibility) private var visibility

    // Drawn geometry of the strip itself.
    fileprivate static let inset: CGFloat = 6
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
                // Layers of their own that light up without redrawing the
                // strip. A new move is a new view, so it starts again at
                // the record's place.
                if count > 0, let mark = marks.first(where: \.current) {
                    MoveGlow(count: count, mark: mark,
                             running: !reduceMotion && appearsActive && (visibility?.isShown ?? true))
                        .id(mark)
                        .allowsHitTesting(false)
                }
            }
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
            // The list below says the same in words.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(inOrder
                ? String(localized: "Alle \(count) Platten stehen in der richtigen Reihenfolge.")
                : String(localized: "Fach mit \(count) Plätzen von links nach rechts, \(marks.filter { !$0.done }.count) Platten zum Umstellen markiert"))
    }

    /// Where places, gaps and marks lie across the strip, for the marks here
    /// and the next move on its own layer alike.
    fileprivate struct Layout {
        let count: Int
        let size: CGSize
        var slot: CGFloat { (size.width - 2 * ShelfOrderStrip.inset) / CGFloat(count) }
        var top: CGFloat { ShelfOrderStrip.inset }
        var bottom: CGFloat { size.height - ShelfOrderStrip.inset }
        /// A record's mark: as wide as its place allows, 2 to 4 points.
        var markWidth: CGFloat { min(max(slot - 1, 2), 4) }
        func center(_ place: Int) -> CGFloat { ShelfOrderStrip.inset + (CGFloat(place) + 0.5) * slot }
        func edge(_ gap: Int) -> CGFloat { ShelfOrderStrip.inset + CGFloat(min(max(gap, 0), count)) * slot }

        /// A mark from top to bottom, rounded at both ends (radius: half its width).
        func barFrame(at x: CGFloat, width: CGFloat) -> CGRect {
            CGRect(x: x - width / 2, y: top, width: width, height: bottom - top)
        }
        func bar(at x: CGFloat, width: CGFloat) -> Path {
            Path(roundedRect: barFrame(at: x, width: width), cornerRadius: width / 2)
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        guard count > 0 else { return }
        let layout = Layout(count: count, size: size)
        let bottom = layout.bottom

        // Every place a short tick at the foot, while they stay apart.
        if layout.slot >= Self.minimumTickSpacing {
            var ticks = Path()
            for place in 1..<count {
                let x = layout.edge(place)
                ticks.move(to: CGPoint(x: x, y: bottom - Self.tickHeight))
                ticks.addLine(to: CGPoint(x: x, y: bottom))
            }
            context.stroke(ticks, with: .color(AppStyle.borderColor), lineWidth: AppStyle.hairlineWidth * 2)
        }
        // Open moves where they stand, quiet; done ones at their new place.
        // The next move is `MoveGlow`'s.
        for mark in marks where !mark.current {
            if mark.done {
                context.fill(layout.bar(at: layout.edge(mark.gap), width: 2), with: .color(AppStyle.successColor))
            } else {
                context.fill(layout.bar(at: layout.center(mark.from), width: layout.markWidth), with: .style(.secondary.opacity(0.6)))
            }
        }
    }
}

/// The next move: where the record stands, in the accent, and where it
/// goes, a little paler. While running, both rest at that paler step and
/// light up one after the other in the full accent – the record's place,
/// then its new place – then rest before the next time (`SortMoveGlow`).
/// Stopped – "Bewegung reduzieren", the window in the background, the page
/// behind another one – both stand still as described first.
///
/// Two Core Animation layers rather than SwiftUI: each run is handed to the
/// system as one animation and plays without the app. Drawn by SwiftUI
/// frame by frame, every frame went through the view graph and laid out the
/// whole window – about a quarter of a core for two marks. Still, every
/// frame of it makes the window server compose the window anew, so a run
/// asks for 30 frames a second only, and in the rest between two runs no
/// animation is attached at all: nothing to compose.
private struct MoveGlow: NSViewRepresentable {
    let count: Int
    let mark: ShelfOrderStrip.Mark
    let running: Bool

    /// A mark of the next move at rest: the new place always, the record's
    /// own while it waits to light up.
    fileprivate static let restOpacity: Double = 0.6

    func makeNSView(context: Context) -> GlowView { GlowView() }

    static func dismantleNSView(_ view: GlowView, coordinator: ()) { view.update(running: false) }

    func updateNSView(_ view: GlowView, context: Context) {
        // Resolved here: the accent of the design, in the mode shown.
        view.update(count: count, mark: mark, color: AppStyle.accent.resolve(in: context.environment).cgColor, running: running)
    }

    final class GlowView: NSView {
        private let source = CALayer()
        private let target = CALayer()
        private var count = 0
        private var mark: ShelfOrderStrip.Mark?
        private var running = false
        /// Starts a run, rests, starts the next – while running.
        private var runs: Task<Void, Never>?
        private static let key = "glow"
        /// A fade needs no more, though the display may run at 120.
        private static let frameRate = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)

        override var isFlipped: Bool { true }

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            layer?.addSublayer(target)
            layer?.addSublayer(source)
            // Still: the record's place in the full accent, the new one paler.
            source.opacity = 1
            target.opacity = Float(MoveGlow.restOpacity)
            setAccessibilityElement(false)
        }

        required init?(coder: NSCoder) { nil }

        // Only shows; clicks go to what lies beneath.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func update(count: Int, mark: ShelfOrderStrip.Mark, color: CGColor, running: Bool) {
            if source.backgroundColor != color {
                withoutActions {
                    source.backgroundColor = color
                    target.backgroundColor = color
                }
            }
            if count != self.count || mark != self.mark {
                self.count = count
                self.mark = mark
                needsLayout = true
            }
            update(running: running)
        }

        func update(running: Bool) {
            guard running != self.running else { return }
            self.running = running
            if running { start() } else { stop() }
        }

        override func layout() {
            super.layout()
            guard count > 0, let mark else { return }
            let layout = ShelfOrderStrip.Layout(count: count, size: bounds.size)
            withoutActions {
                place(source, at: layout.center(mark.from), width: max(layout.markWidth, 3), in: layout)
                place(target, at: layout.edge(mark.gap), width: 2, in: layout)
            }
        }

        private func place(_ bar: CALayer, at x: CGFloat, width: CGFloat, in layout: ShelfOrderStrip.Layout) {
            bar.frame = layout.barFrame(at: x, width: width)
            bar.cornerRadius = width / 2
        }

        /// From the record's place, now; the next run a cycle later, from the
        /// same start, so the rhythm doesn't drift.
        private func start() {
            let frames = SortMoveGlow.keyframes()
            func animation(_ strength: (SortMoveGlow.Glow) -> Double) -> CAKeyframeAnimation {
                let animation = CAKeyframeAnimation(keyPath: "opacity")
                animation.values = frames.map { MoveGlow.restOpacity + (1 - MoveGlow.restOpacity) * strength($0.glow) }
                animation.keyTimes = frames.map { NSNumber(value: $0.time) }
                animation.duration = AppStyle.pulseRunDuration
                animation.preferredFrameRateRange = Self.frameRate
                return animation
            }
            let sourceRun = animation(\.source), targetRun = animation(\.target)
            // Running, the record's place rests paler too, between the runs
            // (where no animation holds it) as well.
            withoutActions { source.opacity = Float(MoveGlow.restOpacity) }
            let cycle = Duration.seconds(AppStyle.pulseRunDuration + AppStyle.pulseRestDuration)
            let clock = ContinuousClock()
            var next = clock.now
            runs?.cancel()
            runs = Task { [weak self] in
                while !Task.isCancelled {
                    // Held only for this call, not through the rest; gone, it ends.
                    guard self?.lightUp(sourceRun, targetRun) != nil else { return }
                    next += cycle
                    try? await Task.sleep(until: next, tolerance: .milliseconds(20), clock: clock)
                }
            }
        }

        /// Both in one go, so they stay in step.
        private func lightUp(_ sourceRun: CAAnimation, _ targetRun: CAAnimation) {
            source.add(sourceRun, forKey: Self.key)
            target.add(targetRun, forKey: Self.key)
        }

        private func stop() {
            runs?.cancel()
            runs = nil
            source.removeAnimation(forKey: Self.key)
            target.removeAnimation(forKey: Self.key)
            withoutActions { source.opacity = 1 }
        }

        private func withoutActions(_ change: () -> Void) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            change()
            CATransaction.commit()
        }
    }
}

/// The timing of the next move lighting up, apart from drawing so it can
/// be tested: within each run (`AppStyle.pulseRunDuration`) first the
/// record's place, then – overlapping, so it reads as one movement – its
/// new place, each rising and falling on `AppStyle.pulseCurve`. The rest
/// between two runs is `MoveGlow`'s.
enum SortMoveGlow {
    /// How strongly the record's place (`source`) and its new place
    /// (`target`) light up, from 0 (at rest) to 1.
    struct Glow: Equatable {
        var source: Double
        var target: Double
        static let none = Glow(source: 0, target: 0)
    }

    /// The part of a run in which each of the two lights up.
    private static let sourceWindow = 0.0...0.6
    private static let targetWindow = 0.4...1.0

    /// The glow at `progress` through a run, from 0 (its start) to 1 (its
    /// end); dark at both ends and outside.
    static func glow(at progress: Double) -> Glow {
        guard progress.isFinite else { return .none }
        return Glow(source: bump(progress, in: sourceWindow), target: bump(progress, in: targetWindow))
    }

    /// The glow over one run, for an animation of it: `time` from 0 to 1
    /// across the run, closely spaced (so the curve stays smooth), the last
    /// at its end, where both rest again. A multiple of 10 steps puts the
    /// start, middle and end of both parts exactly on a frame, so each
    /// reaches its full brightness.
    static func keyframes(steps: Int = 60) -> [(time: Double, glow: Glow)] {
        guard steps > 0 else { return [(0, .none), (1, .none)] }
        return (0...steps).map { step in
            let time = Double(step) / Double(steps)
            return (time, glow(at: time))
        }
    }

    /// 0 outside `window`, rising to 1 in its middle and back to 0.
    private static func bump(_ fraction: Double, in window: ClosedRange<Double>) -> Double {
        let x = (fraction - window.lowerBound) / (window.upperBound - window.lowerBound)
        guard x > 0, x < 1 else { return 0 }
        return AppStyle.pulseCurve.value(at: 1 - abs(2 * x - 1))
    }
}
