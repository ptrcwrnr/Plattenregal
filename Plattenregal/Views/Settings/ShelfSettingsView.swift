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
    @State private var selectedID: UUID?
    @State private var adding = false
    @State private var error: String?
    @State private var labels = ShelfLabels()
    @State private var sync = DiscogsSyncService.shared
    @State private var changes = LibraryChanges.shared
    @FocusState private var stripFocused: Bool

    private var cabinet: Cabinet? { cabinets.first { $0.id == cabinetID } ?? cabinets.first }

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
                                  report: report, deleted: { cabinetID = nil; selectedID = nil })
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
                                        ShelfTile(shelf: shelf, label: labels[shelf.id], selected: shelf.id == selectedID) {
                                            withAnimation(AppStyle.quickAnimation) {
                                                selectedID = selectedID == shelf.id ? nil : shelf.id
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if let shelf = own.first(where: { $0.id == selectedID }) {
                        ShelfLockEditor(shelf: shelf).id(shelf.id)
                    } else {
                        SettingsNote("Wähle ein Fach, um es zu sperren – z. B. für Deko oder andere Dinge. Gesperrte Fächer werden beim Einsortieren übersprungen.")
                    }
                }
            }

            SettingsCard(title: "Beschriftung",
                         subtitle: "Wie die Fächer auf der Regalseite, in Listen und im Export heißen.") {
                SettingsRow(title: "Fächer benennen nach", hint: labelStyle == .range
                            ? "Erste und letzte Buchstaben der Interpreten im Fach, \(labelStyle.example)."
                            : "Platz im Regal von links oben, \(labelStyle.example).") {
                    Picker("Beschriftung", selection: $labelStyle) {
                        ForEach(ShelfLabelStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                }
            }
        }
        .onChange(of: cabinetID) { selectedID = nil; error = nil }
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

    var body: some View {
        VStack(alignment: .trailing, spacing: AppStyle.itemSpacing) {
            Picker("Größe", selection: selection) {
                Section("IKEA KALLAX") {
                    ForEach(KallaxPreset.all) { preset in
                        Text(preset.title + (preset.orientation.map { " (\($0))" } ?? "")).tag(preset.id)
                    }
                }
                Divider()
                Text("Eigene Größe …").tag("custom")
            }
            .labelsHidden()
            .fixedSize()
            if selection.wrappedValue == "custom" {
                HStack(spacing: AppStyle.rowSpacing) {
                    Stepper("\(columns) Spalten", value: $columns, in: ShelfGeometry.sizeRange)
                    Stepper("\(rows) Reihen", value: $rows, in: ShelfGeometry.sizeRange)
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
            SettingsRow(title: "Name") {
                CabinetNameField(placeholder: "Name", text: $name, submit: commitName)
            }
            SettingsRow(title: "Aktiv", hint: activeHint) {
                Toggle("Aktiv", isOn: Binding(get: { cabinet.isActive },
                                              set: { on in report { try service.setActive(cabinet, on) } }))
                    .labelsHidden().toggleStyle(.switch)
                    .disabled(isOnlyActive)
            }
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
            HStack(spacing: AppStyle.itemSpacing) {
                if !isOnly {
                    IconButton(systemImage: "arrow.left", help: "Nach vorne schieben") { report { try service.move(cabinet, by: -1) } }
                        .disabled(isFirst)
                    IconButton(systemImage: "arrow.right", help: "Nach hinten schieben") { report { try service.move(cabinet, by: 1) } }
                        .disabled(isLast)
                }
                Spacer()
                if !isOnly {
                    GhostButton(title: "Regal löschen …") { confirmingDelete = true }
                        .foregroundStyle(AppStyle.errorColor)
                        .disabled(cabinet.recordCount > 0)
                        .help(cabinet.recordCount > 0 ? "Nur leere Regale lassen sich löschen." : "")
                }
            }
            .foregroundStyle(.secondary)
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
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .frame(width: 220, height: AppStyle.controlHeight)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            .onSubmit(submit)
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

/// Lock switch + name for the selected compartment, same wording as the
/// options popover on the shelf page. Follows changes made there while open.
private struct ShelfLockEditor: View {
    let shelf: Shelf
    @Environment(\.modelContext) private var context
    @State private var isLocked: Bool
    @State private var name: String
    /// The name as last stored, so the save on disappear doesn't touch the
    /// model when nothing changed – the shelf may just have been removed by
    /// making the cabinet smaller.
    @State private var savedName: String
    @State private var error: String?

    init(shelf: Shelf) {
        self.shelf = shelf
        _isLocked = State(initialValue: shelf.isReserved)
        _name = State(initialValue: shelf.name)
        _savedName = State(initialValue: shelf.name)
    }
    private var canLock: Bool { shelf.isReserved || shelf.copies.isEmpty }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.itemSpacing) {
            SettingsRow(title: "Sperren",
                        hint: canLock ? nil : "Nur leere Fächer können gesperrt werden.") {
                Toggle("Fach sperren", isOn: $isLocked).labelsHidden().toggleStyle(.switch)
                    .disabled(!canLock)
            }
            if isLocked {
                SettingsRow(title: "Name") {
                    TextField("Optional, z. B. „Deko“", text: $name)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .frame(width: 220, height: AppStyle.controlHeight)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                        .onSubmit(saveName)
                }
                .transition(AppStyle.funnelTransition())
            }
            if let error { AppBanner(message: error, kind: .error).transition(AppStyle.funnelTransition()) }
        }
        .animation(AppStyle.standardAnimation, value: isLocked)
        .animation(AppStyle.standardAnimation, value: error)
        // Only real user changes are written; syncing back from the store
        // (or undoing a failed save) must not trigger another save.
        .onChange(of: isLocked) { _, locked in
            guard locked != shelf.isReserved else { return }
            save(locked: locked, name: locked ? trimmedName : "")
        }
        .onChange(of: shelf.isReserved) { _, stored in isLocked = stored }
        .onChange(of: shelf.name) { _, stored in
            savedName = stored
            if stored != trimmedName { name = stored }
        }
        .task(id: name) {
            // Saves once typing pauses, so the name sticks without pressing ↩.
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            saveName()
        }
        // Tab switch or closed window inside the pause: don't lose the name.
        .onDisappear(perform: saveName)
    }

    private func saveName() {
        guard isLocked, trimmedName != savedName, shelf.modelContext != nil else { return }
        save(locked: true, name: trimmedName)
    }

    private func save(locked: Bool, name: String) {
        do {
            try PositionService(context: context).configure(shelf, name: name, isReserved: locked)
            savedName = name
            error = nil
        } catch {
            self.error = error.reportedMessage()
            isLocked = shelf.isReserved
        }
    }
}
