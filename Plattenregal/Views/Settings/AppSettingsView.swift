import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Settings in the same card language as the app's pages: rounded titles,
/// quiet card surfaces and the shared button vocabulary.
struct AppSettingsView: View {
    enum Tab: String, CaseIterable { case general = "Allgemein", appearance = "Darstellung", shelf = "Regal", discogs = "Discogs"
        case export = "Export", backup = "Sicherung", data = "Daten" }
    @State private var tab: Tab = {
        #if DEBUG
        // Screenshots of a tab without clicking there: --settings-tab=Regal
        if let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--settings-tab=") }),
           let tab = Tab(rawValue: String(raw.dropFirst("--settings-tab=".count))) { return tab }
        #endif
        return .general
    }()

    var body: some View {
        // The same Liquid Glass switch as the main window, instead of tabs.
        Group {
            switch tab {
            case .general: GeneralSettingsView()
            case .appearance: AppearanceSettingsView()
            case .shelf: ShelfSettingsView()
            case .discogs: DiscogsSettingsView()
            case .export: ExportSettingsView()
            case .backup: BackupSettingsView()
            case .data: DataSettingsView()
            }
        }
        .frame(width: 760, height: 620)
        .navigationTitle(tab.rawValue)
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .principal) {
                GlassSegmentedPicker(selection: $tab, options: Tab.allCases, glass: false) { Text($0.rawValue) }
                    .accessibilityLabel("Bereich")
            }
        }
    }
}

// MARK: - Shared building blocks

/// Scrollable page of setting cards.
struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                if DemoMode.isActive {
                    AppBanner(message: "Demo: Diese Einstellungen gelten nur für die Demo. Deine eigenen bleiben, wie sie sind.", kind: .info,
                              actionTitle: "Demo beenden", action: { DemoMode.end() })
                }
                content
            }
                .padding(AppStyle.pagePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One card: title (+ subtitle), then its rows.
struct SettingsCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(AppStyle.sectionTitle)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            content
        }
        .padding(AppStyle.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: AppStyle.cardRadius))
    }
}

/// Label (+ optional hint) on the left, control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    var hint: String?
    @ViewBuilder let control: Control
    var body: some View {
        HStack(alignment: .center, spacing: AppStyle.rowSpacing) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let hint {
                    Text(hint).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: AppStyle.rowSpacing)
            control
        }
    }
}

struct SettingsNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Allgemein

struct GeneralSettingsView: View {
    @State private var preferences = AppPreferences.shared

    var body: some View {
        @Bindable var preferences = preferences
        SettingsPage {
            SettingsCard(title: "Start") {
                SettingsRow(title: "Beim Öffnen zeigen", hint: "Die Seite, mit der das Hauptfenster startet.") {
                    GlassSegmentedPicker(selection: $preferences.startPage, options: StartPage.allCases) { Text($0.title) }
                        .accessibilityLabel("Startseite")
                }
            }
            SettingsCard(title: "Demo", subtitle: "Plattenregal mit einer Beispielsammlung ausprobieren oder vorführen.") {
                SettingsRow(title: DemoMode.isActive ? "Die Demo läuft" : "Beispielsammlung",
                            hint: DemoMode.isActive
                                ? "Beim Beenden startet Plattenregal neu mit deiner eigenen Sammlung. Alles, was du in der Demo geändert hast, ist dann weg."
                                : "Rund 50 Platten in zwei Regalen, Wantlist und Wertverlauf. Alles lässt sich ändern, nichts wird gespeichert, deine Sammlung bleibt unberührt. Plattenregal startet dafür neu.") {
                    if DemoMode.isActive {
                        HStack(spacing: AppStyle.itemSpacing) {
                            GhostButton(title: "Neu starten") { DemoMode.restart() }
                            SecondaryButton(title: "Demo beenden") { DemoMode.end() }
                        }
                    } else {
                        SecondaryButton(title: "Demo starten …") { DemoMode.confirmStart() }
                    }
                }
            }
        }
    }
}

// MARK: - Darstellung

struct AppearanceSettingsView: View {
    @State private var preferences = AppPreferences.shared
    @AppStorage(DisplaySettings.collectionLayoutKey) private var collectionLayout = OverviewLayout.grid
    @AppStorage(DisplaySettings.wantlistLayoutKey) private var wantlistLayout = OverviewLayout.grid
    @AppStorage(DisplaySettings.coverSizeKey) private var storedCoverSize = DisplaySettings.defaultCoverSize
    @AppStorage(DisplaySettings.statisticsOrderKey) private var statisticsOrder = ""

    /// Always within the slider's range, even for an odd stored value, so
    /// slider and label never disagree.
    private var coverSize: Binding<Double> {
        Binding(get: { DisplaySettings.coverSize(storedCoverSize) },
                set: { storedCoverSize = DisplaySettings.coverSize($0) })
    }

    var body: some View {
        @Bindable var preferences = preferences
        SettingsPage {
            SettingsCard(title: "Erscheinungsbild") {
                SettingsRow(title: "Modus", hint: preferences.appearance.hint) {
                    GlassSegmentedPicker(selection: $preferences.appearance, options: AppearanceMode.allCases) { Text($0.title) }
                        .accessibilityLabel("Modus")
                }
                Divider()
                SettingsRow(title: "Akzentfarbe", hint: preferences.accent.title) {
                    HStack(spacing: 6) {
                        ForEach(AccentChoice.allCases) { choice in
                            AccentSwatch(choice: choice, selected: preferences.accent == choice) {
                                withAnimation(AppStyle.quickAnimation) { preferences.accent = choice }
                            }
                        }
                    }
                }
            }
            SettingsCard(title: "Übersicht",
                         subtitle: "Lässt sich auch direkt in der Kopfleiste von Collection und Wantlist umschalten.") {
                SettingsRow(title: "Collection") { OverviewLayoutPicker(selection: $collectionLayout) }
                Divider()
                SettingsRow(title: "Wantlist") { OverviewLayoutPicker(selection: $wantlistLayout) }
            }
            SettingsCard(title: "Cover",
                         subtitle: "Die Spalten füllen die Fensterbreite immer ganz aus.") {
                SettingsRow(title: "Mindestgröße im Raster") {
                    HStack(spacing: AppStyle.tightSpacing) {
                        if coverSize.wrappedValue != DisplaySettings.defaultCoverSize {
                            IconButton(systemImage: "arrow.counterclockwise",
                                       help: "Auf Standard (\(Int(DisplaySettings.defaultCoverSize)) pt) zurücksetzen") {
                                storedCoverSize = DisplaySettings.defaultCoverSize
                            }
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                        }
                        Text("\(Int(coverSize.wrappedValue)) pt").monospacedDigit().foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    .animation(AppStyle.quickAnimation, value: coverSize.wrappedValue)
                }
                HStack(spacing: AppStyle.rowSpacing) {
                    Image(systemName: "square.fill").font(.caption2).foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Slider(value: coverSize, in: DisplaySettings.coverSizeRange, step: 5) {
                        Text("Mindestgröße der Cover")
                    }
                    .labelsHidden()
                    Image(systemName: "square.fill").font(.title3).foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            SettingsCard(title: "Statistik") {
                SettingsRow(title: "Reihenfolge der Abschnitte",
                            hint: "Abschnitte lassen sich auf der Statistikseite per Drag & Drop umsortieren.") {
                    SecondaryButton(title: "Zurücksetzen") { statisticsOrder = "" }
                        .disabled(StatisticsSection.ordered(from: statisticsOrder) == StatisticsSection.allCases)
                }
            }
        }
    }
}

private struct AccentSwatch: View {
    let choice: AccentChoice
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if choice == .system {
                    Circle().fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red], center: .center))
                } else {
                    Circle().fill(choice.color)
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
            .overlay(Circle().strokeBorder(selected ? choice.color : .clear, lineWidth: 2))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(choice.title)
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
