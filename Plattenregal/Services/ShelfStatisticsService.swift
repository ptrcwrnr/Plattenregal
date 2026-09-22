import Foundation

/// One style's share of a shelf's copies, used for the dominant-style label and
/// the optional style breakdown in the shelf detail view.
struct ShelfStyleShare: Identifiable, Hashable {
    var id: String { style }
    let style: String
    let count: Int
    let fraction: Double
}

/// Occupancy and style-distribution statistics for one shelf, derived from its
/// current copies. Never persisted — always recomputed from the live collection
/// so it can't drift from the actual shelf contents.
struct ShelfStatistics {
    let shelfID: UUID
    let count: Int
    let capacity: Int
    let styleShares: [ShelfStyleShare]

    init(shelf: Shelf) {
        shelfID = shelf.id
        count = shelf.copies.count
        capacity = max(shelf.capacity, 1)
        let styles = shelf.copies.compactMap { copy -> String? in
            let style = copy.release?.primaryStyle ?? ""
            return style.isEmpty ? nil : style
        }
        let grouped = Dictionary(grouping: styles, by: { $0 }).mapValues(\.count)
        let total = styles.count
        styleShares = grouped
            .map { ShelfStyleShare(style: $0.key, count: $0.value, fraction: total > 0 ? Double($0.value) / Double(total) : 0) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.style.localizedStandardCompare($1.style) == .orderedAscending
            }
    }

    var occupancyFraction: Double { min(1, Double(count) / Double(capacity)) }
    var occupancyPercent: Int { Int((occupancyFraction * 100).rounded()) }

    enum FillLevel { case low, medium, high, full }
    var fillLevel: FillLevel {
        switch occupancyFraction {
        case ..<0.34: return .low
        case ..<0.70: return .medium
        case ..<0.97: return .high
        default: return .full
        }
    }

    /// Compact "Techno · 56 %" style label for the shelf overview card.
    /// Falls back to "Techno / Trance" when the top two styles are close,
    /// and to a neutral message when the shelf has no usable style data.
    var dominantStyleLabel: String {
        guard let top = styleShares.first else {
            return count == 0 ? "Leer" : "Kein Style erkannt"
        }
        if styleShares.count > 1, abs(styleShares[1].fraction - top.fraction) < 0.05 {
            return "\(top.style) / \(styleShares[1].style)"
        }
        let percent = Int((top.fraction * 100).rounded())
        return "\(top.style) · \(percent) %"
    }

    var dominantStyleName: String? { styleShares.first?.style }

    /// Where, from 0 (left edge) to 1 (right edge), a given 1-based physical
    /// position sits among this shelf's currently stored copies.
    func relativePosition(of position: Int) -> Double {
        guard count > 0 else { return 0 }
        return min(1, max(0, Double(position) / Double(count)))
    }
}
