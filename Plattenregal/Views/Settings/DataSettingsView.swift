import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - Daten

struct DataSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appearsActive) private var appearsActive
    @State private var sync = DiscogsSyncService.shared
    @State private var rateLimit = DiscogsRateLimit.shared
    @State private var autoBackup = ShelfAutoBackup.shared
    @State private var sizes = StorageSizes()
    @State private var clearingCache = false
    @State private var storageError: String?
    @State private var logDocument: ExportDocument?
    @State private var savingLog = false
    @State private var logStatus: (message: String, failed: Bool)?
    @State private var pendingReset: ResetKind?
    @State private var resetting = false
    @State private var resetStatus: (message: String, failed: Bool)?

    enum ResetKind: Identifiable {
        case locations, settings, everything
        var id: Self { self }
        var question: String {
            switch self {
            case .locations: String(localized: "Alle Standorte zurücksetzen?")
            case .settings: String(localized: "Alle Einstellungen zurücksetzen?")
            case .everything: String(localized: "Wirklich alles zurücksetzen?")
            }
        }
        var button: String {
            switch self {
            case .locations: String(localized: "Standorte zurücksetzen")
            case .settings: String(localized: "Einstellungen zurücksetzen")
            case .everything: String(localized: "Alles löschen")
            }
        }
        var message: String {
            switch self {
            case .locations: String(localized: "Alle Platten stehen danach ohne Fach, gesperrte Fächer werden freigegeben, „Nicht im Regal“ und „Vermisst“ werden aufgehoben. Die Regale selbst bleiben.")
                // "Vermisst" isn't part of a backup, so it doesn't come back with one.
                + (DemoMode.isActive ? "" : String(localized: " Die aktuelle Belegung wird vorher gesichert und lässt sich unter „Sicherung“ wiederherstellen – ohne die „Vermisst“-Markierungen."))
            case .settings: String(localized: "Darstellung, Startseite, Export und alle anderen Einstellungen gehen auf ihren Standard zurück. Sammlung, Regale, Standorte, der Discogs-Token sowie Speicherort und Aufbewahrung der Sicherungen bleiben.")
            case .everything: String(localized: "Sammlung, Wantlist, Statistik-Verlauf, zusätzliche Regale, Discogs-Konto samt Token, Cover und alle Einstellungen werden gelöscht – wie bei einer neuen Installation. Nur die Sicherungen der Fach-Belegung bleiben samt Speicherort und Aufbewahrung (eine aktuelle wird vorher geschrieben). Das lässt sich nicht rückgängig machen.")
            }
        }
    }

    nonisolated struct StorageSizes: Equatable, Sendable {
        var database: Int64?
        var covers: Int64?
        var backups: Int64?
        var logs: Int64?
        /// Backups in a folder of the user's choice (iCloud Drive, …) are
        /// shown, but don't take space in the app's own folder.
        var backupsElsewhere = false
        var total: Int64 { [database, covers, backupsElsewhere ? nil : backups, logs].compactMap { $0 }.reduce(0, +) }

        /// Walks the folders off the main thread – a backup folder in
        /// iCloud Drive can take a while and must not stall the settings.
        @concurrent static func measure(customBackupFolder: Bool) async -> StorageSizes {
            var sizes = StorageSizes(backupsElsewhere: customBackupFolder)
            if DemoMode.isActive {
                sizes.database = 0
            } else if let store = try? LibraryStorage.storeURL() {
                let folder = store.deletingLastPathComponent()
                let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileSizeKey]
                let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys))) ?? []
                // The store and its journal files ("Collection.store-wal", "-shm"),
                // counted like the folders below: by the space they take on disk.
                sizes.database = files.filter { $0.lastPathComponent.hasPrefix(store.lastPathComponent) }.reduce(0) {
                    let values = try? $1.resourceValues(forKeys: keys)
                    return $0 + Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
                }
            }
            if customBackupFolder {
                sizes.backups = try? ShelfAutoBackup.folder.withAccess { FolderAccess.size(of: $0) }
            } else {
                sizes.backups = ShelfAutoBackup.defaultDirectory.map(FolderAccess.size) ?? 0
            }
            sizes.logs = AppLog.logDirectory.map(FolderAccess.size) ?? 0
            return sizes
        }
    }

    var body: some View {
        SettingsPage {
            SettingsCard(title: String(localized: "Speicherplatz"),
                         subtitle: sizes.covers == nil ? String(localized: "Wird berechnet …") : String(localized: "Die App belegt \(bytes(sizes.total)) auf diesem Mac.")) {
                SettingsRow(title: String(localized: "Sammlung"), hint: DemoMode.isActive
                            ? String(localized: "In der Demo liegt die Sammlung nur im Arbeitsspeicher.")
                            : String(localized: "Platten, Standorte, Wantlist und Statistik-Verlauf.")) {
                    sizeLabel(sizes.database)
                }
                Divider()
                SettingsRow(title: String(localized: "Cover-Cache"), hint: String(localized: "Cover werden bei Bedarf neu von Discogs geladen.")) {
                    HStack(spacing: AppStyle.itemSpacing) {
                        sizeLabel(sizes.covers)
                        SecondaryButton(title: String(localized: "Leeren"), action: clearCovers)
                            .disabled(clearingCache || (sizes.covers ?? 0) == 0)
                    }
                }
                Divider()
                SettingsRow(title: String(localized: "Sicherungen"), hint: autoBackup.usesCustomFolder
                            ? String(localized: "In \(autoBackup.directory.map(FolderAccess.displayName) ?? "–") – zählt nicht zum Platz der App.")
                            : String(localized: "Automatische Sicherungen der Fach-Belegung (siehe „Sicherung“).")) {
                    sizeLabel(sizes.backups)
                }
                Divider()
                SettingsRow(title: String(localized: "Protokoll"), hint: DemoMode.isActive
                            ? String(localized: "Das gemeinsame Protokoll der App – in der Demo lässt es sich nicht leeren.")
                            : String(localized: "Was die App wann getan hat – hilfreich, wenn etwas nicht klappt.")) {
                    HStack(spacing: AppStyle.itemSpacing) {
                        sizeLabel(sizes.logs)
                        SecondaryButton(title: String(localized: "Leeren")) {
                            AppLog.clear()
                            Task { await updateSizes() }
                        }
                        .disabled((sizes.logs ?? 0) == 0 || DemoMode.isActive)
                    }
                }
                if let storageError { AppBanner(message: storageError, kind: .error).transition(AppStyle.funnelTransition()) }
            }
            .animation(AppStyle.standardAnimation, value: storageError)

            SettingsCard(title: String(localized: "Diagnose")) {
                SettingsRow(title: String(localized: "Protokoll"), hint: String(localized: "Enthält nie den Discogs-Token.")) {
                    HStack(spacing: AppStyle.itemSpacing) {
                        if let directory = AppLog.logDirectory {
                            GhostButton(title: String(localized: "Im Finder zeigen")) {
                                let file = AppLog.fileURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
                                NSWorkspace.shared.activateFileViewerSelecting([file ?? directory])
                            }
                        }
                        SecondaryButton(title: String(localized: "Sichern unter …")) {
                            logDocument = ExportDocument(data: AppLog.exportData())
                            savingLog = true
                        }
                    }
                }
                if let logStatus {
                    AppBanner(message: logStatus.message, kind: logStatus.failed ? .error : .success)
                        .transition(AppStyle.funnelTransition())
                }
                Divider()
                SettingsRow(title: String(localized: "Discogs-Anfragen"), hint: rateLimitHint) {
                    Text(rateLimitValue).monospacedDigit().foregroundStyle(.secondary)
                }
                if let throttled = rateLimit.lastThrottled, Date.now.timeIntervalSince(throttled) < 600 {
                    AppBanner(message: String(localized: "Discogs hat um \(throttled.formatted(date: .omitted, time: .shortened)) gebremst, weil zu viele Anfragen kamen. Plattenregal wartet dann kurz und macht von selbst weiter."), kind: .info)
                }
            }
            .animation(AppStyle.standardAnimation, value: logStatus?.message)

            SettingsCard(title: String(localized: "Zurücksetzen"),
                         subtitle: sync.busy ? String(localized: "Während der Synchronisierung lässt sich nichts zurücksetzen.") : nil) {
                SettingsRow(title: String(localized: "Standorte"), hint: String(localized: "Alle Platten aus den Fächern nehmen, Sperren aufheben.")) {
                    SecondaryButton(title: String(localized: "Zurücksetzen …")) { pendingReset = .locations }
                }
                Divider()
                SettingsRow(title: String(localized: "Einstellungen"), hint: String(localized: "Alle Einstellungen auf Standard, Daten bleiben.")) {
                    SecondaryButton(title: String(localized: "Zurücksetzen …")) { pendingReset = .settings }
                }
                Divider()
                SettingsRow(title: String(localized: "Alles"), hint: String(localized: "Wie eine neue Installation. Sicherungen der Belegung bleiben erhalten.")) {
                    Button("Alles zurücksetzen …", role: .destructive) { pendingReset = .everything }
                        .appGlassButton()
                }
                if resetting { ActivityRing(size: 14).transition(.opacity) }
                if let resetStatus {
                    AppBanner(message: resetStatus.message, kind: resetStatus.failed ? .error : .success)
                        .transition(AppStyle.funnelTransition())
                }
            }
            .disabled(sync.busy || resetting)
            .animation(AppStyle.standardAnimation, value: resetStatus?.message)
        }
        .task(id: appearsActive) {
            // Covers keep loading while the window is open; keep the sizes
            // current, but not in the background or after the window closed.
            await updateSizes()
            guard appearsActive else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                await updateSizes()
            }
        }
        .fileExporter(isPresented: $savingLog, document: logDocument, contentType: .plainText,
                      defaultFilename: String(localized: "Plattenregal Protokoll \(ExportDate.day(.now)).log")) { result in
            switch result {
            case .success(let url): logStatus = (String(localized: "Gespeichert als „\(url.lastPathComponent)“."), false)
            case .failure(let error) where error.isUserCancellation: break
            case .failure(let error): logStatus = (FileTransferError.writeFailed(error).reportedMessage(), true)
            }
            logDocument = nil
        }
        .confirmationDialog(pendingReset?.question ?? "", isPresented: Binding(get: { pendingReset != nil }, set: { if !$0 { pendingReset = nil } }),
                            presenting: pendingReset) { kind in
            Button(kind.button, role: .destructive) { reset(kind) }
        } message: { kind in
            Text(kind.message)
        }
    }

    private var rateLimitValue: String {
        guard let remaining = rateLimit.remaining else { return "–" }
        return rateLimit.limit.map { String(localized: "\(remaining) von \($0) frei") } ?? String(localized: "\(remaining) frei")
    }

    private var rateLimitHint: String {
        guard let last = rateLimit.lastRequest else {
            return String(localized: "In dieser Sitzung noch keine Anfrage. Discogs erlaubt mit Token 60 Anfragen pro Minute.")
        }
        let count = rateLimit.requests == 1 ? String(localized: "1 Anfrage") : String(localized: "\(rateLimit.requests) Anfragen")
        return String(localized: "\(count) in dieser Sitzung, zuletzt \(last.formatted(date: .omitted, time: .standard)). Discogs zählt die Anfragen der letzten Minute.")
    }

    private func sizeLabel(_ value: Int64?) -> some View {
        Text(value.map(bytes) ?? "…").monospacedDigit().foregroundStyle(.secondary)
            .contentTransition(.numericText())
    }

    private func bytes(_ value: Int64) -> String { value.formatted(.byteCount(style: .file)) }

    private func updateSizes() async {
        var new = await StorageSizes.measure(customBackupFolder: autoBackup.usesCustomFolder)
        new.covers = await CoverCache.shared.diskUsage()
        guard !Task.isCancelled else { return }
        if new != sizes { withAnimation(AppStyle.quickAnimation) { sizes = new } }
        // Nothing left to delete: an old "couldn't delete" no longer applies.
        if new.covers == 0 { storageError = nil }
    }

    private func clearCovers() {
        clearingCache = true
        Task {
            let cleared = await CoverCache.shared.clear()
            AppLog.info("Cover", cleared ? "Cover-Cache geleert" : "Cover-Cache nur teilweise geleert")
            storageError = cleared ? nil : String(localized: "Einige Cover ließen sich nicht löschen. Bitte versuche es noch einmal.")
            await updateSizes()
            clearingCache = false
        }
    }

    private func reset(_ kind: ResetKind) {
        resetStatus = nil
        let service = ResetService(context: context)
        switch kind {
        case .locations:
            do {
                try service.resetLocations()
                // The demo writes no backups (see `ResetService.safetyBackup`).
                resetStatus = (DemoMode.isActive ? String(localized: "Alle Standorte zurückgesetzt.")
                               : String(localized: "Alle Standorte zurückgesetzt. Die vorherige Belegung liegt unter „Sicherung“."), false)
            } catch { resetStatus = (error.reportedMessage(), true) }
        case .settings:
            ResetService.resetSettings()
            resetStatus = (String(localized: "Alle Einstellungen stehen wieder auf Standard."), false)
        case .everything:
            resetting = true
            Task {
                do {
                    try await service.resetEverything()
                    resetStatus = (DemoMode.isActive
                        ? String(localized: "Die Beispielsammlung ist geleert. „Demo neu starten“ unter „Allgemein“ holt sie zurück.")
                        : String(localized: "Alles zurückgesetzt. Trage unter „Discogs“ einen Token ein, um neu zu beginnen."), false)
                } catch { resetStatus = (error.reportedMessage(), true) }
                resetting = false
                await updateSizes()
            }
        }
    }
}
