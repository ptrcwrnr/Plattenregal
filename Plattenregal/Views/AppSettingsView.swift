import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Settings in the same card language as the app's pages: rounded titles,
/// quiet card surfaces and the shared button vocabulary.
struct AppSettingsView: View {
    enum Tab: String { case general = "Allgemein", appearance = "Darstellung", shelf = "Regal", discogs = "Discogs"
        case export = "Export", backup = "Sicherung", data = "Daten" }
    @State private var tab: Tab = {
        #if DEBUG
        // Screenshots of a tab without clicking there: --settings-tab=Regal
        if let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--settings-tab=") }),
           let tab = Tab(rawValue: String(raw.dropFirst("--settings-tab=".count))) { return tab }
        #endif
        return .general
    }()

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettingsView().tabItem { Label("Allgemein", systemImage: "gearshape") }.tag(Tab.general)
            AppearanceSettingsView().tabItem { Label("Darstellung", systemImage: "paintbrush") }.tag(Tab.appearance)
            ShelfSettingsView().tabItem { Label("Regal", systemImage: "square.grid.3x3") }.tag(Tab.shelf)
            DiscogsSettingsView().tabItem { Label("Discogs", systemImage: "opticaldisc") }.tag(Tab.discogs)
            ExportSettingsView().tabItem { Label("Export", systemImage: "square.and.arrow.up") }.tag(Tab.export)
            BackupSettingsView().tabItem { Label("Sicherung", systemImage: "clock.arrow.circlepath") }.tag(Tab.backup)
            DataSettingsView().tabItem { Label("Daten", systemImage: "internaldrive") }.tag(Tab.data)
        }
        .frame(width: 680, height: 620)
    }
}

// MARK: - Shared building blocks

/// Scrollable page of setting cards.
private struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                if DemoMode.isActive {
                    AppBanner(message: "Demo: Diese Einstellungen gelten nur für die Demo. Deine eigenen bleiben, wie sie sind.", kind: .info,
                              actionTitle: "Demo beenden", action: { DemoMode.end() })
                }
                content
            }
                .padding(AppStyle.pagePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One card: title (+ subtitle), then its rows.
private struct SettingsCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(AppStyle.sectionTitle)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            content
        }
        .padding(AppStyle.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: AppStyle.cardRadius))
    }
}

/// Label (+ optional hint) on the left, control on the right.
private struct SettingsRow<Control: View>: View {
    let title: String
    var hint: String?
    @ViewBuilder let control: Control
    var body: some View {
        HStack(alignment: .center, spacing: AppStyle.rowSpacing) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let hint {
                    Text(hint).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: AppStyle.rowSpacing)
            control
        }
    }
}

private struct SettingsNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Allgemein

struct GeneralSettingsView: View {
    @State private var preferences = AppPreferences.shared

    var body: some View {
        @Bindable var preferences = preferences
        SettingsPage {
            SettingsCard(title: "Start") {
                SettingsRow(title: "Beim Öffnen zeigen", hint: "Die Seite, mit der das Hauptfenster startet.") {
                    Picker("Startseite", selection: $preferences.startPage) {
                        ForEach(StartPage.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                }
            }
            SettingsCard(title: "Demo", subtitle: "Plattenregal mit einer Beispielsammlung ausprobieren oder vorführen.") {
                SettingsRow(title: DemoMode.isActive ? "Die Demo läuft" : "Beispielsammlung",
                            hint: DemoMode.isActive
                                ? "Beim Beenden startet Plattenregal neu mit deiner eigenen Sammlung. Alles, was du in der Demo geändert hast, ist dann weg."
                                : "Rund 50 Platten in zwei Regalen, Wantlist und Wertverlauf. Alles lässt sich ändern, nichts wird gespeichert, deine Sammlung bleibt unberührt. Plattenregal startet dafür neu.") {
                    if DemoMode.isActive {
                        HStack(spacing: AppStyle.itemSpacing) {
                            GhostButton(title: "Neu starten") { DemoMode.restart() }
                            SecondaryButton(title: "Demo beenden") { DemoMode.end() }
                        }
                    } else {
                        SecondaryButton(title: "Demo starten …") { DemoMode.confirmStart() }
                    }
                }
            }
        }
    }
}

// MARK: - Darstellung

struct AppearanceSettingsView: View {
    @State private var preferences = AppPreferences.shared
    @AppStorage(DisplaySettings.collectionLayoutKey) private var collectionLayout = OverviewLayout.grid
    @AppStorage(DisplaySettings.wantlistLayoutKey) private var wantlistLayout = OverviewLayout.grid
    @AppStorage(DisplaySettings.coverSizeKey) private var storedCoverSize = DisplaySettings.defaultCoverSize
    @AppStorage(DisplaySettings.statisticsOrderKey) private var statisticsOrder = ""

    /// Always within the slider's range, even for an odd stored value, so
    /// slider and label never disagree.
    private var coverSize: Binding<Double> {
        Binding(get: { DisplaySettings.coverSize(storedCoverSize) },
                set: { storedCoverSize = DisplaySettings.coverSize($0) })
    }

    var body: some View {
        @Bindable var preferences = preferences
        SettingsPage {
            SettingsCard(title: "Erscheinungsbild") {
                SettingsRow(title: "Modus", hint: preferences.appearance.hint) {
                    Picker("Modus", selection: $preferences.appearance) {
                        ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                }
                Divider()
                SettingsRow(title: "Akzentfarbe", hint: preferences.accent.title) {
                    HStack(spacing: 6) {
                        ForEach(AccentChoice.allCases) { choice in
                            AccentSwatch(choice: choice, selected: preferences.accent == choice) {
                                withAnimation(AppStyle.quickAnimation) { preferences.accent = choice }
                            }
                        }
                    }
                }
            }
            SettingsCard(title: "Übersicht",
                         subtitle: "Lässt sich auch direkt in der Kopfleiste von Collection und Wantlist umschalten.") {
                SettingsRow(title: "Collection") { OverviewLayoutPicker(selection: $collectionLayout) }
                Divider()
                SettingsRow(title: "Wantlist") { OverviewLayoutPicker(selection: $wantlistLayout) }
            }
            SettingsCard(title: "Cover",
                         subtitle: "Die Spalten füllen die Fensterbreite immer ganz aus.") {
                SettingsRow(title: "Mindestgröße im Raster") {
                    HStack(spacing: AppStyle.tightSpacing) {
                        if coverSize.wrappedValue != DisplaySettings.defaultCoverSize {
                            IconButton(systemImage: "arrow.counterclockwise",
                                       help: "Auf Standard (\(Int(DisplaySettings.defaultCoverSize)) pt) zurücksetzen") {
                                storedCoverSize = DisplaySettings.defaultCoverSize
                            }
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                        }
                        Text("\(Int(coverSize.wrappedValue)) pt").monospacedDigit().foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    .animation(AppStyle.quickAnimation, value: coverSize.wrappedValue)
                }
                HStack(spacing: AppStyle.rowSpacing) {
                    Image(systemName: "square.fill").font(.caption2).foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Slider(value: coverSize, in: DisplaySettings.coverSizeRange, step: 5) {
                        Text("Mindestgröße der Cover")
                    }
                    .labelsHidden()
                    Image(systemName: "square.fill").font(.title3).foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            SettingsCard(title: "Statistik") {
                SettingsRow(title: "Reihenfolge der Abschnitte",
                            hint: "Abschnitte lassen sich auf der Statistikseite per Drag & Drop umsortieren.") {
                    SecondaryButton(title: "Zurücksetzen") { statisticsOrder = "" }
                        .disabled(StatisticsSection.ordered(from: statisticsOrder) == StatisticsSection.allCases)
                }
            }
        }
    }
}

private struct AccentSwatch: View {
    let choice: AccentChoice
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if choice == .system {
                    Circle().fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red], center: .center))
                } else {
                    Circle().fill(choice.color)
                }
                // Shadowed, so the mark stays visible on light swatches like yellow.
                if selected {
                    Circle().fill(.white).frame(width: 6, height: 6)
                        .shadow(color: .black.opacity(0.45), radius: 1)
                }
            }
            .frame(width: 18, height: 18)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.15)))
            .padding(3)
            .overlay(Circle().strokeBorder(selected ? choice.color : .clear, lineWidth: 2))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(choice.title)
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Discogs

struct DiscogsSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var accounts: [DiscogsAccount]
    @Query(sort: \DiscogsFolder.folderID) private var folders: [DiscogsFolder]
    @State private var model = DiscogsSettingsModel()
    @State private var sync = DiscogsSyncService.shared
    @State private var confirmingRemoval = false

    /// The account the stored token belongs to. After a successful test with
    /// a token for another account, the old account's tiles and folders are
    /// no longer shown (nil until the new one has been synced).
    private var account: DiscogsAccount? {
        if case .success(let name) = model.verified { return accounts.first { $0.username == name } }
        // Also after reopening: the account last synced with the stored token.
        if let fingerprint = model.storedFingerprint {
            if let match = accounts.first(where: { $0.credentialFingerprint == fingerprint }) { return match }
            // Accounts synced before fingerprints were kept can't be told apart.
            let current = DiscogsAccount.current(in: accounts)
            return current?.credentialFingerprint == nil ? current : nil
        }
        return DiscogsAccount.current(in: accounts)
    }
    /// A token is stored – or the keychain couldn't be read, in which case the
    /// sync itself reports the problem instead of silently locking the buttons.
    private var canSync: Bool { model.hasStoredToken || model.keychainUnreadable }

    var body: some View {
        @Bindable var model = model
        SettingsPage {
            SettingsCard(title: "Konto",
                         subtitle: DemoMode.isActive ? "Im Demo-Modus ist Discogs ausgeschaltet – Token und Synchronisierung sind gesperrt, dein gespeicherter Token wird nicht gelesen." : accountStatus) {
                SecureField("Persönlicher API-Token", text: $model.token)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .frame(height: AppStyle.controlHeight)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    .onSubmit { if canTest { model.startTest() } }
                    // The tested token replaces the field when the test ends.
                    .disabled(model.busy || DemoMode.isActive)
                HStack(spacing: AppStyle.itemSpacing) {
                    PrimaryButton(title: "Speichern & testen") { model.startTest() }
                        .disabled(!canTest || DemoMode.isActive)
                    if model.busy {
                        GhostButton(title: "Abbrechen") { model.cancelTest() }
                    }
                    if model.hasStoredToken {
                        GhostButton(title: "Token entfernen") { confirmingRemoval = true }
                            .disabled(model.busy || sync.isRunning)
                            .confirmationDialog("Token entfernen?", isPresented: $confirmingRemoval) {
                                Button("Entfernen", role: .destructive) { model.remove() }
                            } message: {
                                Text("Ohne Token kann nicht mehr mit Discogs synchronisiert werden. Deine Sammlung und die Standorte bleiben erhalten.")
                            }
                    }
                    if model.keychainUnreadable {
                        SecondaryButton(title: "Erneut lesen") { model.load() }
                            .disabled(model.busy)
                    }
                    if model.busy { ProgressView().controlSize(.small) }
                    Spacer()
                    Link("Token erstellen ↗", destination: URL(string: "https://www.discogs.com/settings/developers")!)
                        .font(.callout)
                }
                if !model.status.isEmpty {
                    AppBanner(message: model.status, kind: model.failed ? .error : .success)
                        .transition(AppStyle.funnelTransition())
                }
                if sync.isRunning {
                    SettingsNote("Während der Synchronisierung lässt sich der Token nicht ändern.")
                } else if model.hasUnsavedToken && !model.busy {
                    SettingsNote(model.hasStoredToken
                        ? "Der eingegebene Token ist noch nicht gespeichert – synchronisiert wird weiter mit dem gespeicherten."
                        : "Der eingegebene Token ist noch nicht gespeichert.")
                }
                SettingsNote("Der Token liegt ausschließlich im macOS-Schlüsselbund.")
            }
            .animation(AppStyle.standardAnimation, value: model.status)

            SettingsCard(title: "Synchronisierung",
                         subtitle: "Collection und Wantlist lassen sich auch auf ihrer Seite mit ⌘R oder durch Herunterziehen aktualisieren.") {
                if let account {
                    HStack(spacing: AppStyle.itemSpacing) {
                        let counts = counts(for: account.username)
                        syncTile("Collection", count: counts.collection,
                                 date: account.lastCollectionSync, systemImage: "square.stack")
                        syncTile("Wantlist", count: counts.wantlist,
                                 date: account.lastWantlistSync, systemImage: "heart.text.clipboard")
                    }
                }
                HStack(spacing: AppStyle.itemSpacing) {
                    PrimaryButton(title: "Alles synchronisieren") { start(.all) }
                    SecondaryButton(title: "Nur Collection") { start(.collection) }
                    SecondaryButton(title: "Nur Wantlist") { start(.wantlist) }
                }
                .disabled(sync.busy || model.busy || !canSync)
                if sync.hasStatus {
                    DiscogsSyncStatusView()
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(AppStyle.funnelTransition())
                }
            }
            .animation(AppStyle.standardAnimation, value: sync.hasStatus)

            let ownFolders = folders.filter { $0.owner == account?.username }
            if !ownFolders.isEmpty {
                SettingsCard(title: "Discogs-Ordner",
                             subtitle: "Ordner organisieren die Collection bei Discogs. Die Fächer im Regal sind davon unabhängig.") {
                    VStack(spacing: 0) {
                        ForEach(Array(ownFolders.enumerated()), id: \.element.key) { index, folder in
                            if index > 0 { Divider() }
                            HStack {
                                Text(folder.name)
                                Spacer()
                                Text(AppStyle.records(folder.count)).monospacedDigit().foregroundStyle(.secondary)
                                IconButton(systemImage: "arrow.triangle.2.circlepath", help: "Ordner „\(folder.name)“ synchronisieren") {
                                    sync.start(.folder(folder.folderID), container: context.container, expectedOwner: folder.owner)
                                }
                                .disabled(sync.busy || model.busy || !canSync)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }

            SettingsCard(title: "Hinweise", subtitle: "Speicherplatz und Cover-Cache stehen unter „Daten“.") {
                SettingsNote("Release-Daten werden bei jeder Synchronisierung aktualisiert; ältere Einträge lassen sich in der Detailansicht einzeln neu laden. Ohne Verbindung bleiben eigene Exemplar- und Standortdaten vollständig verfügbar.")
                SettingsNote("This application uses Discogs’ API but is not affiliated with, sponsored or endorsed by Discogs. ‘Discogs’ is a trademark of Zink Media, LLC.")
                Link("Discogs API-Nutzungsbedingungen ↗", destination: URL(string: "https://support.discogs.com/hc/en-us/articles/360009334593-API-Terms-of-Use")!)
                    .font(.callout)
            }
        }
        // Not on every activation: after a declined keychain prompt the window
        // becomes active again, which would ask again – over and over.
        .onAppear { model.loadIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .plattenregalDidReset)) { _ in model.forgetAfterReset() }
    }

    /// Not while anything talks to Discogs: a new token mid-download would
    /// switch accounts under the running sync or tracklist backfill.
    private var canTest: Bool {
        !model.busy && !sync.isRunning && !model.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    /// The last test wins over the last sync, so a new token for a different
    /// account doesn't keep showing the old name. Without a test in this
    /// session only the last sync is known – "connected" would be a guess.
    private var accountStatus: String {
        if model.keychainUnreadable { return "Schlüsselbund nicht lesbar" }
        guard model.hasStoredToken else { return "Kein Token gespeichert" }
        switch model.verified {
        case .success(let name): return "Verbunden als \(name)"
        case .failure: return "Token gespeichert · Die Verbindung zu Discogs hat nicht geklappt"
        case nil:
            if let fingerprint = model.storedFingerprint, fingerprint == sync.rejectedFingerprint {
                return "Token ungültig · Discogs hat ihn bei der letzten Synchronisierung abgelehnt"
            }
            return account.map { "Zuletzt synchronisiert als \($0.username)" } ?? "Token gespeichert · noch nicht synchronisiert"
        }
    }

    /// Counted in the store instead of loading every copy into the view;
    /// `libraryVersion` re-renders after each committed sync.
    private func counts(for owner: String) -> (collection: Int, wantlist: Int) {
        _ = sync.libraryVersion
        let collection = (try? context.fetchCount(FetchDescriptor<RecordCopy>(
            predicate: #Predicate { $0.discogsOwner == owner && $0.discogsActive == true }))) ?? 0
        let wantlist = (try? context.fetchCount(FetchDescriptor<WantlistEntry>(
            predicate: #Predicate { $0.owner == owner }))) ?? 0
        return (collection, wantlist)
    }

    private func start(_ scope: DiscogsSyncScope) { sync.start(scope, container: context.container) }

    private func syncTile(_ title: String, count: Int, date: Date?, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(AppStyle.accent)
                .frame(width: 28, height: 28)
                .background(AppStyle.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.headline)
                // Ticks along while the window stays open ("vor 2 Minuten" …).
                TimelineView(.everyMinute) { _ in
                    Text(AppStyle.records(count) + " · " + (date.map { "Stand \($0.formatted(.relative(presentation: .named)))" } ?? "noch nicht synchronisiert"))
                        .monospacedDigit()
                }
                .font(.caption).foregroundStyle(.secondary)
                .help(date?.formatted(date: .abbreviated, time: .shortened) ?? "")
            }
        }
        .padding(StatisticsLayout.tilePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: AppStyle.cardRadius))
    }
}

// MARK: - Export

struct ExportSettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var sync = DiscogsSyncService.shared
    @AppStorage(ExportSettings.formatKey) private var format = ExportFormat.csv
    @AppStorage(ExportSettings.sourceKey) private var source = ExportSource.collection
    @AppStorage(ExportSettings.orderKey) private var order = ExportOrder.shelf
    @AppStorage(ExportSettings.delimiterKey) private var delimiter = ExportDelimiter.semicolon
    @AppStorage(ExportSettings.groupsKey) private var storedGroups = ExportColumnGroup.location.rawValue
    @AppStorage(ShelfLabelStyle.key) private var labelStyle = ShelfLabelStyle.range
    @AppStorage(ScheduledExport.enabledKey) private var autoEnabled = false
    @AppStorage(ScheduledExport.intervalKey) private var autoInterval = ExportInterval.weekly
    @State private var scheduled = ScheduledExport.shared
    @State private var document: ExportDocument?
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
            SettingsCard(title: "Inhalt", subtitle: "Exportiert wird die Collection bzw. Wantlist des aktuellen Discogs-Kontos.") {
                SettingsRow(title: "Daten") {
                    segmented($source, ExportSource.allCases) { $0.title }
                }
                Divider()
                SettingsRow(title: "Format",
                            hint: format == .csv
                                ? "Für Numbers, Excel oder Google Sheets – mit den unten gewählten Spalten."
                                : "Druckfertige Liste im A4-Querformat: Interpret, Titel, Jahr, Label, Katalognummer und Format.") {
                    segmented($format, ExportFormat.allCases) { $0.title }
                }
                if source == .collection {
                    Divider()
                    SettingsRow(title: "Reihenfolge",
                                hint: order == .shelf
                                    ? "Fach für Fach, jeweils von vorne nach hinten; Platten ohne Fach am Ende."
                                    : "Nach Interpret und Titel, wie auf der Collection-Seite.") {
                        segmented($order, ExportOrder.allCases) { $0.title }
                    }
                }
            }

            if format == .csv {
                SettingsCard(title: "Spalten",
                             subtitle: "Interpret, Titel, Jahr, Label, Katalognummer, Format, Land, Genres und Stile sind immer enthalten.") {
                    let available = ExportColumnGroup.allCases.filter { $0.applies(to: source) }
                    ForEach(Array(available.enumerated()), id: \.element) { index, group in
                        if index > 0 { Divider() }
                        SettingsRow(title: group.title, hint: group.hint) {
                            Toggle(group.title, isOn: binding(for: group)).labelsHidden().toggleStyle(.switch)
                        }
                    }
                    Divider()
                    SettingsRow(title: "Trennzeichen", hint: "Excel mit deutschen Einstellungen erwartet Semikolons.") {
                        segmented($delimiter, ExportDelimiter.allCases) { $0.title }
                    }
                }
                .transition(AppStyle.funnelTransition())
            }

            SettingsCard(title: "Datei") {
                SettingsRow(title: AppStyle.records(total),
                            hint: sync.isRunning ? "Nach der laufenden Synchronisierung ist der Export vollständig." : nil) {
                    PrimaryButton(title: "Als \(format.title) exportieren …", action: export)
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
        .fileExporter(isPresented: $exporting, document: document, contentType: format.contentType,
                      defaultFilename: defaultFilename) { result in
            switch result {
            case .success(let url):
                status = ("Gespeichert als „\(url.lastPathComponent)“.", false)
                AppLog.info("Export", "\(format.title)-Export gespeichert (\(source.title), \(url.lastPathComponent))")
            case .failure(let error) where error.isUserCancellation:
                break
            case .failure(let error):
                status = (FileTransferError.writeFailed(error).reportedMessage(), true)
            }
            document = nil
        }
    }

    /// Re-counted after every committed sync.
    private var count: Int {
        _ = sync.libraryVersion
        return CollectionExportService(context: context).count(source)
    }

    private var defaultFilename: String {
        "Plattenregal \(source.title) \(ExportDate.day(.now))\(DemoMode.fileSuffix)"
    }

    private func export() {
        status = nil
        preparing = true
        Task {
            defer { preparing = false }
            do {
                let job = try settings.prepare(context: context, labelStyle: labelStyle)
                document = ExportDocument(data: try await job.renderedInBackground())
                AppLog.info("Export", "\(format.title)-Export erstellt: \(source.title), \(AppStyle.records(job.rows))")
                exporting = true
            } catch {
                status = (FileTransferError.exportFailed(error).reportedMessage(), true)
            }
        }
    }

    /// Writes the export on its own into a fixed folder, with the settings above.
    private var automaticCard: some View {
        let _ = scheduled.version
        let folder = ScheduledExport.folder.url
        return SettingsCard(title: "Automatisch exportieren",
                            subtitle: DemoMode.isActive
                                ? "In der Demo wird nicht automatisch exportiert. Über „Als … exportieren“ oben lässt sich die Beispielsammlung trotzdem als Datei sichern."
                                : "Schreibt den Export mit den Einstellungen oben regelmäßig in einen Ordner – z. B. in iCloud Drive. Die Datei „\(ScheduledExport.fileName(for: settings))“ wird dabei jedes Mal ersetzt.") {
            SettingsRow(title: "Automatisch exportieren") {
                Toggle("Automatisch exportieren", isOn: $autoEnabled).labelsHidden().toggleStyle(.switch)
                    .disabled(DemoMode.isActive)
            }
            if autoEnabled {
                Divider()
                SettingsRow(title: "Häufigkeit") {
                    segmented($autoInterval, ExportInterval.allCases) { $0.title }
                }
                Divider()
                SettingsRow(title: "Ordner", hint: folder.map(FolderAccess.displayName) ?? (ScheduledExport.folder.isSet
                                ? "Der gewählte Ordner ist nicht mehr erreichbar (verschoben, gelöscht oder Laufwerk getrennt). Bitte neu wählen."
                                : "Noch kein Ordner gewählt – ohne Ordner wird nichts exportiert.")) {
                    HStack(spacing: AppStyle.itemSpacing) {
                        if folder != nil {
                            IconButton(systemImage: "folder", help: "Im Finder zeigen") {
                                try? ScheduledExport.folder.withAccess { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
                            }
                            .foregroundStyle(.secondary)
                        }
                        SecondaryButton(title: folder == nil ? "Wählen …" : "Ändern …") { chooseExportFolder() }
                    }
                }
                Divider()
                SettingsRow(title: scheduled.lastRun.map { "Zuletzt \($0.formatted(.relative(presentation: .named)))" } ?? "Noch nicht exportiert",
                            hint: sync.busy ? "Nach der laufenden Synchronisierung."
                                : count == 0 ? "Ohne Platten wird nichts exportiert, damit keine leere Liste die letzte Datei ersetzt."
                                : scheduled.nextRun.map { $0 <= .now ? "Der nächste Export folgt in Kürze." : "Nächster Export \($0.formatted(date: .abbreviated, time: .shortened))." }) {
                    SecondaryButton(title: "Jetzt exportieren") {
                        Task {
                            do { autoStatus = ("Gespeichert als „\(try await scheduled.run(container: context.container))“.", false) }
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
                    AppBanner(message: "Der letzte automatische Export hat nicht geklappt. \(error)", kind: .warning)
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
    }

    private func chooseExportFolder() {
        guard let url = FolderPicker.choose(message: "Ordner für den automatischen Export") else { return }
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
        Picker("", selection: selection) {
            ForEach(values, id: \.self) { Text(title($0)).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
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

// MARK: - Sicherung

struct BackupSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.appearsActive) private var appearsActive
    @State private var sync = DiscogsSyncService.shared
    @State private var autoBackup = ShelfAutoBackup.shared
    @AppStorage(ShelfAutoBackup.enabledKey) private var autoEnabled = true
    @AppStorage(ShelfAutoBackup.keptCountKey) private var keptCount = ShelfAutoBackup.defaultKeptCount
    @AppStorage(ShelfAutoBackup.keptDaysKey) private var keptDays = ShelfAutoBackup.defaultKeptDays
    @State private var folderError: String?
    @State private var entries: [ShelfAutoBackup.Entry] = []
    /// The layout right now; read on reload, not on every redraw (it fetches every copy).
    @State private var current: ShelfBackup?
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
                    Picker("Letzte Stände", selection: $keptCount) {
                        ForEach(ShelfAutoBackup.keptCountOptions, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).fixedSize()
                    .disabled(DemoMode.isActive)
                }
                SettingsRow(title: "Tagesstände behalten", hint: "Der letzte Stand eines Tages – so verdrängt ein Tag mit vielen Änderungen nicht alle älteren Sicherungen.") {
                    Picker("Tagesstände", selection: $keptDays) {
                        ForEach(ShelfAutoBackup.keptDaysOptions, id: \.self) { Text($0 == 0 ? "Keine" : "\($0) Tage").tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    .disabled(DemoMode.isActive)
                }
                Divider()
                SettingsRow(title: "Speicherort", hint: autoBackup.usesCustomFolder
                            ? autoBackup.directory.map(FolderAccess.displayName)
                            : ShelfAutoBackup.folder.isSet
                                ? "Der gewählte Ordner ist nicht erreichbar – bis er wieder da ist oder ein anderer gewählt wird, sichert die App in ihren eigenen Ordner."
                                : "Im Ordner der App. Ein Ordner in iCloud Drive schützt die Belegung auch, wenn der Mac verloren geht.") {
                    HStack(spacing: AppStyle.itemSpacing) {
                        if ShelfAutoBackup.folder.isSet {
                            GhostButton(title: "Standard") { changeFolder(to: nil) }
                        }
                        SecondaryButton(title: "Ändern …") {
                            if let url = FolderPicker.choose(message: "Ordner für die automatischen Sicherungen der Fach-Belegung") { changeFolder(to: url) }
                        }
                    }
                }
                .disabled(DemoMode.isActive)
                if let folderError { AppBanner(message: folderError, kind: .error).transition(AppStyle.funnelTransition()) }
                if autoEnabled, let failure = autoBackup.lastFailure {
                    AppBanner(message: "Die automatische Sicherung um \(failure.formatted(date: .omitted, time: .shortened)) hat nicht geklappt. Sichere die Belegung zur Sicherheit mit „Sichern unter …“ in eine Datei.", kind: .warning)
                        .transition(AppStyle.funnelTransition())
                }
                if !entries.isEmpty {
                    Divider()
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
                if let directory = autoBackup.directory {
                    HStack {
                        GhostButton(title: "Im Finder zeigen") {
                            if autoBackup.usesCustomFolder {
                                try? ShelfAutoBackup.folder.withAccess { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
                            } else {
                                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                                NSWorkspace.shared.activateFileViewerSelecting([directory])
                            }
                        }
                        Spacer()
                    }
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
        .onChange(of: sync.libraryVersion) { reload() }
        .onChange(of: sync.shelvesVersion) { reload() }
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

    private func reload() {
        entries = autoBackup.entries()
        current = try? ShelfBackupService(context: context).makeBackup()
    }

    private func changeFolder(to url: URL?) {
        do {
            try autoBackup.moveBackups(to: url)
            folderError = nil
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
        do { pendingRestore = try ShelfBackupService(context: context).preview(backup) }
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
            sync.libraryDidChange()
            status = ("Belegung vom \(backup.createdAt.formatted(date: .abbreviated, time: .shortened)) wiederhergestellt.", false)
        } catch {
            status = (error.reportedMessage(), true)
        }
        reload()
    }
}

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
            case .locations: "Alle Standorte zurücksetzen?"
            case .settings: "Alle Einstellungen zurücksetzen?"
            case .everything: "Wirklich alles zurücksetzen?"
            }
        }
        var button: String {
            switch self {
            case .locations: "Standorte zurücksetzen"
            case .settings: "Einstellungen zurücksetzen"
            case .everything: "Alles löschen"
            }
        }
        var message: String {
            switch self {
            case .locations: "Alle Platten stehen danach ohne Fach, gesperrte Fächer werden freigegeben und „Nicht im Regal“ wird aufgehoben. Die Regale selbst bleiben. Die aktuelle Belegung wird vorher gesichert und lässt sich unter „Sicherung“ wiederherstellen."
            case .settings: "Darstellung, Startseite, Export und alle anderen Einstellungen gehen auf ihren Standard zurück. Sammlung, Regale, Standorte, der Discogs-Token sowie Speicherort und Aufbewahrung der Sicherungen bleiben."
            case .everything: "Sammlung, Wantlist, Statistik-Verlauf, zusätzliche Regale, Discogs-Konto samt Token, Cover und alle Einstellungen werden gelöscht – wie bei einer neuen Installation. Nur die Sicherungen der Fach-Belegung bleiben samt Speicherort und Aufbewahrung (eine aktuelle wird vorher geschrieben). Das lässt sich nicht rückgängig machen."
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
            SettingsCard(title: "Speicherplatz",
                         subtitle: sizes.covers == nil ? "Wird berechnet …" : "Die App belegt \(bytes(sizes.total)) auf diesem Mac.") {
                SettingsRow(title: "Sammlung", hint: DemoMode.isActive
                            ? "In der Demo liegt die Sammlung nur im Arbeitsspeicher."
                            : "Platten, Standorte, Wantlist und Statistik-Verlauf.") {
                    sizeLabel(sizes.database)
                }
                Divider()
                SettingsRow(title: "Cover-Cache", hint: "Cover werden bei Bedarf neu von Discogs geladen.") {
                    HStack(spacing: AppStyle.itemSpacing) {
                        sizeLabel(sizes.covers)
                        SecondaryButton(title: "Leeren", action: clearCovers)
                            .disabled(clearingCache || (sizes.covers ?? 0) == 0)
                    }
                }
                Divider()
                SettingsRow(title: "Sicherungen", hint: autoBackup.usesCustomFolder
                            ? "In \(autoBackup.directory.map(FolderAccess.displayName) ?? "–") – zählt nicht zum Platz der App."
                            : "Automatische Sicherungen der Fach-Belegung (siehe „Sicherung“).") {
                    sizeLabel(sizes.backups)
                }
                Divider()
                SettingsRow(title: "Protokoll", hint: DemoMode.isActive
                            ? "Das gemeinsame Protokoll der App – in der Demo lässt es sich nicht leeren."
                            : "Was die App wann getan hat – hilfreich, wenn etwas nicht klappt.") {
                    HStack(spacing: AppStyle.itemSpacing) {
                        sizeLabel(sizes.logs)
                        SecondaryButton(title: "Leeren") {
                            AppLog.clear()
                            Task { await updateSizes() }
                        }
                        .disabled((sizes.logs ?? 0) == 0 || DemoMode.isActive)
                    }
                }
                if let storageError { AppBanner(message: storageError, kind: .error).transition(AppStyle.funnelTransition()) }
            }
            .animation(AppStyle.standardAnimation, value: storageError)

            SettingsCard(title: "Diagnose") {
                SettingsRow(title: "Protokoll", hint: "Enthält nie den Discogs-Token.") {
                    HStack(spacing: AppStyle.itemSpacing) {
                        if let directory = AppLog.logDirectory {
                            GhostButton(title: "Im Finder zeigen") {
                                let file = AppLog.fileURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
                                NSWorkspace.shared.activateFileViewerSelecting([file ?? directory])
                            }
                        }
                        SecondaryButton(title: "Sichern unter …") {
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
                SettingsRow(title: "Discogs-Anfragen", hint: rateLimitHint) {
                    Text(rateLimitValue).monospacedDigit().foregroundStyle(.secondary)
                }
                if let throttled = rateLimit.lastThrottled, Date.now.timeIntervalSince(throttled) < 600 {
                    AppBanner(message: "Discogs hat um \(throttled.formatted(date: .omitted, time: .shortened)) gebremst, weil zu viele Anfragen kamen. Plattenregal wartet dann kurz und macht von selbst weiter.", kind: .info)
                }
            }
            .animation(AppStyle.standardAnimation, value: logStatus?.message)

            SettingsCard(title: "Zurücksetzen",
                         subtitle: sync.busy ? "Während der Synchronisierung lässt sich nichts zurücksetzen." : nil) {
                SettingsRow(title: "Standorte", hint: "Alle Platten aus den Fächern nehmen, Sperren aufheben.") {
                    SecondaryButton(title: "Zurücksetzen …") { pendingReset = .locations }
                }
                Divider()
                SettingsRow(title: "Einstellungen", hint: "Alle Einstellungen auf Standard, Daten bleiben.") {
                    SecondaryButton(title: "Zurücksetzen …") { pendingReset = .settings }
                }
                Divider()
                SettingsRow(title: "Alles", hint: "Wie eine neue Installation. Sicherungen der Belegung bleiben erhalten.") {
                    Button("Alles zurücksetzen …", role: .destructive) { pendingReset = .everything }
                        .buttonStyle(.bordered)
                }
                if resetting { ProgressView().controlSize(.small) }
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
                      defaultFilename: "Plattenregal Protokoll \(ExportDate.day(.now)).log") { result in
            switch result {
            case .success(let url): logStatus = ("Gespeichert als „\(url.lastPathComponent)“.", false)
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
        return rateLimit.limit.map { "\(remaining) von \($0) frei" } ?? "\(remaining) frei"
    }

    private var rateLimitHint: String {
        guard let last = rateLimit.lastRequest else {
            return "In dieser Sitzung noch keine Anfrage. Discogs erlaubt mit Token 60 Anfragen pro Minute."
        }
        let count = rateLimit.requests == 1 ? "1 Anfrage" : "\(rateLimit.requests) Anfragen"
        return "\(count) in dieser Sitzung, zuletzt \(last.formatted(date: .omitted, time: .standard)). Discogs zählt die Anfragen der letzten Minute."
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
            storageError = cleared ? nil : "Einige Cover ließen sich nicht löschen. Bitte versuche es noch einmal."
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
                resetStatus = ("Alle Standorte zurückgesetzt. Die vorherige Belegung liegt unter „Sicherung“.", false)
            } catch { resetStatus = (error.reportedMessage(), true) }
        case .settings:
            ResetService.resetSettings()
            resetStatus = ("Alle Einstellungen stehen wieder auf Standard.", false)
        case .everything:
            resetting = true
            Task {
                do {
                    try await service.resetEverything()
                    resetStatus = (DemoMode.isActive
                        ? "Die Beispielsammlung ist geleert. „Demo neu starten“ unter „Allgemein“ holt sie zurück."
                        : "Alles zurückgesetzt. Trage unter „Discogs“ einen Token ein, um neu zu beginnen.", false)
                } catch { resetStatus = (error.reportedMessage(), true) }
                resetting = false
                await updateSizes()
            }
        }
    }
}

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
    @FocusState private var stripFocused: Bool

    private var cabinet: Cabinet? { cabinets.first { $0.id == cabinetID } ?? cabinets.first }

    /// The labels sort every record's artist, so they're only recomputed when
    /// something they depend on changed – not on each click or animation frame.
    private var labelSignature: Int {
        var hasher = Hasher()
        hasher.combine(labelStyle)
        hasher.combine(sync.libraryVersion)
        hasher.combine(sync.shelvesVersion)
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
