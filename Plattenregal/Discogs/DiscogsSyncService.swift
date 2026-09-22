import Foundation
import SwiftData
import Observation
import OSLog

enum DiscogsSyncScope: Equatable, Sendable {
    case collection, wantlist, all, folder(Int), release(Int)
}
struct DiscogsSyncSnapshot: Sendable {
    let username: String
    let userID: Int?
    let fingerprint: String
    let scope: DiscogsSyncScope
    var folders: [DiscogsFolderDTO]?
    var collection: [DiscogsCollectionDTO]?
    var wants: [DiscogsWantDTO]?
    var detail: DiscogsReleaseDTO?
}
struct DiscogsSyncSummary: Sendable {
    var collectionAdded = 0, collectionUpdated = 0, collectionRemoved = 0
    var wantsAdded = 0, wantsRemoved = 0
    var foldersChanged = 0
    var description: String {
        "Collection: +\(collectionAdded), \(collectionUpdated) aktualisiert, −\(collectionRemoved) · Wantlist: +\(wantsAdded), −\(wantsRemoved) · Ordner: \(foldersChanged) geändert"
    }
    func description(for scope: DiscogsSyncScope) -> String {
        switch scope {
        case .collection:
            "Collection: +\(collectionAdded), \(collectionUpdated) aktualisiert, −\(collectionRemoved) · Ordner: \(foldersChanged) geändert"
        case .wantlist:
            "Wantlist: +\(wantsAdded), −\(wantsRemoved)"
        case .folder:
            "Collection: +\(collectionAdded), \(collectionUpdated) aktualisiert, −\(collectionRemoved) · Ordner: \(foldersChanged) geändert"
        case .release:
            "Veröffentlichung aktualisiert"
        case .all:
            description
        }
    }
}

@MainActor @Observable final class DiscogsSyncService {
    static let shared = DiscogsSyncService()
    var busy = false
    var status = ""
    var error: String?
    var summary: String?
    private var task: Task<Bool, Never>?
    private let api: DiscogsAPIClient
    init(api: DiscogsAPIClient = .shared) { self.api = api }
    func start(_ scope: DiscogsSyncScope, container: ModelContainer, expectedOwner: String? = nil) {
        guard !busy else { return }
        // Set synchronously so two windows cannot start competing merges.
        busy = true
        task = Task { await run(scope, container: container, expectedOwner: expectedOwner) }
    }
    /// Runs the same guarded synchronization while allowing launch preparation to
    /// remain visible until the operation has either completed or failed.
    @discardableResult
    func synchronize(_ scope: DiscogsSyncScope, container: ModelContainer, expectedOwner: String? = nil) async -> Bool {
        guard !busy else { return false }
        busy = true
        let operation = Task { await run(scope, container: container, expectedOwner: expectedOwner) }
        task = operation
        return await withTaskCancellationHandler {
            await operation.value
        } onCancel: {
            operation.cancel()
        }
    }
    func cancel() { task?.cancel() }
    private func run(_ scope: DiscogsSyncScope, container: ModelContainer, expectedOwner: String?) async -> Bool {
        error = nil; summary = nil
        defer { busy = false; task = nil }
        do {
            let snapshot = try await fetch(scope, container: container, expectedOwner: expectedOwner)
            try Task.checkCancellation()
            guard try await api.credentialFingerprint() == snapshot.fingerprint else { throw DiscogsError.accountChanged }
            status = "Änderungen werden gespeichert …"
            let mergeTask = Task.detached(priority: .userInitiated) {
                try Self.merge(snapshot, container: container)
            }
            let result = try await withTaskCancellationHandler {
                try await mergeTask.value
            } onCancel: { mergeTask.cancel() }
            status = "Synchronisierung abgeschlossen"; summary = result.description(for: scope)
            if scope == .collection || scope == .all || scope == .folder(0) {
                do {
                    try await CollectionValueHistoryService.shared.refresh(owner: snapshot.username, container: container, api: api, force: true)
                } catch {
                    // Collection merge is committed. A valuation failure must not roll it back or claim it failed.
                    self.error = "Sammlung gespeichert; Sammlungswert nicht aktualisiert: " + error.localizedDescription
                }
            }
            return true
        } catch is CancellationError {
            status = "Synchronisierung abgebrochen. Keine Änderungen gespeichert."
            return false
        }
        catch {
            self.error = error.localizedDescription; status = "Synchronisierung fehlgeschlagen"
            Logger(subsystem: "de.private.Plattenregal", category: "Sync").error("Sync failed: \(String(describing: error), privacy: .private)")
            return false
        }
    }
    func fetch(_ scope: DiscogsSyncScope, container: ModelContainer, expectedOwner: String? = nil) async throws -> DiscogsSyncSnapshot {
        status = "Discogs-Account wird geprüft …"
        let fingerprint = try await api.credentialFingerprint()
        let context = ModelContext(container)
        let accounts = try context.fetch(FetchDescriptor<DiscogsAccount>())
        let cached = accounts.first { $0.credentialFingerprint == fingerprint }
        let username: String; let userID: Int?
        if let cached { username = cached.username; userID = cached.userID }
        else { let identity = try await api.identity(); username = identity.username; userID = identity.id }
        if let expectedOwner, expectedOwner != username { throw DiscogsError.accountChanged }
        var snapshot = DiscogsSyncSnapshot(username: username, userID: userID, fingerprint: fingerprint, scope: scope)
        switch scope {
        case .collection, .all, .folder:
            status = "Discogs-Ordner werden geladen …"
            snapshot.folders = try await api.folders(username: username)
            let folderID: Int
            if case .folder(let id) = scope { folderID = id } else { folderID = 0 }
            status = "Collection wird geladen …"
            snapshot.collection = try await api.collection(username: username, folderID: folderID) { [weak self] page, pages in
                await self?.progress("Collection", page, pages)
            }
        default: break
        }
        if let folders = snapshot.folders, let collection = snapshot.collection {
            let folderIDs = Set(folders.map(\.id))
            guard collection.allSatisfy({ folderIDs.contains($0.folder_id) }) else { throw DiscogsError.incompletePagination }
        }
        if scope == .wantlist || scope == .all {
            status = "Wantlist wird geladen …"
            snapshot.wants = try await api.wants(username: username) { [weak self] page, pages in
                await self?.progress("Wantlist", page, pages)
            }
        }
        if case .release(let id) = scope {
            status = "Veröffentlichung wird geladen …"; snapshot.detail = try await api.release(id: id)
        }
        guard try await api.credentialFingerprint() == fingerprint else { throw DiscogsError.accountChanged }
        return snapshot
    }
    private func progress(_ area: String, _ page: Int, _ pages: Int) {
        status = "\(area) wird geladen … Seite \(page) von \(pages)"
    }

    // A dedicated context isolates rollback from unsaved edits in other windows.
    // Runs on a worker task; no suspension occurs between mutations and the single save.
    nonisolated static func merge(_ snapshot: DiscogsSyncSnapshot, container: ModelContainer, at now: Date = .now) throws -> DiscogsSyncSummary {
        try Task.checkCancellation()
        let context = ModelContext(container); context.autosaveEnabled = false
        var result = DiscogsSyncSummary()
        do {
            let owner = snapshot.username
            let accounts = try context.fetch(FetchDescriptor<DiscogsAccount>())
            let account = accounts.first { $0.username == owner } ?? DiscogsAccount(username: owner)
            context.insert(account)
            let releases = try context.fetch(FetchDescriptor<Release>())
            var byRelease: [Int: Release] = [:]
            for release in releases { if let id = release.discogsID, byRelease[id] == nil { byRelease[id] = release } }
            func release(_ basic: DiscogsBasicInformation) throws -> Release {
                let record = byRelease[basic.id] ?? Release(artist: "", title: basic.title)
                if byRelease[basic.id] == nil { context.insert(record); byRelease[basic.id] = record }
                try basic.apply(to: record, at: now); return record
            }
            let copies = try context.fetch(FetchDescriptor<RecordCopy>())
            if let folders = snapshot.folders {
                let existing = try context.fetch(FetchDescriptor<DiscogsFolder>()).filter { $0.owner == owner }
                let indexed = Dictionary(uniqueKeysWithValues: existing.map { ($0.folderID, $0) })
                let ids = Set(folders.map(\.id))
                for dto in folders {
                    let folder = indexed[dto.id] ?? DiscogsFolder(owner: owner, id: dto.id, name: dto.name, count: dto.count)
                    if indexed[dto.id] == nil || folder.name != dto.name || folder.count != dto.count { result.foldersChanged += 1 }
                    context.insert(folder); folder.name = dto.name; folder.count = dto.count; folder.lastSync = now
                }
                for folder in existing where !ids.contains(folder.folderID) { context.delete(folder); result.foldersChanged += 1 }
                for copy in copies where copy.discogsOwner == owner {
                    if let id = copy.discogsFolderID, !ids.contains(id) { copy.discogsFolderID = nil }
                }
                account.lastFolderSync = now
            }
            if let collection = snapshot.collection {
                let owned = copies.filter { $0.discogsOwner == owner }
                var byInstance: [Int: RecordCopy] = [:]
                for copy in owned { if let id = copy.discogsInstanceID { byInstance[id] = copy } }
                // Reuse unlinked manual copies of this release once, preserving all local data.
                var unlinked: [Int: [RecordCopy]] = [:]
                for copy in copies where copy.discogsInstanceID == nil && copy.discogsOwner == nil {
                    if let id = copy.release?.discogsID { unlinked[id, default: []].append(copy) }
                }
                let ids = Set(collection.map(\.instance_id))
                for dto in collection {
                    try Task.checkCancellation()
                    let metadataChanged = byRelease[dto.id]?.basicInformation != (try DiscogsEncoding.data(dto.basic_information))
                    let metadata = try release(dto.basic_information)
                    let copy: RecordCopy
                    if let existing = byInstance[dto.instance_id] { copy = existing }
                    else {
                        if let local = unlinked[dto.id]?.popLast() { copy = local }
                        else { copy = RecordCopy(release: metadata); context.insert(copy) }
                        result.collectionAdded += 1
                    }
                    let notes = try DiscogsEncoding.data(dto.notes ?? [])
                    if byInstance[dto.instance_id] != nil && (metadataChanged || copy.discogsFolderID != dto.folder_id || copy.discogsRating != dto.rating || copy.discogsNotes != notes || copy.discogsActive != true || copy.discogsDateAdded != dto.date_added) { result.collectionUpdated += 1 }
                    copy.release = metadata; copy.discogsOwner = owner; copy.discogsInstanceID = dto.instance_id
                    copy.discogsFolderID = dto.folder_id; copy.discogsDateAdded = dto.date_added
                    copy.discogsRating = dto.rating; copy.discogsNotes = notes
                    copy.discogsActive = true; copy.lastDiscogsSync = now
                    // Never write shelf, positionInShelf, notes, condition or purchase data.
                }
                for copy in owned where copy.discogsActive == true && !ids.contains(copy.discogsInstanceID ?? -1) {
                    if case .folder(let id) = snapshot.scope, id != 0 {
                        if copy.discogsFolderID == id { copy.discogsFolderID = nil }
                    } else {
                        copy.discogsActive = false; copy.discogsFolderID = nil
                        copy.lastDiscogsSync = now; result.collectionRemoved += 1
                    }
                }
                if snapshot.scope == .collection || snapshot.scope == .all || snapshot.scope == .folder(0) { account.lastCollectionSync = now }
            }
            if let wants = snapshot.wants {
                let existing = try context.fetch(FetchDescriptor<WantlistEntry>()).filter { $0.owner == owner }
                let indexed = Dictionary(uniqueKeysWithValues: existing.map { ($0.releaseID, $0) })
                let ids = Set(wants.map(\.id))
                for dto in wants {
                    let metadata = try release(dto.basic_information)
                    let entry = indexed[dto.id] ?? WantlistEntry(owner: owner, release: metadata, releaseID: dto.id)
                    if indexed[dto.id] == nil { result.wantsAdded += 1 }
                    context.insert(entry); entry.release = metadata; entry.dateAdded = dto.date_added
                    entry.rating = dto.rating; entry.notes = dto.notes; entry.lastDiscogsSync = now
                }
                for entry in existing where !ids.contains(entry.releaseID) { context.delete(entry); result.wantsRemoved += 1 }
                account.lastWantlistSync = now
            }
            if let detail = snapshot.detail {
                for release in releases where release.discogsID == detail.id { detail.apply(to: release) }
            }
            account.userID = snapshot.userID; account.credentialFingerprint = snapshot.fingerprint
            if snapshot.scope == .all { account.lastFullSync = now }
            try Task.checkCancellation()
            try context.save()
            return result
        } catch { context.rollback(); throw error }
    }
}
