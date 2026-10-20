import SwiftUI

// MARK: - Artist podium

/// The top artists as a row of covers with their rank, the rest as a list on demand.
struct ArtistPodium: View {
    let groups: [StatisticGroup]
    let total: Int
    let copies: [UUID: RecordCopy]
    let select: (StatisticGroup) -> Void
    @Environment(\.statisticsColumns) private var podiumCount
    @State private var showsList = false

    var body: some View {
        VStack(alignment: .leading, spacing: StatisticsLayout.titleSpacing) {
            if groups.isEmpty { Text("Keine Angaben vorhanden").font(.callout).foregroundStyle(.secondary) }
            LazyVGrid(columns: StatisticsLayout.columns(podiumCount), alignment: .leading, spacing: StatisticsLayout.gutter) {
                ForEach(Array(groups.prefix(podiumCount).enumerated()), id: \.element.id) { index, group in
                    ArtistTile(rank: index + 1, group: group, total: total, cover: cover(for: group), select: select)
                }
            }
            if groups.count > podiumCount {
                Button {
                    withAnimation(AppStyle.standardAnimation) { showsList.toggle() }
                } label: {
                    Label(showsList ? "Rangliste ausblenden" : "Rangliste ab Platz \(podiumCount + 1)", systemImage: showsList ? "chevron.up" : "chevron.down")
                }
                .appLinkButton().font(.caption)
                if showsList {
                    GroupStatisticsList(groups: Array(groups.dropFirst(podiumCount)), total: total, columnCount: 2, select: select)
                        .transition(AppStyle.funnelTransition())
                }
            }
        }
    }

    /// A representative cover that stays the same across launches and a new
    /// sync (copy IDs don't): the artist's earliest release, then by title.
    private func cover(for group: StatisticGroup) -> String? {
        group.copyIDs.compactMap { copies[$0]?.release }
            .filter { $0.coverURL != nil }
            .min { lhs, rhs in
                let left = lhs.year ?? Int.max, right = rhs.year ?? Int.max
                if left != right { return left < right }
                let order = lhs.displayTitle.localizedStandardCompare(rhs.displayTitle)
                return order == .orderedSame ? lhs.discogsID < rhs.discogsID : order == .orderedAscending
            }?
            .coverURL
    }

    private struct ArtistTile: View {
        let rank: Int
        let group: StatisticGroup
        let total: Int
        let cover: String?
        let select: (StatisticGroup) -> Void
        @State private var hovering = false
        var body: some View {
            Button { select(group) } label: {
                VStack(alignment: .leading, spacing: AppStyle.itemSpacing) {
                    // The rank sits by the name, as on the label tiles: on
                    // the cover it hid the artwork's own lettering.
                    CoverView(url: cover, size: nil)
                        .atelierRecordSleeve()
                        .shadow(color: .black.opacity(AppStyle.isAtelier ? 0 : hovering ? 0.25 : 0.1), radius: hovering ? 10 : 4, y: hovering ? 6 : 2)
                        .scaleEffect(hovering ? 1.03 : 1)
                    VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
                        HStack(alignment: .firstTextBaseline, spacing: AppStyle.tightSpacing) {
                            Text("\(rank)").font(.system(.caption, design: AppStyle.figureDesign, weight: .bold)).foregroundStyle(AppStyle.accent)
                            Text(group.name).font(.callout.weight(.medium)).lineLimit(1)
                        }
                        Text("\(AppStyle.records(group.count)) · \(group.percentage(of: total))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(AppStyle.quickAnimation, value: hovering)
            .help("\(AppStyle.records(group.count)) von \(group.name) anzeigen")
        }
    }
}
