import SwiftUI

// MARK: - Labels

/// The top labels as two rows of tiles on the page grid, the rest as a list on demand.
struct LabelBoard: View {
    let groups: [StatisticGroup]
    let total: Int
    let select: (StatisticGroup) -> Void
    @Environment(\.statisticsColumns) private var columns
    @State private var showsList = false

    private var boardCount: Int { columns * 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: StatisticsLayout.titleSpacing) {
            if groups.isEmpty { Text("Keine Angaben vorhanden").font(.callout).foregroundStyle(.secondary) }
            let maximum = CGFloat(max(1, groups.first?.count ?? 1))
            LazyVGrid(columns: StatisticsLayout.columns(columns), alignment: .leading, spacing: StatisticsLayout.gutter) {
                ForEach(Array(groups.prefix(boardCount).enumerated()), id: \.element.id) { index, group in
                    LabelTile(rank: index + 1, group: group, total: total, ratio: CGFloat(group.count) / maximum, select: select)
                }
            }
            if groups.count > boardCount {
                Button {
                    withAnimation(AppStyle.standardAnimation) { showsList.toggle() }
                } label: {
                    Label(showsList ? "Weitere Labels ausblenden" : "Alle \(groups.count) Labels", systemImage: showsList ? "chevron.up" : "chevron.down")
                }
                .appLinkButton().font(.caption)
                if showsList {
                    GroupStatisticsList(groups: Array(groups.dropFirst(boardCount)), total: total, columnCount: 2, select: select)
                        .transition(AppStyle.funnelTransition())
                }
            }
        }
    }

    private struct LabelTile: View {
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
                        Text("\(rank)").font(.system(.caption, design: AppStyle.figureDesign, weight: .bold)).foregroundStyle(AppStyle.accent)
                        Text(group.name).font(.callout.weight(.medium)).lineLimit(1)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: AppStyle.tightSpacing) {
                        Text(group.count.formatted()).font(.system(.title3, design: AppStyle.figureDesign, weight: .semibold)).monospacedDigit()
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
            .onHover { hovering = $0 }
            .animation(AppStyle.quickAnimation, value: hovering)
            .onAppear {
                if AppStyle.reduceMotion { grown = true } else { withAnimation(.smooth(duration: 0.7).delay(0.05)) { grown = true } }
            }
            .help("\(AppStyle.records(group.count)) von \(group.name) anzeigen")
        }
    }
}
