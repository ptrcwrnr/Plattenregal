import Foundation
import SwiftData

/// Search texts folded (case/diacritics) once when the data changes, so a
/// keystroke only runs plain substring checks instead of rebuilding and
/// Unicode-comparing every record's text.
struct SearchIndex<ID: Hashable> {
    private var texts: [ID: String] = [:]

    init() {}
    init<S: Sequence>(_ items: S, id: (S.Element) -> ID, text: (S.Element) -> String) {
        for item in items { texts[id(item)] = Self.fold(text(item)) }
    }

    /// Every word of the query must occur somewhere in the record's text.
    func matches(_ id: ID, _ words: [String]) -> Bool {
        guard let text = texts[id] else { return false }
        return words.allSatisfy { text.contains($0) }
    }

    nonisolated static func words(_ query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map { fold(String($0)) }
    }

    nonisolated static func fold(_ value: String) -> String {
        // Case folding keeps "ß", so "Strasse" would miss "Straße".
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "ß", with: "ss")
        // Letters without a decomposable accent stay as they are ("Mø",
        // "Øystein", "Łona", "Æther"); Latin-ASCII maps them like the alphabet
        // sections do. Only where such a letter is left: the transform is
        // slow, and most texts (tracklists included) are plain ASCII by now.
        guard folded.unicodeScalars.contains(where: { (0x00C0...0x024F).contains($0.value) }),
              let latin = folded.applyingTransform(StringTransform("Latin-ASCII"), reverse: false) else { return folded }
        return latin.lowercased()
    }
}

/// The search texts of all records and wantlist entries, folded once. The
/// collection index is shared by the collection page and the statistics'
/// drill-down. Built on the first search after a change, not with every
/// change – the tracklist download reports every few seconds, mostly while
/// nobody searches.
///
/// Every record is in it, whichever account and whether still in the
/// collection: the pages only look up the ones they show, so an index never
/// depends on which records count as current right now.
final class LibrarySearchIndexes {
    static let shared = LibrarySearchIndexes()

    enum Kind { case collection, wantlist }

    /// What an index was built from: the counts of all records and entries
    /// (what the pages' queries hold), the reported changes, and the pages'
    /// own data rebuilds (`invalidate`).
    private struct Key: Equatable { let generation: Int; let library: Int; let tracks: Int; let count: Int }
    /// One per index: a wantlist rebuild must not throw away the collection's
    /// index (about 1,700 records with their tracklists folded anew).
    private var generations: [Kind: Int] = [:]
    private var collection: (key: Key, index: SearchIndex<UUID>)?
    private var wantlist: (key: Key, index: SearchIndex<PersistentIdentifier>)?

    /// A page rebuilt from changed data: its next search builds afresh.
    func invalidate(_ kind: Kind) { generations[kind, default: 0] += 1 }

    private func key(_ kind: Kind, count: Int) -> Key {
        Key(generation: generations[kind] ?? 0, library: LibraryChanges.shared.libraryVersion,
            tracks: LibraryChanges.shared.tracksVersion, count: count)
    }

    /// `copies`: every record, only read when the index has to be built.
    func collection(_ copies: [RecordCopy]) -> SearchIndex<UUID> {
        let key = key(.collection, count: copies.count)
        if let collection, collection.key == key { return collection.index }
        let index = SearchIndex(copies, id: \.id, text: SortingService.searchText)
        collection = (key, index)
        return index
    }

    /// `entries`: every wantlist entry.
    func wantlist(_ entries: [WantlistEntry]) -> SearchIndex<PersistentIdentifier> {
        let key = key(.wantlist, count: entries.count)
        if let wantlist, wantlist.key == key { return wantlist.index }
        let index = SearchIndex(entries, id: \.persistentModelID, text: WantlistPresentation.searchText)
        wantlist = (key, index)
        return index
    }
}

extension Release {
    /// The track a search found this release by, shown on its card — `nil`
    /// when the query already matches artist and title (or no track at all).
    /// Folded like the search index, so a record the search kept also shows
    /// the track it was found by ("strasse" → "Straße").
    func track(matching query: String) -> Track? {
        let words = SearchIndex<Int>.words(query)
        guard !words.isEmpty, !tracks.isEmpty else { return nil }
        let name = SearchIndex<Int>.fold(artist + " " + title)
        if words.allSatisfy({ name.contains($0) }) { return nil }
        return tracks.first { track in
            let title = SearchIndex<Int>.fold(track.title)
            return words.allSatisfy { title.contains($0) }
        }
    }
}

extension Release {
    // Discogs-Releases können mehrere Styles besitzen. Für die Regalorganisation wird
    // hier bewusst der erste gespeicherte Style als "Haupt-Style" verwendet, da Discogs
    // Styles in absteigender Relevanz liefert. Diese Zuordnung ist bewusst an einer
    // Stelle gekapselt, damit sie später z.B. durch eine Priorisierungsliste oder eine
    // "häufigster Style im Fach"-Heuristik ersetzt werden kann, ohne Aufrufer anzupassen.
    var primaryStyle: String { styles.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
}
