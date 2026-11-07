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

    /// Klassisch and Vinyl bring their own colors; the choices stay stored for Modern.
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
                SettingsRow(title: String(localized: "Modus"),
                            hint: preferences.signatureDesign.isAlwaysDark
                                ? String(localized: "Das Design „Vinyl“ ist immer dunkel.")
                                : preferences.appearance.hint) {
                    GlassSegmentedPicker(selection: $preferences.appearance, options: AppearanceMode.allCases) { Text($0.title) }
                        .accessibilityLabel("Modus")
                        .disabled(preferences.signatureDesign.isAlwaysDark)
                        .opacity(preferences.signatureDesign.isAlwaysDark ? AppStyle.dimmedOpacity : 1)
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
                    .opacity(preferences.signatureDesign.usesColorChoices ? 1 : AppStyle.dimmedOpacity)
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
                    .opacity(preferences.signatureDesign.usesColorChoices ? 1 : AppStyle.dimmedOpacity)
                }
                Divider()
                SettingsRow(title: String(localized: "Gezeichnete Cover"),
                            hint: DemoMode.isActive
                                ? String(localized: "In der Demo sind die Cover immer gezeichnet.")
                                : String(localized: "Statt der Bilder von Discogs bunte Cover mit Interpret und Titel, wie in der Demo.")) {
                    Toggle("Gezeichnete Cover", isOn: $preferences.drawnCovers).labelsHidden().toggleStyle(.switch)
                        .disabled(DemoMode.isActive)
                }
            }
            SettingsCard(title: String(localized: "Rubriken"),
                         subtitle: String(localized: "Eigene Namen für die Rubriken oben im Fenster, höchstens \(PageNames.maxLength) Zeichen. Ein leeres Feld gibt der Rubrik ihren ursprünglichen Namen zurück.")) {
                ForEach(Destination.allCases) { page in
                    if page != Destination.allCases.first { Divider() }
                    SettingsRow(title: page.defaultTitle) {
                        PageNameField(page: page)
                    }
                }
            }
            // Everything about how the two overview pages show their records,
            // in one place: grid or list, order, cover size.
            SettingsCard(title: String(localized: "\(Destination.collection.title) und \(Destination.wantlist.title)"),
                         subtitle: String(localized: "Raster oder Liste auch direkt auf der Seite über den runden Knopf unten rechts, die Covergröße mit ⌘+ und ⌘−.")) {
                SettingsRow(title: String(localized: "Ansicht \(Destination.collection.title)")) { OverviewLayoutPicker(selection: $collectionLayout) }
                Divider()
                SettingsRow(title: String(localized: "Reihenfolge \(Destination.collection.title)"), hint: collectionOrder.hint) {
                    GlassSegmentedPicker(selection: order($collectionOrder, scope: DisplaySettings.collectionOrderKey), options: OverviewOrder.allCases) { Text($0.title) }
                        .accessibilityLabel(String(localized: "Reihenfolge \(Destination.collection.title)"))
                }
                Divider()
                SettingsRow(title: String(localized: "Ansicht \(Destination.wantlist.title)")) { OverviewLayoutPicker(selection: $wantlistLayout) }
                Divider()
                SettingsRow(title: String(localized: "Reihenfolge \(Destination.wantlist.title)"), hint: wantlistOrder.hint) {
                    GlassSegmentedPicker(selection: order($wantlistOrder, scope: DisplaySettings.wantlistOrderKey), options: OverviewOrder.allCases) { Text($0.title) }
                        .accessibilityLabel(String(localized: "Reihenfolge \(Destination.wantlist.title)"))
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
            SettingsCard(title: Destination.statistics.title) {
                SettingsRow(title: String(localized: "Reihenfolge der Bereiche"),
                            hint: String(localized: "Auf der Statistikseite einen Bereich am Titel greifen und auf einen anderen ziehen. „Zurücksetzen“ stellt die ursprüngliche Reihenfolge wieder her.")) {
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

/// All choices share one selection. The preview is purely decorative and
/// shows the design's surfaces without inventing any collection contents.
private struct SignatureDesignOption: View {
    let design: SignatureDesign
    let selected: Bool
    let action: () -> Void
    @State private var preferences = AppPreferences.shared

    /// Klassisch and Vinyl: band, paper, highlight – in their own colors,
    /// whichever design is in use. Modern: the chosen accent, the window and
    /// the chosen ambient color (the window again when it is off).
    private var swatches: [Color] {
        switch design {
        case .atelier, .vinyl:
            let colors = design.paperColors
            return [colors.petrol, colors.paper, colors.gold]
        case .liquidGlass:
            return [preferences.accent.color, Color(nsColor: .windowBackgroundColor),
                    preferences.ambient.color ?? Color(nsColor: .windowBackgroundColor)]
        }
    }

    private var description: String {
        switch design {
        case .atelier: String(localized: "Petrol, Creme und Gold – inspiriert vom App-Icon. Matte Papierflächen statt Glas.")
        case .liquidGlass: String(localized: "Glas wie in macOS, mit deiner Akzent- und Ambient-Farbe.")
        case .vinyl: String(localized: "Kühles Graphit mit hellblauen Akzenten, immer dunkel. Matte Flächen statt Glas.")
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppStyle.rowSpacing) {
                Group {
                    switch design {
                    case .liquidGlass: LiquidGlassDesignPreview()
                    case .atelier, .vinyl: AtelierDesignPreview(colors: design.paperColors)
                    }
                }
                .frame(width: 112, height: 72)
                VStack(alignment: .leading, spacing: AppStyle.tightSpacing) {
                    Text(design.title).font(.headline)
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: AppStyle.tightSpacing) {
                        ForEach(Array(swatches.enumerated()), id: \.offset) { _, color in
                            Circle().fill(color)
                                .frame(width: 12, height: 12)
                                .overlay(Circle().strokeBorder(design.isPaper ? design.paperColors.border : Color.primary.opacity(0.15), lineWidth: AppStyle.hairlineWidth))
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

/// Klassisch or Vinyl in miniature, in that design's own colors.
private struct AtelierDesignPreview: View {
    let colors: ClassicColors

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Circle().fill(colors.gold).frame(width: 8, height: 8)
                Spacer(minLength: 0)
                ForEach(0..<3) { index in
                    Capsule().fill(index == 0 ? colors.toolbarSelection : Color.white.opacity(0.4))
                        .frame(width: 10, height: 3)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 18)
            .background(colors.petrol)
            VStack(alignment: .leading, spacing: 7) {
                Capsule().fill(colors.ink).frame(width: 42, height: 4)
                HStack(spacing: 5) {
                    ForEach(0..<3) { _ in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(colors.soft)
                            .overlay {
                                Circle().fill(colors.petrol)
                                    .padding(4)
                                    .overlay(Circle().fill(colors.gold).frame(width: 4, height: 4))
                            }
                    }
                }
                .frame(height: 22)
                Capsule().fill(colors.muted.opacity(0.4)).frame(width: 54, height: 3)
                Spacer(minLength: 0)
            }
            .padding(9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(colors.paper)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppStyle.rowRadius))
        .overlay(RoundedRectangle(cornerRadius: AppStyle.rowRadius).strokeBorder(colors.border, lineWidth: AppStyle.hairlineWidth))
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

/// A page's own name as typed; empty shows the app's name as placeholder.
/// The field itself stops at `PageNames.maxLength` characters: a binding
/// that only shortens what it stores leaves the extra letters standing in
/// the field.
private struct PageNameField: View {
    let page: Destination
    @State private var text: String

    init(page: Destination) {
        self.page = page
        _text = State(initialValue: AppPreferences.shared.pageNames[page.rawValue] ?? "")
    }

    var body: some View {
        GlassTextField(placeholder: page.defaultTitle, text: $text)
            .frame(width: AppStyle.nameFieldWidth)
            .accessibilityLabel(String(localized: "Name der Rubrik \(page.defaultTitle)"))
            .onChange(of: text) { _, typed in
                let limited = PageNames.limited(typed)
                // Cut back first; the shortened text comes round again and is stored then.
                guard limited == typed else { text = limited; return }
                AppPreferences.shared.setPageName(limited, for: page)
            }
            // Changed elsewhere ("Einstellungen zurücksetzen"): the field follows.
            .onChange(of: AppPreferences.shared.pageNames[page.rawValue] ?? "") { _, stored in
                if stored != text { text = stored }
            }
    }
}
