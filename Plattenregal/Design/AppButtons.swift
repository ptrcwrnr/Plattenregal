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
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(primary ? AtelierPalette.gold : AtelierPalette.border, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.45)
    }
}

/// One button vocabulary for the whole app: Primary (main action), Secondary
/// (normal action), Ghost (low-emphasis/secondary action), Icon (compact icon-only).
/// Primary and Secondary are Liquid Glass; the main action is told apart by
/// the accent color of its title, like the chosen option of a
/// `GlassSegmentedPicker` – no filled blue.
struct PrimaryButton: View {
    let title: String
    var action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @ViewBuilder
    var body: some View {
        if AppStyle.isAtelier {
            Button(title, action: action).buttonStyle(AtelierButtonStyle(primary: true))
        } else {
        // Disabled: no accent, so it dims like every other button instead of
        // looking clickable.
        Button(action: action) { Text(title).foregroundStyle(isEnabled ? AnyShapeStyle(AppStyle.accent) : AnyShapeStyle(.tertiary)) }
            .appGlassButton()
        }
    }
}
struct SecondaryButton: View {
    let title: String
    var action: () -> Void
    var body: some View {
        Button(title, action: action).appGlassButton()
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
        .frame(height: 30)
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
