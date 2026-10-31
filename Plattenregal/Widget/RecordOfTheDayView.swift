import AppKit
import SwiftUI
import WidgetKit

/// The widget „Platte des Tages“ (medium only): today's record with its
/// cover, as in the app's grids, beside artist, title, year · label and where
/// it stands on the shelf. In the design the app is set to, or the one chosen
/// for the widget (Klassisch or Modern). Part of the widget and of the app,
/// whose tests draw it.
struct RecordOfTheDayView: View {
    let snapshot: RecordOfTheDay?
    let day: RecordOfTheDay.Day?
    /// Chosen for this widget; nil = as in the app.
    var design: RecordOfTheDay.Design? = nil
    /// Where the covers are read from.
    var folder: URL? = RecordOfTheDay.folderURL

    var body: some View {
        let look = WidgetLook(snapshot, design: design)
        Group {
            if let day {
                MediumRecordView(day: day, cover: WidgetCover(day: day, look: look, folder: folder), look: look)
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

    /// The cover itself, square, without the frame.
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
