import Foundation
import SwiftData
import Observation
import OSLog

extension DiscogsSyncService {
    /// Off the main actor; cancelling the sync cancels the merge with it.
    @concurrent nonisolated static func mergeInBackground(_ snapshot: DiscogsSyncSnapshot, container: ModelContainer) async throws -> DiscogsSyncSummary {
        try merge(snapshot, container: container)
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
            let previousCurrent = DiscogsAccount.current(in: accounts)?.username
            let isNewAccount = !accounts.contains { $0.username == owner }
            // Only what differs is written, here and below: a sync that confirms
            // the store saves nothing but the account's dates, instead of every
            // record – each of which the main context then reads again.
            let account = accounts.first { $0.username == owner } ?? DiscogsAccount(username: owner)
            if isNewAccount { context.insert(account) }
            let releases = try context.fetch(FetchDescriptor<Release>())
            var byRelease: [Int: Release] = [:]
            for release in releases where byRelease[release.discogsID] == nil { byRelease[release.discogsID] = release }
            func release(_ basic: DiscogsBasicInformation) throws -> (record: Release, changed: Bool) {
                let record = byRelease[basic.id] ?? Release(discogsID: basic.id, artist: "", title: basic.title)
                if byRelease[basic.id] == nil { context.insert(record); byRelease[basic.id] = record }
                return (record, try basic.apply(to: record, at: now))
            }
            let copies = try context.fetch(FetchDescriptor<RecordCopy>())
            if let folders = snapshot.folders {
                let existing = try context.fetch(FetchDescriptor<DiscogsFolder>(predicate: #Predicate { $0.owner == owner }))
                // The client rejects duplicates in an answer; one already in
                // the store must not trap either – the first one is kept up to date.
                var indexed = Dictionary(existing.map { ($0.folderID, $0) }, uniquingKeysWith: { first, _ in first })
                let ids = Set(folders.map(\.id))
                for dto in folders {
                    guard let folder = indexed[dto.id] else {
                        let folder = DiscogsFolder(owner: owner, id: dto.id, name: dto.name, count: dto.count)
                        context.insert(folder); indexed[dto.id] = folder
                        result.foldersChanged += 1
                        continue
                    }
                    guard folder.name != dto.name || folder.count != dto.count else { continue }
                    folder.name = dto.name; folder.count = dto.count
                    result.foldersChanged += 1
                }
                for folder in existing where !ids.contains(folder.folderID) { context.delete(folder); result.foldersChanged += 1 }
                for copy in copies where copy.discogsOwner == owner {
                    if let id = copy.discogsFolderID, !ids.contains(id) { copy.discogsFolderID = nil; result.otherChanges = true }
                }
            }
            if let collection = snapshot.collection {
                let owned = copies.filter { $0.discogsOwner == owner }
                var byInstance: [Int: RecordCopy] = [:]
                for copy in owned { byInstance[copy.discogsInstanceID] = copy }
                let ids = Set(collection.map(\.instance_id))
                for dto in collection {
                    try Task.checkCancellation()
                    let (metadata, metadataChanged) = try release(dto.basic_information)
                    guard let copy = byInstance[dto.instance_id] else {
                        let copy = RecordCopy(release: metadata, instanceID: dto.instance_id, owner: owner); context.insert(copy)
                        // The release once more after the insert (see `Shelf.insert`).
                        copy.release = metadata
                        copy.discogsFolderID = dto.folder_id; copy.discogsDateAdded = dto.date_added
                        byInstance[dto.instance_id] = copy
                        result.collectionAdded += 1
                        continue
                    }
                    var changed = metadataChanged
                    if copy.release !== metadata { copy.release = metadata; changed = true }
                    if copy.discogsFolderID != dto.folder_id { copy.discogsFolderID = dto.folder_id; changed = true }
                    if copy.discogsDateAdded != dto.date_added { copy.discogsDateAdded = dto.date_added; changed = true }
                    if !copy.discogsActive { copy.discogsActive = true; changed = true }
                    if changed { result.collectionUpdated += 1 }
                    // Never write shelf or positionInShelf.
                }
                for copy in owned where copy.discogsActive && !ids.contains(copy.discogsInstanceID) {
                    if case .folder(let id) = snapshot.scope, id != 0 {
                        if copy.discogsFolderID == id { copy.discogsFolderID = nil; result.otherChanges = true }
                    } else {
                        copy.discogsActive = false; copy.discogsFolderID = nil
                        result.collectionRemoved += 1
                    }
                }
                if snapshot.scope == .collection || snapshot.scope == .all || snapshot.scope == .folder(0) { account.lastCollectionSync = now }
            }
            if let wants = snapshot.wants {
                let existing = try context.fetch(FetchDescriptor<WantlistEntry>(predicate: #Predicate { $0.owner == owner }))
                // As for the folders: a duplicate already in the store must not trap.
                var indexed = Dictionary(existing.map { ($0.releaseID, $0) }, uniquingKeysWith: { first, _ in first })
                let ids = Set(wants.map(\.id))
                for dto in wants {
                    let (metadata, metadataChanged) = try release(dto.basic_information)
                    guard let entry = indexed[dto.id] else {
                        let entry = WantlistEntry(owner: owner, release: metadata, releaseID: dto.id)
                        context.insert(entry); entry.release = metadata
                        entry.dateAdded = dto.date_added; entry.notes = dto.notes
                        indexed[dto.id] = entry
                        result.wantsAdded += 1
                        continue
                    }
                    if metadataChanged { result.otherChanges = true }
                    if entry.release !== metadata { entry.release = metadata; result.otherChanges = true }
                    if entry.dateAdded != dto.date_added { entry.dateAdded = dto.date_added; result.otherChanges = true }
                    if entry.notes != dto.notes { entry.notes = dto.notes; result.otherChanges = true }
                }
                for entry in existing where !ids.contains(entry.releaseID) { context.delete(entry); result.wantsRemoved += 1 }
                // A release that was only wanted (never owned) goes with its last want.
                let wanted = Set(try context.fetch(FetchDescriptor<WantlistEntry>())
                    .filter { !$0.isDeleted }.compactMap { $0.release?.persistentModelID })
                for release in byRelease.values where release.copies.isEmpty && !wanted.contains(release.persistentModelID) {
                    context.delete(release)
                    result.otherChanges = true
                }
                account.lastWantlistSync = now
            }
            if account.userID != snapshot.userID { account.userID = snapshot.userID }
            if account.credentialFingerprint != snapshot.fingerprint { account.credentialFingerprint = snapshot.fingerprint }
            if snapshot.scope == .all { account.lastFullSync = now }
            // The first sync of an account, or another one becoming the current one.
            if isNewAccount || DiscogsAccount.current(in: accounts + (isNewAccount ? [account] : []))?.username != previousCurrent {
                result.otherChanges = true
            }
            try Task.checkCancellation()
            try context.save()
            return result
        } catch { context.rollback(); throw error }
    }
}
