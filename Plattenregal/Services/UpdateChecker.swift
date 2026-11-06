import AppKit
import Foundation

// MARK: - Version numbers

/// A version number such as "1.0.2", compared part by part: "1.0.10" is newer
/// than "1.0.9", and "1.1" is the same as "1.1.0". A leading "v" (the tags on
/// GitHub) and a suffix such as "-beta" or "+5" are ignored.
nonisolated struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    let parts: [Int]

    init?(_ text: String) {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        if let cut = text.firstIndex(where: { $0 == "-" || $0 == "+" || $0 == " " }) { text = String(text[..<cut]) }
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(pieces.count) else { return nil }
        var parts: [Int] = []
        for piece in pieces {
            // ASCII digits only: Swift also counts "١" or "½" as numbers.
            guard (1...6).contains(piece.count), piece.allSatisfy({ ("0"..."9").contains($0) }),
                  let number = Int(piece) else { return nil }
            parts.append(number)
        }
        self.parts = parts
    }

    /// The version of this app, from the bundle (`MARKETING_VERSION`).
    static var current: AppVersion? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
    }

    private static func padded(_ a: AppVersion, _ b: AppVersion) -> ([Int], [Int]) {
        let count = max(a.parts.count, b.parts.count)
        return (a.parts + Array(repeating: 0, count: count - a.parts.count),
                b.parts + Array(repeating: 0, count: count - b.parts.count))
    }
    static func == (a: AppVersion, b: AppVersion) -> Bool { let (x, y) = padded(a, b); return x == y }
    static func < (a: AppVersion, b: AppVersion) -> Bool { let (x, y) = padded(a, b); return x.lexicographicallyPrecedes(y) }

    var description: String { parts.map(String.init).joined(separator: ".") }
}

// MARK: - What GitHub says

/// The newest published version on GitHub, checked and ready to show.
nonisolated struct AvailableRelease: Equatable, Sendable {
    let version: AppVersion
    /// The release page on GitHub, with all notes.
    let pageURL: URL
    /// The DMG; `nil` when the release has none, then the page is offered.
    let downloadURL: URL?
    /// Size of the DMG in bytes, when GitHub tells it.
    let downloadSize: Int?
    let publishedAt: Date?
    /// The release notes as written on GitHub (Markdown, German, then `---`, then English).
    let notes: String

    /// The points under "Neu in …" in the language of the app.
    var highlights: [String] {
        ReleaseNotes.highlights(in: notes, english: Bundle.main.preferredLocalizations.first == "en")
    }
}

/// The release notes on GitHub are written German first, then a line `---`,
/// then the same in English. Each part begins with "**Neu in 1.0.1**" and a
/// list of points; installing instructions follow. The update window shows
/// only that first list – it has its own short instructions.
nonisolated enum ReleaseNotes {
    static let maximumCount = 12

    static func highlights(in notes: String, english: Bool) -> [String] {
        let lines = notes.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var parts: [[String]] = [[]]
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "***" || trimmed == "___" { parts.append([]) } else { parts[parts.count - 1].append(line) }
        }
        let filled = parts.filter { $0.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard let first = filled.first else { return [] }
        // The list under "Neu in …" / "New in …", wherever the rules are; without
        // such a heading the first part is German, the second English.
        let heading = english ? "new in" : "neu in"
        var part = english && filled.count > 1 ? filled[1] : first
        var start = 0
        search: for candidate in filled {
            for (index, line) in candidate.enumerated() where isHeading(line, heading) {
                part = candidate
                start = index + 1
                break search
            }
        }
        var items: [String] = []
        for line in part[start...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let item = bullet(trimmed) {
                items.append(item)
            } else if !items.isEmpty, !trimmed.isEmpty {
                // An indented line goes on with the point above (also after a
                // blank line, as Markdown allows); anything else ends the list.
                guard line.first == " " || line.first == "\t" else { break }
                items[items.count - 1] += " " + trimmed
            }
        }
        return Array(items.prefix(maximumCount))
    }

    /// "**Neu in 1.0.2**", "## New in 1.0.2", "Neu in 1.0.2:" – not "Neu installieren".
    private static func isHeading(_ line: String, _ heading: String) -> Bool {
        let words = line.trimmingCharacters(in: CharacterSet(charactersIn: "*_#: \t")).lowercased()
        return words == heading || words.hasPrefix(heading + " ")
    }

    private static func bullet(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            let item = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
            return item.isEmpty ? nil : item
        }
        return nil
    }
}

/// Everything that can go wrong while asking GitHub, in words for the user.
nonisolated enum UpdateCheckError: LocalizedError, Equatable, Sendable {
    /// The Mac has no internet connection.
    case offline
    /// GitHub couldn't be reached (name not found, connection refused).
    case unreachable
    case timedOut
    /// TLS failed: wrong clock, or a network that redirects (hotel Wi-Fi).
    case insecureConnection
    /// Too many requests from this network; minutes until GitHub takes more, if known.
    case rateLimited(minutes: Int?)
    /// No published release (404).
    case noRelease
    case server(Int)
    case refused(Int)
    /// Not the answer expected – often a login page of a public network.
    case invalidResponse

    var title: String {
        switch self {
        case .offline: String(localized: "Keine Internetverbindung")
        case .unreachable: String(localized: "GitHub ist nicht erreichbar")
        case .timedOut: String(localized: "Keine Antwort von GitHub")
        case .insecureConnection: String(localized: "Keine sichere Verbindung")
        case .rateLimited: String(localized: "Gerade zu viele Anfragen")
        case .noRelease: String(localized: "Keine Version gefunden")
        case .server: String(localized: "Problem bei GitHub")
        case .refused: String(localized: "Anfrage abgelehnt")
        case .invalidResponse: String(localized: "Unerwartete Antwort")
        }
    }

    var errorDescription: String? {
        switch self {
        case .offline: String(localized: "Der Mac ist gerade nicht mit dem Internet verbunden. Prüfe WLAN oder Kabel und versuche es noch einmal.")
        case .unreachable: String(localized: "GitHub, wo die Versionen von Plattenregal liegen, ist gerade nicht erreichbar. Prüfe deine Internetverbindung und versuche es später noch einmal.")
        case .timedOut: String(localized: "GitHub hat nicht rechtzeitig geantwortet. Vielleicht ist die Verbindung gerade langsam – versuche es gleich noch einmal.")
        case .insecureConnection: String(localized: "Die sichere Verbindung zu GitHub ließ sich nicht aufbauen. Prüfe, ob Datum und Uhrzeit des Macs stimmen. In manchen Netzen, etwa im WLAN eines Hotels, musst du dich zuerst im Browser anmelden.")
        case .rateLimited(let minutes?) where minutes > 1:
            String(localized: "GitHub hat aus deinem Netzwerk gerade zu viele Anfragen bekommen. Versuche es in etwa \(minutes) Minuten noch einmal.")
        case .rateLimited(.some):
            String(localized: "GitHub hat aus deinem Netzwerk gerade zu viele Anfragen bekommen. Versuche es in etwa einer Minute noch einmal.")
        case .rateLimited(nil):
            String(localized: "GitHub hat aus deinem Netzwerk gerade zu viele Anfragen bekommen. Versuche es in ein paar Minuten noch einmal.")
        case .noRelease: String(localized: "Auf GitHub ist gerade keine Version von Plattenregal veröffentlicht. Versuche es später noch einmal.")
        case .server(let code): String(localized: "Bei GitHub gibt es gerade ein Problem (Fehler \(code)). Versuche es später noch einmal.")
        case .refused(let code): String(localized: "GitHub hat die Anfrage abgelehnt (Fehler \(code)). Versuche es später noch einmal.")
        case .invalidResponse: String(localized: "GitHub hat eine Antwort geschickt, mit der Plattenregal nichts anfangen kann. Verlangt dein Netzwerk eine Anmeldung, etwa im WLAN eines Hotels, melde dich zuerst im Browser an. Sonst versuche es später noch einmal.")
        }
    }

}

extension UpdateCheckError: UserFacingError {}

// MARK: - Asking GitHub

/// Asks GitHub for the newest published release of Plattenregal. Without an
/// account: the public interface allows 60 requests an hour per network,
/// far more than one check a day. Nothing about the user or the collection
/// is sent – only the app's name and version as the User-Agent.
nonisolated struct UpdateService: Sendable {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let latestReleaseURL = URL(string: "https://api.github.com/repos/ptrcwrnr/Plattenregal/releases/latest")!
    /// Shown when the release itself names no page of its own.
    static let releasesPageURL = URL(string: "https://github.com/ptrcwrnr/Plattenregal/releases/latest")!
    /// A release answer is a few kilobytes; anything far larger isn't one.
    static let maximumResponseSize = 2_000_000

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        // Report "offline" at once instead of waiting for a connection.
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private let fetch: Fetch

    init(fetch: Fetch? = nil) {
        self.fetch = fetch ?? { request in try await Self.session.data(for: request) }
    }

    func latestRelease(now: Date = .now) async throws -> AvailableRelease {
        var request = URLRequest(url: Self.latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("Plattenregal/\(AppVersion.current?.description ?? "?") (macOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        let data: Data, response: URLResponse
        do { (data, response) = try await fetch(request) }
        catch let error as URLError { throw Self.error(for: error) }
        catch is CancellationError { throw CancellationError() }
        catch { throw UpdateCheckError.unreachable }
        return try Self.release(from: data, response: response, now: now)
    }

    /// What a failed connection means for the user.
    static func error(for error: URLError) -> any Error {
        switch error.code {
        case .cancelled:
            return CancellationError()
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
            return UpdateCheckError.offline
        case .timedOut:
            return UpdateCheckError.timedOut
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .clientCertificateRejected, .clientCertificateRequired, .appTransportSecurityRequiresSecureConnection:
            return UpdateCheckError.insecureConnection
        case .badServerResponse, .cannotParseResponse, .cannotDecodeRawData, .cannotDecodeContentData, .zeroByteResource,
             .httpTooManyRedirects, .redirectToNonExistentLocation, .dataLengthExceedsMaximum:
            return UpdateCheckError.invalidResponse
        default:
            return UpdateCheckError.unreachable
        }
    }

    /// Reads GitHub's answer; every status and every broken field is checked.
    static func release(from data: Data, response: URLResponse, now: Date = .now) throws -> AvailableRelease {
        guard let http = response as? HTTPURLResponse else { throw UpdateCheckError.invalidResponse }
        switch http.statusCode {
        case 200...299: break
        case 404: throw UpdateCheckError.noRelease
        case 403, 429:
            if http.statusCode == 429 || http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0"
                || http.value(forHTTPHeaderField: "Retry-After") != nil {
                throw UpdateCheckError.rateLimited(minutes: waitingMinutes(http, now: now))
            }
            throw UpdateCheckError.refused(http.statusCode)
        case 500...599: throw UpdateCheckError.server(http.statusCode)
        default: throw UpdateCheckError.refused(http.statusCode)
        }
        guard data.count <= maximumResponseSize,
              let dto = try? JSONDecoder().decode(GitHubReleaseDTO.self, from: data) else { throw UpdateCheckError.invalidResponse }
        // "latest" never names a draft or a pre-release; if it did, it isn't for everyone yet.
        guard dto.draft != true, dto.prerelease != true else { throw UpdateCheckError.noRelease }
        guard let version = AppVersion(dto.tag_name) else { throw UpdateCheckError.invalidResponse }
        let assets = (dto.assets ?? []).filter {
            $0.name != nil && ($0.state ?? "uploaded") == "uploaded" && gitHubURL($0.browser_download_url) != nil
        }
        let lowered = { (asset: GitHubReleaseDTO.Asset) in (asset.name ?? "").lowercased() }
        let dmg = assets.first { lowered($0) == "plattenregal.dmg" }
            ?? assets.first { lowered($0) == "plattenregal-\(version).dmg" }
            ?? assets.first { lowered($0).hasSuffix(".dmg") }
        return AvailableRelease(
            version: version,
            pageURL: gitHubURL(dto.html_url) ?? releasesPageURL,
            downloadURL: dmg.flatMap { gitHubURL($0.browser_download_url) },
            downloadSize: dmg?.size.flatMap { $0 > 0 ? $0 : nil },
            publishedAt: dto.published_at.flatMap { try? Date.ISO8601FormatStyle().parse($0) },
            notes: dto.body ?? "")
    }

    /// Only GitHub's own pages and downloads are opened, over HTTPS.
    static func gitHubURL(_ text: String?) -> URL? {
        guard let text, let url = URL(string: text), url.scheme?.lowercased() == "https",
              url.host()?.lowercased() == "github.com" else { return nil }
        return url
    }

    /// GitHub names when it takes requests again: a time (`X-RateLimit-Reset`,
    /// seconds since 1970) or a pause (`Retry-After`, seconds). In minutes,
    /// rounded up, at most an hour – the window GitHub counts in.
    private static func waitingMinutes(_ http: HTTPURLResponse, now: Date) -> Int? {
        let seconds: Double
        if let reset = http.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap({ Double($0.trimmingCharacters(in: .whitespaces)) }) {
            seconds = reset - now.timeIntervalSince1970
        } else if let pause = http.value(forHTTPHeaderField: "Retry-After").flatMap({ Double($0.trimmingCharacters(in: .whitespaces)) }) {
            seconds = pause
        } else { return nil }
        guard seconds.isFinite else { return nil }
        return min(max(1, Int((seconds / 60).rounded(.up))), 60)
    }
}

/// The fields of GitHub's release answer that Plattenregal reads.
nonisolated struct GitHubReleaseDTO: Decodable {
    /// Lenient: one odd file at the release doesn't spoil the whole answer.
    struct Asset: Decodable {
        let name: String?
        let browser_download_url: String?
        let size: Int?
        let state: String?
    }
    let tag_name: String
    let html_url: String?
    let body: String?
    let draft: Bool?
    let prerelease: Bool?
    let published_at: String?
    let assets: [Asset]?
}

// MARK: - How often

/// How often Plattenregal asks GitHub by itself (Einstellungen → Allgemein →
/// Updates); weekly by default. Up to 1.0.3 it was a switch for once a day:
/// on became weekly, off became never (see `AppPreferences`).
nonisolated enum UpdateCheckInterval: String, CaseIterable, Identifiable, Sendable {
    case never, weekly, monthly
    var id: Self { self }
    var title: String {
        switch self {
        case .never: String(localized: "Nie")
        case .weekly: String(localized: "Wöchentlich")
        case .monthly: String(localized: "Monatlich")
        }
    }
    var hint: String {
        switch self {
        case .never: String(localized: "Plattenregal sucht nicht von selbst. „Jetzt prüfen“ fragt sofort bei GitHub nach.")
        case .weekly: String(localized: "Fragt einmal in der Woche bei GitHub nach, ob es eine neue Version gibt, und zeigt sie dann. Dabei wird nichts über dich oder deine Sammlung übertragen.")
        case .monthly: String(localized: "Fragt einmal im Monat bei GitHub nach, ob es eine neue Version gibt, und zeigt sie dann. Dabei wird nichts über dich oder deine Sammlung übertragen.")
        }
    }
    /// When the next automatic check is due after the last one; `nil` for never.
    /// By the calendar: a week is seven days, a month the same day next month.
    func next(after lastCheck: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .never: nil
        case .weekly: calendar.date(byAdding: .day, value: 7, to: lastCheck)
        case .monthly: calendar.date(byAdding: .month, value: 1, to: lastCheck)
        }
    }
}

// MARK: - The check in the app

/// "Nach Updates suchen …": on request from the app menu or the settings, and
/// – as often as set (`UpdateCheckInterval`) – on its own. A newer version opens the
/// update window (`UpdateView`); downloading and installing stay with the
/// user: the browser loads the DMG, the new app is dragged to „Programme“.
///
/// The automatic check is quiet: it never shows an error, tries again an hour
/// later, skips a version the user chose to skip, and waits with its window
/// while Plattenregal runs in the background or another app is in front.
@Observable final class UpdateChecker {
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle
        case checking
        case upToDate(latest: AppVersion)
        case available(AvailableRelease)
        case failed(UpdateCheckError)
    }

    enum Key {
        static let lastCheck = "updateLastCheck"
        static let skippedVersion = "updateSkippedVersion"
    }

    /// The schedule looks every hour whether a check is due
    /// (`UpdateCheckInterval`), so a failed check is tried again an hour later.
    static let scheduleStep: Duration = .seconds(60 * 60)
    /// After launching, so the check doesn't compete with opening the collection.
    static let launchDelay: Duration = .seconds(10)
    /// A check shows "Suche …" at least this long, so the answer doesn't flash.
    static let minimumCheckingTime: Duration = .milliseconds(600)

    /// What the update window shows.
    private(set) var state: State = .idle
    /// The last check that got an answer from GitHub.
    private(set) var lastCheck: Date?
    let currentVersion: AppVersion

    /// Opens the update window; handed over by the main window (see `ReleasedInBackground`).
    @ObservationIgnored var openWindow: (() -> Void)?

    @ObservationIgnored private let service: UpdateService
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let interval: () -> UpdateCheckInterval
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var inFlight: Task<Result<AvailableRelease, any Error>, Never>?
    @ObservationIgnored private var manualCheck: Task<Void, Never>?
    @ObservationIgnored private var manualCheckID: UUID?
    @ObservationIgnored private var schedule: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// A newer version the automatic check found while the window couldn't open.
    @ObservationIgnored private var announcementPending = false

    init(service: UpdateService = UpdateService(), defaults: UserDefaults = AppDefaults.store,
         currentVersion: AppVersion? = .current,
         interval: @escaping () -> UpdateCheckInterval = { AppPreferences.shared.updateCheckInterval },
         now: @escaping () -> Date = { .now }) {
        self.service = service
        self.defaults = defaults
        // Without a readable version every release counts as newer – better
        // than never offering one.
        self.currentVersion = currentVersion ?? AppVersion("0")!
        self.interval = interval
        self.now = now
        lastCheck = defaults.object(forKey: Key.lastCheck) as? Date
    }

    /// The version the user chose to skip; the automatic check stays quiet about it.
    var skippedVersion: AppVersion? { defaults.string(forKey: Key.skippedVersion).flatMap(AppVersion.init) }

    /// A newer version is known and not skipped – for the record's menu in the menu bar.
    var announcedRelease: AvailableRelease? {
        guard case .available(let release) = state, release.version != skippedVersion else { return nil }
        return release
    }

    // MARK: Checking

    /// "Nach Updates suchen …": the window shows "Suche …", then the answer.
    /// A check already under way is joined, not started twice.
    func checkNow() {
        guard manualCheck == nil else { return }
        state = .checking
        let started = ContinuousClock.now
        let id = UUID()
        manualCheckID = id
        manualCheck = Task {
            let result = await fetchLatest()
            // Shown at least briefly; cancelling skips the wait.
            try? await Task.sleep(until: started + Self.minimumCheckingTime, clock: .continuous)
            // Cancelled meanwhile, maybe with a new check started: not this one's answer to show.
            guard manualCheckID == id, !Task.isCancelled else { return }
            apply(result, manual: true)
            manualCheck = nil
            manualCheckID = nil
        }
    }

    /// Stops waiting for a check the user started (the window's „Abbrechen“).
    func cancelCheck() {
        manualCheck?.cancel()
        manualCheck = nil
        manualCheckID = nil
        inFlight?.cancel()
        if state == .checking { state = .idle }
    }

    /// Whether the automatic check should ask GitHub now.
    func isAutomaticCheckDue() -> Bool {
        let interval = interval()
        guard interval != .never else { return false }
        guard let lastCheck else { return true }
        let now = now()
        // A date in the future: the clock was wrong or set back – check.
        if now < lastCheck { return true }
        guard let next = interval.next(after: lastCheck) else { return false }
        return now >= next
    }

    /// One automatic check, if due. Errors only go to the protocol.
    func runAutomaticCheckIfDue() async {
        guard isAutomaticCheckDue(), manualCheck == nil else { return }
        apply(await fetchLatest(), manual: false)
    }

    /// One request at a time; a second caller waits for the same answer –
    /// unless that request was just cancelled (‚Abbrechen‘, then checking again).
    private func fetchLatest() async -> Result<AvailableRelease, any Error> {
        if let inFlight, !inFlight.isCancelled {
            let result = await inFlight.value
            // Cancelled for the one who started it (the schedule restarting
            // after the setting changed), not for this caller: ask anew.
            guard case .failure(let error) = result, error.isUserCancellation, !Task.isCancelled else { return result }
        }
        let service = service
        let date = now()
        let task = Task.detached { () -> Result<AvailableRelease, any Error> in
            do { return .success(try await service.latestRelease(now: date)) } catch { return .failure(error) }
        }
        inFlight = task
        let result = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        // A newer request may have taken its place meanwhile.
        if inFlight == task { inFlight = nil }
        return result
    }

    private func apply(_ result: Result<AvailableRelease, any Error>, manual: Bool) {
        switch result {
        case .success(let release):
            lastCheck = now()
            defaults.set(lastCheck, forKey: Key.lastCheck)
            // Switched off while the check was under way: nothing to show for it.
            guard manual || interval() != .never else { return }
            let how = manual ? "Von Hand" : "Automatisch"
            if release.version > currentVersion {
                state = .available(release)
                AppLog.info("Update", "\(how) geprüft: \(release.version) ist da (installiert \(currentVersion))")
                if !manual {
                    if release.version == skippedVersion {
                        AppLog.info("Update", "\(release.version) wurde übersprungen, kein Hinweis")
                    } else {
                        announcementPending = true
                        announceIfPossible()
                    }
                }
            } else {
                // A window still showing an older answer would be wrong now.
                if manual || state != .checking { state = .upToDate(latest: release.version) }
                AppLog.info("Update", "\(how) geprüft: aktuell (installiert \(currentVersion), auf GitHub \(release.version))")
            }
        case .failure(let error):
            if error.isUserCancellation {
                if manual, state == .checking { state = .idle }
                return
            }
            let failure = error as? UpdateCheckError ?? .invalidResponse
            AppLog.warning("Update", "\(manual ? "Prüfung" : "Automatische Prüfung") fehlgeschlagen: \(failure.title) · Technisch: \(String(describing: error))")
            // The automatic check stays quiet: the window keeps what it shows.
            if manual { state = .failed(failure) }
        }
    }

    /// „Plattenregal x ist da …“ in the record's menu: the update window in front.
    func showAvailableRelease() {
        AppLifecycle.shared.leaveBackground()
        NSApp.activate()
        if let openWindow { openWindow(); return }
        // No window has handed over how to open one yet: the main window does,
        // and the update window follows once it's up.
        ShelfQuickSearch.shared.showMainWindow()
        Task {
            try? await Task.sleep(for: .seconds(1))
            if let openWindow { openWindow() } else { AppLog.error("Update", "Update-Fenster ließ sich nicht öffnen") }
        }
    }

    // MARK: Skipping and downloading

    /// „Überspringen“: no more automatic hints until a newer one.
    func skip(_ release: AvailableRelease) {
        defaults.set(release.version.description, forKey: Key.skippedVersion)
        announcementPending = false
        AppLog.info("Update", "Version \(release.version) übersprungen")
    }

    /// The DMG in the browser (or the release page without one).
    func download(_ release: AvailableRelease) {
        let url = release.downloadURL ?? release.pageURL
        if NSWorkspace.shared.open(url) {
            AppLog.info("Update", "Download von \(release.version) im Browser geöffnet: \(url.absoluteString)")
        } else {
            AppLog.error("Update", "Browser ließ sich nicht öffnen für \(url.absoluteString)")
            NSSound.beep()
        }
    }

    // MARK: Schedule

    /// From `applicationDidFinishLaunching`: never in test runs, the demo or
    /// preview starts (`OfflineLaunch`) – a showcase shouldn't pop up windows.
    func startAutomaticChecks() {
        guard schedule == nil, !OfflineLaunch.isActive else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { UpdateChecker.shared.announceSoon() }
        })
        restartSchedule(after: Self.launchDelay)
    }

    /// The setting was switched (or reset): a check soon when it's on.
    func automaticChecksChanged() {
        lastCheck = defaults.object(forKey: Key.lastCheck) as? Date
        guard schedule != nil else { return }
        restartSchedule(after: .seconds(2))
    }

    private func restartSchedule(after delay: Duration) {
        schedule?.cancel()
        schedule = Task { [weak self] in
            try? await Task.sleep(for: delay)
            while !Task.isCancelled {
                await self?.runAutomaticCheckIfDue()
                try? await Task.sleep(for: Self.scheduleStep)
            }
        }
    }

    /// Back in front (app active, out of the background): a hint that had to
    /// wait shows now – a moment later, once the window that brought the app
    /// back is up.
    func announceSoon() {
        guard announcementPending else { return }
        Task {
            try? await Task.sleep(for: .seconds(1))
            announceIfPossible()
        }
    }

    /// Opens the window only while Plattenregal is the app in front with its
    /// Dock icon – not over another app, and not while it runs in the
    /// background with only the record in the menu bar (the record's menu
    /// names the update then).
    private func announceIfPossible() {
        // Skipped meanwhile, or the automatic check switched off: the hint that waited stays away.
        guard announcementPending, announcedRelease != nil, interval() != .never else { announcementPending = false; return }
        guard NSApp.isActive, !AppLifecycle.shared.isInBackground, let openWindow else { return }
        announcementPending = false
        openWindow()
    }

    #if DEBUG
    /// `--preview-update=checking|uptodate|available|nodmg|offline|ratelimit|invalid|server|live|live-release`:
    /// the update window with that answer, without asking GitHub – for screenshots.
    func showPreview() {
        guard let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--preview-update=") }) else { return }
        let name = raw.dropFirst("--preview-update=".count)
        // live: a real check as from the menu; live-release: GitHub's real newest release, shown as if it were newer.
        if name == "live" {
            checkNow()
            openWindow?()
            return
        }
        if name == "live-release" {
            Task {
                do { state = .available(try await service.latestRelease()) } catch { state = .failed(error as? UpdateCheckError ?? .invalidResponse) }
                openWindow?()
            }
            return
        }
        // Built as an older version (MARKETING_VERSION=1.0.1 for a picture of
        // the update): the newest entry of "Was ist neu", as GitHub would offer
        // it. Otherwise a made-up next version.
        var version = AppVersion("1.0.3")!
        var notes = """
            **Neu in 1.0.3**
            - Plattenregal sucht einmal am Tag selbst nach einer neuen Version und zeigt, was neu ist.
            - Fehlermeldungen sagen genauer, was los ist, etwa ohne Internet.
            - Die Statistik lädt schneller.

            ---

            **New in 1.0.3**
            - Plattenregal checks for a new version once a day and shows what’s new.
            - Error messages say more precisely what’s wrong, for example without internet.
            - Statistics load faster.
            """
        var published = Date.now.addingTimeInterval(-2 * 24 * 60 * 60)
        var size: Int? = 11_270_713
        if let newest = Changelog.entries.first, let newer = AppVersion(newest.version), newer > currentVersion {
            // Its own date; no size – the DMG isn't known here.
            version = newer
            notes = newest.changes.map { "- \($0)" }.joined(separator: "\n")
            published = newest.date
            size = nil
        }
        let release = AvailableRelease(version: version, pageURL: UpdateService.releasesPageURL,
                                       downloadURL: name == "nodmg" ? nil : URL(string: "https://github.com/ptrcwrnr/Plattenregal/releases/download/v\(version)/Plattenregal.dmg"),
                                       downloadSize: name == "nodmg" ? nil : size, publishedAt: published, notes: notes)
        lastCheck = .now
        switch name {
        case "checking": state = .checking
        case "uptodate": state = .upToDate(latest: currentVersion)
        case "available", "nodmg": state = .available(release)
        case "offline": state = .failed(.offline)
        case "ratelimit": state = .failed(.rateLimited(minutes: 12))
        case "invalid": state = .failed(.invalidResponse)
        default: state = .failed(.server(503))
        }
        openWindow?()
    }
    #endif
}
