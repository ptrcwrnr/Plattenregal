import SwiftUI

// MARK: - Darstellung

struct AppearanceSettingsView: View {
    @State private var preferences = AppPreferences.shared
    @AppStorage(DisplaySettings.collectionLayoutKey) private var collectionLayout = OverviewLayout.grid
    @AppStorage(DisplaySettings.wantlistLayoutKey) private var wantlistLayout = OverviewLayout.grid
    @AppStorage(DisplaySettings.collectionOrderKey) private var collectionOrder = OverviewOrder.alphabetical
    @AppStorage(DisplaySettings.wantlistOrderKey) private var wantlistOrder = OverviewOrder.alphabetical
    @AppStorage(DisplaySettings.coverSizeKey) private var storedCoverSize = DisplaySettings.defaultCoverSize
    @AppStorage(DisplaySettings.statisticsOrderKey) private var statisticsOrder = ""

    /// Switching to "Zufällig" shuffles anew, not only each launch.
    private func order(_ stored: Binding<OverviewOrder>, scope: String) -> Binding<OverviewOrder> {
        Binding(get: { stored.wrappedValue }, set: { new in
            if new == .random && stored.wrappedValue != .random { OverviewOrder.reshuffle(scope) }
            stored.wrappedValue = new
        })
    }

    /// Klein, Mittel or Groß – always one of them, even for an odd stored
    /// value, so the switch always shows a choice.
    private var coverSize: Binding<Double> {
        Binding(get: { DisplaySettings.coverSize(storedCoverSize) },
                set: { storedCoverSize = $0 })
    }

    /// Klassisch brings its own colors; the choices stay stored for Modern.
    private var colorHint: String? {
        preferences.signatureDesign.usesColorChoices ? nil : String(localized: "Gilt nur für das Design „Modern“.")
    }

    var body: some View {
        @Bindable var preferences = preferences
        SettingsPage {
            SettingsCard(title: String(localized: "Design")) {
                ForEach(SignatureDesign.allCases) { design in
                    SignatureDesignOption(design: design, selected: preferences.signatureDesign == design) {
                        withAnimation(AppStyle.fadeAnimation) { preferences.signatureDesign = design }
                    }
                }
            }
            SettingsCard(title: String(localized: "Erscheinungsbild")) {
                SettingsRow(title: String(localized: "Modus"), hint: preferences.appearance.hint) {
                    GlassSegmentedPicker(selection: $preferences.appearance, options: AppearanceMode.allCases) { Text($0.title) }
                        .accessibilityLabel("Modus")
                }
                Divider()
                SettingsRow(title: String(localized: "Akzentfarbe"), hint: colorHint) {
                    HStack(spacing: AppStyle.itemSpacing) {
                        ForEach(AccentChoice.allCases) { choice in
                            ColorSwatch(title: choice.title, color: choice.color, rainbow: choice == .system,
                                        selected: preferences.accent == choice) {
                                withAnimation(AppStyle.quickAnimation) { preferences.accent = choice }
                            }
                        }
                    }
                    .disabled(!preferences.signatureDesign.usesColorChoices)
                    .opacity(preferences.signatureDesign.usesColorChoices ? 1 : 0.4)
                }
                Divider()
                SettingsRow(title: String(localized: "Ambient-Farbe"), hint: colorHint) {
                    HStack(spacing: AppStyle.itemSpacing) {
                        ForEach(AmbientChoice.allCases) { choice in
                            ColorSwatch(title: choice.title, color: choice.color ?? .secondary, off: choice == .off,
                                        selected: preferences.ambient == choice) {
                                withAnimation(AppStyle.quickAnimation) { preferences.ambient = choice }
                            }
                        }
                    }
                    .disabled(!preferences.signatureDesign.usesColorChoices)
                    .opacity(preferences.signatureDesign.usesColorChoices ? 1 : 0.4)
                }
            }
            // Everything about how the two overview pages show their records,
            // in one place: grid or list, order, cover size.
            SettingsCard(title: String(localized: "Collection und Wantlist"),
                         subtitle: String(localized: "Raster oder Liste auch direkt auf der Seite über den runden Knopf unten rechts, die Covergröße mit ⌘+ und ⌘−.")) {
                SettingsRow(title: String(localized: "Ansicht Collection")) { OverviewLayoutPicker(selection: $collectionLayout) }
                Divider()
                SettingsRow(title: String(localized: "Reihenfolge Collection"), hint: collectionOrder.hint) {
                    GlassSegmentedPicker(selection: order($collectionOrder, scope: DisplaySettings.collectionOrderKey), options: OverviewOrder.allCases) { Text($0.title) }
                        .accessibilityLabel("Reihenfolge der Collection")
                }
                Divider()
                SettingsRow(title: String(localized: "Ansicht Wantlist")) { OverviewLayoutPicker(selection: $wantlistLayout) }
                Divider()
                SettingsRow(title: String(localized: "Reihenfolge Wantlist"), hint: wantlistOrder.hint) {
                    GlassSegmentedPicker(selection: order($wantlistOrder, scope: DisplaySettings.wantlistOrderKey), options: OverviewOrder.allCases) { Text($0.title) }
                        .accessibilityLabel("Reihenfolge der Wantlist")
                }
                Divider()
                SettingsRow(title: String(localized: "Covergröße im Raster"),
                            hint: String(localized: "Die kleinste Breite eines Covers. Die Spalten füllen die Fensterbreite immer ganz aus.")) {
                    GlassSegmentedPicker(selection: coverSize, options: DisplaySettings.coverSizes) {
                        Text(DisplaySettings.coverSizeName($0))
                    }
                    .accessibilityLabel("Mindestgröße der Cover")
                }
            }
            SettingsCard(title: String(localized: "Statistik")) {
                SettingsRow(title: String(localized: "Reihenfolge der Abschnitte"),
                            hint: String(localized: "Abschnitte lassen sich auf der Statistikseite per Drag & Drop umsortieren.")) {
                    SecondaryButton(title: String(localized: "Zurücksetzen")) { statisticsOrder = "" }
                        .disabled(StatisticsSection.ordered(from: statisticsOrder) == StatisticsSection.allCases)
                }
            }
        }
        .animation(AppStyle.quickAnimation, value: preferences.signatureDesign)
        // Changes every page's look: worth a line in the protocol for bug reports.
        .onChange(of: preferences.signatureDesign) { old, new in
            AppLog.info("Einstellungen", "Design: \(new.logName) statt \(old.logName)")
        }
    }
}

/// Both choices share one selection. The preview is purely decorative and
/// shows the design's surfaces without inventing any collection contents.
private struct SignatureDesignOption: View {
    let design: SignatureDesign
    let selected: Bool
    let action: () -> Void
    @State private var preferences = AppPreferences.shared

    /// Klassisch: petrol, paper, gold. Modern: the chosen accent, the window
    /// and the chosen ambient color (the window again when it is off).
    private var swatches: [Color] {
        switch design {
        case .atelier: [AtelierPalette.petrol, AtelierPalette.paper, AtelierPalette.gold]
        case .liquidGlass:
            [preferences.accent.color, Color(nsColor: .windowBackgroundColor),
             preferences.ambient.color ?? Color(nsColor: .windowBackgroundColor)]
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppStyle.rowSpacing) {
                Group {
                    switch design {
                    case .liquidGlass: LiquidGlassDesignPreview()
                    case .atelier: AtelierDesignPreview()
                    }
                }
                .frame(width: 112, height: 72)
                VStack(alignment: .leading, spacing: AppStyle.tightSpacing) {
                    Text(design.title).font(.headline)
                        .foregroundStyle(.primary)
                    Text(design == .atelier
                         ? String(localized: "Petrol, Creme und Gold – inspiriert vom App-Icon. Matte Papierflächen statt Glas.")
                         : String(localized: "Glas wie in macOS, mit deiner Akzent- und Ambient-Farbe."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: AppStyle.tightSpacing) {
                        ForEach(Array(swatches.enumerated()), id: \.offset) { _, color in
                            Circle().fill(color)
                                .frame(width: 12, height: 12)
                                .overlay(Circle().strokeBorder(design == .atelier ? AtelierPalette.border : Color.primary.opacity(0.15), lineWidth: AppStyle.hairlineWidth))
                        }
                    }
                    .padding(.top, AppStyle.hairSpacing)
                    .animation(AppStyle.quickAnimation, value: preferences.accent)
                    .animation(AppStyle.quickAnimation, value: preferences.ambient)
                    .accessibilityHidden(true)
                }
                Spacer(minLength: AppStyle.itemSpacing)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? AppStyle.accent : Color.secondary.opacity(0.5))
                    .accessibilityHidden(true)
            }
            .padding(AppStyle.rowSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? AppStyle.selectedBackground : Color.clear,
                        in: RoundedRectangle(cornerRadius: AppStyle.surfaceRadius))
            .overlay {
                RoundedRectangle(cornerRadius: AppStyle.surfaceRadius)
                    .strokeBorder(selected ? AppStyle.selectedBorder.opacity(AppStyle.isAtelier ? 1 : 0.5) : AppStyle.borderColor,
                                  lineWidth: selected ? AppStyle.selectionLineWidth : AppStyle.borderWidth)
            }
            .contentShape(RoundedRectangle(cornerRadius: AppStyle.surfaceRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(design.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Modern (Liquid Glass) in miniature: a glass page switch over a soft ambient glow
/// and a few colored sleeves.
private struct LiquidGlassDesignPreview: View {
    @State private var preferences = AppPreferences.shared
    var body: some View {
        let glow = preferences.ambient.color ?? .secondary
        ZStack(alignment: .top) {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(colors: [glow.opacity(0.35), .clear], center: .top, startRadius: 0, endRadius: 80)
            VStack(spacing: 7) {
                Capsule().fill(.white.opacity(0.55))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.8), lineWidth: AppStyle.hairlineWidth))
                    .overlay(Capsule().fill(preferences.accent.color.opacity(0.9)).frame(width: 12, height: 3))
                    .frame(width: 46, height: 10)
                    .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                HStack(spacing: 5) {
                    ForEach([Color.pink, .teal, .indigo], id: \.self) { color in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(LinearGradient(colors: [color.opacity(0.75), color.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
                .frame(height: 26)
                .padding(.horizontal, 9)
                // The caption under the covers, as in Klassisch.
                Capsule().fill(Color.secondary.opacity(0.4)).frame(width: 54, height: 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
            }
            .padding(.top, 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.rowRadius))
        .overlay(RoundedRectangle(cornerRadius: AppStyle.rowRadius).strokeBorder(Color.primary.opacity(0.1), lineWidth: AppStyle.hairlineWidth))
        .accessibilityHidden(true)
    }
}

private struct AtelierDesignPreview: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Circle().fill(AtelierPalette.gold).frame(width: 8, height: 8)
                Spacer(minLength: 0)
                ForEach(0..<3) { index in
                    Capsule().fill(index == 0 ? AtelierPalette.toolbarSelection : Color.white.opacity(0.4))
                        .frame(width: 10, height: 3)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 18)
            .background(AtelierPalette.petrol)
            VStack(alignment: .leading, spacing: 7) {
                Capsule().fill(AtelierPalette.ink).frame(width: 42, height: 4)
                HStack(spacing: 5) {
                    ForEach(0..<3) { _ in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(AtelierPalette.soft)
                            .overlay {
                                Circle().fill(AtelierPalette.petrol)
                                    .padding(4)
                                    .overlay(Circle().fill(AtelierPalette.gold).frame(width: 4, height: 4))
                            }
                    }
                }
                .frame(height: 22)
                Capsule().fill(AtelierPalette.muted.opacity(0.4)).frame(width: 54, height: 3)
                Spacer(minLength: 0)
            }
            .padding(9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AtelierPalette.paper)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.rowRadius))
        .overlay(RoundedRectangle(cornerRadius: AppStyle.rowRadius).strokeBorder(AtelierPalette.border, lineWidth: AppStyle.hairlineWidth))
        .accessibilityHidden(true)
    }
}

/// One round color choice; `rainbow` for "System", `off` (a white ball) for "Aus".
private struct ColorSwatch: View {
    let title: String
    let color: Color
    var rainbow = false
    var off = false
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if rainbow {
                    Circle().fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red], center: .center))
                } else if off {
                    Circle().fill(.white)
                } else {
                    Circle().fill(color)
                }
                // Shadowed, so the mark stays visible on light swatches like yellow.
                if selected {
                    Circle().fill(.white).frame(width: 6, height: 6)
                        .shadow(color: .black.opacity(0.45), radius: 1)
                }
            }
            .frame(width: 18, height: 18)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.15)))
            .padding(3)
            .overlay(Circle().strokeBorder(selected ? (off ? Color.secondary : color) : .clear, lineWidth: AppStyle.selectionLineWidth))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
