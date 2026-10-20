import SwiftUI

// MARK: - Facts

struct StatisticsFacts: View {
    let statistics: CollectionStatistics
    let select: (StatisticGroup) -> Void

    private struct Fact: Identifiable {
        let title: String, value: String, detail: String, systemImage: String, color: Color
        var group: StatisticGroup?
        var help: String?
        var id: String { title }
    }

    private var facts: [Fact] {
        var facts: [Fact] = []
        let total = statistics.totalItems
        if let artist = statistics.artists.first {
            facts.append(.init(title: String(localized: "Häufigster Künstler"), value: artist.name, detail: "\(AppStyle.records(artist.count)) · \(artist.percentage(of: total))", systemImage: "music.mic", color: .blue, group: artist))
        }
        if let style = statistics.styles.first {
            facts.append(.init(title: String(localized: "Häufigster Style"), value: style.name, detail: "\(AppStyle.records(style.count)) · \(style.percentage(of: total))", systemImage: "waveform", color: .teal, group: style))
        }
        if let decade = statistics.decades.max(by: { $0.count < $1.count }) {
            facts.append(.init(title: String(localized: "Stärkstes Jahrzehnt"), value: decade.name, detail: "\(AppStyle.records(decade.count))", systemImage: "calendar", color: .indigo, group: decade))
        }
        if let year = statistics.years.max(by: { $0.count < $1.count }) {
            facts.append(.init(title: String(localized: "Häufigstes Jahr"), value: year.name, detail: "\(AppStyle.records(year.count))", systemImage: "star", color: .purple, group: year))
        }
        let thisYear = Calendar.current.component(.year, from: .now)
        // Compared with the same stretch of last year, not all of it: early in
        // the year a whole previous year would always look like much more.
        let current = statistics.addedThisYear, previous = statistics.addedLastYearToDate
        let comparison = current > previous ? String(localized: "\(current - previous) mehr als im Vorjahreszeitraum")
            : current < previous ? String(localized: "\(previous - current) weniger als im Vorjahreszeitraum")
            : String(localized: "genauso viele wie im Vorjahreszeitraum")
        let period = Date.now.formatted(.dateTime.day().month(.abbreviated))
        facts.append(.init(title: String(localized: "Neu in \(String(thisYear))"), value: "\(AppStyle.records(current))", detail: comparison, systemImage: "plus.circle", color: .orange,
                           help: String(localized: "1. Jan. bis \(period): \(current) in \(String(thisYear)), \(previous) in \(String(thisYear - 1))")))
        return facts
    }

    @Environment(\.statisticsColumns) private var columns

    var body: some View {
        LazyVGrid(columns: StatisticsLayout.columns(columns), alignment: .leading, spacing: StatisticsLayout.gutter) {
            ForEach(facts) { fact in
                FactTile(fact: fact, select: select)
            }
        }
    }

    private struct FactTile: View {
        let fact: Fact
        let select: (StatisticGroup) -> Void
        @State private var hovering = false
        var body: some View {
            Button { if let group = fact.group { select(group) } } label: {
                VStack(alignment: .leading, spacing: AppStyle.itemSpacing) {
                    HStack(spacing: AppStyle.itemSpacing) {
                        // Klassisch: one petrol for all, no rainbow.
                        Image(systemName: fact.systemImage)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(AppStyle.isAtelier ? AppStyle.accent : fact.color)
                            .frame(width: 28, height: 28)
                            .background(AppStyle.isAtelier ? AtelierPalette.soft : fact.color.opacity(0.14), in: RoundedRectangle(cornerRadius: AppStyle.rowRadius))
                        Text(fact.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                        if fact.group != nil {
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                .opacity(hovering ? 1 : 0)
                        }
                    }
                    VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
                        Text(fact.value).font(.headline).lineLimit(1)
                        Text(fact.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .padding(StatisticsLayout.tilePadding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .statisticsTile(hovering: hovering && fact.group != nil)
                .contentShape(RoundedRectangle(cornerRadius: AppStyle.cardRadius))
            }
            .buttonStyle(.plain)
            // Tiles without records to open still take the pointer for their tooltip.
            .allowsHitTesting(fact.group != nil || fact.help != nil)
            .onHover { hovering = $0 }
            .animation(AppStyle.quickAnimation, value: hovering)
            .help(fact.help ?? fact.group.map { String(localized: "\(AppStyle.records($0.count)) mit \($0.name) anzeigen") } ?? "")
        }
    }
}
