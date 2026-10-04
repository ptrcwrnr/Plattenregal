import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Export

struct ExportSettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var sync = DiscogsSyncService.shared
    @State private var changes = LibraryChanges.shared
    @AppStorage(ExportSettings.formatKey) private var format = ExportFormat.csv
    @AppStorage(ExportSettings.sourceKey) private var source = ExportSource.collection
    @AppStorage(ExportSettings.orderKey) private var order = ExportOrder.shelf
    @AppStorage(ExportSettings.delimiterKey) private var delimiter = ExportDelimiter.standard
    @AppStorage(ExportSettings.groupsKey) private var storedGroups = ""
    @AppStorage(ShelfLabelStyle.key) private var labelStyle = ShelfLabelStyle.range
    @AppStorage(ScheduledExport.enabledKey) private var autoEnabled = false
    @AppStorage(ScheduledExport.intervalKey) private var autoInterval = ExportInterval.weekly
    @State private var scheduled = ScheduledExport.shared
    /// The export folder, resolved when the page appears or the export ran –
    /// not on every redraw (a bookmark can stall on a disconnected drive).
    @State private var folder: URL?
    @State private var document: ExportDocument?
    /// The settings the file was built with: switching format or data while a
    /// large PDF is drawn must not save it as CSV or under the wrong name.
    @State private var exported: ExportSettings?
    @State private var exporting = false
    /// A large PDF takes a moment to draw; a second click would draw it twice.
    @State private var preparing = false
    @State private var status: (message: String, failed: Bool)?
    @State private var autoStatus: (message: String, failed: Bool)?

    private var groups: Set<ExportColumnGroup> { ExportSettings.parseGroups(storedGroups) }
    private var settings: ExportSettings {
        ExportSettings(format: format, source: source, order: order, delimiter: delimiter, groups: groups)
    }

    var body: some View {
        let total = count
        SettingsPage {
            SettingsCard(title: String(localized: "Inhalt"), subtitle: String(localized: "Exportiert wird die Collection bzw. Wantlist des aktuellen Discogs-Kontos.")) {
                SettingsRow(title: String(localized: "Daten")) {
                    segmented($source, ExportSource.allCases) { $0.title }
                }
                Divider()
                SettingsRow(title: String(localized: "Format"),
                            hint: format == .csv
                                ? String(localized: "Für Numbers, Excel oder Google Sheets – mit den unten gewählten Spalten.")
                                : source == .collection
                                    ? String(localized: "Druckfertige Liste im A4-Querformat: Interpret, Titel, Jahr, Label, Katalognummer, Format und Fach.")
                                    : String(localized: "Druckfertige Liste im A4-Querformat: Interpret, Titel, Jahr, Label, Katalognummer und Format.")) {
                    segmented($format, ExportFormat.allCases) { $0.title }
                }
                if source == .collection {
                    Divider()
                    SettingsRow(title: String(localized: "Reihenfolge"),
                                hint: order == .shelf
                                    ? String(localized: "Fach für Fach, jeweils von vorne nach hinten; Platten ohne Fach am Ende.")
                                    : String(localized: "Nach Interpret und Titel, wie auf der Collection-Seite.")) {
                        segmented($order, ExportOrder.allCases) { $0.title }
                    }
                }
            }

            if format == .csv {
                SettingsCard(title: String(localized: "Spalten"),
                             subtitle: String(localized: "Interpret, Titel, Jahr, Label, Katalognummer, Format, Land und Stile sind immer enthalten.")) {
                    let available = ExportColumnGroup.allCases.filter { $0.applies(to: source) }
                    ForEach(Array(available.enumerated()), id: \.element) { index, group in
                        if index > 0 { Divider() }
                        SettingsRow(title: group.title, hint: group.hint(for: source)) {
                            Toggle(group.title, isOn: binding(for: group)).labelsHidden().toggleStyle(.switch)
                        }
                    }
                    Divider()
                    SettingsRow(title: String(localized: "Trennzeichen"), hint: String(localized: "Excel mit deutschen Einstellungen erwartet Semikolons.")) {
                        segmented($delimiter, ExportDelimiter.allCases) { $0.title }
                    }
                }
                .transition(AppStyle.funnelTransition())
            }

            SettingsCard(title: String(localized: "Datei")) {
                SettingsRow(title: AppStyle.records(total),
                            hint: sync.isRunning ? String(localized: "Nach der laufenden Synchronisierung ist der Export vollständig.") : nil) {
                    PrimaryButton(title: preparing ? String(localized: "Wird erstellt …") : String(localized: "Als \(format.title) exportieren …"), action: export)
                        .disabled(total == 0 || preparing)
                }
                if let status {
                    AppBanner(message: status.message, kind: status.failed ? .error : .success)
                        .transition(AppStyle.funnelTransition())
                }
            }
            .animation(AppStyle.standardAnimation, value: status?.message)

            automaticCard
        }
        .animation(AppStyle.standardAnimation, value: format)
        .onChange(of: source) { status = nil }
        .onChange(of: format) { status = nil }
        .fileExporter(isPresented: $exporting, document: document, contentType: (exported ?? settings).format.contentType,
                      defaultFilename: defaultFilename) { result in
            let done = exported ?? settings
            switch result {
            case .success(let url):
                status = (String(localized: "Gespeichert als „\(url.lastPathComponent)“."), false)
                AppLog.info("Export", "\(done.format.title)-Export gespeichert (\(done.source.title), \(url.lastPathComponent))")
            case .failure(let error) where error.isUserCancellation:
                break
            case .failure(let error):
                status = (FileTransferError.writeFailed(error).reportedMessage(), true)
            }
            document = nil
            exported = nil
        }
    }

    /// Re-counted after every committed sync.
    private var count: Int {
        _ = changes.libraryVersion
        return CollectionExportService(context: context).count(source)
    }

    private var defaultFilename: String {
        String(localized: "Plattenregal \((exported ?? settings).source.title) \(ExportDate.day(.now))\(DemoMode.fileSuffix)")
    }

    private func export() {
        status = nil
        preparing = true
        Task {
            defer { preparing = false }
            let settings = settings
            do {
                let job = try settings.prepare(context: context, labelStyle: labelStyle)
                document = ExportDocument(data: try await job.renderedInBackground())
                exported = settings
                AppLog.info("Export", "\(settings.format.title)-Export erstellt: \(settings.source.title), \(AppStyle.records(job.rows))")
                exporting = true
            } catch {
                status = (FileTransferError.exportFailed(error).reportedMessage(), true)
            }
        }
    }

    /// Writes the export on its own into a fixed folder, with the settings above.
    private var automaticCard: some View {
        SettingsCard(title: String(localized: "Automatisch exportieren"),
                            subtitle: DemoMode.isActive
                                ? String(localized: "In der Demo wird nicht automatisch exportiert. Über „Als … exportieren“ oben lässt sich die Beispielsammlung trotzdem als Datei sichern.")
                                : String(localized: "Schreibt den Export mit den Einstellungen oben regelmäßig in einen Ordner – z. B. in iCloud Drive. Die Datei „\(ScheduledExport.fileName(for: settings))“ wird dabei jedes Mal ersetzt.")) {
            SettingsRow(title: String(localized: "Automatisch exportieren")) {
                Toggle("Automatisch exportieren", isOn: $autoEnabled).labelsHidden().toggleStyle(.switch)
                    .disabled(DemoMode.isActive)
            }
            if autoEnabled {
                Divider()
                SettingsRow(title: String(localized: "Häufigkeit")) {
                    segmented($autoInterval, ExportInterval.allCases) { $0.title }
                }
                Divider()
                SettingsRow(title: String(localized: "Ordner"), hint: folder.map(FolderAccess.displayName) ?? (ScheduledExport.folder.isSet
                                ? String(localized: "Der gewählte Ordner ist nicht mehr erreichbar (verschoben, gelöscht oder Laufwerk getrennt). Bitte neu wählen.")
                                : String(localized: "Noch kein Ordner gewählt – ohne Ordner wird nichts exportiert."))) {
                    HStack(spacing: AppStyle.itemSpacing) {
                        // Worded like "Im Finder zeigen" under Sicherung and Daten.
                        if folder != nil {
                            GhostButton(title: String(localized: "Im Finder zeigen")) {
                                try? ScheduledExport.folder.withAccess { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
                            }
                        }
                        SecondaryButton(title: folder == nil ? String(localized: "Wählen …") : String(localized: "Ändern …")) { chooseExportFolder() }
                    }
                }
                Divider()
                SettingsRow(title: scheduled.lastRun.map { String(localized: "Zuletzt \($0.formatted(.relative(presentation: .named)))") } ?? String(localized: "Noch nicht exportiert"),
                            hint: sync.busy ? String(localized: "Nach der laufenden Synchronisierung.")
                                : count == 0 ? String(localized: "Ohne Platten wird nichts exportiert, damit keine leere Liste die letzte Datei ersetzt.")
                                : scheduled.nextRun.map { $0 <= .now ? String(localized: "Der nächste Export folgt in Kürze.") : String(localized: "Nächster Export \($0.formatted(date: .abbreviated, time: .shortened)).") }) {
                    SecondaryButton(title: String(localized: "Jetzt exportieren")) {
                        Task {
                            do { autoStatus = (String(localized: "Gespeichert als „\(try await scheduled.run(container: context.container))“."), false) }
                            catch { autoStatus = (scheduled.lastError ?? error.reportedMessage(), true) }
                        }
                    }
                    // Mid-sync the list is half updated, and it replaces the file.
                    .disabled(folder == nil || count == 0 || sync.busy || scheduled.isRunning)
                }
                if let autoStatus {
                    AppBanner(message: autoStatus.message, kind: autoStatus.failed ? .error : .success)
                        .transition(AppStyle.funnelTransition())
                } else if let error = scheduled.lastError {
                    AppBanner(message: String(localized: "Der letzte automatische Export hat nicht geklappt. \(error)"), kind: .warning)
                        .transition(AppStyle.funnelTransition())
                }
            }
        }
        .animation(AppStyle.standardAnimation, value: autoEnabled)
        .animation(AppStyle.standardAnimation, value: autoStatus?.message)
        .onChange(of: autoEnabled) { _, on in
            AppLog.info("Export", "Automatischer Export \(on ? "eingeschaltet" : "ausgeschaltet")")
            autoStatus = nil; scheduled.settingsChanged()
        }
        .onChange(of: autoInterval) { scheduled.settingsChanged() }
        .onAppear { folder = ScheduledExport.folder.url }
        .onChange(of: scheduled.version) { folder = ScheduledExport.folder.url }
    }

    private func chooseExportFolder() {
        guard let url = FolderPicker.choose(message: String(localized: "Ordner für den automatischen Export")) else { return }
        do {
            try ScheduledExport.folder.set(url)
            autoStatus = nil
            scheduled.settingsChanged()
            AppLog.info("Export", "Ordner für den automatischen Export: \(FolderAccess.displayName(of: url))")
        } catch { autoStatus = (FileTransferError.readFailed(error).reportedMessage(), true) }
    }

    private func binding(for group: ExportColumnGroup) -> Binding<Bool> {
        Binding {
            groups.contains(group)
        } set: { on in
            var updated = groups
            if on { updated.insert(group) } else { updated.remove(group) }
            storedGroups = ExportColumnGroup.allCases.filter(updated.contains).map(\.rawValue).joined(separator: ",")
        }
    }

    private func segmented<Value: Hashable>(_ selection: Binding<Value>, _ values: [Value],
                                            title: @escaping (Value) -> String) -> some View {
        GlassSegmentedPicker(selection: selection, options: values) { Text(title($0)) }
    }
}

/// The finished file handed to the save panel; the export is built up front.
struct ExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.commaSeparatedText, .pdf, .json, .plainText]
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
