import SwiftUI
import AppKit
import ObjectiveC

/// A choice between a few options. The chosen one sits on a pill that glides
/// to a new choice, the same in both designs: in Modern a Liquid Glass lens
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
    /// The selection pill is one view sliding between the options.
    @Namespace private var pill

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
                        .frame(width: 1, height: small ? 12 : 14)
                        .opacity(besidePill ? 0 : 1)
                }
                Button { selection = option } label: {
                    label(option)
                        // Color only: a heavier weight would widen the label
                        // and shift its neighbours on every switch.
                        .foregroundStyle(AppStyle.isAtelier
                            ? AnyShapeStyle(selected ? (glass ? AtelierPalette.ink : AtelierPalette.toolbarInk) : glass ? AtelierPalette.muted : Color.white.opacity(0.8))
                            : selected ? AnyShapeStyle(AppStyle.accent) : AnyShapeStyle(.secondary))
                        .padding(.horizontal, small ? AppStyle.itemSpacing : AppStyle.rowSpacing)
                        .frame(height: small ? 24 : 30)
                        .background {
                            if selected {
                                if AppStyle.isAtelier {
                                    RoundedRectangle(cornerRadius: 7).fill(glass ? AtelierPalette.surface : AtelierPalette.toolbarSelection)
                                        .padding(.vertical, 3)
                                        .matchedGeometryEffect(id: "pill", in: pill)
                                } else {
                                    Capsule().fill(.clear)
                                        .glassEffect(.regular, in: .capsule)
                                        .padding(.vertical, 3)
                                        .matchedGeometryEffect(id: "pill", in: pill)
                                }
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .modifier(OptionalSecondaryClick(action: secondaryClick.map { click in { click(option, $0) } }))
            }
        }
        .font(small ? .callout : .body)
        .animation(.smooth(duration: 0.3), value: selection)
        .fixedSize()
        // A group: a label given to the picker (`.accessibilityLabel("Modus")`)
        // names the group instead of replacing every option's name.
        .accessibilityElement(children: .contain)
        if glass {
            row.padding(.horizontal, 3)
                .background {
                    if AppStyle.isAtelier {
                        RoundedRectangle(cornerRadius: 10).fill(AtelierPalette.soft)
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AtelierPalette.border, lineWidth: 1))
                    }
                }
                .glassEffect(AppStyle.isAtelier ? .identity : .regular.interactive(), in: .capsule)
        } else {
            row
        }
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
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        // A plain menu inside our own glass capsule: the button styles leave
        // a menu gray-filled.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .padding(.horizontal, AppStyle.cardPadding)
        .frame(height: 30)
        .background {
            if AppStyle.isAtelier {
                RoundedRectangle(cornerRadius: 9).fill(AtelierPalette.surface)
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(AtelierPalette.border, lineWidth: 1))
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
