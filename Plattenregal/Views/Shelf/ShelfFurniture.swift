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
    static let otherFamily = String(localized: "Sonstige")

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
        // A touch translucent, so the sheen and the glass around them shine through.
        return solid ? base : base.opacity(0.94)
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
/// Where the spines stand: the first one flush with the left edge, and in a
/// full row the last one flush with the right, so the strip lines up with
/// the text above it. Shared by drawing, clicks and the hover cover.
struct SpineLayout {
    /// Share of a pitch left empty between two spines.
    private static let gapRatio: CGFloat = 0.38
    /// Distance from one spine's left edge to the next one's.
    let pitch: CGFloat
    let spineWidth: CGFloat

    init(width: CGFloat, slots: Int) {
        // n spines and n − 1 gaps fill the width exactly.
        pitch = width / (CGFloat(max(slots, 1)) - Self.gapRatio)
        spineWidth = max(0.8, pitch * (1 - Self.gapRatio))
    }

    var gap: CGFloat { pitch * Self.gapRatio }
    func minX(_ index: Int) -> CGFloat { CGFloat(index) * pitch }
    func midX(_ index: Int) -> CGFloat { minX(index) + spineWidth / 2 }
    /// The spine at `x`; a gap belongs half to each neighbour.
    func index(at x: CGFloat) -> Int { Int(max(0, x + gap / 2) / pitch) }
}

struct SpineRack: View {
    let styles: [String]
    let slots: Int
    let palette: StylePalette
    var selectedPosition: Int? = nil
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
            missingPositions: missingPositions,
            reservesHeadroom: selectable
        )
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .onTapGesture { location in
            guard selectable, let onSelect, !styles.isEmpty, width > 0 else { return }
            let index = SpineLayout(width: width, slots: max(slots, styles.count, 1)).index(at: location.x)
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
    let missingPositions: Set<Int>
    let reservesHeadroom: Bool

    nonisolated var animatableData: Double {
        get { lift }
        set { lift = newValue }
    }

    /// Light from the left across each sleeve: a sheen on one edge, shade on
    /// the other, so the bars read as cardboard rather than flat color.
    private static let sheen = Gradient(stops: [
        .init(color: .white.opacity(0.32), location: 0),
        .init(color: .white.opacity(0.06), location: 0.35),
        .init(color: .clear, location: 0.6),
        .init(color: .black.opacity(0.24), location: 1),
    ])

    private func drawSpine(_ rect: CGRect, color: Color, alpha: Double, in context: GraphicsContext) {
        var context = context
        context.opacity = alpha
        let path = Path(roundedRect: rect, cornerRadius: min(1, rect.width / 2))
        context.fill(path, with: .color(color))
        guard rect.width >= 2 else { return }
        context.fill(path, with: .linearGradient(Self.sheen, startPoint: CGPoint(x: rect.minX, y: 0),
                                                 endPoint: CGPoint(x: rect.maxX, y: 0)))
    }

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)),
                         with: .color(AppStyle.borderColor))
            let layout = SpineLayout(width: size.width, slots: slots)
            let baseWidth = layout.spineWidth
            let usable = size.height - 1
            // Leave room above the row so a pulled-out spine (1.4×) still fits.
            let scale: CGFloat = reservesHeadroom ? 0.66 : 0.8
            let t = CGFloat(lift)
            let dim = liftedPosition != nil ? 1 - 0.45 * Double(t) : 1
            for (index, style) in styles.enumerated() {
                let jitter = CGFloat((index &* 37 &+ style.count &* 11) % 9) / 100
                let isLifted = liftedPosition == index + 1
                if isLifted && t > 0 { continue }
                let height = min(usable, usable * (scale + jitter * (reservesHeadroom ? 0.5 : 1)))
                let rect = CGRect(x: layout.minX(index), y: usable - height,
                                  width: baseWidth, height: height)
                if missingPositions.contains(index + 1) {
                    // A gap where the record should stand: a red outline, like its tag.
                    let line = min(1.2, baseWidth / 3)
                    context.stroke(Path(roundedRect: rect.insetBy(dx: line / 2, dy: line / 2), cornerRadius: min(1, baseWidth / 2)),
                                   with: .color(AppStyle.errorColor.opacity(liftedPosition != nil ? 0.8 - 0.35 * Double(t) : 0.8)),
                                   lineWidth: line)
                } else {
                    drawSpine(rect, color: palette.color(for: style), alpha: dim, in: context)
                }
            }
            // Draw the lifted spine last so its wider body sits on top of its neighbours.
            if let position = liftedPosition, styles.indices.contains(position - 1), t > 0 {
                let index = position - 1, style = styles[index]
                let jitter = CGFloat((index &* 37 &+ style.count &* 11) % 9) / 100
                let height = min(usable, usable * (scale + jitter * (reservesHeadroom ? 0.5 : 1)) * (1 + 0.4 * t))
                let width = min(layout.pitch * 1.6, baseWidth * (1 + 0.5 * t))
                // Grows around its middle, but never past the strip's edges.
                let x = min(max(layout.midX(index) - width / 2, 0), size.width - width)
                let rect = CGRect(x: x, y: usable - height, width: width, height: height)
                drawSpine(rect, color: palette.color(for: style, solid: true), alpha: 1, in: context)
            }
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

/// Small colored tag beside a record's title ("Vermisst", "Nicht in der
/// Collection", "Als Nächstes"), the same everywhere on the shelf page.
struct StatusTag: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.12), in: Capsule())
            .fixedSize()
    }
}

/// Small tag on a record marked "Vermisst" (table, search, "Platte hinzufügen").
struct MissingBadge: View {
    var body: some View { StatusTag(text: String(localized: "Vermisst"), color: AppStyle.errorColor) }
}

/// The "Vermisst" column beside "Platte hinzufügen": grouped by shelf (in
/// shelf order), records without a shelf last, each with its cover to look
/// for at the shelf. A row shows the record in its shelf, the check mark
/// marks it found again.
struct MissingCopiesColumn: View {
    let copies: [RecordCopy]
    let labels: ShelfLabels
    let show: (RecordCopy) -> Void
    let found: (RecordCopy) -> Void
    /// Folds the column away (see `ShelfAssignmentView`).
    var collapse: (() -> Void)?

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
                let title = copy.shelf.map { labels.prefix(for: $0) + (labels[$0.id] ?? $0.numberText) } ?? String(localized: "Noch ohne Fach")
                result.append(Group(id: id, title: title, copies: [copy]))
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Vermisst").font(AppStyle.dialogTitle)
                    Text(AppStyle.records(copies.count))
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                        .contentTransition(.numericText())
                    Spacer()
                    if let collapse {
                        IconButton(systemImage: "chevron.right", help: String(localized: "Vermisst einklappen"), action: collapse)
                            .foregroundStyle(.secondary)
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                    }
                }
                Text("Beim Einsortieren nicht gefunden – vermutlich noch in einem anderen Fach.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AppStyle.pagePadding)
            .padding(.top, AppStyle.pagePadding)
            .padding(.bottom, AppStyle.rowSpacing)
            ScrollView { list }
                .scrollIndicators(.automatic)
                .frame(maxHeight: .infinity)
        }
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
                    // Comes in from the list on the left, goes back there.
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
        }
        // Marks set in the list on the left arrive through the store, outside
        // any `withAnimation`: animate every change of the list here.
        .animation(AppStyle.standardAnimation, value: copies.map(\.id))
        .padding(.horizontal, AppStyle.pagePadding - 8)
        .padding(.bottom, 8)
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
        // Like the rows of the search and "Sortierung prüfen".
        .appHoverable(hovering, cornerRadius: 8)
        .onHover { hovering = $0 }
    }
}

// MARK: - Shelf furniture

/// The KALLAX as one piece of furniture: a single Liquid Glass body with the
/// compartments set into it as shallow wells, so the rack is the one distinct
/// shape on the page. The selected compartment rises out of its well as a
/// raised plate, fading in within its own compartment (no gliding across
/// the rack); the compartment under the pointer brightens a little.
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
    /// The "+" in a compartment: add records to it ("Platte hinzufügen").
    let add: (Shelf) -> Void
    @ViewBuilder let menu: (Shelf) -> Menu

    /// The compartment whose menu is open, and where it was right-clicked.
    @State private var menuFor: (id: UUID, anchor: UnitPoint)?
    /// The compartment under the pointer: it brightens and shows its "+".
    @State private var hoveredID: UUID?

    static var wellRadius: CGFloat { ShelfFurnitureMetrics.wellRadius }
    static var gap: CGFloat { ShelfFurnitureMetrics.gap }

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
        VStack(spacing: Self.gap) {
            ForEach(Array(grid.enumerated()), id: \.offset) { _, row in
                HStack(spacing: Self.gap) {
                    ForEach(row, id: \.0) { _, shelf in
                        if let shelf {
                            Button { select(shelf) } label: {
                                ShelfCompartment(
                                    shelf: shelf,
                                    stats: stats(shelf),
                                    rangeLabel: rangeLabel(shelf),
                                    lockPreview: lockPreview,
                                    selected: selectedID == shelf.id,
                                    hovered: hoveredID == shelf.id,
                                    dimmed: litIDs.map { !$0.contains(shelf.id) } ?? false
                                )
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            // Beside the compartment's button, not inside it: a button
                            // in a button's label wouldn't get the click.
                            // Where the count stands, which gives way to it.
                            .overlay(alignment: .topTrailing) {
                                CompartmentAddButton(shelf: shelf, lockPreview: lockPreview,
                                                     shown: hoveredID == shelf.id || selectedID == shelf.id) { add(shelf) }
                                    .padding(.top, 5)
                                    .padding(.trailing, 7)
                            }
                            .onHover { inside in
                                if inside { hoveredID = shelf.id } else if hoveredID == shelf.id { hoveredID = nil }
                            }
                            // The app's own menu, as in the collection.
                            .onSecondaryClick { point in menuFor = (shelf.id, point) }
                            .popover(isPresented: Binding(
                                get: { menuFor?.id == shelf.id },
                                set: { if !$0, menuFor?.id == shelf.id { menuFor = nil } }
                            ), attachmentAnchor: .point(menuFor?.anchor ?? .center), arrowEdge: .trailing) {
                                AppMenu(dismiss: { menuFor = nil }) { menu(shelf) }
                            }
                        } else {
                            ShelfWell().frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(Self.gap)
        .background {
            if AppStyle.isAtelier {
                RoundedRectangle(cornerRadius: Self.wellRadius + Self.gap)
                    .fill(AtelierPalette.petrol)
                    .overlay {
                        RoundedRectangle(cornerRadius: Self.wellRadius + Self.gap)
                            .strokeBorder(AtelierPalette.gold.opacity(0.3), lineWidth: 1)
                    }
            }
        }
        .glassEffect(AppStyle.isAtelier ? .identity : .regular,
                     in: .rect(cornerRadius: Self.wellRadius + Self.gap))
        .shadow(color: .black.opacity(AppStyle.isAtelier ? 0.12 : 0),
                radius: AppStyle.isAtelier ? 10 : 0, y: AppStyle.isAtelier ? 4 : 0)
    }
}

/// A compartment's recess in the glass body: a little darker than the glass,
/// shaded under its top edge and catching light along its bottom edge.
private struct ShelfWell: View {
    private static let fill = Color.adaptive(NSColor.black.withAlphaComponent(0.06), NSColor.black.withAlphaComponent(0.22))
    private static let shade = Color.adaptive(NSColor.black.withAlphaComponent(0.2), NSColor.black.withAlphaComponent(0.5))
    private static let rim = Color.adaptive(NSColor.white.withAlphaComponent(0.7), NSColor.white.withAlphaComponent(0.07))

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShelfFurnitureMetrics.wellRadius)
        let fill = AppStyle.isAtelier ? AtelierPalette.soft : Self.fill
        let shade = AppStyle.isAtelier ? AtelierPalette.petrol.opacity(0.18) : Self.shade
        let rim = AppStyle.isAtelier ? AtelierPalette.surface.opacity(0.8) : Self.rim
        shape
            .fill(fill.shadow(.inner(color: shade, radius: 2.5, y: 1.5)))
            .overlay(shape.strokeBorder(LinearGradient(colors: [.clear, rim], startPoint: .center, endPoint: .bottom), lineWidth: 1))
    }
}

/// The small "+" in a compartment's corner: on the one under the pointer
/// and on the selected one, never on a locked one.
private struct CompartmentAddButton: View {
    let shelf: Shelf
    let lockPreview: ShelfLockPreview
    let shown: Bool
    let action: () -> Void

    var body: some View {
        ShelfLockReader(shelf: shelf, preview: lockPreview) { locked in
            let visible = shown && !locked
            Button(action: action) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppStyle.accent)
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
                    .background(AppStyle.isAtelier ? AtelierPalette.surface : .clear, in: Circle())
                    .glassEffect(AppStyle.isAtelier ? .identity : .regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .help("Platte hinzufügen")
            .accessibilityLabel("Platte hinzufügen")
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible ? 1 : 0.6)
            // Fades and grows in (and out again) however it gets shown: on
            // hover, or when another compartment is picked.
            .animation(AppStyle.standardAnimation, value: visible)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
        }
    }
}

/// The compartment under the pointer: its well lit a little from within.
private struct HoveredWell: View {
    private static let light = Color.adaptive(NSColor.white.withAlphaComponent(0.4), NSColor.white.withAlphaComponent(0.06))

    var body: some View {
        RoundedRectangle(cornerRadius: ShelfFurnitureMetrics.wellRadius)
            .fill(AppStyle.isAtelier ? AtelierPalette.surface.opacity(0.55) : Self.light)
    }
}

/// The selected compartment lifted out of its well: brighter than the glass,
/// with a highlight along its top edge and a soft shadow beneath.
private struct RaisedPlate: View {
    private static let fill = Color.adaptive(NSColor.white, NSColor.white.withAlphaComponent(0.13))
    private static let edge = Color.adaptive(NSColor.white, NSColor.white.withAlphaComponent(0.28))
    private static let shadow = Color.adaptive(NSColor.black.withAlphaComponent(0.2), NSColor.black.withAlphaComponent(0.5))

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShelfFurnitureMetrics.wellRadius)
        let fill = AppStyle.isAtelier ? AtelierPalette.surface : Self.fill
        let edge = AppStyle.isAtelier ? AtelierPalette.gold : Self.edge
        shape
            .fill(fill)
            .overlay {
                if AppStyle.isAtelier {
                    shape.strokeBorder(edge, lineWidth: 1.5)
                } else {
                    shape.strokeBorder(LinearGradient(colors: [edge, .clear], startPoint: .top, endPoint: .center), lineWidth: 1)
                }
            }
            .shadow(color: AppStyle.isAtelier ? AtelierPalette.petrol.opacity(0.15) : Self.shadow,
                    radius: AppStyle.isAtelier ? 3 : 6, y: AppStyle.isAtelier ? 1 : 2.5)
    }
}

/// A locked compartment: its well frosted over like milk glass.
private struct FrostedWell: View {
    private static let frost = Color.adaptive(NSColor.white.withAlphaComponent(0.55), NSColor.white.withAlphaComponent(0.07))

    var body: some View {
        let frost = AppStyle.isAtelier ? AtelierPalette.paper.opacity(0.65) : Self.frost
        RoundedRectangle(cornerRadius: ShelfFurnitureMetrics.wellRadius)
            .fill(LinearGradient(colors: [frost, frost.opacity(0.5)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: ShelfFurnitureMetrics.wellRadius).strokeBorder(frost, lineWidth: 1))
    }
}

/// Metrics the non-generic helpers and the shelf page share with `ShelfFurniture`.
enum ShelfFurnitureMetrics {
    static let wellRadius: CGFloat = 10
    static let gap: CGFloat = 5
    private static let rowHeight: CGFloat = 52
    /// Height of the whole rack for a cabinet with this many rows.
    static func height(rows: Int) -> CGFloat {
        CGFloat(rows) * rowHeight + CGFloat(rows + 1) * gap
    }
}

private struct ShelfCompartment: View {
    let shelf: Shelf
    let stats: ShelfStatistics
    let rangeLabel: String?
    let lockPreview: ShelfLockPreview
    var selected = false
    var hovered = false
    var dimmed = false

    /// Follows the options popover's switch immediately (see `ShelfLockPreview`).
    private var isReserved: Bool { lockPreview.isLocked(shelf) }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                ZStack {
                    ShelfWell()
                    // Always in the tree and faded via opacity: the most reliable way to
                    // animate it, independent of how the change arrives.
                    FrostedWell().opacity(isReserved ? 1 : 0)
                    // Under the pointer the well brightens a little — this one only.
                    HoveredWell().opacity(hovered && !selected ? 1 : 0)
                        .animation(AppStyle.quickAnimation, value: hovered)
                    // Rises in place: fades and grows within this compartment
                    // instead of gliding over from the previous one.
                    RaisedPlate()
                        .scaleEffect(selected ? 1 : 0.94)
                        .opacity(selected ? 1 : 0)
                        .animation(AppStyle.standardAnimation, value: selected)
                }
            }
            .contentShape(Rectangle())
            .opacity(dimmed ? 0.3 : 1)
            .animation(AppStyle.standardAnimation, value: dimmed)
            // Frost and label crossfade when the shelf is (un)locked.
            .animation(AppStyle.standardAnimation, value: isReserved)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var content: some View {
        if isReserved {
            VStack(spacing: 3) {
                Image(systemName: "lock.fill").font(.callout)
                if !shelf.name.isEmpty { Text(shelf.name).font(.caption).lineLimit(1) }
            }
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if stats.count > 0 {
            // The range in the top left corner, the count in the top right.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(rangeLabel ?? "—")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    // The accent marks the choice, in the text only.
                    .foregroundStyle(selected ? AnyShapeStyle(AppStyle.accent) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Text(stats.count.formatted())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    // The "+" takes its place (see `CompartmentAddButton`).
                    .opacity(hovered || selected ? 0 : 1)
                    .animation(AppStyle.standardAnimation, value: hovered || selected)
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
        } else {
            // Without a view here the compartment collapses to nothing and
            // can't be clicked, so empty shelves get a quiet placeholder –
            // centered like a locked one's, not posing as a range label.
            Text("Leer")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var accessibilityText: String {
        if isReserved { return String(localized: "\(shelf.name.isEmpty ? String(localized: "Fach") : shelf.name), gesperrt") }
        if stats.count == 0 { return String(localized: "Leeres Fach") }
        return String(localized: "\(rangeLabel ?? String(localized: "Fach")), \(AppStyle.records(stats.count))")
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
                    Text(share.fraction.formatted(.percent.precision(.fractionLength(0)))).foregroundStyle(.tertiary)
                }
                .fixedSize()
                .help(share.members.joined(separator: ", "))
            }
        }
    }
}

private extension Color {
    static func adaptive(hex light: UInt32, dark: UInt32) -> Color {
        func rgb(_ v: UInt32) -> NSColor {
            NSColor(srgbRed: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255, alpha: 1)
        }
        return adaptive(rgb(light), rgb(dark))
    }

    static func adaptive(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}
