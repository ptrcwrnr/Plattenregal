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
    /// A smaller retention that would delete files, waiting for confirmation.
    /// Stored only once confirmed: a backup written meanwhile must not prune with it.
    @State private var pendingRetention: (count: Int, days: Int, removed: Int)?

    var body: some View {
        SettingsPage {
            SettingsCard(title: String(localized: "Fach-Belegung"),
                         subtitle: String(localized: "Die Platten selbst kommen jederzeit wieder aus Discogs. Wo sie im Regal stehen, gibt es nur hier – die Sicherung bewahrt genau das.")) {
                SettingsRow(title: String(localized: "Aktuell"), hint: current?.summary ?? String(localized: "Die aktuelle Belegung ließ sich gerade nicht lesen. Bleibt das so, starte Plattenregal neu.")) {
                    PrimaryButton(title: String(localized: "Sichern unter …"), action: saveToFile)
                        .disabled(current == nil)
                }
                Divider()
                SettingsRow(title: String(localized: "Wiederherstellen"),
                            hint: String(localized: "Zuerst mit Discogs synchronisieren, damit alle Platten da sind. Zugeordnet wird über die Discogs-Exemplar-ID.")) {
                    SecondaryButton(title: String(localized: "Aus Datei …")) { importing = true }
                        .disabled(sync.busy)
                }
                if sync.busy {
                    SettingsNote(String(localized: "Während der Synchronisierung lässt sich keine Belegung wiederherstellen."))
                }
                if let status {
                    AppBanner(message: status.message, kind: status.failed ? .error : .success)
                        .transition(AppStyle.funnelTransition())
                }
            }
            .animation(AppStyle.standardAnimation, value: status?.message)

            SettingsCard(title: String(localized: "Automatische Sicherung"),
                         subtitle: DemoMode.isActive
                            ? String(localized: "In der Demo wird nicht automatisch gesichert, und Speicherort und Aufbewahrung lassen sich nicht ändern – so bleiben deine echten Sicherungen unberührt.")
                            : String(localized: "Ein paar Sekunden nach jeder Änderung am Regal. ") + (keptDays > 0
                            ? String(localized: "Erhalten bleiben die letzten \(keptCount) Stände und zusätzlich der letzte Stand jedes Tages der vergangenen \(keptDays) Tage.")
                            : String(localized: "Erhalten bleiben die letzten \(keptCount) Stände."))) {
                SettingsRow(title: String(localized: "Automatisch sichern")) {
                    Toggle("Automatisch sichern", isOn: $autoEnabled).labelsHidden().toggleStyle(.switch)
                        .disabled(DemoMode.isActive)
                }
                Divider()
                SettingsRow(title: String(localized: "Letzte Stände behalten")) {
                    GlassSegmentedPicker(selection: retention(\.count), options: ShelfAutoBackup.keptCountOptions) { Text("\($0)") }
                        .accessibilityLabel("Letzte Stände")
                    .disabled(DemoMode.isActive)
                }
                Divider()
                SettingsRow(title: String(localized: "Tagesstände behalten"), hint: String(localized: "Der letzte Stand eines Tages – so verdrängt ein Tag mit vielen Änderungen nicht alle älteren Sicherungen.")) {
                    GlassMenuPicker(title: String(localized: "Tagesstände"), selection: retention(\.days),
                                    current: keptDays == 0 ? String(localized: "Keine") : String(localized: "\(keptDays) Tage")) {
                        ForEach(ShelfAutoBackup.keptDaysOptions, id: \.self) { Text($0 == 0 ? "Keine" : "\($0) Tage").tag($0) }
                    }
                    .disabled(DemoMode.isActive)
                }
                Divider()
                SettingsRow(title: String(localized: "Speicherort"), hint: customFolder.map(FolderAccess.displayName)
                            ?? (ShelfAutoBackup.folder.isSet
                                ? String(localized: "Der gewählte Ordner ist nicht erreichbar – bis er wieder da ist oder ein anderer gewählt wird, sichert die App in ihren eigenen Ordner.")
                                : String(localized: "Im Ordner der App. Ein Ordner in iCloud Drive schützt die Belegung auch, wenn der Mac verloren geht."))) {
                    HStack(spacing: AppStyle.itemSpacing) {
                        if customFolder != nil || ShelfAutoBackup.defaultDirectory != nil {
                            GhostButton(title: String(localized: "Im Finder zeigen"), action: showInFinder)
                        }
                        Group {
                            if ShelfAutoBackup.folder.isSet {
                                GhostButton(title: String(localized: "Standard")) { changeFolder(to: nil) }
                            }
                            SecondaryButton(title: String(localized: "Ändern …")) {
                                if let url = FolderPicker.choose(message: String(localized: "Ordner für die automatischen Sicherungen der Fach-Belegung")) { changeFolder(to: url) }
                            }
                        }
                        .disabled(DemoMode.isActive)
                    }
                }
                if let folderError { AppBanner(message: folderError, kind: .error).transition(AppStyle.funnelTransition()) }
                if autoEnabled, let failure = autoBackup.lastFailure {
                    AppBanner(message: String(localized: "Die automatische Sicherung um \(failure.formatted(date: .omitted, time: .shortened)) hat nicht geklappt. Sichere die Belegung zur Sicherheit mit „Sichern unter …“ in eine Datei."), kind: .warning)
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
                                GhostButton(title: String(localized: "Wiederherstellen …")) { prepareRestore(entry.backup) }
                                    .disabled(sync.busy)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } else {
                    SettingsNote(String(localized: "Noch keine automatische Sicherung vorhanden."))
                }
            }
            .animation(AppStyle.standardAnimation, value: folderError)
            .confirmationDialog(pendingRetention.map { $0.removed == 1 ? String(localized: "1 ältere Sicherung löschen?") : String(localized: "\($0.removed) ältere Sicherungen löschen?") } ?? "",
                                isPresented: Binding(get: { pendingRetention != nil }, set: { if !$0 { pendingRetention = nil } })) {
                Button("Löschen", role: .destructive) {
                    if let pendingRetention { applyRetention(count: pendingRetention.count, days: pendingRetention.days) }
                }
            } message: {
                Text("Mit der neuen Einstellung bleiben weniger Sicherungen erhalten. Die überzähligen werden sofort gelöscht und lassen sich nicht zurückholen.")
            }
        }
        .onAppear(perform: reload)
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
                      defaultFilename: String(localized: "Plattenregal Belegung \(ExportDate.day(.now))\(DemoMode.fileSuffix)")) { result in
            switch result {
            case .success(let url):
                status = (String(localized: "Gespeichert als „\(url.lastPathComponent)“."), false)
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

    private struct Retention { var count: Int; var days: Int }

    /// Picker binding: a change that would delete backups asks first.
    private func retention(_ part: WritableKeyPath<Retention, Int>) -> Binding<Int> {
        Binding {
            Retention(count: keptCount, days: keptDays)[keyPath: part]
        } set: { value in
            var next = Retention(count: keptCount, days: keptDays)
            next[keyPath: part] = value
            let removed = autoBackup.filesRemoved(keptCount: max(1, next.count), keptDays: max(0, next.days))
            if removed > 0 { pendingRetention = (next.count, next.days, removed) }
            else { applyRetention(count: next.count, days: next.days) }
        }
    }

    private func applyRetention(count: Int, days: Int) {
        guard count != keptCount || days != keptDays else { return }
        keptCount = count; keptDays = days
        AppLog.info("Sicherung", "Aufbewahrung: letzte \(count) Stände, Tagesstände der letzten \(days) Tage")
        autoBackup.applyRetention()
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
            status = (String(localized: "Belegung vom \(backup.createdAt.formatted(date: .abbreviated, time: .shortened)) wiederhergestellt."), false)
        } catch {
            status = (error.reportedMessage(), true)
        }
        reload()
    }
}
