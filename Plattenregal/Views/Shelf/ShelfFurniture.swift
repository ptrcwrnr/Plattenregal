import SwiftUI
import SwiftData

// MARK: - Style colors

/// The one place genre colors are defined: a fixed style → color mapping used
/// by the spine strip, its legend and the dot in each compartment. Muted tones,
/// each with a slightly lighter dark-mode variant so the dark ones stay visible
/// on a dark background. Every style not listed shares one light neutral.
///
/// Each color group is also a style *family* with a name: the legend counts
/// families, so one color is one line ("Trance" covers Progressive Trance).
struct StylePalette {
    private static let groups: [(name: String, light: UInt32, dark: UInt32, styles: [String])] = [
        ("Techno", 0x4A4A4F, 0x7A7A80, ["Techno", "Minimal", "Minimal Techno"]),                     // dark grey
        ("Trance", 0x8B2E2E, 0xB04A48, ["Trance", "Progressive Trance"]),                            // dark red
        ("Hard Trance", 0xC8483F, 0xD8645A, ["Hard Trance", "Euro Dance", "Hands Up"]),              // red
        ("House & Electro", 0x9A9A9E, 0xA8A8AD, ["Progressive House", "Electro House", "Electro", "Tech House"]), // grey
        ("Neo Trance", 0x5E4232, 0x8A6A55, ["Neo Trance"]),                                          // dark brown
        ("Deep House", 0x2F4A6E, 0x5577A3, ["Deep House"]),                                          // dark blue
        ("Hardstyle", 0xD4A93A, 0xDDB654, ["Hardstyle"]),                                            // yellow
        ("Drum & Bass / Breaks", 0x3A2A4A, 0x6E5788, ["Drum & Bass", "Breaks"]),                     // black-violet
    ]
    /// Name of the neutral family for every style not listed above.
    static let otherFamily = "Sonstige"

    private static let families: [String: (name: String, colorStyle: String)] = {
        var result: [String: (name: String, colorStyle: String)] = [:]
        for group in groups {
            for style in group.styles { result[normalize(style)] = (group.name, group.styles[0]) }
        }
        return result
    }()

    /// The family a style belongs to, and a style that stands for its color.
    /// Unlisted styles form "Sonstige" (colored like any unlisted style).
    static func family(of style: String) -> (name: String, colorStyle: String) {
        families[normalize(style)] ?? (otherFamily, "")
    }
    private static let other = Color.adaptive(hex: 0xD6D6D8, dark: 0x5C5C61)

    private static let mapping: [String: Color] = {
        var result: [String: Color] = [:]
        for group in groups {
            let color = Color.adaptive(hex: group.light, dark: group.dark)
            for style in group.styles { result[normalize(style)] = color }
        }
        return result
    }()

    /// Folds case, spaces, hyphens, "&"/"and"/"n" and similar spellings, so
    /// "Hardtrance", "hard-trance" and "Hard Trance" (or "Drum n Bass" and
    /// "Drum & Bass") land on the same key.
    static func normalize(_ style: String) -> String {
        let folded = style.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "&", with: "and")
        var key = String(folded.unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(Character.init))
        for alias in ["drumnbass", "drumbass", "dnb"] where key == alias { key = "drumandbass" }
        return key
    }

    func color(for style: String, solid: Bool = false) -> Color {
        let base = Self.mapping[Self.normalize(style)] ?? Self.other
        return solid ? base : base.opacity(0.9)
    }
}

// MARK: - Spine rack

/// Records as thin vertical spines standing left to right, one slot per unit of
/// slot, so rows sharing a slot count show sleeves at the same width.
/// Empty slots draw nothing but the shelf floor.
///
/// With `selectable`, the selected position is pulled out like a real sleeve
/// (taller, a bit wider, full opacity, smooth animation) while the rest dims
/// slightly; clicking a spine reports its 1-based position.
struct SpineRack: View {
    let styles: [String]
    let slots: Int
    let palette: StylePalette
    var selectedPosition: Int? = nil
    /// Draws a marker in front of this 1-based position (count + 1 = the end).
    var insertionPosition: Int? = nil
    /// 1-based positions drawn as an outline only: listed there, but not found.
    var missingPositions: Set<Int> = []
    var selectable = false
    var onSelect: ((Int) -> Void)? = nil

    // The spine being animated; kept while it slides back in after deselection.
    @State private var liftedPosition: Int?
    @State private var lift: Double = 0
    /// Only needed to map a tap to its slot; the canvas lays itself out.
    @State private var width: CGFloat = 0

    var body: some View {
        SpineCanvas(
            styles: styles,
            slots: max(slots, styles.count, 1),
            palette: palette,
            liftedPosition: liftedPosition,
            lift: lift,
            insertionPosition: insertionPosition,
            missingPositions: missingPositions,
            reservesHeadroom: selectable
        )
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .onTapGesture { location in
            guard selectable, let onSelect, !styles.isEmpty, width > 0 else { return }
            let slot = width / CGFloat(max(slots, styles.count, 1))
            let index = Int(location.x / slot)
            if styles.indices.contains(index) { onSelect(index + 1) }
        }
        .onAppear {
            if let selectedPosition { liftedPosition = selectedPosition; lift = 1 }
        }
        .onChange(of: selectedPosition) { _, position in
            if let position {
                if liftedPosition != position { liftedPosition = position; lift = 0 }
                withAnimation(AppStyle.layoutAnimation) { lift = 1 }
            } else {
                withAnimation(AppStyle.layoutAnimation) { lift = 0 }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct SpineCanvas: View, Animatable {
    let styles: [String]
    let slots: Int
    let palette: StylePalette
    let liftedPosition: Int?
    var lift: Double
    let insertionPosition: Int?
    let missingPositions: Set<Int>
    let reservesHeadroom: Bool

    nonisolated var animatableData: Double {
        get { lift }
        set { lift = newValue }
    }

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)),
                         with: .color(AppStyle.borderColor))
            let slot = size.width / CGFloat(slots)
            let baseWidth = max(0.8, slot * 0.62)
            let usable = size.height - 1
            // Leave room above the row so a pulled-out spine (1.4×) still fits.
            let scale: CGFloat = reservesHeadroom ? 0.66 : 0.8
            let t = CGFloat(lift)
            for (index, style) in styles.enumerated() {
                let jitter = CGFloat((index &* 37 &+ style.count &* 11) % 9) / 100
                let isLifted = liftedPosition == index + 1
                if isLifted && t > 0 { continue }
                let height = min(usable, usable * (scale + jitter * (reservesHeadroom ? 0.5 : 1)))
                var color = palette.color(for: style)
                if liftedPosition != nil { color = color.opacity(1 - 0.45 * Double(t)) }
                let rect = CGRect(x: CGFloat(index) * slot + (slot - baseWidth) / 2, y: usable - height,
                                  width: baseWidth, height: height)
                if missingPositions.contains(index + 1) {
                    // A gap where the record should stand: a red outline, like its tag.
                    let line = min(1.2, baseWidth / 3)
                    context.stroke(Path(roundedRect: rect.insetBy(dx: line / 2, dy: line / 2), cornerRadius: min(1, baseWidth / 2)),
                                   with: .color(AppStyle.errorColor.opacity(liftedPosition != nil ? 0.8 - 0.35 * Double(t) : 0.8)),
                                   lineWidth: line)
                } else {
                    context.fill(Path(roundedRect: rect, cornerRadius: min(1, baseWidth / 2)), with: .color(color))
                }
            }
            // Draw the lifted spine last so its wider body sits on top of its neighbours.
            if let position = liftedPosition, styles.indices.contains(position - 1), t > 0 {
                let index = position - 1, style = styles[index]
                let jitter = CGFloat((index &* 37 &+ style.count &* 11) % 9) / 100
                let height = min(usable, usable * (scale + jitter * (reservesHeadroom ? 0.5 : 1)) * (1 + 0.4 * t))
                let width = min(slot * 1.6, baseWidth * (1 + 0.5 * t))
                let rect = CGRect(x: CGFloat(index) * slot + (slot - width) / 2, y: usable - height, width: width, height: height)
                let color = palette.color(for: style, solid: true)
                context.fill(Path(roundedRect: rect, cornerRadius: min(1, width / 2)), with: .color(color))
            }
            // The gap a new record goes into: an accent bar standing between the spines, a bit taller than them.
            if let position = insertionPosition, position >= 1 {
                let width: CGFloat = 3
                let x = min(max(CGFloat(position - 1) * slot - width / 2, 0), size.width - width)
                let rect = CGRect(x: x, y: 0, width: width, height: usable)
                context.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(AppStyle.accent))
            }
        }
    }
}

/// Diagonal hatching for reserved compartments.
private struct HatchPattern: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 7
            }
            context.stroke(path, with: .color(Color.secondary.opacity(0.18)), lineWidth: 1)
        }
    }
}

// MARK: - Status

/// Status next to the search field: records still in a shelf although they
/// left the Discogs collection, plus the way to take them out.
struct ShelfStatusControl: View {
    let soldInShelves: Int
    let removeSold: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Text("\(soldInShelves) nicht in der Collection").monospacedDigit().foregroundStyle(AppStyle.warningColor)
                .help("Nicht (mehr) in deiner Discogs-Collection – verkauft, verschenkt oder aus einem anderen Konto –, aber noch im Regal")
            Text("·").foregroundStyle(.tertiary)
            Button("Aus Regal nehmen", action: removeSold)
                .buttonStyle(.link)
        }
        .font(.callout)
    }
}

/// Small tag on a record marked "Vermisst" (table, search, "Platte hinzufügen").
struct MissingBadge: View {
    var body: some View {
        Text("Vermisst")
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppStyle.errorColor)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(AppStyle.errorColor.opacity(0.12), in: Capsule())
            .fixedSize()
    }
}

/// Status next to the search field: records marked "Vermisst" while
/// sorting. The popover lists them by shelf; a row shows the record in its
/// shelf, the check mark marks it found again.
struct MissingCopiesControl: View {
    let copies: [RecordCopy]
    let labels: ShelfLabels
    let show: (RecordCopy) -> Void
    let found: (RecordCopy) -> Void
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            // A glass capsule like the search bar beside it.
            HStack(spacing: 5) {
                Circle().fill(AppStyle.errorColor).frame(width: 6, height: 6)
                Text("Vermisst").lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .frame(height: AppStyle.searchBarHeight)
            .foregroundStyle(.secondary)
            .contentShape(Capsule())
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .font(.callout)
        .help("Beim Einsortieren nicht gefunden – vermutlich noch in einem anderen Fach")
        .accessibilityLabel("\(copies.count) vermisst")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            MissingCopiesPopover(copies: copies, labels: labels,
                                 show: { isPresented = false; show($0) },
                                 found: found)
        }
    }
}

/// The list behind "Vermisst": grouped by shelf (in shelf order), records
/// without a shelf last, each with its cover to look for at the shelf.
private struct MissingCopiesPopover: View {
    let copies: [RecordCopy]
    let labels: ShelfLabels
    let show: (RecordCopy) -> Void
    let found: (RecordCopy) -> Void

    private struct Group: Identifiable {
        let id: String
        let title: String
        let copies: [RecordCopy]
    }

    /// `copies` already comes in shelf order, so neighbours share a group.
    private var groups: [Group] {
        var result: [Group] = []
        for copy in copies {
            let id = copy.shelf?.id.uuidString ?? "none"
            if let last = result.last, last.id == id {
                result[result.count - 1] = Group(id: id, title: last.title, copies: last.copies + [copy])
            } else {
                let title = copy.shelf.map { labels.prefix(for: $0) + (labels[$0.id] ?? $0.numberText) } ?? "Noch ohne Fach"
                result.append(Group(id: id, title: title, copies: [copy]))
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Vermisst").font(.headline)
                    Spacer()
                    Text(copies.count == 1 ? "1 Platte" : "\(copies.count) Platten")
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                        .contentTransition(.numericText())
                }
                Text("Beim Einsortieren nicht gefunden – vermutlich noch in einem anderen Fach.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppStyle.cardPadding)
            .padding(.top, 14)
            .padding(.bottom, 10)
            Divider()
            ViewThatFits(in: .vertical) {
                list
                ScrollView { list }.scrollIndicators(.automatic)
            }
            .frame(maxHeight: 420)
        }
        .frame(width: 330)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(groups) { group in
                Text(group.title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.top, group.id == groups.first?.id ? 4 : 10)
                    .padding(.bottom, 2)
                ForEach(group.copies) { copy in
                    MissingCopyRow(copy: copy, show: { show(copy) }, found: {
                        withAnimation(AppStyle.standardAnimation) { found(copy) }
                    })
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
        }
        .padding(8)
    }
}

private struct MissingCopyRow: View {
    let copy: RecordCopy
    let show: () -> Void
    let found: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: show) {
                HStack(spacing: 10) {
                    CoverView(url: copy.release?.coverURL, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(copy.release?.displayTitle ?? "—").fontWeight(.medium)
                        Text(copy.release?.displayArtist ?? "—").foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(copy.shelf == nil ? "Platz finden" : "Zeigen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .opacity(hovering ? 1 : 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(copy.shelf == nil ? "Platz im Regal finden" : "Im Fach zeigen")
            Button(action: found) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(hovering ? AppStyle.successColor : Color.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Wieder gefunden")
            .accessibilityLabel("Wieder gefunden")
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(hovering ? AppStyle.hoverBackground : .clear, in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }
        .animation(AppStyle.quickAnimation, value: hovering)
    }
}

// MARK: - Shelf furniture

/// The KALLAX as one piece of furniture: a single outer frame with the
/// compartments separated by thin dividers, so the rack is the one distinct
/// shape on the page.
struct ShelfFurniture<Menu: View>: View {
    let shelves: [Shelf]
    let rows: Int
    let columns: Int
    let stats: (Shelf) -> ShelfStatistics
    let rangeLabel: (Shelf) -> String?
    let palette: StylePalette
    let selectedID: UUID?
    /// Shelves kept at full strength; `nil` = no search/focus, nothing dimmed.
    let litIDs: Set<UUID>?
    let lockPreview: ShelfLockPreview
    let select: (Shelf) -> Void
    @ViewBuilder let menu: (Shelf) -> Menu

    private static var frameColor: Color { Color.primary.opacity(0.28) }
    private static var dividerColor: Color { Color.primary.opacity(0.14) }

    /// Always the cabinet's full grid of equal cells, addressed by the place
    /// in the cabinet, so a missing shelf can never shift or stretch its neighbours.
    private var grid: [[(Int, Shelf?)]] {
        (0..<rows).map { row in
            (1...columns).map { column in
                let slot = row * columns + column
                return (slot, shelves.first { $0.sortOrder == slot })
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(grid.enumerated()), id: \.offset) { index, row in
                if index > 0 { Self.dividerColor.frame(height: 1) }
                HStack(spacing: 0) {
                    ForEach(row, id: \.0) { number, shelf in
                        if (number - 1) % columns > 0 { Self.dividerColor.frame(width: 1) }
                        if let shelf {
                            Button { select(shelf) } label: {
                                ShelfCompartment(
                                    shelf: shelf,
                                    stats: stats(shelf),
                                    rangeLabel: rangeLabel(shelf),
                                    palette: palette,
                                    lockPreview: lockPreview,
                                    selected: selectedID == shelf.id,
                                    dimmed: litIDs.map { !$0.contains(shelf.id) } ?? false
                                )
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contextMenu { menu(shelf) }
                        } else {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .background(Color.primary.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Self.frameColor, lineWidth: 2))
    }
}

private struct ShelfCompartment: View {
    let shelf: Shelf
    let stats: ShelfStatistics
    let rangeLabel: String?
    let palette: StylePalette
    let lockPreview: ShelfLockPreview
    var selected = false
    var dimmed = false
    @State private var hovering = false

    /// Follows the options popover's switch immediately (see `ShelfLockPreview`).
    private var isReserved: Bool { lockPreview.isLocked(shelf) }

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Always in the tree and faded via opacity: the most reliable way to
            // animate it, independent of how the change arrives.
            .background { HatchPattern().opacity(isReserved ? 1 : 0) }
            .background(selected ? AppStyle.accent.opacity(0.12) : hovering ? AppStyle.hoverBackground : Color.clear)
            .contentShape(Rectangle())
            .opacity(dimmed ? 0.3 : 1)
            .onHover { hovering = $0 }
            .animation(AppStyle.quickAnimation, value: selected)
            .animation(AppStyle.standardAnimation, value: dimmed)
            // Hatching and label crossfade when the shelf is (un)locked.
            .animation(AppStyle.standardAnimation, value: isReserved)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var content: some View {
        if isReserved {
            HStack(spacing: 5) {
                Image(systemName: "lock")
                Text(shelf.name.isEmpty ? "Gesperrt" : shelf.name).lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        } else if stats.count > 0 {
            VStack(alignment: .leading, spacing: 0) {
                Text(rangeLabel ?? "—")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                HStack(spacing: 5) {
                    Circle()
                        .fill(palette.color(for: stats.dominantColorStyle ?? "", solid: true))
                        .frame(width: 6, height: 6)
                    Text(AppStyle.records(stats.count)).monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } else {
            // Without a view here the compartment collapses to nothing and
            // can't be clicked, so empty shelves get a quiet placeholder.
            Text("Leer")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var accessibilityText: String {
        if isReserved { return "\(shelf.name.isEmpty ? "Fach" : shelf.name), gesperrt" }
        if stats.count == 0 { return "Leeres Fach" }
        return "\(rangeLabel ?? "Fach"), \(AppStyle.records(stats.count))"
    }
}

// MARK: - Style legend

/// Genre legend for the spine strip. Shows as many of the top styles as fit
/// on one line instead of wrapping onto a row of its own.
struct ShelfStyleLegend: View {
    let stats: ShelfStatistics
    let palette: StylePalette

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(stride(from: min(4, stats.styleShares.count), through: 1, by: -1)), id: \.self) { count in
                entries(count)
            }
            Color.clear.frame(width: 0, height: 0)
        }
        .font(.caption.monospacedDigit())
    }

    private func entries(_ count: Int) -> some View {
        HStack(spacing: AppStyle.rowSpacing) {
            ForEach(stats.styleShares.prefix(count)) { share in
                HStack(spacing: 5) {
                    Circle().fill(palette.color(for: share.colorStyle)).frame(width: 7, height: 7)
                    Text(share.style).foregroundStyle(.secondary)
                    Text("\(Int((share.fraction * 100).rounded())) %").foregroundStyle(.tertiary)
                }
                .fixedSize()
                .help(share.members.joined(separator: ", "))
            }
        }
    }
}

private extension Color {
    static func adaptive(hex light: UInt32, dark: UInt32) -> Color {
        func rgb(_ v: UInt32) -> (Double, Double, Double) {
            (Double(v >> 16 & 0xFF) / 255, Double(v >> 8 & 0xFF) / 255, Double(v & 0xFF) / 255)
        }
        return adaptive(light: rgb(light), dark: rgb(dark))
    }

    static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}
