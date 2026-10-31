import AppKit
import SwiftUI
import WidgetKit

/// The widget „Platte des Tages“ (medium only), in the paper of Klassisch:
/// today's record as a sleeve beside artist and title, below them the
/// cabinet in small with the record's compartment in gold – filled where it
/// stands, outlined where it only belongs – and its name and position.
/// Light and dark follow the system. Part of the widget and of the app,
/// whose tests draw it.
///
/// When macOS dims desktop widgets (an app in front), it drops the paper and
/// draws everything in one tint on glass; the cover keeps its colors and the
/// gold compartment is tinted apart from the rest (`widgetAccentable`).
struct RecordOfTheDayView: View {
    let snapshot: RecordOfTheDay?
    let day: RecordOfTheDay.Day?
    /// Where the covers are read from.
    var folder: URL? = RecordOfTheDay.folderURL

    var body: some View {
        Group {
            if let day {
                RackRecordView(day: day, cover: WidgetCover(day: day, folder: folder))
            } else {
                EmptyRecordView(hasSnapshot: snapshot != nil)
            }
        }
        .widgetURL(day.map { RecordOfTheDay.link(to: $0.copyID) })
        .containerBackground(for: .widget) { AtelierPalette.paper }
    }
}

/// Sizes of the drawn rack (geometry, not spacing): it always fits the same
/// box, so a 6 × 6 cabinet gets smaller cells than a 4 × 3 one, never larger
/// ones than `cellHeight`.
enum RackMetrics {
    static let boxWidth: CGFloat = 92
    /// Holds three rows of full cells: a 4 × 3 KALLAX as in the mockup.
    static let boxHeight: CGFloat = 49
    static let cellHeight: CGFloat = 13
    /// Width to height of a cell, like a KALLAX compartment seen from the front.
    static let cellAspect: CGFloat = 1.3
    static let gap: CGFloat = 2
    /// Between the frame and the cells.
    static let inset: CGFloat = 3
    static let cellRadius: CGFloat = 2
    static let frameRadius: CGFloat = 4

    /// The cell size for a cabinet of `columns` × `rows` inside the box.
    static func cell(columns: Int, rows: Int) -> CGSize {
        let columns = CGFloat(max(columns, 1)), rows = CGFloat(max(rows, 1))
        let byHeight = (boxHeight - 2 * inset - (rows - 1) * gap) / rows
        let byWidth = (boxWidth - 2 * inset - (columns - 1) * gap) / columns / cellAspect
        let height = max(1, min(cellHeight, byHeight, byWidth))
        return CGSize(width: height * cellAspect, height: height)
    }
}

/// The cover the app wrote for the day – or, while it has none (no network
/// when it was written), the record drawn like the app's drawn covers.
struct WidgetCover: View {
    let day: RecordOfTheDay.Day
    let folder: URL?
    /// Drawn covers at this edge stay sharp.
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

    /// Square, as large as the height allows, as a sleeve like in Klassisch.
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high)
                    // Album art keeps its colors when macOS tints the widget.
                    .widgetAccentedRenderingMode(.fullColor)
                    .scaledToFill()
            } else {
                Rectangle().fill(AtelierPalette.soft)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        // Covers that aren't square fill the square, never more.
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: RecordFrame.sleeve.coverRadius))
        .recordFrame(.sleeve)
        .accessibilityHidden(true)
    }
}

/// The record beside its cover, the rack at the foot.
struct RackRecordView: View {
    let day: RecordOfTheDay.Day
    let cover: WidgetCover

    var body: some View {
        HStack(alignment: .top, spacing: DesignScale.cardPadding) {
            cover
            VStack(alignment: .leading, spacing: DesignScale.tightSpacing) {
                Text("Platte des Tages")
                    .font(DesignScale.captionMark)
                    .foregroundStyle(AtelierPalette.accent)
                    .widgetAccentable()
                    .lineLimit(1)
                Text(day.artist).font(.headline).foregroundStyle(AtelierPalette.ink).lineLimit(1)
                Text(day.title).font(.subheadline).foregroundStyle(AtelierPalette.muted).lineLimit(1)
                Spacer(minLength: 0)
                if let rack = day.rack {
                    HStack(alignment: .bottom, spacing: DesignScale.rowSpacing) {
                        RackView(rack: rack)
                        VStack(alignment: .leading, spacing: DesignScale.hairSpacing) {
                            Text(rack.label)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(AtelierPalette.ink)
                                .lineLimit(1)
                            Text(rack.position.map { String(localized: "Position \($0)") }
                                 ?? String(localized: "Noch nicht einsortiert"))
                                .font(.caption)
                                .foregroundStyle(AtelierPalette.muted)
                                .lineLimit(1)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(day.place)
                } else {
                    // „Ohne Regalplatz“, or no shelf to belong in yet.
                    WidgetPlace(day: day, color: AtelierPalette.ink).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DesignScale.cardPadding)
    }
}

/// The cabinet in small: every compartment in its place, locked ones and
/// places without a compartment hollow, the record's in gold – filled where
/// it stands, outlined where it belongs.
struct RackView: View {
    let rack: RecordOfTheDay.Rack

    var body: some View {
        let cell = RackMetrics.cell(columns: rack.columns, rows: rack.rows)
        let locked = Set(rack.locked)
        VStack(spacing: RackMetrics.gap) {
            ForEach(0..<max(rack.rows, 1), id: \.self) { row in
                HStack(spacing: RackMetrics.gap) {
                    ForEach(0..<max(rack.columns, 1), id: \.self) { column in
                        let index = row * rack.columns + column
                        compartment(target: index == rack.compartment, locked: locked.contains(index))
                            .frame(width: cell.width, height: cell.height)
                    }
                }
            }
        }
        .padding(RackMetrics.inset)
        .background {
            RoundedRectangle(cornerRadius: RackMetrics.frameRadius)
                .strokeBorder(AtelierPalette.accent.opacity(0.5), lineWidth: DesignScale.borderWidth)
        }
    }

    @ViewBuilder private func compartment(target: Bool, locked: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: RackMetrics.cellRadius)
        if target {
            Group {
                if rack.position == nil {
                    shape.strokeBorder(AtelierPalette.gold, lineWidth: DesignScale.selectionLineWidth)
                } else {
                    shape.fill(AtelierPalette.gold)
                }
            }
            .widgetAccentable()
        } else if locked {
            shape.strokeBorder(AtelierPalette.ink.opacity(0.2), lineWidth: DesignScale.hairlineWidth)
        } else {
            shape.fill(AtelierPalette.ink.opacity(0.12))
        }
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

/// Nothing to show yet: the app hasn't written anything, or the collection
/// is empty.
struct EmptyRecordView: View {
    let hasSnapshot: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DesignScale.itemSpacing) {
            Image(systemName: "opticaldisc")
                .font(DesignScale.emptyStateSymbol)
                .foregroundStyle(AtelierPalette.accent)
            Text("Platte des Tages")
                .font(DesignScale.captionMark)
                .foregroundStyle(AtelierPalette.accent)
                .widgetAccentable()
            Text(hasSnapshot ? "Noch keine Platten in deiner Collection." : "Öffne Plattenregal einmal, dann liegt hier jeden Tag eine Platte aus deiner Sammlung.")
                .font(.caption)
                .foregroundStyle(AtelierPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(DesignScale.cardPadding)
    }
}
