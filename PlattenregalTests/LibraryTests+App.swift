import AppKit
import SwiftUI
import Foundation
import Testing
import SwiftData
@testable import Plattenregal

extension AllTests.LibraryTests {
    @Test func errorsReachTheUserInPlainGerman() {
        // The app's own errors keep their text.
        #expect(LibraryError.reserved.userMessage == LibraryError.reserved.errorDescription)
        #expect(DiscogsError.offline.userMessage == DiscogsError.offline.errorDescription)
        // System errors never show their English wording or codes.
        let saveFailure = NSError(domain: NSCocoaErrorDomain, code: 134030)
        #expect(saveFailure.userMessage == ErrorMessages.saveFailed)
        // A failed "Gesucht" names the action instead of a general save error.
        let mark = LibraryError.missingMarkNotSaved(found: false, saveFailure).userMessage
        #expect(mark.hasPrefix("„Gesucht“ konnte nicht gespeichert werden"))
        #expect(LibraryError.missingMarkNotSaved(found: true, saveFailure).userMessage.hasPrefix("„Wieder gefunden“"))
        // "Reihenfolge übernehmen" says the shelf is unchanged, not a general save error.
        let order = LibraryError.orderNotSaved(saveFailure).userMessage
        #expect(order.hasPrefix("Die neue Reihenfolge konnte nicht gespeichert werden"))
        #expect(!order.contains("134030"))
        #expect(!mark.contains("134030"))
        #expect(URLError(.notConnectedToInternet).userMessage == DiscogsError.offline.errorDescription)
        #expect(NSError(domain: "Other", code: 1).userMessage == ErrorMessages.generic)
        // 4xx is not a server problem.
        #expect(DiscogsError.http(418).userMessage.contains("abgelehnt"))
        #expect(DiscogsError.http(503).userMessage.contains("Problem"))
        #expect(DiscogsError.rateLimited(1).userMessage.contains("einer Sekunde"))
        // Files: the backup's own texts, and no "couldn't save the change" for a file.
        #expect(ShelfBackupError.unreadable.userMessage == ShelfBackupError.unreadable.errorDescription)
        #expect(FileTransferError.readFailed(saveFailure).userMessage.contains("geöffnet"))
        #expect(FileTransferError.writeFailed(saveFailure).userMessage != ErrorMessages.saveFailed)
        #expect(String(describing: FileTransferError.restoreFailed(saveFailure)).contains("134030"))
        #expect(CocoaError(.userCancelled).isUserCancellation)
        #expect(!saveFailure.isUserCancellation)
        // Cabinet and reset errors used to fall back to the generic text.
        #expect(CabinetError.lastActive.userMessage == CabinetError.lastActive.errorDescription)
        #expect(ResetError.tokenNotRemoved.userMessage == ResetError.tokenNotRemoved.errorDescription)
        #expect(StorageError.alreadyOpen.userMessage == StorageError.alreadyOpen.errorDescription)
        #expect(FileTransferError.folderUnavailable.userMessage.contains("nicht erreichbar"))
        #expect(URLError(.timedOut).userMessage.contains("rechtzeitig"))
        // Reading (statistics, "Platte hinzufügen") never claims a change wasn't saved.
        #expect(ReadError.wrapping(saveFailure).userMessage.contains("nicht gelesen"))
        #expect(ReadError.wrapping(DiscogsError.offline).userMessage == DiscogsError.offline.errorDescription)
        #expect(String(describing: ReadError.wrapping(saveFailure)).contains("134030"))
    }
    @Test func cancellationAndKeychainErrorsStayReadable() {
        let message = CancellationError().userMessage
        #expect(message == "Der Vorgang wurde abgebrochen.")
        let cancellations: [any Error] = [CancellationError(), URLError(.cancelled), CocoaError(.userCancelled)]
        for error in cancellations {
            #expect(error.isUserCancellation)
            #expect(error.userMessage == message)
            #expect(ReadError.wrapping(error).userMessage == message)
        }
        #expect(!URLError(.timedOut).isUserCancellation)
        #expect(!CocoaError(.fileWriteNoPermission).isUserCancellation)
        let keychain = KeychainError(status: -25308)
        #expect(keychain.userMessage.contains("Schlüsselbund"))
        #expect(!keychain.userMessage.contains("-25308"))
        #expect(String(describing: keychain).contains("-25308"))
    }
    /// The demo's sample collection: every page has something to show, and
    /// the layout is consistent (as a sync and the shelf page expect it).
    @Test func demoCollectionIsCompleteAndConsistent() throws {
        #expect(!DemoMode.isActive)
        #expect(AppDefaults.store === UserDefaults.standard)
        let container = try DemoData.makeContainer()
        let context = container.mainContext
        let copies = try context.fetch(FetchDescriptor<RecordCopy>())
        let account = DiscogsAccount.current(in: try context.fetch(FetchDescriptor<DiscogsAccount>()))
        #expect(account?.username == DemoData.owner)
        #expect(copies.count > 40)
        // One example of every state: left the collection but still on the shelf, …
        let left = copies.filter { !$0.isInCurrentCollection(owner: DemoData.owner) }
        #expect(left.count == 1 && left.allSatisfy { $0.shelf != nil })
        #expect(copies.filter { $0.shelf == nil }.count >= 5)
        let cabinets = try context.fetch(FetchDescriptor<Cabinet>())
        #expect(cabinets.count == 2)
        let shelves = try context.fetch(FetchDescriptor<Shelf>())
        #expect(shelves.contains { $0.isReserved && $0.copies.isEmpty })
        for shelf in shelves where !shelf.copies.isEmpty {
            #expect(shelf.copies.map(\.positionInShelf).sorted() == Array(1...shelf.copies.count))
        }
        #expect(Set(copies.map(\.discogsInstanceID)).count == copies.count)
        #expect(try context.fetchCount(FetchDescriptor<WantlistEntry>()) == 10)
        #expect(try context.fetchCount(FetchDescriptor<CollectionValueSnapshot>()) == 18)
        #expect(try context.fetchCount(FetchDescriptor<OptimizationExclusion>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<MissingCopyMark>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<SaleCopyMark>()) == 2)
        // … and a "Verlauf" whose open changes can all be undone, one already undone.
        let history = try context.fetch(FetchDescriptor<ShelfHistoryEntry>())
        #expect(history.count == 4)
        let byID = Dictionary(uniqueKeysWithValues: copies.map { ($0.id, $0) })
        let blockers = ShelfHistory.blockers(history, copies: byID, shelves: Dictionary(uniqueKeysWithValues: shelves.map { ($0.id, $0) }),
                                             excluded: Set(try context.fetch(FetchDescriptor<OptimizationExclusion>()).map(\.copyID)))
        #expect(history.filter { blockers[$0.id] == nil }.count == 3)
        #expect(history.filter { blockers[$0.id] == .undone }.count == 1)
    }
    @Test func onlyAFreshRequestStartsTheDemo() {
        let now = Date.now
        #expect(DemoMode.accepts(request: now.addingTimeInterval(-2), now: now, isTest: false))
        #expect(!DemoMode.accepts(request: nil, now: now, isTest: false))
        // A relaunch that failed long ago must not turn a normal start into a demo.
        #expect(!DemoMode.accepts(request: now.addingTimeInterval(-600), now: now, isTest: false))
        // A clock set back doesn't keep an old request alive.
        #expect(!DemoMode.accepts(request: now.addingTimeInterval(600), now: now, isTest: false))
        #expect(!DemoMode.accepts(request: now, now: now, isTest: true))
        #expect(DemoMode.fileSuffix.isEmpty)
        #expect(ScheduledExport.fileName(for: ExportSettings()) == "Plattenregal Collection.csv")
        #expect(ScheduledExport.fileName(for: ExportSettings(format: .pdf, source: .sale)) == "Plattenregal Verkaufsliste.pdf")
    }
    @Test func crashOfThePreviousSessionIsFoundInTheLog() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("crash-\(UUID()).log")
        defer { try? FileManager.default.removeItem(at: url) }
        // An old crash before the last start doesn't count.
        let crashed = """
        ──── Start · Version 1.0 (1)
        ==== ABSTURZ: SIGABRT (abgebrochen) · Unix-Zeit 1000 ====
        ──── Start · Version 1.0 (2)
        [Regal] irgendwas
        ==== ABSTURZ: SIGSEGV (ungültiger Speicherzugriff) · Unix-Zeit 1790000000 · Version 1.0 (2) ====
        0 Plattenregal 0x0000000100001234 main + 52
        ==== Ende Absturz ====

        """
        try Data(crashed.utf8).write(to: url)
        let crash = try #require(AppLog.previousCrash(in: url))
        #expect(crash.reason == "SIGSEGV (ungültiger Speicherzugriff)")
        #expect(crash.date == Date(timeIntervalSince1970: 1_790_000_000))
        try Data("──── Start · Version 1.0 (1)\n==== ABSTURZ: SIGABRT (abgebrochen) · Unix-Zeit 1000 ====\n──── Start · Version 1.0 (2)\nBeendet\n".utf8).write(to: url)
        #expect(AppLog.previousCrash(in: url) == nil)
    }
}
