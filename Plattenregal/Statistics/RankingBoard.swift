import SwiftUI

// MARK: - Top artists and labels

/// The top ten artists or labels as tiles with rank, count and a bar – one
/// building block for both cards, so they look and behave the same. No
/// covers and no further ranking: ten places, and that's it.
struct RankingBoard: View {
    let groups: [StatisticGroup]
    let total: Int
    let select: (StatisticGroup) -> Void
    @Environment(\.statisticsColumns) private var pageColumns

    var body: some View {
        VStack(alignment: .leading, spacing: StatisticsLayout.titleSpacing) {
            if groups.isEmpty { Text("Keine Angaben vorhanden").font(.callout).foregroundStyle(.secondary) }
            let maximum = CGFloat(max(1, groups.first?.count ?? 1))
            LazyVGrid(columns: StatisticsLayout.columns(StatisticsLayout.rankingColumns(page: pageColumns)), alignment: .leading, spacing: StatisticsLayout.gutter) {
                ForEach(Array(groups.prefix(StatisticsLayout.rankingCount).enumerated()), id: \.element.id) { index, group in
                    RankingTile(rank: index + 1, group: group, total: total, ratio: CGFloat(group.count) / maximum, select: select)
                }
            }
        }
    }

    private struct RankingTile: View {
        let rank: Int
        let group: StatisticGroup
        let total: Int
        let ratio: CGFloat
        let select: (StatisticGroup) -> Void
        @State private var hovering = false
        @State private var grown = false
        var body: some View {
            Button { select(group) } label: {
                VStack(alignment: .leading, spacing: AppStyle.itemSpacing) {
                    HStack(alignment: .firstTextBaseline, spacing: AppStyle.tightSpacing) {
                        Text("\(rank)").font(AppStyle.rankFigure).foregroundStyle(AppStyle.accent)
                        Text(group.name).font(AppStyle.rowTitle).lineLimit(1)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: AppStyle.tightSpacing) {
                        Text(group.count.formatted()).font(AppStyle.figureHeading).monospacedDigit()
                        Text("\(group.count == 1 ? String(localized: "Platte") : String(localized: "Platten")) · \(group.percentage(of: total))").font(.caption).foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        Capsule().fill(Color.primary.opacity(0.06))
                        Capsule().fill(AppStyle.accent.opacity(hovering ? 1 : 0.65))
                            .frame(width: geo.size.width * ratio * (grown ? 1 : 0))
                    }
                    .frame(height: 4)
                }
                .padding(StatisticsLayout.tilePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .statisticsTile(hovering: hovering)
                .contentShape(RoundedRectangle(cornerRadius: AppStyle.cardRadius))
            }
            .buttonStyle(.plain)
            .statisticsHover { hovering = $0 }
            .animation(AppStyle.quickAnimation, value: hovering)
            .onAppear {
                if AppStyle.reduceMotion { grown = true } else { withAnimation(AppStyle.growAnimation) { grown = true } }
            }
            .help("\(AppStyle.records(group.count)) von \(group.name) anzeigen")
        }
    }
}
