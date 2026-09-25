import Foundation
import Observation
import SwiftData

@Observable final class MetadataRefreshService {
    var busy = false
    var error: String?
    func refresh(_ releases: [Release], context: ModelContext) async {
        guard !busy else { return }; busy = true; error = nil; defer { busy = false }
        let synced = releases.filter { !$0.isFresh && $0.basicInformation != nil }
        if !synced.isEmpty {
            DiscogsSyncService.shared.start(.collection, container: context.container)
        }
        for release in releases where !release.isFresh && release.basicInformation == nil {
            let id = release.discogsID
            do {
                let dto = try await DiscogsAPIClient.shared.release(id: id)
                guard !release.isDeleted else { continue }
                try PositionService(context: context).save { dto.apply(to: release) }
            } catch is CancellationError { return }
            catch { self.error = error.reportedMessage() }
        }
    }
}

extension MetadataRefreshService {
    /// Reloads the Discogs data of the given releases right away, fresh or
    /// not — for "Discogs-Daten aktualisieren" on selected records.
    func reload(_ releases: [Release], context: ModelContext) async {
        guard !busy else { return }; busy = true; error = nil
        defer { busy = false; LibraryChanges.shared.libraryDidChange() }
        var failed = 0, total = 0
        var reason: String?
        AppLog.info("Discogs", "Release-Daten neu laden: \(releases.count) Release(s)")
        for release in releases {
            let id = release.discogsID
            total += 1
            do {
                let dto = try await DiscogsAPIClient.shared.release(id: id)
                guard !release.isDeleted else { continue }
                try PositionService(context: context).save { dto.apply(to: release) }
            } catch is CancellationError { return }
            catch { failed += 1; reason = error.reportedMessage() }
        }
        // One message for the whole selection, saying how much went through.
        if failed > 0, let reason {
            error = total == 1 ? reason
                : failed == total ? "Keine der \(total) Platten konnte aktualisiert werden. " + reason
                : "\(failed) von \(total) Platten konnten nicht aktualisiert werden, die übrigen schon. " + reason
        }
    }
}

@Observable final class DiscogsSettingsModel {
    var token = ""
    var status = ""
    var busy = false
    var failed = false
    /// Whether a token is in the keychain (not just typed into the field).
    private(set) var hasStoredToken = false
    /// The keychain couldn't be read: whether a token is stored is unknown,
    /// so nothing may claim "no token" or lock the sync buttons.
    private(set) var keychainUnreadable = false
    /// Result of the last connection test: the Discogs user it answered for,
    /// or the error; `nil` when not tested since the token last changed.
    private(set) var verified: Result<String, Error>?
    /// Fingerprint of the stored token, to find the account it was synced
    /// with (`DiscogsAccount.credentialFingerprint`); `nil` without a token.
    private(set) var storedFingerprint: String?
    /// The token in the keychain, to tell whether the field holds something unsaved.
    private var storedToken = ""
    private var testTask: Task<Void, Never>?
    private var loaded = false
    private let keychainLoad: () throws -> String?
    private let keychainStore: (String) throws -> Void
    private let testToken: (String) async throws -> String
    private let isSyncRunning: () -> Bool
    private let tokenAccepted: (String) -> Void
    private let tokenChanged: () -> Void

    init(keychainLoad: @escaping () throws -> String? = { try KeychainStore.load() },
         keychainStore: @escaping (String) throws -> Void = { try KeychainStore.store($0) },
         testToken: ((String) async throws -> String)? = nil,
         isSyncRunning: (() -> Bool)? = nil,
         tokenAccepted: ((String) -> Void)? = nil,
         tokenChanged: (() -> Void)? = nil) {
        self.keychainLoad = keychainLoad
        self.keychainStore = keychainStore
        // A separate client that only knows the typed token, so it can be
        // checked before it replaces the stored one.
        self.testToken = testToken ?? { token in try await DiscogsAPIClient.quickTest(token) }
        self.isSyncRunning = isSyncRunning ?? { DiscogsSyncService.shared.isRunning }
        self.tokenAccepted = tokenAccepted ?? { DiscogsSyncService.shared.tokenAccepted(fingerprint: $0) }
        self.tokenChanged = tokenChanged ?? { DiscogsSyncService.shared.tokenChanged() }
    }

    /// Reads the keychain once; switching settings tabs keeps what was typed.
    /// A failed read is retried the next time the page appears.
    func loadIfNeeded() {
        guard !loaded else { return }
        load()
    }
    /// After "Alles zurücksetzen": the token is gone, so is any test result.
    func forgetAfterReset() {
        verified = nil; status = ""; failed = false
        load()
    }
    func load() {
        do {
            token = try keychainLoad() ?? ""
            storedToken = token
            hasStoredToken = !token.isEmpty
            storedFingerprint = hasStoredToken ? DiscogsAPIClient.fingerprint(of: token) : nil
            loaded = true
            if keychainUnreadable { keychainUnreadable = false; status = ""; failed = false }
        } catch {
            keychainUnreadable = true
            status = error.reportedMessage(); failed = true
        }
    }
    @discardableResult private func persist(_ value: String) -> Bool {
        do {
            try keychainStore(value)
            token = value; storedToken = value
            hasStoredToken = !value.isEmpty
            storedFingerprint = hasStoredToken ? DiscogsAPIClient.fingerprint(of: value) : nil
            keychainUnreadable = false; loaded = true
            verified = nil
            tokenChanged()
            AppLog.info("Token", hasStoredToken ? "Neuer Token im Schlüsselbund gespeichert" : "Token aus dem Schlüsselbund entfernt")
            status = hasStoredToken ? "Token sicher gespeichert." : "Token entfernt."
            failed = false; return true
        } catch { status = error.reportedMessage(); failed = true; return false }
    }
    /// The field holds a token that isn't the stored one (syncs still use the stored one).
    var hasUnsavedToken: Bool {
        let typed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return !typed.isEmpty && typed != storedToken
    }
    /// Runs the test so it can be cancelled from the settings. `busy` is set
    /// right here, not once the task runs: a quick second click must not
    /// start another task and leave "Abbrechen" pointing at the wrong one.
    func startTest() {
        guard let candidate = beginTest() else { return }
        testTask = Task { await runTest(candidate) }
    }
    func cancelTest() {
        testTask?.cancel()
    }
    /// The field is only cleared once the keychain entry is really gone.
    func remove() { persist("") }
    /// Tests the typed token before it replaces the stored one: a token Discogs
    /// rejects never overwrites a working one. When Discogs just can't be
    /// reached, the token is saved anyway so it can be entered offline.
    func test() async {
        guard let candidate = beginTest() else { return }
        await runTest(candidate)
    }
    /// The trimmed token to test, with `busy` set; `nil` if nothing to test.
    private func beginTest() -> String? {
        let candidate = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, !candidate.isEmpty else { return nil }
        guard DiscogsAPIClient.isWellFormedToken(candidate) else {
            // Not even sent: the stored token stays untouched.
            status = "Der Token enthält Leerzeichen, Zeilenumbrüche oder Sonderzeichen. Kopiere ihn noch einmal vollständig von Discogs und füge ihn neu ein."
                + (hasStoredToken ? " Der bisher gespeicherte Token bleibt erhalten." : "")
            failed = true; verified = nil
            AppLog.warning("Token", "Eingegebener Token hat ungültige Zeichen, nicht getestet")
            return nil
        }
        busy = true
        return candidate
    }
    private func runTest(_ candidate: String) async {
        defer { busy = false; testTask = nil }
        do {
            let name = try await testToken(candidate)
            guard !syncStartedMeanwhile(), persist(candidate) else { return }
            status = "Verbunden als \(name)"; failed = false
            verified = .success(name)
            AppLog.info("Token", "Verbindungstest erfolgreich, Konto \(name)")
            // Discogs accepts it now: an earlier rejection no longer applies.
            if let storedFingerprint { tokenAccepted(storedFingerprint) }
        } catch DiscogsError.unauthorized {
            reject(.unauthorized)
        } catch DiscogsError.forbidden {
            reject(.forbidden)
        } catch let error where Task.isCancelled || error is CancellationError {
            // Stopped by "Abbrechen" (a cancelled request can also surface as
            // a network error): nothing saved, the stored token stays.
            AppLog.info("Token", "Verbindungstest abgebrochen")
            status = ""; failed = false
        } catch {
            guard !syncStartedMeanwhile(), persist(candidate) else { return }
            status = error.reportedMessage(); failed = true; verified = .failure(error)
        }
    }
    /// A sync started while the test ran (e.g. ⌘R in the main window) must not
    /// get a different token under its feet; it would fail with "account changed".
    private func syncStartedMeanwhile() -> Bool {
        guard isSyncRunning() else { return false }
        AppLog.warning("Token", "Neuer Token nicht gespeichert: während des Tests wurde eine Synchronisierung gestartet")
        status = "Während einer Synchronisierung lässt sich der Token nicht ändern. Bitte teste ihn danach noch einmal."
        failed = true
        return true
    }
    /// Discogs turned the typed token down; the stored one stays untouched.
    private func reject(_ error: DiscogsError) {
        status = error.reportedMessage() + (hasStoredToken ? " Der bisher gespeicherte Token bleibt erhalten." : "")
        failed = true
    }
}
