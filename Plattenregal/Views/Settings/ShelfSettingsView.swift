import SwiftUI
import SwiftData

// MARK: - Regal

struct ShelfSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Shelf.number) private var shelves: [Shelf]
    @Query(sort: \Cabinet.sortOrder) private var cabinets: [Cabinet]
    @AppStorage(ShelfLabelStyle.key) private var labelStyle = ShelfLabelStyle.range
    @AppStorage(ShelfSecondaryOrder.key) private var secondaryOrder = ShelfSecondaryOrder.title
    @State private var cabinetID: UUID?
    /// The compartment whose menu is open (a click on its tile).
    @State private var menuID: UUID?
    /// The locked compartment whose name is being edited.
    @State private var namingID: UUID?
    @State private var shelfError: String?
    @State private var adding = false
    @State private var error: String?
    @State private var labels = ShelfLabels()
    @State private var labelsCache = ShelfLabelsCache()
    @State private var changes = LibraryChanges.shared
    @FocusState private var stripFocused: Bool

    private var cabinet: Cabinet? { cabinets.first { $0.id == cabinetID } ?? cabinets.first }

    private func shown(_ id: Binding<UUID?>, _ shelf: UUID) -> Binding<Bool> {
        Binding(get: { id.wrappedValue == shelf }, set: { if !$0, id.wrappedValue == shelf { id.wrappedValue = nil } })
    }

    /// Same entries as the compartment's menu on the shelf page.
    @ViewBuilder private func lockMenu(_ shelf: Shelf) -> some View {
        if shelf.isReserved {
            Button("Namen ändern") { namingID = shelf.id }
            AppMenuDivider()
            Button("Fach entsperren") { setLocked(shelf, false) }
        } else {
            Button("Fach sperren") { setLocked(shelf, true) }
                .disabled(!shelf.copies.isEmpty)
        }
    }

    /// Unlocking drops the name as well.
    private func setLocked(_ shelf: Shelf, _ locked: Bool) {
        // Removed meanwhile (cabinet made smaller, backup restored).
        guard !shelf.isDeleted, shelf.modelContext != nil else { return }
        do {
            try PositionService(context: context).configure(shelf, name: locked ? shelf.name : "", isReserved: locked)
            shelfError = nil
        } catch { shelfError = error.reportedMessage() }
    }

    /// The labels sort every record's artist, so they're only recomputed when
    /// something they depend on changed – not on each click or animation frame.
    private var labelSignature: Int {
        var hasher = Hasher()
        hasher.combine(labelStyle)
        hasher.combine(changes.libraryVersion)
        hasher.combine(changes.shelvesVersion)
        // A swap between two shelves keeps their counts; `ShelfLabelsCache`
        // then reads only those two again.
        hasher.combine(changes.placementsVersion)
        for shelf in shelves { hasher.combine(shelf.id); hasher.combine(shelf.isReserved); hasher.combine(shelf.copies.count) }
        return hasher.finalize()
    }

    var body: some View {
        SettingsPage {
            SettingsCard(title: String(localized: "Regale"),
                         subtitle: String(localized: "Mit ← / → zwischen den Regalen wechseln, mit der Leertaste aktivieren oder deaktivieren.")) {
                cabinetStrip
                if adding {
                    CabinetCreator(suggestedName: CabinetService(context: context).suggestedName(),
                                   cancel: { withAnimation(AppStyle.standardAnimation) { adding = false } },
                                   create: create)
                        .transition(AppStyle.funnelTransition())
                } else if let cabinet {
                    Divider()
                    CabinetEditor(cabinet: cabinet, isOnly: cabinets.count == 1,
                                  isOnlyActive: cabinet.isActive && !cabinets.contains { $0.isActive && $0.id != cabinet.id },
                                  isFirst: cabinet.id == cabinets.first?.id, isLast: cabinet.id == cabinets.last?.id,
                                  report: report, deleted: { cabinetID = nil; menuID = nil; namingID = nil })
                        .id(cabinet.id)
                }
                if let error { AppBanner(message: error, kind: .error).transition(AppStyle.funnelTransition()) }
            }
            .animation(AppStyle.standardAnimation, value: adding)
            .animation(AppStyle.standardAnimation, value: error)

            if let cabinet, !adding {
                let own = cabinet.orderedShelves
                SettingsCard(title: String(localized: "Fächer · \(cabinet.name)"),
                             subtitle: String(localized: "\(cabinet.sizeText) Fächer · \(AppStyle.records(cabinet.recordCount)) eingeräumt\(cabinet.isActive ? "" : String(localized: " · inaktiv"))")) {
                    Grid(horizontalSpacing: AppStyle.itemSpacing, verticalSpacing: AppStyle.itemSpacing) {
                        ForEach(0..<cabinet.rows, id: \.self) { row in
                            GridRow {
                                ForEach(1...cabinet.columns, id: \.self) { column in
                                    if let shelf = own.first(where: { $0.sortOrder == row * cabinet.columns + column }) {
                                        ShelfTile(shelf: shelf, label: labels[shelf.id],
                                                  selected: shelf.id == menuID || shelf.id == namingID) { menuID = shelf.id }
                                            .popover(isPresented: shown($menuID, shelf.id), arrowEdge: .bottom) {
                                                AppMenu(dismiss: { menuID = nil }) { lockMenu(shelf) }
                                            }
                                            .background {
                                                Color.clear.popover(isPresented: shown($namingID, shelf.id), arrowEdge: .bottom) {
                                                    ShelfNamePopover(shelf: shelf)
                                                }
                                            }
                                    }
                                }
                            }
                        }
                    }
                    SettingsNote(String(localized: "Klicke auf ein Fach, um es zu sperren oder zu entsperren – z. B. für Deko oder andere Dinge. Gesperrte Fächer werden beim Einsortieren übersprungen."))
                    if let shelfError { AppBanner(message: shelfError, kind: .error).transition(AppStyle.funnelTransition()) }
                }
            }

            // The two choices that apply to every shelf, in one card below
            // the shelf being edited.
            SettingsCard(title: String(localized: "Sortierung und Beschriftung"),
                         subtitle: String(localized: "Gilt für alle Regale.")) {
                SettingsRow(title: String(localized: "Bei gleichem Interpreten nach"), hint: String(localized: "Immer zuerst nach Interpret. \(secondaryOrder.hint) Gilt für Platzsuche, Hinzufügen, „Sortierung prüfen“ und die alphabetische Collection.")) {
                    GlassSegmentedPicker(selection: $secondaryOrder, options: ShelfSecondaryOrder.allCases) { Text($0.title) }
                        .accessibilityLabel("Bei gleichem Interpreten nach")
                }
                Divider()
                SettingsRow(title: String(localized: "Fächer benennen nach"), hint: labelStyle == .range
                            ? String(localized: "Erste und letzte Buchstaben der Interpreten im Fach, \(labelStyle.example). So heißen die Fächer auf der Regalseite, in Listen und im Export.")
                            : String(localized: "Platz im Regal von links oben, \(labelStyle.example). So heißen die Fächer auf der Regalseite, in Listen und im Export.")) {
                    GlassSegmentedPicker(selection: $labelStyle, options: ShelfLabelStyle.allCases) { Text($0.title) }
                        .accessibilityLabel("Beschriftung")
                }
            }
        }
        .onChange(of: cabinetID) { menuID = nil; namingID = nil; error = nil; shelfError = nil }
        // Changes where records go: worth a line in the protocol.
        .onChange(of: secondaryOrder) { old, new in
            AppLog.info("Einstellungen", "Bei gleichem Interpreten jetzt nach \(new.title) statt \(old.title)")
        }
        .animation(AppStyle.standardAnimation, value: shelfError)
        .task(id: labelSignature) { labels = labelsCache.labels(for: shelves, style: labelStyle) }
    }

    /// The cabinets side by side; arrow keys walk through them, space
    /// switches the selected one on or off.
    private var cabinetStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppStyle.itemSpacing) {
                    ForEach(cabinets) { item in
                        CabinetChip(cabinet: item, selected: !adding && item.id == cabinet?.id, focused: stripFocused) {
                            select(item)
                        }
                        .id(item.id)
                    }
                    Button { withAnimation(AppStyle.standardAnimation) { adding = true }; error = nil } label: {
                        Label("Regal hinzufügen", systemImage: "plus")
                            .padding(.horizontal, AppStyle.rowSpacing)
                            .frame(minHeight: 52)
                            .background(Color.primary.opacity(adding ? 0.08 : 0.03), in: RoundedRectangle(cornerRadius: AppStyle.rowRadius))
                            .overlay(RoundedRectangle(cornerRadius: AppStyle.rowRadius).strokeBorder(AppStyle.borderColor, style: StrokeStyle(lineWidth: AppStyle.borderWidth, dash: [4, 3])))
                            .contentShape(RoundedRectangle(cornerRadius: AppStyle.rowRadius))
                    }
                    .buttonStyle(.plain)
                }
                .padding(AppStyle.hairSpacing)
            }
            .focusable()
            .focused($stripFocused)
            .focusEffectDisabled()
            .onKeyPress(.leftArrow) { step(-1, proxy); return .handled }
            .onKeyPress(.rightArrow) { step(1, proxy); return .handled }
            .onKeyPress(.space) { toggleActive(); return .handled }
        }
        .onAppear { stripFocused = true }
    }

    private func select(_ item: Cabinet) {
        adding = false
        withAnimation(AppStyle.quickAnimation) { cabinetID = item.id }
        stripFocused = true
    }

    private func step(_ offset: Int, _ proxy: ScrollViewProxy) {
        guard !cabinets.isEmpty else { return }
        let index = cabinets.firstIndex { $0.id == cabinet?.id } ?? 0
        let next = cabinets[min(max(index + offset, 0), cabinets.count - 1)]
        select(next)
        withAnimation(AppStyle.quickAnimation) { proxy.scrollTo(next.id) }
    }

    private func toggleActive() {
        guard let cabinet, !adding else { return }
        report { try CabinetService(context: context).setActive(cabinet, !cabinet.isActive) }
    }

    private func create(name: String, columns: Int, rows: Int) {
        report {
            let new = try CabinetService(context: context).add(name: name, columns: columns, rows: rows)
            withAnimation(AppStyle.standardAnimation) { adding = false }
            cabinetID = new.id
        }
    }

    private func report(_ action: () throws -> Void) {
        do { try action(); error = nil } catch { self.error = error.reportedMessage() }
    }
}

/// One cabinet in the strip: name, KALLAX size and how full it is.
private struct CabinetChip: View {
    let cabinet: Cabinet
    let selected: Bool
    let focused: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
                HStack(spacing: AppStyle.tightSpacing) {
                    Circle().fill(cabinet.isActive ? AppStyle.successColor : Color.secondary.opacity(0.5))
                        .frame(width: 7, height: 7)
                    Text(cabinet.name).font(AppStyle.strongCallout).lineLimit(1)
                }
                Text("\(cabinet.sizeText) · \(AppStyle.records(cabinet.recordCount))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
            .foregroundStyle(cabinet.isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, AppStyle.rowSpacing).padding(.vertical, AppStyle.itemSpacing)
            .frame(minWidth: 120, maxWidth: 240, minHeight: 52, alignment: .leading)
            .background(selected ? AppStyle.selectedBackground : (hovering ? AppStyle.hoverBackground : Color.primary.opacity(0.03)),
                        in: RoundedRectangle(cornerRadius: AppStyle.rowRadius))
            .overlay(RoundedRectangle(cornerRadius: AppStyle.rowRadius)
                .strokeBorder(selected ? AppStyle.selectedBorder.opacity(focused ? 0.8 : 0.35) : AppStyle.borderColor,
                              lineWidth: selected && focused ? AppStyle.selectionLineWidth : AppStyle.borderWidth))
            .contentShape(RoundedRectangle(cornerRadius: AppStyle.rowRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(AppStyle.quickAnimation, value: hovering)
        .help(cabinet.isActive ? String(localized: "Aktiv – Leertaste deaktiviert es") : String(localized: "Inaktiv – Leertaste aktiviert es"))
        .accessibilityLabel("\(cabinet.name), \(cabinet.sizeText), \(cabinet.isActive ? String(localized: "aktiv") : String(localized: "inaktiv"))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// One compartment in the settings' shelf map.
private struct ShelfTile: View {
    let shelf: Shelf
    let label: String?
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
                HStack(spacing: AppStyle.tightSpacing) {
                    if shelf.isReserved { Image(systemName: "lock.fill").font(.caption2) }
                    Text(title).font(AppStyle.strongCallout).lineLimit(1)
                }
                Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
            .foregroundStyle(shelf.isReserved ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .padding(.horizontal, AppStyle.rowSpacing).padding(.vertical, AppStyle.itemSpacing)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
            .background(selected ? AppStyle.selectedBackground : (hovering ? AppStyle.hoverBackground : Color.primary.opacity(0.03)),
                        in: RoundedRectangle(cornerRadius: AppStyle.rowRadius))
            .overlay(RoundedRectangle(cornerRadius: AppStyle.rowRadius)
                .strokeBorder(selected ? AppStyle.selectedBorder.opacity(0.35) : AppStyle.borderColor))
            .contentShape(RoundedRectangle(cornerRadius: AppStyle.rowRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(AppStyle.quickAnimation, value: hovering)
        .help(shelf.numberText)
        .accessibilityLabel("\(shelf.numberText): \(title), \(detail)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var title: String {
        if shelf.isReserved { return shelf.name.isEmpty ? shelf.numberText : shelf.name }
        return label ?? shelf.numberText
    }
    private var detail: String {
        shelf.isReserved ? String(localized: "Gesperrt") : shelf.copies.isEmpty ? String(localized: "Leer") : AppStyle.records(shelf.copies.count)
    }
}
