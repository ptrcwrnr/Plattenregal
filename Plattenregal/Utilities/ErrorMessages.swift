import Foundation

/// The app's own errors, whose `errorDescription` is written for the user.
/// Every such error type conforms, so a new one can't silently fall back to
/// "Da ist etwas schiefgelaufen" – which happened to cabinet and reset errors.
nonisolated protocol UserFacingError: LocalizedError {}

extension DiscogsError: UserFacingError {}
extension LibraryError: UserFacingError {}
extension KeychainError: UserFacingError {}
extension ShelfBackupError: UserFacingError {}
extension FileTransferError: UserFacingError {}
extension CabinetError: UserFacingError {}
extension ResetError: UserFacingError {}
extension StorageError: UserFacingError {}

extension Error {
    /// What the user reads when something fails: plain German, no error
    /// codes or English system texts. The app's own errors (Discogs, shelf,
    /// keychain) bring their text along; everything else — mostly failed
    /// database saves and network hiccups — gets a sentence that says what
    /// happened and what to do. Technical details belong in the log.
    nonisolated var userMessage: String {
        switch self {
        case let error as any UserFacingError: return error.errorDescription ?? ErrorMessages.generic
        case is CancellationError: return "Der Vorgang wurde abgebrochen."
        case let error as URLError where error.code == .timedOut:
            return "Discogs hat nicht rechtzeitig geantwortet. Prüfe deine Internetverbindung und versuche es noch einmal."
        case is URLError: return DiscogsError.offline.errorDescription ?? ErrorMessages.generic
        case is DecodingError: return DiscogsError.invalidResponse.errorDescription ?? ErrorMessages.generic
        default:
            let error = self as NSError
            // Core Data / SwiftData report failed saves in the Cocoa domain.
            if error.domain == NSCocoaErrorDomain { return ErrorMessages.saveFailed }
            return ErrorMessages.generic
        }
    }
}

extension Error {
    /// `userMessage` for showing, with the technical detail and the code
    /// location written to the protocol (`AppLog`) – used wherever the app
    /// shows an error, so every one of them can be traced later. Cancelling
    /// isn't an error and isn't logged.
    nonisolated func reportedMessage(file: String = #fileID, line: Int = #line) -> String {
        let text = userMessage
        if !(self is CancellationError) {
            let name = String(file.split(separator: "/").last ?? Substring(file))
            AppLog.error(name.replacingOccurrences(of: ".swift", with: ""),
                         "\(text) · Technisch: \(String(describing: self)) · \(name):\(line)")
        }
        return text
    }
}

/// Exports, backups and restores: the underlying system error would read as
/// "couldn't save the change", which is wrong for a file the user picked.
/// The original error is kept for the protocol.
nonisolated enum FileTransferError: LocalizedError, CustomStringConvertible {
    case exportFailed(any Error)
    case writeFailed(any Error)
    case readFailed(any Error)
    case safetyBackupFailed(any Error)
    case restoreFailed(any Error)
    /// A chosen folder (export, backups) can't be reached any more.
    case folderUnavailable
    /// Switching the backup folder failed; the old one stays.
    case folderChangeFailed(any Error)

    var errorDescription: String? {
        switch self {
        case .exportFailed: "Der Export konnte nicht erstellt werden. Bitte versuche es noch einmal. Klappt es weiterhin nicht, starte Plattenregal neu."
        case .writeFailed: "Die Datei konnte nicht gespeichert werden. Prüfe, ob am gewählten Ort genug Platz ist und du dort speichern darfst, und versuche es noch einmal."
        case .readFailed: "Die Datei konnte nicht geöffnet werden. Prüfe, ob sie noch vorhanden ist, und wähle sie noch einmal aus."
        case .safetyBackupFailed: "Die aktuelle Belegung konnte vorher nicht gesichert werden. Zur Sicherheit wurde nichts verändert – bitte versuche es noch einmal."
        case .restoreFailed: "Die Belegung konnte nicht wiederhergestellt werden. Dein Regal ist unverändert. Bitte versuche es noch einmal."
        case .folderUnavailable: "Der gewählte Ordner ist nicht erreichbar – vielleicht wurde er verschoben, gelöscht oder das Laufwerk ist nicht angeschlossen. Wähle den Ordner neu aus."
        case .folderChangeFailed: "Die vorhandenen Sicherungen ließen sich nicht in den neuen Ordner kopieren. Es bleibt beim bisherigen Ordner. Prüfe, ob du im neuen Ordner speichern darfst und genug Platz ist."
        }
    }
    var description: String {
        switch self {
        case .exportFailed(let error): "exportFailed(\(error))"
        case .writeFailed(let error): "writeFailed(\(error))"
        case .readFailed(let error): "readFailed(\(error))"
        case .safetyBackupFailed(let error): "safetyBackupFailed(\(error))"
        case .restoreFailed(let error): "restoreFailed(\(error))"
        case .folderUnavailable: "folderUnavailable"
        case .folderChangeFailed(let error): "folderChangeFailed(\(error))"
        }
    }
}

extension Error {
    /// The user closed a save or open panel – not an error.
    nonisolated var isUserCancellation: Bool {
        let error = self as NSError
        return error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError
    }
}

nonisolated enum ErrorMessages {
    static let saveFailed = "Die Änderung konnte nicht gespeichert werden. Bitte versuche es noch einmal. Klappt es weiterhin nicht, starte Plattenregal neu."
    static let generic = "Da ist etwas schiefgelaufen. Bitte versuche es noch einmal."
}
