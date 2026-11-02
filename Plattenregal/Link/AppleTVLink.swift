import Foundation
import Network
import CryptoKit
import SwiftData
import Observation
import SystemConfiguration

/// The link to Plattenregal on Apple TV, Mac side. While at least one Apple
/// TV is paired, or a pairing is open in the settings, the app offers the
/// Bonjour service `_plattenregal._tcp` on the home network. An Apple TV
/// connects to it and asks; the Mac answers with the Discogs token (if
/// sharing it is on) and the shelf layout, in the format of a backup
/// (`ShelfBackup`), sealed with the key of that Apple TV. The Apple TV only
/// shows the layout and never writes back. Protocol and encryption:
/// `TVLink`, the same file in both projects.
///
/// Off in the demo: its sample shelf must never reach a real Apple TV.
@Observable final class AppleTVLink {
    static let shared = AppleTVLink()

    struct Device: Codable, Identifiable, Equatable {
        let id: UUID
        var name: String
        var pairedAt: Date
        var lastFetch: Date?
    }

    enum Pairing: Equatable {
        /// Waiting for an Apple TV to come forward.
        case waiting
        /// An Apple TV came forward; the code from the TV screen is missing.
        case code(device: String, error: String?)
        case checking(device: String)
        case done(device: String)
        case failed(String)
    }

    private(set) var devices: [Device]
    private(set) var pairing: Pairing?
    private(set) var isListening = false
    private(set) var listenerError: String?
    /// Send the Discogs token along, so the Apple TV syncs by itself.
    var sendsToken: Bool {
        didSet { AppDefaults.store.set(sendsToken, forKey: Keys.sendsToken) }
    }

    /// This Mac towards the Apple TVs; stays the same across launches.
    let macID: UUID
    /// The computer name from the system settings, read once: `Host.current()`
    /// resolves network names and can stall the main thread for seconds.
    static let macName: String = (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? String(localized: "Mac")

    private var listener: NWListener?
    /// A failed service comes back by itself after `listenerRetry` (a Wi-Fi
    /// change, say) – otherwise the Apple TV couldn't reach the Mac until
    /// something changed here.
    private var listenerRetry: Task<Void, Never>?
    private static let listenerRetryDelay: Duration = .seconds(30)
    private var container: ModelContainer?
    private var pending: PendingPairing?

    private struct PendingPairing {
        let link: TVLinkConnection
        let deviceID: UUID
        let deviceName: String
        let tvKey: Data
        let macKey: Data
        let shared: SharedSecret
    }

    private enum Keys {
        static let devices = "appleTVDevices"
        static let sendsToken = "appleTVSendsToken"
        static let macID = "appleTVMacID"
    }
    private static let keyService = "de.private.Plattenregal.appletv"

    private init() {
        let defaults = AppDefaults.store
        devices = defaults.data(forKey: Keys.devices).flatMap { try? JSONDecoder().decode([Device].self, from: $0) } ?? []
        sendsToken = defaults.object(forKey: Keys.sendsToken) as? Bool ?? true
        if let raw = defaults.string(forKey: Keys.macID), let id = UUID(uuidString: raw) {
            macID = id
        } else {
            macID = UUID()
            defaults.set(macID.uuidString, forKey: Keys.macID)
        }
    }

    /// At launch, with the real collection (never the demo's).
    func attach(_ container: ModelContainer) {
        self.container = container
        updateListener()
    }

    // MARK: Pairing

    func startPairing() {
        closePending()
        pairing = .waiting
        updateListener()
    }

    func cancelPairing() {
        closePending()
        pairing = nil
        updateListener()
    }

    /// The six digits from the TV screen.
    func submit(code raw: String) {
        let code = raw.filter(\.isNumber)
        guard let pending else { return }
        guard code.count == 6 else {
            pairing = .code(device: pending.deviceName, error: String(localized: "Der Code hat sechs Ziffern."))
            return
        }
        pairing = .checking(device: pending.deviceName)
        Task {
            do {
                let key = TVLink.pairingKey(shared: pending.shared, code: code, tvKey: pending.tvKey, macKey: pending.macKey)
                try await pending.link.send(.confirm(proof: TVLink.seal(TVLink.proofText, key: key, device: pending.deviceID)))
                switch try await pending.link.receive() {
                case .paired:
                    try TVLinkKeychain.store(key, service: Self.keyService, account: pending.deviceID.uuidString)
                    devices.removeAll { $0.id == pending.deviceID }
                    devices.append(Device(id: pending.deviceID, name: pending.deviceName, pairedAt: .now))
                    saveDevices()
                    closePending()
                    pairing = .done(device: pending.deviceName)
                    AppLog.info("Apple TV", "Gekoppelt: \(pending.deviceName)")
                case .declined(let reason):
                    // Wrong code: the Apple TV keeps waiting for another try.
                    pairing = .code(device: pending.deviceName, error: reason)
                default:
                    throw TVLinkError.invalid
                }
            } catch {
                // Cancelled in the settings while the code was being checked:
                // closing the connection lands here, but the pairing is
                // already over (or a new one is waiting) – no error to show.
                guard pairing == .checking(device: pending.deviceName) else {
                    AppLog.info("Apple TV", "Kopplung während der Prüfung beendet: \(pending.deviceName)")
                    return
                }
                closePending()
                pairing = .failed(String(localized: "Die Verbindung zum Apple TV ist abgebrochen. Starte die Kopplung auf beiden Seiten neu."))
                AppLog.warning("Apple TV", "Kopplung abgebrochen: \(error)")
            }
        }
    }

    /// The settings page closed: an open pairing ends, a finished one is put away.
    func closePairing() {
        guard pairing != nil else { return }
        cancelPairing()
    }

    /// "Fertig" after a pairing.
    func finishPairing() {
        pairing = nil
        updateListener()
    }

    func remove(_ device: Device) {
        TVLinkKeychain.delete(service: Self.keyService, account: device.id.uuidString)
        devices.removeAll { $0.id == device.id }
        saveDevices()
        updateListener()
        AppLog.info("Apple TV", "Entfernt: \(device.name)")
    }

    private func closePending() {
        pending?.link.close()
        pending = nil
    }

    private func saveDevices() {
        AppDefaults.store.set(try? JSONEncoder().encode(devices), forKey: Keys.devices)
    }

    // MARK: Listener

    /// Offers the service only while it is needed: something is paired, or a pairing is open.
    private func updateListener() {
        let needed = container != nil && !OfflineLaunch.isActive && (!devices.isEmpty || pairing != nil)
        if needed, listener == nil {
            startListener()
        } else if !needed {
            listenerRetry?.cancel()
            listenerRetry = nil
            listener?.cancel()
            listener = nil
            isListening = false
            listenerError = nil
        }
    }

    private func startListener() {
        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(name: Self.macName, type: TVLink.serviceType,
                                                  txtRecord: NWTXTRecord([TVLink.macIDKey: macID.uuidString]))
            // Everything on the main queue: the handlers touch this object.
            // A replaced listener's late events are ignored.
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                MainActor.assumeIsolated {
                    guard let self, let listener, self.listener === listener else { return }
                    self.listenerChanged(state)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.accept(connection) }
            }
            self.listener = listener
            listener.start(queue: .main)
        } catch {
            listenerError = String(localized: "Plattenregal ist im Heimnetz gerade nicht erreichbar (\(error.localizedDescription)).")
            AppLog.warning("Apple TV", "Dienst nicht gestartet: \(error)")
            scheduleListenerRetry()
        }
    }

    private func scheduleListenerRetry() {
        listenerRetry?.cancel()
        listenerRetry = Task { [weak self] in
            try? await Task.sleep(for: Self.listenerRetryDelay)
            guard !Task.isCancelled, let self else { return }
            self.listenerRetry = nil
            self.updateListener()
        }
    }

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            isListening = true
            listenerError = nil
        case .failed(let error):
            isListening = false
            listener?.cancel()
            listener = nil
            listenerError = String(localized: "Plattenregal ist im Heimnetz gerade nicht erreichbar (\(error.localizedDescription)). Erlaube den Zugriff aufs lokale Netzwerk unter Systemeinstellungen → Datenschutz & Sicherheit.")
            AppLog.warning("Apple TV", "Dienst ausgefallen: \(error)")
            scheduleListenerRetry()
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        let link = TVLinkConnection(connection)
        Task { await serve(link) }
    }

    private func serve(_ link: TVLinkConnection) async {
        // Connections that never say anything are no requests: the system
        // tries several addresses at once and keeps only one (seen as a few
        // silent connections per fetch). Only a request that went wrong is logged.
        var spoke = false
        do {
            try await link.open()
            let message = try await link.receive()
            spoke = true
            switch message {
            case let .hello(deviceID, deviceName, tvKey, version):
                try await beginPairing(link, deviceID: deviceID, deviceName: deviceName, tvKey: tvKey, version: version)
            case let .fetch(deviceID, nonce):
                try await answer(link, deviceID: deviceID, nonce: nonce)
                link.close()
            default:
                throw TVLinkError.invalid
            }
        } catch {
            link.close()
            if spoke { AppLog.warning("Apple TV", "Anfrage abgebrochen: \(error)") }
        }
    }

    // Reasons sent to the Apple TV stay German: its app speaks only German.
    private func beginPairing(_ link: TVLinkConnection, deviceID: UUID, deviceName: String, tvKey: Data, version: Int) async throws {
        guard version == TVLink.version else {
            try await link.send(.declined(reason: "Plattenregal am Mac und auf dem Apple TV passen nicht zusammen. Bring beide auf den neuesten Stand."))
            link.close()
            return
        }
        guard pairing == .waiting, pending == nil else {
            try await link.send(.declined(reason: "Am Mac ist gerade keine Kopplung offen. Öffne dort Einstellungen → Apple TV und klicke auf „Apple TV verbinden …“."))
            link.close()
            return
        }
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let macKey = privateKey.publicKey.rawRepresentation
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: .init(rawRepresentation: tvKey))
        try await link.send(.welcome(macID: macID, macName: Self.macName, publicKey: macKey))
        pending = PendingPairing(link: link, deviceID: deviceID, deviceName: deviceName, tvKey: tvKey, macKey: macKey, shared: shared)
        pairing = .code(device: deviceName, error: nil)
    }

    private func answer(_ link: TVLinkConnection, deviceID: UUID, nonce: Data) async throws {
        guard !DemoMode.isActive, let container else {
            try await link.send(.declined(reason: "Am Mac läuft gerade die Demo. Beende sie dort, dann bekommt das Apple TV wieder deine Sammlung."))
            return
        }
        guard let index = devices.firstIndex(where: { $0.id == deviceID }),
              let key = TVLinkKeychain.load(service: Self.keyService, account: deviceID.uuidString) else {
            try await link.send(.declined(reason: "Dieses Apple TV ist am Mac nicht mehr verbunden. Verbinde es in den Einstellungen des Apple TV neu."))
            return
        }
        var backup = try ShelfBackupService.makeBackup(of: container.mainContext)
        // The names are only for reading a backup file; the Apple TV goes by instance ID.
        for index in backup.placements.indices { backup.placements[index].record = nil }
        let token = sendsToken ? ((try? KeychainStore.load()) ?? nil) : nil
        let snapshot = TVLink.Snapshot(nonce: nonce, macName: Self.macName, createdAt: .now, token: token,
                                       backup: try TVLink.encode(backup))
        try await link.send(.snapshot(sealed: TVLink.seal(try TVLink.encode(snapshot), key: key, device: deviceID)))
        devices[index].lastFetch = .now
        saveDevices()
    }
}
