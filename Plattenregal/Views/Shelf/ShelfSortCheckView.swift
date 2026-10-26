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
struct ShelfSortCheckView: View {
    let shelf: Shelf
    let rangeLabel: String?
    /// Closes the panel once the new order is saved: left open, it would
    /// only say "Alles in Ordnung", and the next click on the shelf page
    /// would merely close it instead of reaching a compartment.
    let close: () -> Void
    @Environment(\.modelContext) private var context
    @AppStorage(ShelfSecondaryOrder.key) private var savedOrder = ShelfSecondaryOrder.title
    @State private var order = ShelfSecondaryOrder.current
    /// Steps ticked off at the shelf.
    @State private var done: Set<UUID> = []
    @State private var error: String?

    private var gone: Bool { shelf.isDeleted || shelf.modelContext == nil }

    var body: some View {
        // A sync may be removing records meanwhile: never read a deleted one.
        let copies = gone ? [] : PositionService.inShelfOrder(shelf.copies.filter { !$0.isDeleted && $0.modelContext != nil })
        let steps = ShelfSortCheck.steps(copies, by: order)
        VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
            VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
                Text("Sortierung prüfen").font(AppStyle.dialogTitle)
                Text("\(rangeLabel.map { String(localized: "Fach „\($0)“") } ?? String(localized: "Dieses Fach")) · \(AppStyle.records(copies.count)) · Plätze von links gezählt")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .trailing, spacing: AppStyle.tightSpacing) {
                HStack(spacing: AppStyle.rowSpacing) {
                    Text("Nach Interpret, bei gleichem Interpreten nach").font(.callout).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    GlassSegmentedPicker(selection: $order, options: ShelfSecondaryOrder.allCases, small: true) { Text($0.title) }
                        .accessibilityLabel("Bei gleichem Interpreten nach")
                }
                // Said where it arises instead of next to the button.
                if order != savedOrder && !steps.isEmpty {
                    Text("Übernimmt „\(order.title)“ auch für Platzsuche und Hinzufügen in allen Fächern.")
                        .font(.caption).foregroundStyle(AppStyle.accent)
                        .transition(.opacity)
                }
            }
            if steps.isEmpty {
                inOrder(count: copies.count)
            } else {
                summary(steps)
                ScrollView {
                    VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
                        let current = steps.first { !done.contains($0.id) }?.id
                        ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                            SortStepRow(number: index + 1, step: step, done: done.contains(step.id), current: step.id == current) {
                                if done.contains(step.id) { done.remove(step.id) } else { done.insert(step.id) }
                            }
                        }
                    }
                }
                .frame(maxHeight: 360)
                .fixedSize(horizontal: false, vertical: true)
                footer(steps)
            }
            if let error { AppBanner(message: error, kind: .error).transition(AppStyle.funnelTransition()) }
        }
        .padding(AppStyle.pagePadding)
        .frame(width: 560)
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

    private func inOrder(count: Int) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
            HStack(spacing: AppStyle.rowSpacing) {
                Image(systemName: "checkmark.circle.fill").font(AppStyle.statusSymbol).foregroundStyle(AppStyle.successColor)
                VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
                    Text("Alles in Ordnung").font(.headline)
                    Text(count < 2 ? String(localized: "Zu wenige Platten, um etwas zu prüfen.") : String(localized: "Alle \(count) Platten stehen in der richtigen Reihenfolge."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppStyle.cardPadding)
            .padding(.vertical, AppStyle.rowSpacing)
            .accentGlassCard()
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

    /// What is left to move: count, progress, and once everything is ticked
    /// off "Alles umgestellt" – then the button below turns into the main action.
    private func summary(_ steps: [ShelfSortCheck.Step]) -> some View {
        let finished = steps.filter { done.contains($0.id) }.count
        let complete = finished == steps.count
        return VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
            HStack(spacing: AppStyle.rowSpacing) {
                Image(systemName: complete ? "checkmark.circle.fill" : "arrow.left.arrow.right")
                    .font(AppStyle.statusSymbol)
                    .foregroundStyle(complete ? AppStyle.successColor : AppStyle.accent)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 26)
                Text(complete ? String(localized: "Alles umgestellt")
                     : steps.count == 1 ? String(localized: "1 Platte umstellen") : String(localized: "\(steps.count) Platten umstellen"))
                    .font(.headline)
                Spacer(minLength: AppStyle.itemSpacing)
                Text("\(finished) von \(steps.count)")
                    .font(AppStyle.rowTitle).monospacedDigit()
                    .foregroundStyle(complete ? AppStyle.successColor : AppStyle.accent)
                    .contentTransition(.numericText())
            }
            SortProgressBar(fraction: Double(finished) / Double(max(steps.count, 1)), complete: complete)
        }
        .padding(.horizontal, AppStyle.cardPadding)
        .padding(.vertical, AppStyle.rowSpacing)
        .accentGlassCard()
        .animation(AppStyle.standardAnimation, value: finished)
    }

    /// Only the button: a quiet one while moves are open, the main action
    /// once all are ticked off. Saving early stays possible.
    private func footer(_ steps: [ShelfSortCheck.Step]) -> some View {
        let complete = steps.allSatisfy { done.contains($0.id) }
        return HStack {
            Spacer(minLength: 0)
            if complete {
                PrimaryButton(title: String(localized: "Reihenfolge übernehmen")) { apply() }
            } else {
                SecondaryButton(title: String(localized: "Reihenfolge übernehmen")) { apply() }
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

/// One move: the record with its cover and where it stands now, then where
/// it goes – behind the record shown (or at the very front, before it).
private struct SortStepRow: View {
    let number: Int
    let step: ShelfSortCheck.Step
    let done: Bool
    /// The next open move: framed like every selection (gold in Klassisch).
    let current: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        let release = step.copy.release
        Button(action: toggle) {
            HStack(spacing: AppStyle.rowSpacing) {
                StepNumber(number: number, done: done)
                CoverView(url: release?.shownCoverURL, size: 40)
                VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
                    Text("\(release?.displayArtist ?? "—") – \(release?.displayTitle ?? "—")")
                        .font(AppStyle.rowTitle).lineLimit(1).truncationMode(.middle)
                    // Where it goes is what matters at the shelf: in the text's
                    // own color, only the current place muted.
                    HStack(spacing: AppStyle.tightSpacing) {
                        Text("Platz \(step.position)").monospacedDigit().foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").font(AppStyle.indicatorSymbol).foregroundStyle(.secondary)
                        if let neighbour = step.before ?? step.after {
                            CoverView(url: neighbour.release?.shownCoverURL, size: 16)
                            Text(target(neighbour)).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .font(.caption)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppStyle.itemSpacing).frame(minHeight: AssignmentRowMetrics.height)
            .opacity(done ? 0.45 : 1)
            .contentShape(Rectangle())
            .appHoverable(hovering && !current, cornerRadius: AppStyle.rowRadius)
            .background {
                if current {
                    RoundedRectangle(cornerRadius: AppStyle.rowRadius).fill(AppStyle.selectedBackground)
                        .overlay(RoundedRectangle(cornerRadius: AppStyle.rowRadius).strokeBorder(AppStyle.selectedBorder, lineWidth: AppStyle.selectionLineWidth))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(AppStyle.quickAnimation, value: done)
        .animation(AppStyle.standardAnimation, value: current)
        .help(done ? "Doch noch nicht umgestellt" : "Als umgestellt abhaken")
    }

    /// "hinter **Artist** – Title" (or "ganz vorn, vor …"): the artist in bold.
    private func target(_ neighbour: RecordCopy) -> AttributedString {
        var artist = AttributedString(neighbour.release?.displayArtist ?? "—")
        artist.inlinePresentationIntent = .stronglyEmphasized
        return AttributedString((step.before == nil ? String(localized: "ganz vorn, vor") : String(localized: "hinter")) + " ")
            + artist + AttributedString(" – \(neighbour.release?.displayTitle ?? "—")")
    }
}

/// Thin bar under the count: the accent filling up, green when complete.
private struct SortProgressBar: View {
    let fraction: Double
    let complete: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(AppStyle.borderColor)
                Capsule().fill(complete ? AppStyle.successColor : AppStyle.accent)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 4)
    }
}
