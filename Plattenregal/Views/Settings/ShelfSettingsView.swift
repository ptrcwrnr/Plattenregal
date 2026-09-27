import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Regal

struct ShelfSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Shelf.number) private var shelves: [Shelf]
    @Query(sort: \Cabinet.sortOrder) private var cabinets: [Cabinet]
    @AppStorage(ShelfLabelStyle.key) private var labelStyle = ShelfLabelStyle.range
    @State private var cabinetID: UUID?
    /// The compartment whose menu is open (a click on its tile).
    @State private var menuID: UUID?
    /// The locked compartment whose name is being edited.
    @State private var namingID: UUID?
    @State private var shelfError: String?
    @State private var adding = false
    @State private var error: String?
    @State private var labels = ShelfLabels()
    @State private var changes = LibraryChanges.shared
    @FocusState private var stripFocused: Bool

    private var cabinet: Cabinet? { cabinets.first { $0.id == cabinetID } ?? cabinets.first }

    private func shown(_ id: Binding<UUID?>, _ shelf: UUID) -> Binding<Bool> {
        Binding(get: { id.wrappedValue == shelf }, set: { if !$0, id.wrappedValue == shelf { id.wrappedValue = nil } })
    }

    /// Same entries as the compartment's menu on the shelf page.
    @ViewBuilder private func lockMenu(_ shelf: Shelf) -> some View {
        if shelf.isReserved {
            Button("Namen ändern …") { namingID = shelf.id }
            Button("Fach entsperren") { setLocked(shelf, false) }
        } else {
            Button {
                setLocked(shelf, true)
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Fach sperren")
                    if !shelf.copies.isEmpty {
                        Text("Nur leere Fächer lassen sich sperren").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
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
        for shelf in shelves { hasher.combine(shelf.id); hasher.combine(shelf.isReserved); hasher.combine(shelf.copies.count) }
        return hasher.finalize()
    }

    var body: some View {
        SettingsPage {
            SettingsCard(title: "Regale",
                         subtitle: "Mit ← / → zwischen den Regalen wechseln, mit der Leertaste aktivieren oder deaktivieren.") {
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
                SettingsCard(title: "Fächer · \(cabinet.name)",
                             subtitle: "\(cabinet.sizeText) Fächer · \(AppStyle.records(cabinet.recordCount)) eingeräumt\(cabinet.isActive ? "" : " · inaktiv")") {
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
                    SettingsNote("Klicke auf ein Fach, um es zu sperren oder zu entsperren – z. B. für Deko oder andere Dinge. Gesperrte Fächer werden beim Einsortieren übersprungen.")
                    if let shelfError { AppBanner(message: shelfError, kind: .error).transition(AppStyle.funnelTransition()) }
                }
            }

            SettingsCard(title: "Beschriftung",
                         subtitle: "Wie die Fächer auf der Regalseite, in Listen und im Export heißen.") {
                SettingsRow(title: "Fächer benennen nach", hint: labelStyle == .range
                            ? "Erste und letzte Buchstaben der Interpreten im Fach, \(labelStyle.example)."
                            : "Platz im Regal von links oben, \(labelStyle.example).") {
                    GlassSegmentedPicker(selection: $labelStyle, options: ShelfLabelStyle.allCases) { Text($0.title) }
                        .accessibilityLabel("Beschriftung")
                }
            }
        }
        .onChange(of: cabinetID) { menuID = nil; namingID = nil; error = nil; shelfError = nil }
        .animation(AppStyle.standardAnimation, value: shelfError)
        .task(id: labelSignature) { labels = ShelfRangeLabels.compute(for: shelves, style: labelStyle) }
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
                            .padding(.horizontal, 12)
                            .frame(minHeight: 52)
                            .background(Color.primary.opacity(adding ? 0.08 : 0.03), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AppStyle.borderColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(2)
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
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Circle().fill(cabinet.isActive ? AppStyle.successColor : Color.secondary.opacity(0.5))
                        .frame(width: 7, height: 7)
                    Text(cabinet.name).font(.callout.weight(.semibold)).lineLimit(1)
                }
                Text("\(cabinet.sizeText) · \(AppStyle.records(cabinet.recordCount))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
            .foregroundStyle(cabinet.isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(minWidth: 120, maxWidth: 240, minHeight: 52, alignment: .leading)
            .background(selected ? AppStyle.selectedBackground : (hovering ? AppStyle.hoverBackground : Color.primary.opacity(0.03)),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selected ? AppStyle.selectedBorder.opacity(focused ? 0.8 : 0.35) : AppStyle.borderColor,
                              lineWidth: selected && focused ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(AppStyle.quickAnimation, value: hovering)
        .help(cabinet.isActive ? "Aktiv – Leertaste deaktiviert es" : "Inaktiv – Leertaste aktiviert es")
        .accessibilityLabel("\(cabinet.name), \(cabinet.sizeText), \(cabinet.isActive ? "aktiv" : "inaktiv")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A KALLAX variant or a size of one's own (columns × rows, 1–6 each).
private struct CabinetSizePicker: View {
    @Binding var columns: Int
    @Binding var rows: Int
    @State private var custom = false

    private var selection: Binding<String> {
        Binding {
            custom ? "custom" : (KallaxPreset.matching(columns: columns, rows: rows)?.id ?? "custom")
        } set: { id in
            if let preset = KallaxPreset.all.first(where: { $0.id == id }) {
                custom = false; columns = preset.columns; rows = preset.rows
            } else {
                custom = true
            }
        }
    }

    private func presetTitle(_ preset: KallaxPreset) -> String {
        preset.title + (preset.orientation.map { " (\($0))" } ?? "")
    }
    private var currentSizeTitle: String {
        KallaxPreset.all.first { $0.id == selection.wrappedValue }.map(presetTitle) ?? "Eigene Größe"
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: AppStyle.itemSpacing) {
            GlassMenuPicker(title: "Größe", selection: selection, current: currentSizeTitle) {
                Section("IKEA KALLAX") {
                    ForEach(KallaxPreset.all) { preset in
                        Text(presetTitle(preset)).tag(preset.id)
                    }
                }
                Divider()
                Text("Eigene Größe …").tag("custom")
            }
            if selection.wrappedValue == "custom" {
                HStack(spacing: AppStyle.rowSpacing) {
                    GlassStepper(value: $columns, range: ShelfGeometry.sizeRange) { "\($0) Spalten" }
                    GlassStepper(value: $rows, range: ShelfGeometry.sizeRange) { "\($0) Reihen" }
                }
                .monospacedDigit()
            }
        }
        .onAppear { custom = KallaxPreset.matching(columns: columns, rows: rows) == nil }
    }
}

private struct CabinetCreator: View {
    let suggestedName: String
    let cancel: () -> Void
    let create: (String, Int, Int) -> Void
    @State private var name = ""
    @State private var columns = 2
    @State private var rows = 4

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
            Divider()
            SettingsRow(title: "Name") {
                CabinetNameField(placeholder: suggestedName, text: $name) { add() }
            }
            Divider()
            SettingsRow(title: "Größe", hint: "Spalten × Reihen, wie auf dem IKEA-Etikett: Breite × Höhe.") {
                CabinetSizePicker(columns: $columns, rows: $rows)
            }
            HStack(spacing: AppStyle.itemSpacing) {
                Spacer()
                GhostButton(title: "Abbrechen", action: cancel).keyboardShortcut(.cancelAction)
                PrimaryButton(title: "Regal anlegen", action: add).keyboardShortcut(.defaultAction)
            }
        }
    }

    private func add() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        create(trimmed.isEmpty ? suggestedName : trimmed, columns, rows)
    }
}

/// Name, on/off, size, order and removal of the selected cabinet.
private struct CabinetEditor: View {
    let cabinet: Cabinet
    let isOnly: Bool
    /// The last active cabinet can't be switched off – there'd be nowhere to sort into.
    let isOnlyActive: Bool
    let isFirst: Bool
    let isLast: Bool
    let report: (() throws -> Void) -> Void
    let deleted: () -> Void
    @Environment(\.modelContext) private var context
    @State private var name: String
    /// The name as last stored. Compared instead of `cabinet.name`, so a
    /// save on disappear never reads the model when nothing changed.
    @State private var savedName: String
    @State private var columns: Int
    @State private var rows: Int
    @State private var confirmingDelete = false

    init(cabinet: Cabinet, isOnly: Bool, isOnlyActive: Bool, isFirst: Bool, isLast: Bool,
         report: @escaping (() throws -> Void) -> Void, deleted: @escaping () -> Void) {
        self.cabinet = cabinet; self.isOnly = isOnly; self.isOnlyActive = isOnlyActive
        self.isFirst = isFirst; self.isLast = isLast
        self.report = report; self.deleted = deleted
        _name = State(initialValue: cabinet.name)
        _savedName = State(initialValue: cabinet.name)
        _columns = State(initialValue: cabinet.columns)
        _rows = State(initialValue: cabinet.rows)
    }

    private var service: CabinetService { CabinetService(context: context) }
    private var sizeChanged: Bool { columns != cabinet.columns || rows != cabinet.rows }
    private var activeHint: String {
        if !cabinet.isActive {
            return "Die Platten behalten ihre Plätze, sind aber auf der Regalseite ausgeblendet und werden beim Einsortieren übersprungen."
        }
        return isOnlyActive
            ? "Das einzige aktive Regal – mindestens eines muss aktiv bleiben, damit es Platz zum Einsortieren gibt."
            : "Wird auf der Regalseite gezeigt und beim Einsortieren berücksichtigt."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
            SettingsRow(title: "Name", hint: "Auch per Rechtsklick auf den Reiter der Regalseite.") {
                CabinetNameField(placeholder: "Name", text: $name, submit: commitName)
            }
            Divider()
            SettingsRow(title: "Aktiv", hint: activeHint) {
                Toggle("Aktiv", isOn: Binding(get: { cabinet.isActive },
                                              set: { on in report { try service.setActive(cabinet, on) } }))
                    .labelsHidden().toggleStyle(.switch)
                    .disabled(isOnlyActive)
            }
            Divider()
            SettingsRow(title: "Größe", hint: sizeChanged
                        ? "Die Fächer behalten ihre Reihenfolge von links oben. Fallen Fächer weg, müssen sie leer sein – gesperrte verlieren dabei Sperre und Namen."
                        : "Spalten × Reihen · Breite × Höhe") {
                CabinetSizePicker(columns: $columns, rows: $rows)
            }
            if sizeChanged {
                HStack(spacing: AppStyle.itemSpacing) {
                    Spacer()
                    GhostButton(title: "Zurücksetzen") { columns = cabinet.columns; rows = cabinet.rows }
                    PrimaryButton(title: "Größe übernehmen") {
                        report { try service.resize(cabinet, columns: columns, rows: rows) }
                    }
                }
                .transition(AppStyle.funnelTransition())
            }
            if !isOnly {
                Divider()
                SettingsRow(title: "Reihenfolge", hint: "Position unter den Reitern der Regalseite.") {
                    HStack(spacing: AppStyle.tightSpacing) {
                        IconButton(systemImage: "arrow.left", help: "Nach vorne schieben") { report { try service.move(cabinet, by: -1) } }
                            .disabled(isFirst)
                        IconButton(systemImage: "arrow.right", help: "Nach hinten schieben") { report { try service.move(cabinet, by: 1) } }
                            .disabled(isLast)
                    }
                    .foregroundStyle(.secondary)
                }
                Divider()
                SettingsRow(title: "Regal löschen", hint: cabinet.recordCount > 0
                            ? "Nur leere Regale lassen sich löschen."
                            : "Das Regal ist leer und kann entfernt werden.") {
                    GhostButton(title: "Löschen …") { confirmingDelete = true }
                        .foregroundStyle(AppStyle.errorColor)
                        .disabled(cabinet.recordCount > 0)
                }
            }
        }
        .animation(AppStyle.standardAnimation, value: sizeChanged)
        .onChange(of: cabinet.columns) { _, value in columns = value }
        .onChange(of: cabinet.rows) { _, value in rows = value }
        .onChange(of: cabinet.name) { _, value in
            savedName = value
            if value != name.trimmingCharacters(in: .whitespacesAndNewlines) { name = value }
        }
        .task(id: name) {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            saveName()
        }
        .onDisappear(perform: saveName)
        .confirmationDialog("„\(savedName)“ löschen?", isPresented: $confirmingDelete) {
            Button("Regal löschen", role: .destructive) {
                report { try service.delete(cabinet); deleted() }
            }
        } message: {
            Text("Das Regal ist leer. Seine Fächer samt Sperren und Namen werden entfernt.")
        }
    }

    /// A cabinet always has a name: an empty field keeps the stored one.
    /// No context = deleted (SwiftData clears it on save); don't touch it then.
    private func saveName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != savedName, cabinet.modelContext != nil else { return }
        report { try service.rename(cabinet, to: trimmed); savedName = trimmed }
    }

    /// ↩: saves, or brings the stored name back into an emptied field.
    private func commitName() {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { name = savedName } else { saveName() }
    }
}

private struct CabinetNameField: View {
    let placeholder: String
    @Binding var text: String
    let submit: () -> Void
    var body: some View {
        GlassTextField(placeholder: placeholder, text: $text, onSubmit: submit)
            .frame(width: 220)
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
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if shelf.isReserved { Image(systemName: "lock.fill").font(.caption2) }
                    Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                }
                Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
            .foregroundStyle(shelf.isReserved ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
            .background(selected ? AppStyle.selectedBackground : (hovering ? AppStyle.hoverBackground : Color.primary.opacity(0.03)),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selected ? AppStyle.selectedBorder.opacity(0.35) : AppStyle.borderColor))
            .contentShape(RoundedRectangle(cornerRadius: 8))
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
        shelf.isReserved ? "Gesperrt" : shelf.copies.isEmpty ? "Leer" : AppStyle.records(shelf.copies.count)
    }
}

