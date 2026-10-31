import AppIntents
import SwiftUI
import WidgetKit

/// The widget extension of Plattenregal.
@main
struct PlattenregalWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecordOfTheDayWidget()
    }
}

/// „Platte des Tages“: one record from the collection a day, from what the
/// app last wrote (`RecordOfTheDay`).
struct RecordOfTheDayWidget: Widget {
    static let kind = "de.private.Plattenregal.RecordOfTheDay"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: RecordOfTheDayConfiguration.self, provider: RecordOfTheDayProvider()) { entry in
            RecordOfTheDayView(snapshot: entry.snapshot, day: entry.day, family: entry.family, design: entry.design)
        }
        .configurationDisplayName("Platte des Tages")
        .description("Jeden Tag eine Platte aus deiner Sammlung – und wo sie im Regal steht.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        // The small one shows the cover edge to edge; the others keep the
        // app's padding themselves.
        .contentMarginsDisabled()
    }
}

/// The design of one widget: as in the app, or Klassisch or Modern of its
/// own („Widget bearbeiten“).
enum WidgetDesignChoice: String, AppEnum {
    case app, classic, modern

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Design" }
    static var caseDisplayRepresentations: [WidgetDesignChoice: DisplayRepresentation] {
        [.app: "Wie in der App", .classic: "Klassisch", .modern: "Modern"]
    }

    var design: RecordOfTheDay.Design? {
        switch self {
        case .app: nil
        case .classic: .classic
        case .modern: .modern
        }
    }
}

struct RecordOfTheDayConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Platte des Tages" }
    static var description: IntentDescription { "Jeden Tag eine Platte aus deiner Sammlung – und wo sie im Regal steht." }

    @Parameter(title: "Design", default: .app)
    var design: WidgetDesignChoice
}

nonisolated struct RecordOfTheDayEntry: TimelineEntry {
    let date: Date
    let snapshot: RecordOfTheDay?
    let day: RecordOfTheDay.Day?
    let family: WidgetFamily
    let design: RecordOfTheDay.Design?
}

/// Reads what the app wrote. One entry per day, from the start of that day;
/// a few days at a time, then the widget reads the file again. The app also
/// asks for a reload whenever it writes something new.
nonisolated struct RecordOfTheDayProvider: AppIntentTimelineProvider {
    /// Days per timeline: each entry is kept with its cover, so not all of them.
    static let entriesPerTimeline = 3
    /// Without anything written yet, the widget looks again after this.
    static let emptyRefresh: TimeInterval = 60 * 60

    func placeholder(in context: Context) -> RecordOfTheDayEntry {
        RecordOfTheDayEntry(date: Date(), snapshot: .sample, day: RecordOfTheDay.sample.days.first,
                            family: context.family, design: nil)
    }

    func snapshot(for configuration: RecordOfTheDayConfiguration, in context: Context) async -> RecordOfTheDayEntry {
        let now = Date()
        let stored = RecordOfTheDay.load()
        // The gallery shows the user's record of today, or an example.
        let snapshot = context.isPreview && stored?.day(at: now) == nil ? .sample : stored
        return RecordOfTheDayEntry(date: now, snapshot: snapshot, day: snapshot?.day(at: now),
                                   family: context.family, design: configuration.design.design)
    }

    func timeline(for configuration: RecordOfTheDayConfiguration, in context: Context) async -> Timeline<RecordOfTheDayEntry> {
        let now = Date()
        let design = configuration.design.design
        let snapshot = RecordOfTheDay.load()
        let days = Array((snapshot?.days(from: now) ?? []).prefix(Self.entriesPerTimeline))
        guard let first = days.first else {
            let entry = RecordOfTheDayEntry(date: now, snapshot: snapshot, day: nil, family: context.family, design: design)
            return Timeline(entries: [entry], policy: .after(now.addingTimeInterval(Self.emptyRefresh)))
        }
        // Today's from now on, each later one from the start of its day.
        let entries = [RecordOfTheDayEntry(date: now, snapshot: snapshot, day: first, family: context.family, design: design)]
            + days.dropFirst().map {
                RecordOfTheDayEntry(date: $0.date, snapshot: snapshot, day: $0, family: context.family, design: design)
            }
        // Read again when the last day shown begins – or, at the end of what
        // the app wrote, at the next midnight, in case it wrote more meanwhile.
        let calendar = Calendar.current
        let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        let refresh = days.count > 1 ? days[days.count - 1].date : nextDay
        return Timeline(entries: entries, policy: .after(refresh))
    }
}

extension RecordOfTheDay {
    /// The example in the widget gallery, before the app wrote anything.
    nonisolated static var sample: RecordOfTheDay {
        let day = RecordOfTheDay.Day(day: dayNumber(Date()), date: Calendar.current.startOfDay(for: Date()),
                                     copyID: UUID(), artist: "Boards of Canada",
                                     title: "Music Has the Right to Children", seed: 7,
                                     tracks: [("A1", "Wildlife Analysis"), ("A2", "An Eagle in Your Mind"), ("A3", "The Color of the Fire"),
                                              ("A4", "Telephasic Workshop"), ("B1", "Triangles & Rhombuses"), ("B2", "Sixtyten"),
                                              ("B3", "Turquoise Hexagon Sun"), ("B4", "Kaini Industries"), ("C1", "Bocuma"),
                                              ("C2", "Roygbiv"), ("C3", "Rue the Whirl")].map { TrackLine(position: $0.0, title: $0.1) },
                                     details: "1998 · Warp",
                                     place: String(localized: "Fach \(3)") + " · " + String(localized: "Position \(12)"), isPlaced: true, cover: nil)
        return RecordOfTheDay(design: .classic, classicFrame: .sleeve, accent: nil, days: [day], history: [])
    }
}
