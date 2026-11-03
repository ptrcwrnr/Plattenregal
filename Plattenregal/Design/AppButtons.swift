import SwiftUI

struct AtelierButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .foregroundStyle(primary ? AtelierPalette.goldForeground : AtelierPalette.ink)
            .padding(.horizontal, AppStyle.rowSpacing).padding(.vertical, 6)
            .background(primary ? AtelierPalette.gold : configuration.isPressed ? AtelierPalette.soft : AtelierPalette.surface,
                        in: RoundedRectangle(cornerRadius: AppStyle.atelierControlRadius))
            .overlay(RoundedRectangle(cornerRadius: AppStyle.atelierControlRadius).strokeBorder(primary ? AtelierPalette.gold : AtelierPalette.border, lineWidth: AppStyle.borderWidth))
            .opacity(isEnabled ? 1 : 0.45)
    }
}

/// One button vocabulary for the whole app: Primary (main action), Secondary
/// (normal action), Ghost (low-emphasis/secondary action), Icon (compact icon-only).
/// Primary and Secondary are Liquid Glass; the main action is told apart by
/// the accent color of its title, like the chosen option of a
/// `GlassSegmentedPicker` – no filled blue. In dark mode the title stays
/// light: the accent on dark glass was hard to read.
struct PrimaryButton: View {
    let title: String
    /// Takes all the width it's offered – a row of equally wide buttons that
    /// ends flush with the text above (the update window).
    var fillsWidth = false
    var action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder
    var body: some View {
        if AppStyle.isAtelier {
            Button(action: action) { Text(title).frame(maxWidth: fillsWidth ? .infinity : nil) }
                .buttonStyle(AtelierButtonStyle(primary: true))
        } else {
        // Disabled: no accent, so it dims like every other button instead of
        // looking clickable.
        Button(action: action) {
            Text(title).foregroundStyle(!isEnabled ? AnyShapeStyle(.tertiary)
                                        : colorScheme == .dark ? AnyShapeStyle(.primary) : AnyShapeStyle(AppStyle.accent))
                .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
            .appGlassButton()
        }
    }
}
struct SecondaryButton: View {
    let title: String
    /// See `PrimaryButton.fillsWidth`.
    var fillsWidth = false
    var action: () -> Void
    var body: some View {
        Button(action: action) { Text(title).frame(maxWidth: fillsWidth ? .infinity : nil) }.appGlassButton()
    }
}
struct GhostButton: View {
    let title: String
    var action: () -> Void
    var body: some View {
        Button(title, action: action).buttonStyle(.borderless)
    }
}
struct IconButton: View {
    let systemImage: String
    var help: String = ""
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// − value + in a Liquid Glass capsule, in place of the gray system stepper.
struct GlassStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let label: (Int) -> String

    var body: some View {
        HStack(spacing: AppStyle.hairSpacing) {
            step("minus", String(localized: "Verringern"), by: -1).disabled(value <= range.lowerBound)
            Text(label(value))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
                .padding(.horizontal, AppStyle.tightSpacing)
            step("plus", String(localized: "Erhöhen"), by: 1).disabled(value >= range.upperBound)
        }
        .animation(AppStyle.quickAnimation, value: value)
        .padding(.horizontal, AppStyle.itemSpacing)
        .frame(height: AppStyle.controlHeight)
        .appChipSurface(in: Capsule(), interactive: true)
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityValue(label(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 1, range.upperBound)
            case .decrement: value = max(value - 1, range.lowerBound)
            @unknown default: break
            }
        }
    }

    private func step(_ systemImage: String, _ help: String, by offset: Int) -> some View {
        GlassStepButton(systemImage: systemImage, help: help) {
            value = min(max(value + offset, range.lowerBound), range.upperBound)
        }
    }
}

/// A small round icon button inside a glass capsule (stepper).
private struct GlassStepButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(AppStyle.buttonSymbol)
                .foregroundStyle(AppStyle.isAtelier ? AnyShapeStyle(AtelierPalette.muted) : AnyShapeStyle(.secondary))
                .frame(width: 20, height: 20)
                .background(hovering && isEnabled ? AppStyle.hoverBackground : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { hovering = $0 }
    }
}

/// The small round button with a symbol only ("Platte hinzufügen" on a
/// compartment, "Auf Discogs öffnen" in a record's details): the glyph in the
/// accent on the chip surface – Liquid Glass in Modern, paper with a fine
/// rim in Klassisch (see `appChipSurface`).
struct SmallRoundButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(AppStyle.buttonSymbol)
                .foregroundStyle(AppStyle.accent)
                .frame(width: AppStyle.smallControlHeight, height: AppStyle.smallControlHeight)
                .contentShape(Circle())
                .appChipSurface(in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
