import Foundation
import SwiftData
import Observation
import OSLog

nonisolated enum DiscogsSyncScope: Equatable, Sendable {
    case collection, wantlist, all, folder(Int)
    /// For the protocol (`AppLog`).
    var logName: String {
        switch self {
        case .collection: "Collection"
        case .wantlist: "Wantlist"
        case .all: "Alles"
        case .folder(let id): "Ordner \(id)"
        }
    }
}
nonisolated struct DiscogsSyncSnapshot: Sendable {
    let username: String
    let userID: Int?
    let fingerprint: String
    let scope: DiscogsSyncScope
    var folders: [DiscogsFolderDTO]?
    var collection: [DiscogsCollectionDTO]?
    var wants: [DiscogsWantDTO]?
}
nonisolated struct DiscogsSyncSummary: Sendable {
    var collectionAdded = 0, collectionUpdated = 0, collectionRemoved = 0
    var wantsAdded = 0, wantsRemoved = 0
    var foldersChanged = 0
    /// Changes the counts above don't show: wantlist notes and dates, release
    /// data that came with the wantlist, folders cleared on copies, another
    /// account becoming the current one.
    var otherChanges = false
    /// Whether the store holds anything new for the pages. A sync that only
    /// confirmed what was there lets them keep what they derived from it.
    var hasChanges: Bool {
        collectionAdded + collectionUpdated + collectionRemoved + wantsAdded + wantsRemoved + foldersChanged > 0 || otherChanges
    }
    // Only additions are reported; updates, removals and folder changes stay silent.
    private static func added(_ count: Int) -> String { count == 0 ? String(localized: "Nichts hinzugefügt") : String(localized: "\(count.formatted()) hinzugefügt") }
    /// Both areas at once need their names to be told apart.
    var description: String { String(localized: "Collection: \(Self.added(collectionAdded))\nWantlist: \(Self.added(wantsAdded))") }
    func description(for scope: DiscogsSyncScope) -> String {
        switch scope {
        case .collection, .folder: Self.added(collectionAdded)
        case .wantlist: Self.added(wantsAdded)
        case .all: description
        }
    }
}
