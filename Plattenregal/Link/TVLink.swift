import Foundation
import Network
import CryptoKit
import Synchronization

// Die Verbindung zwischen Plattenregal für macOS und Plattenregal für
// Apple TV im Heimnetz. Diese Datei liegt wortgleich in beiden Projekten
// (`Plattenregal/Link/TVLink.swift` am Mac und auf dem Apple TV) – ändert
// sich etwas, dann in beiden.
//
// Ablauf: Der Mac bietet den Bonjour-Dienst `_plattenregal._tcp` an,
// solange er gekoppelte Apple TVs hat oder auf eine Kopplung wartet. Das
// Apple TV sucht ihn und verbindet sich; es fragt, der Mac antwortet.
//
// Kopplung: Beide Seiten schicken einen frischen X25519-Schlüssel. Das
// Apple TV zeigt einen sechsstelligen Code, der am Mac eingetippt wird. Aus
// dem gemeinsamen Geheimnis und dem Code leiten beide denselben Schlüssel
// ab; der Mac beweist ihn mit einer versiegelten Bestätigung. Danach liegt
// der Schlüssel auf beiden Seiten im Schlüsselbund. Wer im Netz mitliest,
// sieht nur die öffentlichen Schlüssel; wer den Code nicht kennt, wird nicht
// gekoppelt.
//
// Abholen: Das Apple TV schickt seine ID und eine Zufallszahl; der Mac
// antwortet mit Discogs-Token und Regal-Belegung, mit ChaChaPoly versiegelt.
// Die Zufallszahl steckt im versiegelten Inhalt, damit keine alte Antwort
// wiederholt werden kann.

nonisolated enum TVLink {
    static let serviceType = "_plattenregal._tcp"
    static let version = 1
    /// Größer wird keine Nachricht; schützt vor fremden Daten.
    static let maximumMessageSize = 16_000_000
    /// Schlüssel im TXT-Eintrag des Dienstes: die ID des Macs.
    static let macIDKey = "id"
    /// So lange wartet eine Kopplung auf den Code vom Mac.
    static let pairingTimeout: Duration = .seconds(180)
    /// Für alles andere: Verbinden und jede Antwort.
    static let replyTimeout: Duration = .seconds(15)
    /// So oft darf am Mac ein falscher Code kommen, dann bricht das Apple TV ab.
    static let codeAttempts = 3

    enum Message: Codable, Sendable {
        /// Apple TV → Mac: Kopplung beginnen.
        case hello(deviceID: UUID, deviceName: String, publicKey: Data, version: Int)
        /// Mac → Apple TV: bereit, hier sein Schlüssel.
        case welcome(macID: UUID, macName: String, publicKey: Data)
        /// Beide Richtungen: nein, mit Grund in Worten.
        case declined(reason: String)
        /// Mac → Apple TV: der eingetippte Code, als versiegelter Beweis.
        case confirm(proof: Data)
        /// Apple TV → Mac: der Code stimmt, gekoppelt.
        case paired
        /// Apple TV → Mac: den neuesten Stand bitte.
        case fetch(deviceID: UUID, nonce: Data)
        /// Mac → Apple TV: der Stand, versiegelt (`Snapshot` als JSON).
        case snapshot(sealed: Data)
    }

    /// Was der Mac dem Apple TV schickt.
    struct Snapshot: Codable, Sendable {
        var nonce: Data
        var macName: String
        var createdAt: Date
        /// Fehlt, wenn am Mac keiner gespeichert ist oder das Mitschicken aus ist.
        var token: String?
        /// Die Regal-Belegung im Format der Sicherungen der Mac-App
        /// („Belegung …json“, `ShelfBackup`), als JSON.
        var backup: Data?
    }

    // MARK: Schlüssel

    /// Der gemeinsame Schlüssel einer Kopplung: aus dem X25519-Geheimnis, dem
    /// Code und beiden öffentlichen Schlüsseln.
    static func pairingKey(shared: SharedSecret, code: String, tvKey: Data, macKey: Data) -> SymmetricKey {
        shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(code.utf8),
                                       sharedInfo: Data("Plattenregal Apple TV 1".utf8) + tvKey + macKey,
                                       outputByteCount: 32)
    }

    /// Was der Mac als Beweis versiegelt.
    static let proofText = Data("Plattenregal gekoppelt".utf8)

    static func seal(_ data: Data, key: SymmetricKey, device: UUID) throws -> Data {
        try ChaChaPoly.seal(data, using: key, authenticating: Data(device.uuidString.utf8)).combined
    }

    static func open(_ data: Data, key: SymmetricKey, device: UUID) throws -> Data {
        try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: data), using: key, authenticating: Data(device.uuidString.utf8))
    }

    /// Sechs Ziffern aus dem sicheren Zufall des Systems.
    static func makeCode() -> String {
        var generator = SystemRandomNumberGenerator()
        return String(format: "%06d", Int.random(in: 0..<1_000_000, using: &generator))
    }

    static func makeNonce() -> Data {
        Data(SymmetricKey(size: .bits256).withUnsafeBytes { Array($0) })
    }

    // MARK: Kodieren

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do { return try decoder.decode(type, from: data) } catch { throw TVLinkError.invalid }
    }
}

nonisolated enum TVLinkError: LocalizedError, Equatable {
    case closed, invalid, timeout, declined(String), wrongCode, notPaired, macNotFound

    var errorDescription: String? {
        switch self {
        case .closed: "Die Verbindung wurde unterbrochen."
        case .invalid: "Die Gegenseite hat etwas geschickt, mit dem Plattenregal nichts anfangen kann. Sind beide Apps auf dem neuesten Stand?"
        case .timeout: "Die Gegenseite hat nicht rechtzeitig geantwortet."
        case .declined(let reason): reason
        case .wrongCode: "Der Code stimmte nicht."
        case .notPaired: "Dieses Gerät ist noch nicht verbunden."
        case .macNotFound: "Der Mac ist im Heimnetz nicht zu finden. Ist Plattenregal dort geöffnet?"
        }
    }
}

/// Eine Verbindung, die ganze Nachrichten schickt und empfängt: je vier
/// Bytes Länge, dann JSON. Läuft auf einer eigenen Warteschlange.
nonisolated final class TVLinkConnection: Sendable {
    let connection: NWConnection
    private static let queue = DispatchQueue(label: "de.private.Plattenregal.tvlink")

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    convenience init(to endpoint: NWEndpoint) {
        self.init(NWConnection(to: endpoint, using: .tcp))
    }

    /// Baut die Verbindung auf; scheitert nach `timeout`.
    func open(timeout: Duration = TVLink.replyTimeout) async throws {
        let once = TVLinkFlag()
        let timer = Task { [connection] in
            try await Task.sleep(for: timeout)
            connection.cancel()
        }
        defer { timer.cancel() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            @Sendable func finish(_ result: Result<Void, Error>) {
                guard once.take() else { return }
                continuation.resume(with: result)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(.success(()))
                case .failed(let error), .waiting(let error): finish(.failure(error))
                case .cancelled: finish(.failure(TVLinkError.timeout))
                default: break
                }
            }
            connection.start(queue: Self.queue)
        }
    }

    func send(_ message: TVLink.Message) async throws {
        let body = try TVLink.encode(message)
        var length = UInt32(body.count).bigEndian
        let frame = Data(bytes: &length, count: 4) + body
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: frame, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    /// Die nächste ganze Nachricht; nach `timeout` wird die Verbindung geschlossen.
    func receive(timeout: Duration = TVLink.replyTimeout) async throws -> TVLink.Message {
        let expired = TVLinkFlag()
        let timer = Task { [connection] in
            try await Task.sleep(for: timeout)
            _ = expired.take()
            connection.cancel()
        }
        defer { timer.cancel() }
        do {
            let header = try await read(4)
            let length = header.reduce(0) { $0 << 8 | Int($1) }
            guard length > 0, length <= TVLink.maximumMessageSize else { throw TVLinkError.invalid }
            return try TVLink.decode(TVLink.Message.self, from: try await read(length))
        } catch {
            if expired.isSet { throw TVLinkError.timeout }
            throw error
        }
    }

    func close() {
        connection.cancel()
    }

    private func read(_ count: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                if let error { continuation.resume(throwing: error) }
                else if let data, data.count == count { continuation.resume(returning: data) }
                else { continuation.resume(throwing: TVLinkError.closed) }
            }
        }
    }
}

/// Ein Schalter, der sich genau einmal umlegen lässt – auch über Threads hinweg.
nonisolated final class TVLinkFlag: Sendable {
    private let state = Mutex(false)
    /// `true` nur beim ersten Aufruf.
    func take() -> Bool { state.withLock { done in defer { done = true }; return !done } }
    var isSet: Bool { state.withLock { $0 } }
}

/// Schlüssel einer Kopplung im Schlüsselbund – am Mac je Apple TV, auf dem
/// Apple TV der eine für seinen Mac.
nonisolated enum TVLinkKeychain {
    private static func query(service: String, account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load(service: String, account: String) -> SymmetricKey? {
        var q = query(service: service, account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
              data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    static func store(_ key: SymmetricKey, service: String, account: String) throws {
        delete(service: service, account: account)
        var q = query(service: service, account: account)
        q[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw TVLinkKeychainError(status: status) }
    }

    static func delete(service: String, account: String) {
        SecItemDelete(query(service: service, account: account) as CFDictionary)
    }
}

nonisolated struct TVLinkKeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "Der Schlüssel der Verbindung ließ sich nicht im Schlüsselbund ablegen (Fehler \(status))." }
}
