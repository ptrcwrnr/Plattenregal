import SwiftUI

/// A choice between a few options. The chosen one sits on a pill that, on a
/// new choice, fades out where it was and settles onto the new option from a
/// little above, in the beat of a page switch (`AppStyle.pageOutAnimation`,
/// `pageInAnimation`, `pillSettleDistance`),
/// the same in both designs: in Modern a Liquid Glass lens
/// (never a gray or blue fill) with the label in the accent, in Klassisch
/// cream paper. In the toolbar the toolbar's bar is the background
/// (`glass: false`, see `toolbarBar`); anywhere else it brings its own capsule.
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

    var body: some View {
        let row = HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                let selected = option == selection
                if separators && index > 0 {
                    // Not beside the pill: it marks its own edges, and the
                    // line would touch it.
                    let besidePill = selected || options[index - 1] == selection
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: AppStyle.borderWidth, height: small ? 12 : 14)
                        .opacity(besidePill ? 0 : 1)
                }
                Button { selection = option } label: {
                    label(option)
                        .foregroundStyle(unselectedStyle)
                        // The pill brings the label in its own color (below):
                        // a color fading between the two would, halfway, be as
                        // gray as the half-shown pill and vanish on it. This
                        // one fades while the pill's fades in at the same spot.
                        .opacity(selected ? 0 : 1)
                        .animation(AppStyle.pageInAnimation, value: selected)
                        .padding(.horizontal, small ? AppStyle.itemSpacing : AppStyle.rowSpacing)
                        .frame(height: small ? AppStyle.smallControlHeight : AppStyle.controlHeight)
                        // Every option has its pill, shown only when chosen –
                        // states animated in a fixed beat instead of views
                        // coming and going: the old one fades out on the spot
                        // (`pageOutAnimation`), then the new one fades in and
                        // settles from `pillSettleDistance` above.
                        .background {
                            ZStack {
                                Group {
                                    if AppStyle.isAtelier {
                                        RoundedRectangle(cornerRadius: AppStyle.atelierControlRadius - AppStyle.controlInset).fill(glass ? AtelierPalette.surface : AtelierPalette.toolbarSelection)
                                    } else {
                                        Capsule().fill(.clear)
                                            .glassEffect(.regular, in: .capsule)
                                    }
                                }
                                .padding(.vertical, AppStyle.controlInset)
                                // Settles on the way in, lifts as it fades out.
                                .offset(y: selected || AppStyle.reduceMotion ? 0 : -AppStyle.pillSettleDistance)
                                // Only fades, it doesn't settle with the pill:
                                // text moved by a point or two snaps from pixel
                                // to pixel. Color only: a heavier weight would
                                // widen the label and shift its neighbours.
                                label(option)
                                    .foregroundStyle(selectedStyle)
                                    .accessibilityHidden(true)
                            }
                            .opacity(selected ? 1 : 0)
                            .animation(selected ? AppStyle.pageInAnimation : AppStyle.pageOutAnimation, value: selected)
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .modifier(OptionalSecondaryClick(action: secondaryClick.map { click in { click(option, $0) } }))
            }
        }
        .font(small ? .callout : .body)
        // The separators beside the pill, in the same beat.
        .animation(AppStyle.pageInAnimation, value: selection)
        .fixedSize()
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

    private var selectedStyle: AnyShapeStyle {
        AppStyle.isAtelier ? AnyShapeStyle(glass ? AtelierPalette.ink : AtelierPalette.toolbarInk) : AnyShapeStyle(AppStyle.accent)
    }

    private var unselectedStyle: AnyShapeStyle {
        AppStyle.isAtelier ? AnyShapeStyle(glass ? AtelierPalette.muted : Color.white.opacity(0.8)) : AnyShapeStyle(.secondary)
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
