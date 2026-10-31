import AppKit
import SwiftUI
import WidgetKit

/// The widget „Platte des Tages“: today's record with its cover, as in the
/// app's grids, and where it stands on the shelf. Small shows the cover with
/// artist and place on a band at its foot, medium the cover beside the
/// caption, large both over the record's tracks. In the design the app is
/// set to, or the one chosen for the widget (Klassisch or Modern).
/// Part of the widget and of the app, whose tests draw it.
struct RecordOfTheDayView: View {
    let snapshot: RecordOfTheDay?
    let day: RecordOfTheDay.Day?
    let family: WidgetFamily
    /// Chosen for this widget; nil = as in the app.
    var design: RecordOfTheDay.Design? = nil
    /// Where the covers are read from.
    var folder: URL? = RecordOfTheDay.folderURL
    /// How macOS draws the widget; set only by the tests, which have no
    /// widget around them.
    var renderingMode: WidgetRenderingMode?
    @Environment(\.widgetRenderingMode) private var systemRenderingMode

    var body: some View {
        let look = WidgetLook(snapshot, design: design)
        // In color, or – with „Widgets auf dem Schreibtisch abdunkeln“ while
        // an app is in front – in one tint on glass: backgrounds gone, text
        // and shapes in the tint, only the covers keep their colors.
        let inColor = (renderingMode ?? systemRenderingMode) == .fullColor
        Group {
            if let day {
                let cover = WidgetCover(day: day, look: look, folder: folder)
                switch family {
                case .systemSmall:
                    if inColor { SmallRecordView(day: day, cover: cover, look: look) }
                    else { SmallTintedRecordView(day: day, cover: cover, look: look) }
                case .systemLarge: LargeRecordView(day: day, cover: cover, look: look)
                default: MediumRecordView(day: day, cover: cover, look: look)
                }
            } else {
                EmptyRecordView(look: look, hasSnapshot: snapshot != nil)
            }
        }
        .widgetURL(day.map { RecordOfTheDay.link(to: $0.copyID) })
        .containerBackground(for: .widget) { look.background }
    }
}

/// The colors and frame of the widget's design.
struct WidgetLook {
    let isClassic: Bool
    let frame: RecordFrame
    let accent: Color

    /// `design`: chosen for the widget; nil = as in the app – or, without
    /// anything written yet, Klassisch like the handbook.
    init(_ snapshot: RecordOfTheDay?, design: RecordOfTheDay.Design? = nil) {
        isClassic = (design ?? snapshot?.design ?? .classic) == .classic
        frame = isClassic ? snapshot?.classicFrame ?? .sleeve : .modernMat
        accent = isClassic ? AtelierPalette.accent : snapshot?.accent.map(Self.color) ?? .accentColor
    }

    var ink: Color { isClassic ? AtelierPalette.ink : .primary }
    var muted: Color { isClassic ? AtelierPalette.muted : .secondary }
    var background: Color { isClassic ? AtelierPalette.paper : Color(nsColor: .windowBackgroundColor) }

    /// The band across the foot of the small widget's cover, like the obi on
    /// a record: petrol like Klassisch's toolbar, the window's color in Modern.
    var band: Color { isClassic ? AtelierPalette.petrol : Color(nsColor: .windowBackgroundColor) }
    var bandInk: Color { isClassic ? .white : .primary }
    var bandMuted: Color { isClassic ? AtelierPalette.bandLabel : .secondary }

    private static func color(_ tint: RecordOfTheDay.Tint) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? tint.dark : tint.light
            guard rgb.count == 3 else { return .controlAccentColor }
            return NSColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
        })
    }
}

/// The cover the app wrote for the day – or, while it has none (no network
/// when it was written), the record drawn like the app's drawn covers.
struct WidgetCover: View {
    let day: RecordOfTheDay.Day
    let look: WidgetLook
    let folder: URL?
    /// Drawn covers at this edge are sharp on the large widget.
    static let drawnPixels = 640

    var image: NSImage? {
        if let name = day.cover, let file = RecordOfTheDay.coverURL(name, in: folder),
           let image = NSImage(contentsOf: file) {
            return image
        }
        let address = DemoCover.url(artist: day.artist, title: day.title, seed: day.seed)
        return URL(string: address).flatMap { DemoCover.render($0, pixelSize: Self.drawnPixels) }
            .map { NSImage(cgImage: $0, size: .zero) }
    }

    /// Square, as large as the room allows, in the app's frame.
    var body: some View {
        plain
            .clipShape(RoundedRectangle(cornerRadius: look.frame.coverRadius))
            .recordFrame(look.frame)
            .aspectRatio(1, contentMode: .fit)
    }

    /// Without frame: filling the small widget.
    var plain: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high)
                    // Album art keeps its colors when macOS tints the widget.
                    .widgetAccentedRenderingMode(.fullColor)
                    .scaledToFill()
            } else {
                Rectangle().fill(look.muted.opacity(0.2))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        // Covers that aren't square fill the square, never more.
        .clipped()
        .accessibilityHidden(true)
    }
}

/// Where the record stands, with the shelf's symbol: filled where it
/// stands, outlined where it only belongs.
struct WidgetPlace: View {
    let day: RecordOfTheDay.Day
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignScale.tightSpacing) {
            Image(systemName: day.isPlaced ? "square.grid.3x3.fill" : "square.grid.3x3")
            Text(Self.keepingNumber(day.place))
        }
        .font(DesignScale.captionLabel)
        .foregroundStyle(color)
    }

    /// „… · Position 14“ never breaks between the word and its number.
    static func keepingNumber(_ place: String) -> String {
        guard let range = place.range(of: #" (\d+)$"#, options: .regularExpression) else { return place }
        return place.replacingCharacters(in: range.lowerBound..<place.index(after: range.lowerBound), with: "\u{00A0}")
    }
}

/// The kicker over the caption.
struct WidgetKicker: View {
    let look: WidgetLook
    var body: some View {
        Text("Platte des Tages")
            .font(DesignScale.captionMark)
            .foregroundStyle(look.accent)
            .lineLimit(1)
            // Tinted apart from the rest when macOS draws the widget in one tint.
            .widgetAccentable()
    }
}

/// Artist, title and year · label, as under the covers in the app.
struct WidgetCaption: View {
    let day: RecordOfTheDay.Day
    let look: WidgetLook
    var titleLines = 1

    var body: some View {
        VStack(alignment: .leading, spacing: DesignScale.hairSpacing) {
            Text(day.artist).font(.headline).foregroundStyle(look.ink).lineLimit(1)
            Text(day.title).font(.subheadline).foregroundStyle(look.muted).lineLimit(titleLines)
            if !day.details.isEmpty {
                Text(day.details).font(.caption).foregroundStyle(look.muted).lineLimit(1)
            }
        }
    }
}

/// Fixed sizes of the widget's layout.
enum WidgetMetrics {
    /// The cover beside the caption on the large widget: room below for the tracks.
    static let largeCoverEdge: CGFloat = 148
    /// Tracks the large widget lists; more are counted.
    static let largeTrackCount = 9
}

/// The cover filling the widget, artist and place on a band at its foot –
/// solid, so lettering on the cover never runs into them.
struct SmallRecordView: View {
    let day: RecordOfTheDay.Day
    let cover: WidgetCover
    let look: WidgetLook

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: DesignScale.hairSpacing) {
                Text(day.artist).font(.headline).foregroundStyle(look.bandInk).lineLimit(1)
                WidgetPlace(day: day, color: look.bandMuted).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignScale.rowSpacing)
            .padding(.vertical, DesignScale.itemSpacing)
            .background(look.band)
        }
        .background { cover.plain }
        .clipped()
    }
}

/// The small widget while macOS tints it: the band would lose its color and
/// its text would stand on the cover unreadable, so the artist goes below.
struct SmallTintedRecordView: View {
    let day: RecordOfTheDay.Day
    let cover: WidgetCover
    let look: WidgetLook

    var body: some View {
        VStack(alignment: .leading, spacing: DesignScale.itemSpacing) {
            cover.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            Text(day.artist).font(.headline).foregroundStyle(look.ink).lineLimit(1)
        }
        .padding(DesignScale.cardPadding)
    }
}

/// The cover beside the caption, the place at its foot.
struct MediumRecordView: View {
    let day: RecordOfTheDay.Day
    let cover: WidgetCover
    let look: WidgetLook

    var body: some View {
        HStack(alignment: .top, spacing: DesignScale.cardPadding) {
            cover
            VStack(alignment: .leading, spacing: DesignScale.tightSpacing) {
                WidgetKicker(look: look)
                WidgetCaption(day: day, look: look, titleLines: 2)
                Spacer(minLength: 0)
                WidgetPlace(day: day, color: look.ink).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignScale.cardPadding)
    }
}

/// The medium widget's top – cover beside caption and place – over the
/// record's tracks. Without tracks (not loaded yet) the cover takes the room.
struct LargeRecordView: View {
    let day: RecordOfTheDay.Day
    let cover: WidgetCover
    let look: WidgetLook

    var body: some View {
        VStack(alignment: .leading, spacing: DesignScale.rowSpacing) {
            if day.tracks.isEmpty {
                cover.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: DesignScale.tightSpacing) {
                    WidgetKicker(look: look)
                    WidgetCaption(day: day, look: look, titleLines: 2)
                    WidgetPlace(day: day, color: look.ink).lineLimit(1)
                        .padding(.top, DesignScale.hairSpacing)
                }
            } else {
                HStack(alignment: .top, spacing: DesignScale.cardPadding) {
                    cover.frame(width: WidgetMetrics.largeCoverEdge, height: WidgetMetrics.largeCoverEdge)
                    VStack(alignment: .leading, spacing: DesignScale.tightSpacing) {
                        WidgetKicker(look: look)
                        WidgetCaption(day: day, look: look, titleLines: 2)
                        Spacer(minLength: 0)
                        WidgetPlace(day: day, color: look.ink).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: WidgetMetrics.largeCoverEdge, alignment: .leading)
                }
                WidgetTracks(tracks: day.tracks, look: look)
                Spacer(minLength: 0)
            }
        }
        .padding(DesignScale.cardPadding)
    }
}

/// The first tracks, position and title as in the record's popover.
struct WidgetTracks: View {
    let tracks: [RecordOfTheDay.TrackLine]
    let look: WidgetLook

    var body: some View {
        let shown = tracks.prefix(WidgetMetrics.largeTrackCount)
        VStack(alignment: .leading, spacing: DesignScale.hairSpacing) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, track in
                HStack(alignment: .firstTextBaseline, spacing: DesignScale.itemSpacing) {
                    Text(track.position).foregroundStyle(look.muted).monospacedDigit()
                    Text(track.title).foregroundStyle(look.ink).lineLimit(1)
                }
            }
            if tracks.count > shown.count {
                Text("+ \(tracks.count - shown.count) weitere").foregroundStyle(look.muted)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Nothing to show yet: the app hasn't written anything, or the collection
/// is empty.
struct EmptyRecordView: View {
    let look: WidgetLook
    let hasSnapshot: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DesignScale.itemSpacing) {
            Image(systemName: "opticaldisc")
                .font(DesignScale.emptyStateSymbol)
                .foregroundStyle(look.accent)
            WidgetKicker(look: look)
            Text(hasSnapshot ? "Noch keine Platten in deiner Collection." : "Öffne Plattenregal einmal, dann liegt hier jeden Tag eine Platte aus deiner Sammlung.")
                .font(.caption)
                .foregroundStyle(look.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(DesignScale.cardPadding)
    }
}
