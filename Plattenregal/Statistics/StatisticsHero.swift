import SwiftUI
import Charts

struct StatisticsHero: View {
    let statistics: CollectionStatistics
    let history: [CollectionValueSnapshot]
    let hasOwner: Bool
    let hasToken: Bool
    @Environment(\.statisticsColumns) private var columns
    @State private var width: CGFloat = 0

    private var sameCurrency: [CollectionValueSnapshot] {
        guard let currency = history.last?.currency else { return [] }
        return history.filter { $0.currency == currency }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StatisticsLayout.gutter) {
            // Value on the first two columns, the curve on the remaining ones.
            HStack(alignment: .center, spacing: StatisticsLayout.gutter) {
                valueBlock.frame(width: StatisticsLayout.span(2, of: columns, in: width), alignment: .leading)
                sparkline.frame(maxWidth: .infinity)
            }
            LazyVGrid(columns: StatisticsLayout.columns(columns), alignment: .leading, spacing: StatisticsLayout.gutter) {
                figure(String(localized: "Schallplatten"), statistics.totalItems, "opticaldisc")
                figure(String(localized: "Releases"), statistics.uniqueReleases, "square.stack")
                figure(String(localized: "Künstler"), statistics.artists.count, "music.mic")
                figure(String(localized: "Styles"), statistics.styles.count, "waveform")
                figure(String(localized: "Labels"), statistics.labels.count, "tag")
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
    }

    @ViewBuilder private var valueBlock: some View {
        if let latest = sameCurrency.last {
            VStack(alignment: .leading, spacing: AppStyle.itemSpacing) {
                Text("Sammlungswert · Median").font(.callout).foregroundStyle(.secondary)
                RollingNumber(value: NSDecimalNumber(decimal: latest.medianValue).doubleValue) {
                    DiscogsMoney.format(Decimal($0.rounded()), currency: latest.currency)
                }
                .font(AppStyle.heroFigure)
                // The digits' own side bearing, so the number starts at
                // the edge of the words above and below it.
                .padding(.leading, -3)
                .lineLimit(1).minimumScaleFactor(0.6)
                HStack(spacing: AppStyle.itemSpacing) {
                    if sameCurrency.count >= 2 { DeltaChip(current: latest.medianValue, previous: sameCurrency[sameCurrency.count - 2].medianValue, currency: latest.currency) }
                    Text("Spanne \(DiscogsMoney.format(latest.minimumValue, currency: latest.currency)) – \(DiscogsMoney.format(latest.maximumValue, currency: latest.currency))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(([latest.averagePerItem.map { String(localized: "≈ \(DiscogsMoney.format($0, currency: latest.currency)) pro Platte") }]
                      + [String(localized: "Stand \(latest.date.formatted(date: .abbreviated, time: .shortened))")]).compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.tertiary)
            }
        } else {
            VStack(alignment: .leading, spacing: AppStyle.itemSpacing) {
                Text("Schallplatten in der Sammlung").font(.callout).foregroundStyle(.secondary)
                RollingNumber(value: Double(statistics.totalItems)) { Int($0.rounded()).formatted() }
                    .font(AppStyle.heroFigure)
                // The digits' own side bearing, so the number starts at
                // the edge of the words above and below it.
                .padding(.leading, -3)
                Text(!hasOwner ? "Verbinde eine Discogs-Collection, um ihren Wert zu verfolgen."
                     : !hasToken ? "Für den Sammlungswert fehlt der Discogs-Token. Trage ihn in den Einstellungen ein."
                     : "Noch kein Sammlungswert. Zum Laden die Seite nach unten ziehen oder ⌘R drücken.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var sparkline: some View {
        if sameCurrency.count >= 2 {
            Chart(sameCurrency) { snapshot in
                let value = NSDecimalNumber(decimal: snapshot.medianValue).doubleValue
                AreaMark(x: .value("Datum", snapshot.date), y: .value("Wert", value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(colors: [AppStyle.accent.opacity(0.35), AppStyle.accent.opacity(0)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Datum", snapshot.date), y: .value("Wert", value))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .foregroundStyle(AppStyle.accent)
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 96)
            .accessibilityLabel("Verlauf des Sammlungswerts")
        }
    }

    private func figure(_ title: String, _ value: Int, _ systemImage: String) -> some View {
        HStack(spacing: AppStyle.rowSpacing) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppStyle.accent)
                .frame(width: 34, height: 34)
                .background(AppStyle.isAtelier ? AtelierPalette.soft : AppStyle.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                RollingNumber(value: Double(value)) { Int($0.rounded()).formatted() }
                    .font(.system(.title2, design: AppStyle.figureDesign, weight: .semibold))
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(StatisticsLayout.tilePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .statisticsTile()
    }
}

/// Small capsule with the change since the previous snapshot.
private struct DeltaChip: View {
    let current: Decimal
    let previous: Decimal
    let currency: String
    var body: some View {
        let change = CollectionValueHistoryService.change(current: current, previous: previous)
        let color: Color = change.amount > 0 ? AppStyle.successColor : change.amount < 0 ? AppStyle.errorColor : .secondary
        HStack(spacing: AppStyle.tightSpacing) {
            Image(systemName: change.amount > 0 ? "arrow.up.right" : change.amount < 0 ? "arrow.down.right" : "equal")
            Text((change.amount > 0 ? "+" : "") + DiscogsMoney.format(change.amount, currency: currency))
            if let percent = change.percent {
                Text("(" + (percent > 0 ? "+" : "") + (percent / 100).formatted(.percent.precision(.fractionLength(2))) + ")")
            }
        }
        .font(.caption.weight(.semibold)).monospacedDigit()
        .foregroundStyle(color)
        .padding(.horizontal, AppStyle.itemSpacing).padding(.vertical, AppStyle.tightSpacing)
        .background(color.opacity(0.12), in: Capsule())
        .help("Veränderung seit der letzten Momentaufnahme")
    }
}
