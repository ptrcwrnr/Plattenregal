import SwiftUI

/// The card over the covers of "Platte hinzufügen" (the shelf the records go
/// to) and of the "Verlauf" (what it is for).
struct AssignmentCard<Trailing: View>: View {
    /// Covers in the lists below; the symbol is centered above them.
    static var coverSize: CGFloat { 38 }
    var systemImage = "square.grid.3x3.fill"
    let title: String
    let detail: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: AppStyle.rowSpacing) {
            Image(systemName: systemImage)
                .resizable()
                .frame(width: 24, height: 24)
                .foregroundStyle(AppStyle.accent)
                .frame(width: Self.coverSize)
            VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
                Text(title).font(.headline).lineLimit(1)
                // One line, so long names never grow the card.
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: AppStyle.itemSpacing)
            trailing
        }
        .padding(.horizontal, AppStyle.rowSpacing)
        .padding(.vertical, AppStyle.rowSpacing)
        // Flush with the outer covers of the grid below.
        .appCardSurface(cornerRadius: AppStyle.featureRadius)
    }
}

/// Rows of the shelf search, the "Gesucht" list and the sort check: the same height.
enum AssignmentRowMetrics {
    static let height: CGFloat = 52
    /// The large rows of "Platte hinzufügen" and the "Verlauf": the cover
    /// about as wide as in a compartment's grid.
    static let largeCoverSize: CGFloat = 132
}

/// What the open panel has done so far, at the card's trailing edge: the
/// count in the title's style, below it what was done in the detail's – two
/// lines level with those on the left, so the card keeps its height when the
/// count appears. Plain text, so it doesn't read as a button.
struct AssignmentTally: View {
    let count: Int
    /// "Platte einsortiert" for 1, "Platten einsortiert" otherwise.
    let one: String
    let many: String

    var body: some View {
        VStack(alignment: .trailing, spacing: AppStyle.hairSpacing) {
            Text(count, format: .number)
                .font(.headline).monospacedDigit()
                .contentTransition(.numericText(value: Double(count)))
            Text(count == 1 ? one : many)
                .font(.caption).foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
