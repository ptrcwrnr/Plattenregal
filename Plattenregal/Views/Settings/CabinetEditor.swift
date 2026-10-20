import SwiftUI
import SwiftData

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
        KallaxPreset.all.first { $0.id == selection.wrappedValue }.map(presetTitle) ?? String(localized: "Eigene Größe")
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: AppStyle.itemSpacing) {
            GlassMenuPicker(title: String(localized: "Größe"), selection: selection, current: currentSizeTitle) {
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
                    GlassStepper(value: $columns, range: ShelfGeometry.sizeRange) { String(localized: "\($0) Spalten") }
                    GlassStepper(value: $rows, range: ShelfGeometry.sizeRange) { String(localized: "\($0) Reihen") }
                }
                .monospacedDigit()
            }
        }
        .onAppear { custom = KallaxPreset.matching(columns: columns, rows: rows) == nil }
    }
}

struct CabinetCreator: View {
    let suggestedName: String
    let cancel: () -> Void
    let create: (String, Int, Int) -> Void
    @State private var name = ""
    @State private var columns = 2
    @State private var rows = 4

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
            Divider()
            SettingsRow(title: String(localized: "Name")) {
                CabinetNameField(placeholder: suggestedName, text: $name) { add() }
            }
            Divider()
            SettingsRow(title: String(localized: "Größe"), hint: String(localized: "Spalten × Reihen.")) {
                CabinetSizePicker(columns: $columns, rows: $rows)
            }
            HStack(spacing: AppStyle.itemSpacing) {
                Spacer()
                GhostButton(title: String(localized: "Abbrechen"), action: cancel).keyboardShortcut(.cancelAction)
                PrimaryButton(title: String(localized: "Regal anlegen"), action: add).keyboardShortcut(.defaultAction)
            }
        }
        .preference(key: SettingsEscapeKey.self, value: true)
    }

    private func add() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        create(trimmed.isEmpty ? suggestedName : trimmed, columns, rows)
    }
}

/// Name, on/off, size, order and removal of the selected cabinet.
struct CabinetEditor: View {
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
            return String(localized: "Die Platten behalten ihre Plätze, sind aber auf der Regalseite ausgeblendet und werden beim Einsortieren übersprungen.")
        }
        return isOnlyActive
            ? String(localized: "Das einzige aktive Regal – mindestens eines muss aktiv bleiben, damit es Platz zum Einsortieren gibt.")
            : String(localized: "Wird auf der Regalseite gezeigt und beim Einsortieren berücksichtigt.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
            SettingsRow(title: String(localized: "Name"), hint: String(localized: "Auch per Rechtsklick auf den Reiter der Regalseite.")) {
                CabinetNameField(placeholder: String(localized: "Name"), text: $name, submit: commitName)
            }
            Divider()
            SettingsRow(title: String(localized: "Aktiv"), hint: activeHint) {
                Toggle("Aktiv", isOn: Binding(get: { cabinet.isActive },
                                              set: { on in report { try service.setActive(cabinet, on) } }))
                    .labelsHidden().toggleStyle(.switch)
                    .disabled(isOnlyActive)
            }
            Divider()
            SettingsRow(title: String(localized: "Größe"), hint: sizeChanged
                        ? String(localized: "Die Fächer behalten ihre Reihenfolge von links oben. Fallen Fächer weg, müssen sie leer sein – gesperrte verlieren dabei Sperre und Namen.")
                        : String(localized: "Spalten × Reihen")) {
                CabinetSizePicker(columns: $columns, rows: $rows)
            }
            if sizeChanged {
                HStack(spacing: AppStyle.itemSpacing) {
                    Spacer()
                    GhostButton(title: String(localized: "Zurücksetzen")) { columns = cabinet.columns; rows = cabinet.rows }
                    PrimaryButton(title: String(localized: "Größe übernehmen")) {
                        report { try service.resize(cabinet, columns: columns, rows: rows) }
                    }
                }
                .transition(AppStyle.funnelTransition())
            }
            if !isOnly {
                Divider()
                SettingsRow(title: String(localized: "Reihenfolge"), hint: String(localized: "Position unter den Reitern der Regalseite.")) {
                    HStack(spacing: AppStyle.tightSpacing) {
                        IconButton(systemImage: "arrow.left", help: String(localized: "Nach vorne schieben")) { report { try service.move(cabinet, by: -1) } }
                            .disabled(isFirst)
                        IconButton(systemImage: "arrow.right", help: String(localized: "Nach hinten schieben")) { report { try service.move(cabinet, by: 1) } }
                            .disabled(isLast)
                    }
                    .foregroundStyle(.secondary)
                }
                Divider()
                SettingsRow(title: String(localized: "Regal löschen"), hint: cabinet.recordCount > 0
                            ? String(localized: "Nur leere Regale lassen sich löschen.")
                            : String(localized: "Das Regal ist leer und kann entfernt werden.")) {
                    // Red only while it can be used: a set color would hide the
                    // dimmed look of a disabled button.
                    GhostButton(title: String(localized: "Löschen")) { confirmingDelete = true }
                        .foregroundStyle(cabinet.recordCount > 0 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(AppStyle.errorColor))
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
