import SwiftUI

/// The card over the covers of "Platte hinzufügen": the shelf the records go to.
struct AssignmentCard<Trailing: View>: View {
    /// Covers in the lists below; the symbol is centered above them.
    static var coverSize: CGFloat { 38 }
    let title: String
    let detail: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: AppStyle.rowSpacing) {
            Image(systemName: "square.grid.3x3.fill")
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
}
