import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Sicherung

struct BackupSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appearsActive) private var appearsActive
    @State private var sync = DiscogsSyncService.shared
    @State private var changes = LibraryChanges.shared
    @State private var autoBackup = ShelfAutoBackup.shared
    @AppStorage(ShelfAutoBackup.enabledKey) private var autoEnabled = true
    @AppStorage(ShelfAutoBackup.keptCountKey) private var keptCount = ShelfAutoBackup.defaultKeptCount
    @AppStorage(ShelfAutoBackup.keptDaysKey) private var keptDays = ShelfAutoBackup.defaultKeptDays
    @State private var folderError: String?
    @State private var entries: [ShelfAutoBackup.Entry] = []
    /// The layout right now; read on reload, not on every redraw (it fetches every copy).
    @State private var current: ShelfBackup?
    /// The chosen folder, resolved on reload: resolving a bookmark on every
    /// redraw can stall on a slow or disconnected drive.
    @State private var customFolder: URL?
    @State private var document: ExportDocument?
    @State private var saving = false
    @State private var importing = false
    @State private var pendingRestore: ShelfRestorePreview?
    @State private var status: (message: String, failed: Bool)?

    var body: some View {
        SettingsPage {
            SettingsCard(title: "Fach-Belegung",
                         subtitle: "Die Platten selbst kommen jederzeit wieder aus Discogs. Wo sie im Regal stehen, gibt es nur hier – die Sicherung bewahrt genau das.") {
                SettingsRow(title: "Aktuell", hint: current?.summary ?? "Die aktuelle Belegung ließ sich gerade nicht lesen. Bleibt das so, starte Plattenregal neu.") {
                    PrimaryButton(title: "Sichern unter …", action: saveToFile)
                        .disabled(current == nil)
                }
                Divider()
                SettingsRow(title: "Wiederherstellen",
                            hint: "Zuerst mit Discogs synchronisieren, damit alle Platten da sind. Zugeordnet wird über die Discogs-Exemplar-ID.") {
                    SecondaryButton(title: "Aus Datei …") { importing = true }
                        .disabled(sync.busy)
                }
                if sync.busy {
                    SettingsNote("Während der Synchronisierung lässt sich keine Belegung wiederherstellen.")
                }
                if let status {
                    AppBanner(message: status.message, kind: status.failed ? .error : .success)
                        .transition(AppStyle.funnelTransition())
                }
            }
            .animation(AppStyle.standardAnimation, value: status?.message)

            SettingsCard(title: "Automatische Sicherung",
                         subtitle: DemoMode.isActive
                            ? "In der Demo wird nicht automatisch gesichert, und Speicherort und Aufbewahrung lassen sich nicht ändern – so bleiben deine echten Sicherungen unberührt."
                            : "Ein paar Sekunden nach jeder Änderung am Regal. " + (keptDays > 0
                            ? "Erhalten bleiben die letzten \(keptCount) Stände und zusätzlich der letzte Stand jedes Tages der vergangenen \(keptDays) Tage."
                            : "Erhalten bleiben die letzten \(keptCount) Stände.")) {
                SettingsRow(title: "Automatisch sichern") {
                    Toggle("Automatisch sichern", isOn: $autoEnabled).labelsHidden().toggleStyle(.switch)
                        .disabled(DemoMode.isActive)
                }
                Divider()
                SettingsRow(title: "Letzte Stände behalten") {
                    GlassSegmentedPicker(selection: $keptCount, options: ShelfAutoBackup.keptCountOptions) { Text("\($0)") }
                        .accessibilityLabel("Letzte Stände")
                    .disabled(DemoMode.isActive)
                }
                Divider()
                SettingsRow(title: "Tagesstände behalten", hint: "Der letzte Stand eines Tages – so verdrängt ein Tag mit vielen Änderungen nicht alle älteren Sicherungen.") {
                    GlassMenuPicker(title: "Tagesstände", selection: $keptDays,
                                    current: keptDays == 0 ? "Keine" : "\(keptDays) Tage") {
                        ForEach(ShelfAutoBackup.keptDaysOptions, id: \.self) { Text($0 == 0 ? "Keine" : "\($0) Tage").tag($0) }
                    }
                    .disabled(DemoMode.isActive)
                }
                Divider()
                SettingsRow(title: "Speicherort", hint: customFolder.map(FolderAccess.displayName)
                            ?? (ShelfAutoBackup.folder.isSet
                                ? "Der gewählte Ordner ist nicht erreichbar – bis er wieder da ist oder ein anderer gewählt wird, sichert die App in ihren eigenen Ordner."
                                : "Im Ordner der App. Ein Ordner in iCloud Drive schützt die Belegung auch, wenn der Mac verloren geht.")) {
                    HStack(spacing: AppStyle.itemSpacing) {
                        if customFolder != nil || ShelfAutoBackup.defaultDirectory != nil {
                            GhostButton(title: "Im Finder zeigen", action: showInFinder)
                        }
                        Group {
                            if ShelfAutoBackup.folder.isSet {
                                GhostButton(title: "Standard") { changeFolder(to: nil) }
                            }
                            SecondaryButton(title: "Ändern …") {
                                if let url = FolderPicker.choose(message: "Ordner für die automatischen Sicherungen der Fach-Belegung") { changeFolder(to: url) }
                            }
                        }
                        .disabled(DemoMode.isActive)
                    }
                }
                if let folderError { AppBanner(message: folderError, kind: .error).transition(AppStyle.funnelTransition()) }
                if autoEnabled, let failure = autoBackup.lastFailure {
                    AppBanner(message: "Die automatische Sicherung um \(failure.formatted(date: .omitted, time: .shortened)) hat nicht geklappt. Sichere die Belegung zur Sicherheit mit „Sichern unter …“ in eine Datei.", kind: .warning)
                        .transition(AppStyle.funnelTransition())
                }
                Divider()
                if !entries.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 { Divider() }
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.backup.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    Text(entry.backup.summary).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                }
                                Spacer()
                                GhostButton(title: "Wiederherstellen …") { prepareRestore(entry.backup) }
                                    .disabled(sync.busy)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } else {
                    SettingsNote("Noch keine automatische Sicherung vorhanden.")
                }
            }
            .animation(AppStyle.standardAnimation, value: folderError)
        }
        .onAppear(perform: reload)
        .onChange(of: keptCount) { _, value in
            AppLog.info("Sicherung", "Aufbewahrung: letzte \(value) Stände")
            autoBackup.applyRetention()
        }
        .onChange(of: keptDays) { _, value in
            AppLog.info("Sicherung", "Aufbewahrung: Tagesstände der letzten \(value) Tage")
            autoBackup.applyRetention()
        }
        // Re-read after shelf changes (each one leads to a backup) and syncs.
        .onChange(of: autoBackup.version) { reload() }
        .onChange(of: changes.libraryVersion) { reload() }
        .onChange(of: changes.shelvesVersion) { reload() }
        // Moves in the main window only bump a version when a backup is written.
        .onChange(of: appearsActive) { _, active in if active { reload() } }
        .onChange(of: autoEnabled) { _, on in
            AppLog.info("Sicherung", "Automatische Sicherung \(on ? "eingeschaltet" : "ausgeschaltet")")
            if on { autoBackup.scheduleBackup(of: context.container) }
        }
        .fileExporter(isPresented: $saving, document: document, contentType: .json,
                      defaultFilename: "Plattenregal Belegung \(ExportDate.day(.now))\(DemoMode.fileSuffix)") { result in
            switch result {
            case .success(let url):
                status = ("Gespeichert als „\(url.lastPathComponent)“.", false)
                AppLog.info("Sicherung", "Fach-Belegung als Datei gesichert: \(url.lastPathComponent)")
            case .failure(let error) where error.isUserCancellation:
                break
            case .failure(let error):
                status = (FileTransferError.writeFailed(error).reportedMessage(), true)
            }
            document = nil
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            let url: URL
            do { url = try result.get() } catch {
                if !error.isUserCancellation { status = (FileTransferError.readFailed(error).reportedMessage(), true) }
                return
            }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let backup = try ShelfBackupService.read(url)
                AppLog.info("Sicherung", "Sicherung aus Datei geöffnet: \(url.lastPathComponent) · \(backup.summary)")
                prepareRestore(backup)
            } catch let error as ShelfBackupError {
                status = (error.reportedMessage(), true)
            } catch {
                status = (FileTransferError.readFailed(error).reportedMessage(), true)
            }
        }
        .confirmationDialog("Belegung vom \(pendingRestore?.backup.createdAt.formatted(date: .abbreviated, time: .shortened) ?? "") wiederherstellen?",
                            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } })) {
            Button("Wiederherstellen", role: .destructive) { if let pendingRestore { restore(pendingRestore.backup) } }
        } message: {
            Text(pendingRestore?.message ?? "")
        }
    }

    private func showInFinder() {
        if customFolder != nil {
            try? ShelfAutoBackup.folder.withAccess { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
        } else if let directory = ShelfAutoBackup.defaultDirectory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([directory])
        }
    }

    private func reload() {
        customFolder = ShelfAutoBackup.folder.url
        entries = autoBackup.entries()
        current = try? ShelfBackupService(context: context).makeBackup()
    }

    private func changeFolder(to url: URL?) {
        do {
            try autoBackup.moveBackups(to: url)
            folderError = nil
            reload()
            if autoEnabled { autoBackup.scheduleBackup(of: context.container) }
        } catch {
            folderError = FileTransferError.folderChangeFailed(error).reportedMessage()
        }
    }

    private func saveToFile() {
        status = nil
        do {
            document = ExportDocument(data: try ShelfBackupService.encode(try ShelfBackupService(context: context).makeBackup()))
            saving = true
        } catch {
            status = (FileTransferError.exportFailed(error).reportedMessage(), true)
        }
    }

    private func prepareRestore(_ backup: ShelfBackup) {
        status = nil
        do {
            let preview = try ShelfBackupService(context: context).preview(backup)
            // Nothing to confirm: the shelf already looks like this.
            if preview.unchanged { status = (preview.message, false) } else { pendingRestore = preview }
        }
        catch let error as ShelfBackupError { status = (error.reportedMessage(), true) }
        catch { status = (FileTransferError.restoreFailed(error).reportedMessage(), true) }
    }

    private func restore(_ backup: ShelfBackup) {
        let service = ShelfBackupService(context: context)
        // The collection may have changed while the dialog was open (a sync
        // finished, another account); check again before touching anything.
        do { _ = try service.preview(backup) }
        catch let error as ShelfBackupError { status = (error.reportedMessage(), true); return }
        catch { status = (FileTransferError.restoreFailed(error).reportedMessage(), true); return }
        // The layout being replaced stays available as the newest backup;
        // without that safety net nothing is replaced.
        do {
            try autoBackup.backUpNow(service)
        } catch {
            status = (FileTransferError.safetyBackupFailed(error).reportedMessage(), true)
            return
        }
        do {
            try service.restore(backup)
            changes.libraryDidChange()
            status = ("Belegung vom \(backup.createdAt.formatted(date: .abbreviated, time: .shortened)) wiederhergestellt.", false)
        } catch {
            status = (error.reportedMessage(), true)
        }
        reload()
    }
}
