import Foundation
import Observation

/// What changed in the store, for pages that cache what they derive from it
/// (sorted lists, search indexes, shelf labels). Comparing `@Query` arrays
/// doesn't catch changed metadata on the same objects, so every write path
/// reports here what kind of data it touched, and pages rebuild on that:
///
/// - `PositionService.save` (and with it every shelf, cabinet, backup and
///   reset write) reports placements,
/// - `CabinetService` and restoring a backup report shelves,
/// - the Discogs sync, single-release reloads and resets report the library,
/// - the tracklist download reports tracks.
@Observable final class LibraryChanges {
    static let shared = LibraryChanges()

    /// Bumped after records or their metadata changed (sync, reloading
    /// single releases, reset). Collection lists and search indexes rebuild.
    private(set) var libraryVersion = 0
    /// Bumped whenever stored tracklists changed, so search indexes pick them up.
    private(set) var tracksVersion = 0
    /// Bumped when cabinets or compartments change (added, resized, renamed,
    /// switched on/off, removed, restored). Only shelf labels depend on that –
    /// the collection lists and search indexes don't need a rebuild.
    private(set) var shelvesVersion = 0
    /// Bumped after every committed position change (sorting in, moving,
    /// taking out). Range labels follow the records in the compartments, so
    /// pages caching them refresh – without the heavier `shelvesVersion` work.
    private(set) var placementsVersion = 0

    /// Records and their tracklists may have changed.
    func libraryDidChange() { libraryVersion += 1; tracksVersion += 1 }
    /// A sync committed: records and metadata, but no tracklists (those
    /// follow in the background and report themselves).
    func syncDidCommit() { libraryVersion += 1 }
    func tracksDidChange() { tracksVersion += 1 }
    func shelvesDidChange() { shelvesVersion += 1 }
    func placementsDidChange() { placementsVersion += 1 }
}
