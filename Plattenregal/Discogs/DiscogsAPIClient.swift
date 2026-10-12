import Foundation
import OSLog
import CryptoKit

nonisolated enum DiscogsError: LocalizedError {
    case incompletePagination, accountChanged, notFound, forbidden
    case missingToken, demoMode, unauthorized, rateLimited(Int), http(Int), invalidResponse, offline
    var errorDescription: String? {
        switch self {
        case .incompletePagination: String(localized: "Deine Liste bei Discogs hat sich während des Ladens verändert. Es wurde nichts gespeichert. Bitte synchronisiere noch einmal.")
        case .accountChanged: String(localized: "Der Discogs-Token passt nicht mehr zum geladenen Konto – vermutlich wurde er gerade geändert. Es wurde nichts gespeichert. Bitte synchronisiere noch einmal.")
        case .notFound: String(localized: "Discogs findet diese Platte oder diesen Ordner nicht (mehr). Vielleicht wurde sie dort gelöscht.")
        case .forbidden: String(localized: "Discogs lässt den Zugriff nicht zu. Prüfe in den Einstellungen, ob der Token stimmt und zu deinem Konto gehört.")
        case .demoMode: String(localized: "Im Demo-Modus ist Discogs ausgeschaltet – die Beispieldaten bleiben, wie sie sind. Beende die Demo, um deine eigene Sammlung zu synchronisieren.")
        case .missingToken: String(localized: "Es ist noch kein Discogs-Token eingetragen. Das Feld dafür findest du in den Einstellungen unter „Discogs“.")
        case .unauthorized: String(localized: "Discogs hat den Token nicht angenommen. Vielleicht ist er abgelaufen oder unvollständig kopiert. Prüfe ihn in den Einstellungen.")
        case .rateLimited(let seconds): String(localized: "Discogs bremst gerade, weil in kurzer Zeit viele Anfragen kamen. Versuche es in \(seconds == 1 ? String(localized: "einer Sekunde") : String(localized: "\(seconds) Sekunden")) noch einmal.")
        case .http(let code) where code >= 500: String(localized: "Bei Discogs gibt es gerade ein Problem (Fehler \(code)). Versuche es später noch einmal.")
        case .http(let code): String(localized: "Discogs hat die Anfrage abgelehnt (Fehler \(code)). Versuche es später noch einmal.")
        case .invalidResponse: String(localized: "Discogs hat Daten geschickt, mit denen Plattenregal nichts anfangen kann. Versuche es später noch einmal.")
        case .offline: String(localized: "Discogs ist gerade nicht erreichbar. Prüfe deine Internetverbindung und versuche es noch einmal.")
        }
    }
}
actor DiscogsAPIClient {
    static let shared = DiscogsAPIClient()
    private let session: URLSession
    private let tokenProvider: @Sendable () throws -> String?
    private var nextRequest = Date.distantPast
    private var blockedUntil = Date.distantPast
    private let logger = Logger(subsystem: "de.private.Plattenregal", category: "Discogs")
    /// Seconds between two requests (Discogs allows 60 a minute) and before
    /// the first repeat of a failed one, doubled for the second. Only the
    /// tests shorten them.
    private let spacing: TimeInterval
    private let retryPause: TimeInterval
    init(session: URLSession? = nil, tokenProvider: @escaping @Sendable () throws -> String? = { try KeychainStore.load() },
         spacing: TimeInterval = 1.1, retryPause: TimeInterval = 1) {
        self.tokenProvider = tokenProvider
        self.spacing = spacing; self.retryPause = retryPause
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.timeoutIntervalForRequest = 25
        self.session = session ?? URLSession(configuration: config)
    }
    func release(id: Int) async throws -> DiscogsReleaseDTO { try await request(path: "/releases/\(id)") }
    func fetchCollectionValue(username: String) async throws -> DiscogsCollectionValue {
        try await request(path: userPath(username) + "/collection/value")
    }
    func identity() async throws -> DiscogsIdentity { try await request(path: "/oauth/identity") }
    /// One quick attempt for the settings' connection test: no retries and
    /// no waiting out a rate limit, so the answer comes within seconds.
    static func quickTest(_ token: String) async throws -> String {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.timeoutIntervalForRequest = 10; config.timeoutIntervalForResource = 15
        let client = DiscogsAPIClient(session: URLSession(configuration: config), tokenProvider: { token })
        let identity: DiscogsIdentity = try await client.requestOnce(path: "/oauth/identity", items: [])
        return identity.username
    }
    func credentialFingerprint() throws -> String {
        guard let token = try tokenProvider(), !token.isEmpty else { throw DemoMode.isActive ? DiscogsError.demoMode : .missingToken }
        return Self.fingerprint(of: token)
    }
    /// Discogs tokens are plain letters and digits. Anything with spaces,
    /// line breaks or control characters inside was pasted wrongly – and must
    /// never reach the Authorization header.
    nonisolated static func isWellFormedToken(_ token: String) -> Bool {
        !token.isEmpty && token.count <= 256 && token.unicodeScalars.allSatisfy { (0x21...0x7E).contains($0.value) }
    }
    /// Identifies a token without keeping it (stored per account after a sync).
    nonisolated static func fingerprint(of token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func userPath(_ username: String) throws -> String {
        guard !username.isEmpty, !username.contains("/"), !username.contains("?"), !username.contains("#"),
              let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { throw DiscogsError.invalidResponse }
        return "/users/" + encoded
    }
    func folders(username: String) async throws -> [DiscogsFolderDTO] {
        let response: DiscogsFoldersResponse = try await request(path: userPath(username) + "/collection/folders")
        guard Set(response.folders.map(\.id)).count == response.folders.count else { throw DiscogsError.invalidResponse }
        return response.folders
    }
    func collection(username: String, folderID: Int = 0) async throws -> [DiscogsCollectionDTO] {
        var all: [DiscogsCollectionDTO] = []; var expected: DiscogsPagination?
        var page = 1
        repeat {
            let result: DiscogsCollectionPage = try await request(path: userPath(username) + "/collection/folders/\(folderID)/releases", items: pageItems(page))
            try validate(result.pagination, page: page, expected: expected, count: result.releases.count)
            expected = result.pagination; all += result.releases
            page += 1
        } while page <= (expected?.pages ?? 0)
        guard all.count == expected?.items, Set(all.map(\.instance_id)).count == all.count,
              all.allSatisfy({ $0.id == $0.basic_information.id && $0.instance_id > 0 && (folderID == 0 || $0.folder_id == folderID) }) else { throw DiscogsError.incompletePagination }
        return all
    }
    func wants(username: String) async throws -> [DiscogsWantDTO] {
        var all: [DiscogsWantDTO] = []; var expected: DiscogsPagination?; var page = 1
        repeat {
            let result: DiscogsWantPage = try await request(path: userPath(username) + "/wants", items: pageItems(page))
            try validate(result.pagination, page: page, expected: expected, count: result.wants.count)
            expected = result.pagination; all += result.wants
            page += 1
        } while page <= (expected?.pages ?? 0)
        guard all.count == expected?.items, Set(all.map(\.id)).count == all.count,
              all.allSatisfy({ $0.id == $0.basic_information.id }) else { throw DiscogsError.incompletePagination }
        return all
    }
    private func pageItems(_ page: Int) -> [URLQueryItem] {
        [URLQueryItem(name: "per_page", value: "100"), URLQueryItem(name: "page", value: String(page)),
         URLQueryItem(name: "sort", value: "added"), URLQueryItem(name: "sort_order", value: "asc")]
    }
    private func validate(_ p: DiscogsPagination, page: Int, expected: DiscogsPagination?, count: Int) throws {
        // Bounded before any arithmetic: absurd numbers in a broken answer
        // would overflow below and trap instead of failing the sync.
        guard p.page == page, (0...100_000_000).contains(p.items), (1...1_000).contains(p.per_page), (0...100_000).contains(p.pages),
              p.pages == (p.items == 0 ? p.pages : (p.items + p.per_page - 1) / p.per_page),
              (p.items > 0 || p.pages <= 1),
              count == min(p.per_page, max(0, p.items - (page - 1) * p.per_page)) else { throw DiscogsError.incompletePagination }
        if let expected, (p.pages != expected.pages || p.items != expected.items || p.per_page != expected.per_page) { throw DiscogsError.incompletePagination }
    }
    /// HTTP date as used by Retry-After, e.g. "Thu, 01 Jan 1970 00:01:00 GMT".
    private static let httpDate = Date.VerbatimFormatStyle(
        format: "\(weekday: .abbreviated), \(day: .twoDigits) \(month: .abbreviated) \(year: .defaultDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits) GMT",
        locale: Locale(identifier: "en_US_POSIX"), timeZone: .gmt, calendar: Calendar(identifier: .gregorian))
    /// Discogs counts in one-minute windows; anything far beyond (a broken
    /// header or proxy) would block every request for hours without a word.
    nonisolated static let maximumRetryDelay = 600
    nonisolated static func retryDelay(_ value: String?, now: Date = .now) -> Int {
        let seconds: Int
        if let value, let parsed = Int(value.trimmingCharacters(in: .whitespaces)) { seconds = parsed }
        else if let value, let date = try? httpDate.parseStrategy.parse(value) {
            let interval = date.timeIntervalSince(now)
            seconds = interval.isFinite ? Int(ceil(min(interval, Double(maximumRetryDelay)))) : 60
        } else { return 60 }
        return min(max(1, seconds), maximumRetryDelay)
    }
    private func request<T: Decodable>(path: String, items: [URLQueryItem] = []) async throws -> T {
        for attempt in 0...2 {
            do { return try await requestOnce(path: path, items: items) }
            catch {
                let retry: Bool
                switch error {
                case DiscogsError.rateLimited: retry = true
                case DiscogsError.http(let code): retry = (500...599).contains(code)
                case DiscogsError.offline: retry = true
                default: retry = false
                }
                guard retry, attempt < 2 else { throw error }
                logger.notice("Retrying Discogs GET, attempt \(attempt + 2)")
                try await Task.sleep(for: .seconds(retryPause * Double(1 << attempt)))
            }
        }
        throw DiscogsError.invalidResponse
    }
    private func requestOnce<T: Decodable>(path: String, items: [URLQueryItem]) async throws -> T {
        guard let token = try tokenProvider(), !token.isEmpty else { throw DemoMode.isActive ? DiscogsError.demoMode : .missingToken }
        guard Self.isWellFormedToken(token) else { throw DiscogsError.unauthorized }
        // Reserve a slot before suspension, so concurrent clients cannot burst the rate limit.
        let slot = max(Date(), nextRequest); nextRequest = slot.addingTimeInterval(spacing)
        let delay = slot.timeIntervalSinceNow
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        // Re-check server cooldown after suspension; queued requests must respect it too.
        while blockedUntil > Date() {
            try await Task.sleep(for: .seconds(blockedUntil.timeIntervalSinceNow))
            let resumedSlot = max(Date(), nextRequest)
            nextRequest = resumedSlot.addingTimeInterval(spacing)
            if resumedSlot > Date() { try await Task.sleep(for: .seconds(resumedSlot.timeIntervalSinceNow)) }
        }
        try Task.checkCancellation()
        var components = URLComponents(string: "https://api.discogs.com\(path)")!
        components.queryItems = items.isEmpty ? nil : items
        guard let url = components.url else { throw DiscogsError.invalidResponse }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        req.setValue("Plattenregal/1.0 (native macOS personal record library)", forHTTPHeaderField: "User-Agent")
        req.setValue("Discogs token=\(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.discogs.v2.discogs+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw DiscogsError.invalidResponse }
            let limit = Int(http.value(forHTTPHeaderField: "X-Discogs-Ratelimit") ?? "")
            let remaining = Int(http.value(forHTTPHeaderField: "X-Discogs-Ratelimit-Remaining") ?? "")
            let status = http.statusCode
            Task { @MainActor in DiscogsRateLimit.shared.record(limit: limit, remaining: remaining, status: status) }
            if http.value(forHTTPHeaderField: "X-Discogs-Ratelimit-Remaining") == "0" {
                blockedUntil = Date().addingTimeInterval(60)
                nextRequest = max(nextRequest, blockedUntil)
            }
            if http.statusCode >= 400 { logger.error("Discogs HTTP \(http.statusCode) for \(path, privacy: .private)") }
            switch http.statusCode {
            case 200...299: break
            case 401: throw DiscogsError.unauthorized
            case 403: throw DiscogsError.forbidden
            case 404: throw DiscogsError.notFound
            case 429:
                let retry = Self.retryDelay(http.value(forHTTPHeaderField: "Retry-After"))
                blockedUntil = Date().addingTimeInterval(Double(retry))
                nextRequest = max(nextRequest, blockedUntil)
                throw DiscogsError.rateLimited(retry)
            default: throw DiscogsError.http(http.statusCode)
            }
            do { return try JSONDecoder().decode(T.self, from: data) }
            catch { logger.error("Discogs JSON decoding failed: \(String(describing: error), privacy: .private)"); throw DiscogsError.invalidResponse }
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            logger.error("Network failure, code \(error.code.rawValue)")
            throw DiscogsError.offline
        } catch { throw error }
    }
}

/// What Discogs said about its request budget in the last answer this
/// session, for the diagnosis in the settings. Discogs allows a number of
/// requests per minute (60 with a token) and counts them in a moving window.
@Observable final class DiscogsRateLimit {
    static let shared = DiscogsRateLimit()
    private(set) var limit: Int?
    private(set) var remaining: Int?
    private(set) var lastRequest: Date?
    private(set) var requests = 0
    /// Set when Discogs answered 429 ("too many requests").
    private(set) var lastThrottled: Date?

    func record(limit: Int?, remaining: Int?, status: Int) {
        if let limit { self.limit = limit }
        if let remaining { self.remaining = remaining }
        lastRequest = .now
        requests += 1
        if status == 429 { lastThrottled = .now }
    }
}
