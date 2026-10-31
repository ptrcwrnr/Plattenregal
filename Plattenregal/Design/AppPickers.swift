import SwiftUI

/// A choice between a few options. The chosen one sits on a pill that, on a
/// new choice, travels there like a drop: the edge in front runs ahead on a
/// taut spring (`AppStyle.pillLeadAnimation`), the one behind follows on a
/// softer one (`pillTrailAnimation`), so the pill stretches on the way and
/// pulls itself together at the new option. It is one pill for the whole
/// row, so never two half-shown pills; the labels take the pill's color
/// exactly where it covers them (masked by the same shape), so no text is
/// ever doubled. With "Bewegung reduzieren" the pill fades out and in at
/// the new option in the beat of a page switch instead. The same in both
/// designs: in Modern a Liquid Glass lens (never a gray or blue fill, no
/// rim) with the label semibold in the text color, in Klassisch cream paper.
/// In the toolbar the toolbar's bar is the background (`glass: false`, see
/// `toolbarBar`); anywhere else it brings its own capsule.
struct GlassSegmentedPicker<Value: Hashable, Label: View>: View {
    @Binding var selection: Value
    let options: [Value]
    var glass = true
    var small = false
    /// A faint line between neighbouring options (e.g. the cabinet tabs).
    var separators = false
    /// Right-click on an option, with the click position (see `onSecondaryClick`).
    var secondaryClick: ((Value, UnitPoint) -> Void)? = nil
    @ViewBuilder let label: (Value) -> Label

    /// The option the pill stands on or travels to. Follows `selection` in
    /// `onChange`, so the direction of travel is known when the edges move;
    /// nil only until the picker appears.
    @State private var shown: Value?
    @State private var movingRight = true
    /// Off until the first switch: the pill appears where it belongs
    /// instead of sliding in from the row's edge when the options are measured.
    @State private var animatesEdges = false
    /// Only with "Bewegung reduzieren": the pill fading out before it jumps.
    @State private var pillFaded = false
    /// Each option's width. Positions are added up from these instead of
    /// measured: a measured position follows whatever moves the row (in
    /// Klassisch the toolbar shifts the bar animated when the search comes
    /// or goes), and the label masks lagged behind the pill.
    @State private var widths: [Value: CGFloat] = [:]

    var body: some View {
        let row = HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                if separators && index > 0 {
                    // Holds the place; the line is drawn beneath the pill (below).
                    ControlSeparator(small: small).hidden()
                }
                Button { selection = option } label: {
                    label(option)
                        .foregroundStyle(unselectedStyle)
                        .padding(.horizontal, small ? AppStyle.itemSpacing : AppStyle.rowSpacing)
                        .frame(height: rowHeight)
                        // Gone where the pill covers it: there its copy in the
                        // pill's color stands (below).
                        .mask { pillMask(for: option, inverted: true) }
                        // The copy on the pill. Semibold in Modern: only this
                        // copy – the regular label sets the width, so the
                        // neighbours never shift and the few points more fit
                        // in the pill's inset.
                        .background {
                            label(option)
                                .fontWeight(AppStyle.isAtelier ? nil : AppStyle.selectedOptionWeight)
                                .fixedSize()
                                .foregroundStyle(selectedStyle)
                                .accessibilityHidden(true)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .mask { pillMask(for: option, inverted: false) }
                        }
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { widths[option] = $0 }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(option == selection ? .isSelected : [])
                .modifier(OptionalSecondaryClick(action: secondaryClick.map { click in { click(option, $0) } }))
            }
        }
        .background(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                separatorLines
                pillLayer(pillFill)
            }
        }
        .font(small ? .callout : .body)
        .fixedSize()
        // Taken over right away: until then the pill follows `selection`
        // directly, and the first switch would jump there unanimated.
        .onAppear { shown = selection }
        .onChange(of: selection) { old, new in move(from: old, to: new) }
        // A group: a label given to the picker (`.accessibilityLabel("Modus")`)
        // names the group instead of replacing every option's name.
        .accessibilityElement(children: .contain)
        if glass {
            row.padding(.horizontal, AppStyle.controlInset)
                .background {
                    if AppStyle.isAtelier {
                        RoundedRectangle(cornerRadius: AppStyle.atelierControlRadius).fill(AtelierPalette.soft)
                            .overlay(RoundedRectangle(cornerRadius: AppStyle.atelierControlRadius).strokeBorder(AtelierPalette.border, lineWidth: AppStyle.borderWidth))
                    }
                }
                .glassEffect(AppStyle.isAtelier ? .identity : .regular.interactive(), in: .capsule)
        } else {
            row
        }
    }

    // MARK: The pill

    private var current: Value { shown ?? selection }
    private var rowHeight: CGFloat { small ? AppStyle.smallControlHeight : AppStyle.controlHeight }
    /// The hidden separators between the options take this much room.
    private var separatorWidth: CGFloat { separators ? AppStyle.borderWidth : 0 }

    /// Where an option starts in the row and how wide it is; nil until all
    /// options before it are measured.
    private func span(of option: Value) -> (minX: CGFloat, width: CGFloat)? {
        var x: CGFloat = 0
        for candidate in options {
            guard let width = widths[candidate] else { return nil }
            if candidate == option { return (x, width) }
            x += width + separatorWidth
        }
        return nil
    }

    private var rowWidth: CGFloat {
        options.reduce(0) { $0 + (widths[$1] ?? 0) } + separatorWidth * CGFloat(max(0, options.count - 1))
    }
    private var left: CGFloat { span(of: current)?.minX ?? 0 }
    private var right: CGFloat { span(of: current).map { $0.minX + $0.width } ?? 0 }
    /// The edge in front of the travel leads, the one behind trails.
    private var leftAnimation: Animation? { animatesEdges ? (movingRight ? AppStyle.pillTrailAnimation : AppStyle.pillLeadAnimation) : nil }
    private var rightAnimation: Animation? { animatesEdges ? (movingRight ? AppStyle.pillLeadAnimation : AppStyle.pillTrailAnimation) : nil }

    private func move(from old: Value, to new: Value) {
        if AppStyle.reduceMotion {
            animatesEdges = false
            withAnimation(AppStyle.pageOutAnimation) { pillFaded = true } completion: {
                shown = selection
                withAnimation(AppStyle.pageInAnimation) { pillFaded = false }
            }
        } else {
            movingRight = (options.firstIndex(of: new) ?? 0) > (options.firstIndex(of: old) ?? 0)
            animatesEdges = true
            shown = new
        }
    }

    private var pillShape: AnyShape {
        AppStyle.isAtelier ? AnyShape(RoundedRectangle(cornerRadius: AppStyle.atelierControlRadius - AppStyle.controlInset)) : AnyShape(Capsule())
    }

    @ViewBuilder private var pillFill: some View {
        if AppStyle.isAtelier {
            pillShape.fill(glass ? AtelierPalette.surface : AtelierPalette.toolbarSelection)
        } else {
            Color.clear.glassEffect(.regular, in: .capsule)
        }
    }

    /// Anything shaped and placed like the pill, across the whole row: each
    /// edge on its own spring. The pill and both label masks go through here,
    /// so they move as one.
    private func pillLayer(_ content: some View) -> some View {
        content
            .modifier(DropEdgeInset(edge: .leading, inset: left))
            .animation(leftAnimation, value: left)
            .modifier(DropEdgeInset(edge: .trailing, inset: rowWidth - right))
            .animation(rightAnimation, value: right)
            .padding(.vertical, AppStyle.controlInset)
            .frame(width: rowWidth, height: rowHeight)
            .opacity(span(of: current) == nil || pillFaded ? 0 : 1)
    }

    /// The pill seen from one option's area: what of the option it covers,
    /// or (`inverted`) what it leaves free.
    private func pillMask(for option: Value, inverted: Bool) -> some View {
        let span = span(of: option) ?? (0, 0)
        let pill = pillLayer(pillShape)
            .offset(x: -span.minX)
            .frame(width: span.width, height: rowHeight, alignment: .topLeading)
        return Group {
            if inverted {
                Rectangle().overlay { pill.blendMode(.destinationOut) }.compositingGroup()
            } else {
                pill
            }
        }
    }

    /// The lines between the options, beneath the pill. Not beside the
    /// chosen option: the pill marks its own edges, and a line would touch it.
    @ViewBuilder private var separatorLines: some View {
        if separators {
            ForEach(Array(options.enumerated().dropFirst()), id: \.element) { index, option in
                if let span = span(of: option) {
                    ControlSeparator(small: small)
                        .opacity(current == option || current == options[index - 1] ? 0 : 1)
                        .animation(AppStyle.pageOutAnimation, value: current)
                        .position(x: span.minX - separatorWidth / 2, y: rowHeight / 2)
                }
            }
        }
    }

    private var selectedStyle: AnyShapeStyle {
        AppStyle.isAtelier ? AnyShapeStyle(glass ? AtelierPalette.ink : AtelierPalette.toolbarInk) : AnyShapeStyle(.primary)
    }

    private var unselectedStyle: AnyShapeStyle {
        glass ? (AppStyle.isAtelier ? AnyShapeStyle(AtelierPalette.muted) : AnyShapeStyle(.secondary)) : AppStyle.toolbarLabel
    }
}

/// One edge of a shape that moves like a drop, set in from the edge of its
/// area: the selection pill, the drop of the search in the menu bar
/// (`QuickSearchDrop`). Animatable, so each edge runs on its own spring, and
/// never beyond the area: the edge in front overshoots a little, and where it
/// would leave the area (the pill at the first or last option, the drop at
/// its full size) it presses flat against the edge instead.
struct DropEdgeInset: ViewModifier, Animatable {
    let edge: Edge.Set
    var inset: CGFloat
    /// The furthest in the edge may go, not animated: the area can shrink
    /// at once while the edge is still on its way (the search in the menu
    /// bar emptied while it springs open again), and an edge set in further
    /// than the area is big would leave the shape no size at all.
    var limit: CGFloat = .infinity
    var animatableData: CGFloat {
        get { inset }
        set { inset = newValue }
    }
    func body(content: Content) -> some View {
        content.padding(edge, min(max(0, inset), max(0, limit)))
    }
}

/// The faint line between neighbouring parts of a bar: the cabinet tabs,
/// the page switch and the search in the toolbar.
struct ControlSeparator: View {
    var small = false
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: AppStyle.borderWidth, height: small ? 12 : 14)
    }
}

private struct OptionalSecondaryClick: ViewModifier {
    let action: ((UnitPoint) -> Void)?
    func body(content: Content) -> some View {
        if let action { content.onSecondaryClick(perform: action) } else { content }
    }
}

/// A choice from a longer list, as a menu behind a Liquid Glass button that
/// shows the current value – the native pop-up button would be filled with
/// the accent color.
struct GlassMenuPicker<Value: Hashable, Options: View>: View {
    let title: String
    @Binding var selection: Value
    /// What the button shows for the current value.
    let current: String
    @ViewBuilder let options: Options

    var body: some View {
        Menu {
            Picker(title, selection: $selection) { options }
                .pickerStyle(.inline)
                .labelsHidden()
        } label: {
            HStack(spacing: AppStyle.itemSpacing) {
                Text(current)
                Image(systemName: "chevron.up.chevron.down")
                    .font(AppStyle.indicatorSymbol)
                    .foregroundStyle(.secondary)
            }
        }
        // A plain menu inside our own glass capsule: the button styles leave
        // a menu gray-filled.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .padding(.horizontal, AppStyle.cardPadding)
        .frame(height: AppStyle.controlHeight)
        .background {
            if AppStyle.isAtelier {
                RoundedRectangle(cornerRadius: AppStyle.atelierControlRadius).fill(AtelierPalette.surface)
                    .overlay(RoundedRectangle(cornerRadius: AppStyle.atelierControlRadius).strokeBorder(AtelierPalette.border, lineWidth: AppStyle.borderWidth))
            }
        }
        .glassEffect(AppStyle.isAtelier ? .identity : .regular.interactive(), in: .capsule)
        .fixedSize()
        .accessibilityLabel(title)
    }
}

/// Grid or list, as two icons.
struct OverviewLayoutPicker: View {
    @Binding var selection: OverviewLayout

    var body: some View {
        GlassSegmentedPicker(selection: $selection, options: OverviewLayout.allCases) { layout in
            Image(systemName: layout.systemImage)
                .accessibilityLabel(layout.title)
                .help(layout.title)
        }
    }
}
