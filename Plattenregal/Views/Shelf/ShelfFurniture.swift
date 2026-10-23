import SwiftUI

/// The KALLAX as one piece of furniture: a single Liquid Glass body with the
/// compartments set into it as shallow wells, so the rack is the one distinct
/// shape on the page. The selected compartment rises out of its well as a
/// raised plate, fading in within its own compartment (no gliding across
/// the rack); the compartment under the pointer brightens a little. While a
/// search or the placement card lights some compartments, the others fade
/// and the selection shows only if it is one of the lit ones.
struct ShelfFurniture<Menu: View>: View {
    let shelves: [Shelf]
    let rows: Int
    let columns: Int
    let stats: (Shelf) -> ShelfStatistics
    let rangeLabel: (Shelf) -> String?
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
                            // While a search or the placement card points at other
                            // compartments, only those stand out: the open one
                            // drops its selection too instead of keeping a faded gold rim.
                            let dimmed = litIDs.map { !$0.contains(shelf.id) } ?? false
                            let selected = selectedID == shelf.id && !dimmed
                            Button { select(shelf) } label: {
                                ShelfCompartment(
                                    shelf: shelf,
                                    stats: stats(shelf),
                                    rangeLabel: rangeLabel(shelf),
                                    lockPreview: lockPreview,
                                    selected: selected,
                                    hovered: hoveredID == shelf.id,
                                    dimmed: dimmed
                                )
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            // Beside the compartment's button, not inside it: a button
                            // in a button's label wouldn't get the click.
                            // Where the count stands, which gives way to it.
                            .overlay(alignment: .topTrailing) {
                                CompartmentAddButton(shelf: shelf, lockPreview: lockPreview,
                                                     shown: hoveredID == shelf.id || selected) { add(shelf) }
                                    .padding(.top, AppStyle.tightSpacing)
                                    .padding(.trailing, AppStyle.itemSpacing)
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
                // Klassisch: a light frame like the cabinet tabs above, the
                // compartments set into it as cream sleeves.
                RoundedRectangle(cornerRadius: Self.wellRadius + Self.gap)
                    .fill(AtelierPalette.soft)
                    .overlay {
                        RoundedRectangle(cornerRadius: Self.wellRadius + Self.gap)
                            .strokeBorder(AtelierPalette.border, lineWidth: AppStyle.borderWidth)
                    }
            }
        }
        .glassEffect(AppStyle.isAtelier ? .identity : .regular,
                     in: .rect(cornerRadius: Self.wellRadius + Self.gap))
        .shadow(color: AtelierPalette.shadow.opacity(AppStyle.isAtelier ? 1 : 0),
                radius: AppStyle.isAtelier ? 8 : 0, y: AppStyle.isAtelier ? 2 : 0)
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
        if AppStyle.isAtelier {
            // Klassisch: matte paper with a fine rim, like the sleeves and
            // cards – no glassy shading or light catching the edge.
            shape.fill(AtelierPalette.surface)
                .overlay(shape.strokeBorder(AtelierPalette.border, lineWidth: AppStyle.borderWidth))
        } else {
            shape
                .fill(Self.fill.shadow(.inner(color: Self.shade, radius: 2.5, y: 1.5)))
                .overlay(shape.strokeBorder(LinearGradient(colors: [.clear, Self.rim], startPoint: .center, endPoint: .bottom), lineWidth: AppStyle.borderWidth))
        }
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
            SmallRoundButton(systemImage: "plus", help: String(localized: "Platte hinzufügen"), action: action)
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
            .fill(AppStyle.isAtelier ? AtelierPalette.petrol.opacity(0.06) : Self.light)
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
                    shape.strokeBorder(edge, lineWidth: AppStyle.selectionLineWidth)
                } else {
                    // A selection carries a rim in both designs (Klassisch:
                    // gold); here the accent, as on the chosen design card.
                    shape.strokeBorder(LinearGradient(colors: [edge, .clear], startPoint: .top, endPoint: .center), lineWidth: AppStyle.borderWidth)
                    shape.strokeBorder(AppStyle.selectedBorder.opacity(0.5), lineWidth: AppStyle.borderWidth)
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
            .overlay(RoundedRectangle(cornerRadius: ShelfFurnitureMetrics.wellRadius).strokeBorder(frost, lineWidth: AppStyle.borderWidth))
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
            VStack(spacing: AppStyle.tightSpacing) {
                Image(systemName: "lock.fill").font(.callout)
                if !shelf.name.isEmpty { Text(shelf.name).font(.caption).lineLimit(1) }
            }
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if stats.count > 0 {
            // The range in the top left corner, the count in the top right.
            HStack(alignment: .firstTextBaseline, spacing: AppStyle.tightSpacing) {
                Text(rangeLabel ?? "—")
                    .font(AppStyle.sectionTitle)
                    // The accent marks the choice, in the text only.
                    .foregroundStyle(selected ? AnyShapeStyle(AppStyle.accent) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: AppStyle.tightSpacing)
                Text(stats.count.formatted())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    // The "+" takes its place (see `CompartmentAddButton`).
                    .opacity(hovered || selected ? 0 : 1)
                    .animation(AppStyle.standardAnimation, value: hovered || selected)
            }
            .padding(.horizontal, AppStyle.rowSpacing)
            .padding(.top, AppStyle.itemSpacing)
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

private extension Color {
    static func adaptive(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}
