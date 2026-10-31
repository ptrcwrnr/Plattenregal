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
        StaticConfiguration(kind: Self.kind, provider: RecordOfTheDayProvider()) { entry in
            RecordOfTheDayView(snapshot: entry.snapshot, day: entry.day)
        }
        .configurationDisplayName("Platte des Tages")
        .description("Jeden Tag eine Platte aus deiner Sammlung – und wo sie im Regal steht.")
        // One size: cover, caption and rack need the medium's width.
        .supportedFamilies([.systemMedium])
        // The view keeps the app's padding itself (`DesignScale.cardPadding`).
        .contentMarginsDisabled()
    }
}

nonisolated struct RecordOfTheDayEntry: TimelineEntry {
    let date: Date
    let snapshot: RecordOfTheDay?
    let day: RecordOfTheDay.Day?
}

/// Reads what the app wrote. One entry per day, from the start of that day;
/// a few days at a time, then the widget reads the file again. The app also
/// asks for a reload whenever it writes something new.
nonisolated struct RecordOfTheDayProvider: TimelineProvider {
    /// Days per timeline: each entry is kept with its cover, so not all of them.
    static let entriesPerTimeline = 3

    func placeholder(in context: Context) -> RecordOfTheDayEntry {
        RecordOfTheDayEntry(date: Date(), snapshot: .sample, day: RecordOfTheDay.sample.days.first)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecordOfTheDayEntry) -> Void) {
        let now = Date()
        let stored = RecordOfTheDay.load()
        // The gallery shows the user's record of today, or an example.
        let snapshot = context.isPreview && stored?.day(at: now) == nil ? .sample : stored
        completion(RecordOfTheDayEntry(date: now, snapshot: snapshot, day: snapshot?.day(at: now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecordOfTheDayEntry>) -> Void) {
        let snapshot = RecordOfTheDay.load()
        let plan = RecordOfTheDay.plan(snapshot, now: Date(), count: Self.entriesPerTimeline)
        let entries = plan.entries.map { RecordOfTheDayEntry(date: $0.date, snapshot: snapshot, day: $0.day) }
        completion(Timeline(entries: entries, policy: .after(plan.refresh)))
    }
}

extension RecordOfTheDay {
    /// The example in the widget gallery, before the app wrote anything.
    nonisolated static var sample: RecordOfTheDay {
        let rack = Rack(columns: 4, rows: 3, compartment: 9, locked: [0, 1],
                        label: "B – De", position: 14)
        let day = RecordOfTheDay.Day(day: dayNumber(Date()), date: Calendar.current.startOfDay(for: Date()),
                                     copyID: UUID(), artist: "Boards of Canada",
                                     title: "Music Has the Right to Children", seed: 7,
                                     details: "1998 · Warp",
                                     place: String(localized: "Fach \(10)") + " · " + String(localized: "Position \(14)"),
                                     isPlaced: true, rack: rack, cover: nil)
        return RecordOfTheDay(days: [day], history: [])
    }
}
