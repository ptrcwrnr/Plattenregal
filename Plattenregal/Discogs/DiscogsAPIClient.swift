import Foundation
import OSLog
import CryptoKit

enum DiscogsError: LocalizedError {
    case incompletePagination, accountChanged, notFound, forbidden
    case missingToken, unauthorized, rateLimited(Int), http(Int), invalidResponse, offline
    var errorDescription: String? {
        switch self {
        case .incompletePagination: "Discogs hat keine vollständige, konsistente Liste geliefert. Es wurden keine Änderungen gespeichert. Bitte erneut synchronisieren."
        case .accountChanged: "Der Discogs-Account oder Token hat sich geändert. Bitte starte die Synchronisierung erneut."
        case .notFound: "Die Veröffentlichung oder der Discogs-Ordner wurde nicht gefunden."
        case .forbidden: "Discogs verweigert den Zugriff. Bitte prüfe Token und Zugriffsrechte."
        case .missingToken: "Bitte hinterlege deinen persönlichen Discogs-Token in den Einstellungen."
        case .unauthorized: "Discogs hat den Token abgelehnt. Bitte prüfe ihn in den Einstellungen."
        case .rateLimited(let seconds): "Discogs erlaubt gerade keine weiteren Anfragen. Bitte warte \(seconds) Sekunden."
        case .http(let code): "Discogs meldet einen Serverfehler (HTTP \(code)). Bitte versuche es später erneut."
        case .invalidResponse: "Die Antwort von Discogs konnte nicht gelesen werden."
        case .offline: "Discogs ist nicht erreichbar. Bitte prüfe deine Internetverbindung."
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
    init(session: URLSession? = nil, tokenProvider: @escaping @Sendable () throws -> String? = { try KeychainStore.load() }) {
        self.tokenProvider = tokenProvider
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.timeoutIntervalForRequest = 25
        self.session = session ?? URLSession(configuration: config)
    }
    func search(_ query: String, page: Int = 1) async throws -> DiscogsSearchResponse {
        try await request(path: "/database/search", items: [URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "release"), URLQueryItem(name: "format", value: "Vinyl"),
            URLQueryItem(name: "per_page", value: "30"), URLQueryItem(name: "page", value: String(page))])
    }
    func release(id: Int) async throws -> DiscogsReleaseDTO { try await request(path: "/releases/\(id)") }
    func fetchCollectionValue(username: String) async throws -> DiscogsCollectionValue {
        try await request(path: userPath(username) + "/collection/value")
    }
    func priceSuggestions(releaseID: Int) async throws -> [String: DiscogsPrice] {
        try await request(path: "/marketplace/price_suggestions/\(releaseID)")
    }
    func marketplaceStats(releaseID: Int) async throws -> DiscogsMarketplaceStats {
        try await request(path: "/marketplace/stats/\(releaseID)", items: [URLQueryItem(name: "curr_abbr", value: "EUR")])
    }
    func identity() async throws -> DiscogsIdentity { try await request(path: "/oauth/identity") }
    func testToken() async throws -> String { try await identity().username }
    func credentialFingerprint() throws -> String {
        guard let token = try tokenProvider(), !token.isEmpty else { throw DiscogsError.missingToken }
        return SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
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
    func collection(username: String, folderID: Int = 0,
                    progress: @Sendable (Int, Int) async -> Void = { _, _ in }) async throws -> [DiscogsCollectionDTO] {
        var all: [DiscogsCollectionDTO] = []; var expected: DiscogsPagination?
        var page = 1
        repeat {
            let result: DiscogsCollectionPage = try await request(path: userPath(username) + "/collection/folders/\(folderID)/releases", items: pageItems(page))
            try validate(result.pagination, page: page, expected: expected, count: result.releases.count)
            expected = result.pagination; all += result.releases
            await progress(page, max(1, result.pagination.pages))
            page += 1
        } while page <= (expected?.pages ?? 0)
        guard all.count == expected?.items, Set(all.map(\.instance_id)).count == all.count,
              all.allSatisfy({ $0.id == $0.basic_information.id && $0.instance_id > 0 && (folderID == 0 || $0.folder_id == folderID) }) else { throw DiscogsError.incompletePagination }
        return all
    }
    func wants(username: String, progress: @Sendable (Int, Int) async -> Void = { _, _ in }) async throws -> [DiscogsWantDTO] {
        var all: [DiscogsWantDTO] = []; var expected: DiscogsPagination?; var page = 1
        repeat {
            let result: DiscogsWantPage = try await request(path: userPath(username) + "/wants", items: pageItems(page))
            try validate(result.pagination, page: page, expected: expected, count: result.wants.count)
            expected = result.pagination; all += result.wants
            await progress(page, max(1, result.pagination.pages)); page += 1
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
        guard p.page == page, p.items >= 0, p.per_page > 0, p.pages >= 0, p.pages <= 100_000,
              p.pages == (p.items == 0 ? p.pages : (p.items + p.per_page - 1) / p.per_page),
              (p.items > 0 || p.pages <= 1),
              count == min(p.per_page, max(0, p.items - (page - 1) * p.per_page)) else { throw DiscogsError.incompletePagination }
        if let expected, (p.pages != expected.pages || p.items != expected.items || p.per_page != expected.per_page) { throw DiscogsError.incompletePagination }
    }
    nonisolated static func retryDelay(_ value: String?, now: Date = .now) -> Int {
        if let value, let seconds = Int(value) { return max(1, seconds) }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let value, let date = formatter.date(from: value) { return max(1, Int(ceil(date.timeIntervalSince(now)))) }
        return 60
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
                try await Task.sleep(for: .seconds(Double(1 << attempt)))
            }
        }
        throw DiscogsError.invalidResponse
    }
    private func requestOnce<T: Decodable>(path: String, items: [URLQueryItem]) async throws -> T {
        guard let token = try tokenProvider(), !token.isEmpty else { throw DiscogsError.missingToken }
        // Reserve a slot before suspension, so concurrent clients cannot burst the rate limit.
        let slot = max(Date(), nextRequest); nextRequest = slot.addingTimeInterval(1.1)
        let delay = slot.timeIntervalSinceNow
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        // Re-check server cooldown after suspension; queued requests must respect it too.
        while blockedUntil > Date() {
            try await Task.sleep(for: .seconds(blockedUntil.timeIntervalSinceNow))
            let resumedSlot = max(Date(), nextRequest)
            nextRequest = resumedSlot.addingTimeInterval(1.1)
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
