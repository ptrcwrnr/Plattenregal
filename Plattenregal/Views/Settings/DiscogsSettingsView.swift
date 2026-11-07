import SwiftUI
import SwiftData

// MARK: - Discogs

struct DiscogsSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var accounts: [DiscogsAccount]
    @Query(sort: \DiscogsFolder.folderID) private var folders: [DiscogsFolder]
    @State private var model = DiscogsSettingsModel()
    @State private var sync = DiscogsSyncService.shared
    @State private var changes = LibraryChanges.shared
    @State private var confirmingRemoval = false
    @FocusState private var tokenFocused: Bool

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
            SettingsCard(title: String(localized: "Konto"),
                         subtitle: DemoMode.showsBanner ? String(localized: "Im Demo-Modus ist Discogs ausgeschaltet – Token und Synchronisierung sind gesperrt, dein gespeicherter Token wird nicht gelesen.") : accountStatus) {
                GlassTextField(placeholder: String(localized: "Persönlicher API-Token"), text: $model.token, secure: true,
                               onSubmit: { if canTest { model.startTest() } }, focus: $tokenFocused)
                    // Without a token (first start) the field is where to begin.
                    .onAppear { if !model.hasStoredToken && !DemoMode.isActive { tokenFocused = true } }
                    // The tested token replaces the field when the test ends.
                    .disabled(model.busy || DemoMode.showsBanner)
                HStack(spacing: AppStyle.itemSpacing) {
                    PrimaryButton(title: String(localized: "Speichern & testen")) { model.startTest() }
                        .disabled(!canTest || DemoMode.isActive)
                    if model.busy {
                        GhostButton(title: String(localized: "Abbrechen")) { model.cancelTest() }
                    }
                    if model.hasStoredToken {
                        GhostButton(title: String(localized: "Token entfernen")) { confirmingRemoval = true }
                            .disabled(model.busy || sync.isRunning)
                            .confirmationDialog("Token entfernen?", isPresented: $confirmingRemoval) {
                                Button("Entfernen", role: .destructive) { model.remove() }
                            } message: {
                                Text("Ohne Token kann nicht mehr mit Discogs synchronisiert werden. Deine Sammlung und die Standorte bleiben erhalten.")
                            }
                    }
                    if model.keychainUnreadable {
                        SecondaryButton(title: String(localized: "Erneut lesen")) { model.load() }
                            .disabled(model.busy)
                    }
                    if model.busy { ActivityRing(size: 14).transition(.opacity) }
                    Spacer()
                    Link("Token erstellen ↗", destination: URL(string: "https://www.discogs.com/settings/developers")!)
                        .font(.callout)
                        .appLinkButton()
                }
                if !model.status.isEmpty {
                    AppBanner(message: model.status, kind: model.failed ? .error : .success)
                        .transition(AppStyle.funnelTransition())
                }
                if sync.isRunning {
                    SettingsNote(String(localized: "Während der Synchronisierung lässt sich der Token nicht ändern."))
                } else if model.hasUnsavedToken && !model.busy {
                    SettingsNote(model.hasStoredToken
                        ? String(localized: "Der eingegebene Token ist noch nicht gespeichert – synchronisiert wird weiter mit dem gespeicherten.")
                        : String(localized: "Der eingegebene Token ist noch nicht gespeichert."))
                }
                SettingsNote(String(localized: "Der Token liegt ausschließlich im macOS-Schlüsselbund."))
            }
            .animation(AppStyle.standardAnimation, value: model.status)

            SettingsCard(title: String(localized: "Synchronisierung"),
                         subtitle: String(localized: "Collection und Wantlist lassen sich auch auf ihrer Seite mit ⌘R oder durch Herunterziehen aktualisieren.")) {
                // Like every other setting: what it is on the left, its button on the right.
                let counts = account.map { counts(for: $0.username) }
                syncRow(String(localized: "Collection"), count: counts?.collection, date: account?.lastCollectionSync,
                        accessibility: String(localized: "Collection synchronisieren")) { start(.collection) }
                Divider()
                syncRow(String(localized: "Wantlist"), count: counts?.wantlist, date: account?.lastWantlistSync,
                        accessibility: String(localized: "Wantlist synchronisieren")) { start(.wantlist) }
                Divider()
                SettingsRow(title: String(localized: "Beides"), hint: String(localized: "Collection und Wantlist nacheinander.")) {
                    PrimaryButton(title: String(localized: "Alles synchronisieren")) { start(.all) }
                        .disabled(!syncAvailable)
                }
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
                SettingsCard(title: String(localized: "Discogs-Ordner"),
                             subtitle: String(localized: "Ordner organisieren die Collection bei Discogs. Die Fächer im Regal sind davon unabhängig.")) {
                    VStack(spacing: 0) {
                        ForEach(Array(ownFolders.enumerated()), id: \.element.key) { index, folder in
                            if index > 0 { Divider() }
                            HStack {
                                Text(folder.name)
                                Spacer()
                                Text(AppStyle.records(folder.count)).monospacedDigit().foregroundStyle(.secondary)
                                IconButton(systemImage: "arrow.triangle.2.circlepath", help: String(localized: "Ordner „\(folder.name)“ synchronisieren")) {
                                    sync.start(.folder(folder.folderID), container: context.container, expectedOwner: folder.owner)
                                }
                                .disabled(sync.busy || model.busy || !canSync)
                            }
                            .padding(.vertical, AppStyle.hairSpacing)
                        }
                    }
                }
            }

            SettingsCard(title: String(localized: "Hinweise")) {
                SettingsNote(String(localized: "Release-Daten werden bei jeder Synchronisierung aktualisiert; die Tracklisten folgen danach im Hintergrund. Ohne Verbindung bleiben Sammlung und Standorte vollständig verfügbar."))
                SettingsNote("This application uses Discogs’ API but is not affiliated with, sponsored or endorsed by Discogs. ‘Discogs’ is a trademark of Zink Media, LLC.")
                Link("Discogs API-Nutzungsbedingungen ↗", destination: URL(string: "https://support.discogs.com/hc/en-us/articles/360009334593-API-Terms-of-Use")!)
                    .font(.callout)
                    .appLinkButton()
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
        if model.keychainUnreadable { return String(localized: "Schlüsselbund nicht lesbar") }
        guard model.hasStoredToken else { return String(localized: "Kein Token gespeichert") }
        switch model.verified {
        case .success(let name): return String(localized: "Verbunden als \(name)")
        case .failure: return String(localized: "Token gespeichert · Die Verbindung zu Discogs hat nicht geklappt")
        case nil:
            if let fingerprint = model.storedFingerprint, fingerprint == sync.rejectedFingerprint {
                return String(localized: "Token ungültig · Discogs hat ihn bei der letzten Synchronisierung abgelehnt")
            }
            return account.map { String(localized: "Zuletzt synchronisiert als \($0.username)") } ?? String(localized: "Token gespeichert · noch nicht synchronisiert")
        }
    }

    /// Counted in the store instead of loading every copy into the view;
    /// `libraryVersion` re-renders after each committed sync.
    private func counts(for owner: String) -> (collection: Int, wantlist: Int) {
        _ = changes.libraryVersion
        let collection = (try? context.fetchCount(FetchDescriptor<RecordCopy>(
            predicate: #Predicate { $0.discogsOwner == owner && $0.discogsActive == true }))) ?? 0
        let wantlist = (try? context.fetchCount(FetchDescriptor<WantlistEntry>(
            predicate: #Predicate { $0.owner == owner }))) ?? 0
        return (collection, wantlist)
    }

    private func start(_ scope: DiscogsSyncScope) { sync.start(scope, container: context.container) }

    /// Collection or Wantlist: how many and when last synced, ticking along
    /// while the window stays open ("vor 2 Minuten" …), the exact time as
    /// help; its own sync on the right.
    private func syncRow(_ title: String, count: Int?, date: Date?, accessibility: String, action: @escaping () -> Void) -> some View {
        TimelineView(.everyMinute) { _ in
            SettingsRow(title: title, hint: syncHint(count: count, date: date)) {
                SecondaryButton(title: String(localized: "Synchronisieren"), action: action)
                    .disabled(!syncAvailable)
                    .accessibilityLabel(accessibility)
            }
        }
        .help(date?.formatted(date: .abbreviated, time: .shortened) ?? "")
    }

    private func syncHint(count: Int?, date: Date?) -> String {
        let when = date.map { String(localized: "synchronisiert \($0.formatted(.relative(presentation: .named)))") }
            ?? String(localized: "noch nicht synchronisiert")
        guard let count else { return when.prefix(1).uppercased() + when.dropFirst() }
        return AppStyle.records(count) + " · " + when
    }

    /// Nothing runs and a token is there to sync with.
    private var syncAvailable: Bool { !sync.busy && !model.busy && canSync }
}
