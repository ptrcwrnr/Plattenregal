import SwiftUI

/// A grid tile represents one release, even when the collection contains
/// several physical copies. Only the cover and a quiet copy count are shown.
struct CollectionCoverGroup: Identifiable {
    enum Identity: Hashable {
        case discogs(Int)
        case orphan(UUID)
    }

    let id: Identity
    var copies: [RecordCopy]
    var primary: RecordCopy { copies[0] }

    static func make(from copies: [RecordCopy]) -> [Self] {
        var groups: [Self] = []
        var positions: [Identity: Int] = [:]
        for copy in copies {
            let identity = identity(of: copy)
            if let position = positions[identity] {
                groups[position].copies.append(copy)
            } else {
                positions[identity] = groups.count
                groups.append(Self(id: identity, copies: [copy]))
            }
        }
        return groups
    }

    /// The tile a copy belongs to: its Discogs release.
    static func identity(of copy: RecordCopy) -> Identity {
        if let release = copy.release { return .discogs(release.discogsID) }
        return .orphan(copy.id)
    }
}
