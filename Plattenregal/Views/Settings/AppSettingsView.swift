import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// A settings tab asked for from the main window ("Token eintragen" on an
/// empty collection, "Belegung wiederherstellen" on an empty shelf). Read
/// when the settings window opens, and followed while it is already open.
@MainActor @Observable
final class SettingsRequest {
    static let shared = SettingsRequest()
    private(set) var tab: AppSettingsView.Tab?
    private(set) var count = 0
    func show(_ tab: AppSettingsView.Tab) { self.tab = tab; count += 1 }
    /// The requested tab, once.
    func take() -> AppSettingsView.Tab? { defer { tab = nil }; return tab }
}

extension View {
    /// Opens the settings window on `tab`.
    func settingsOpener(_ open: Binding<AppSettingsView.Tab?>) -> some View {
        modifier(SettingsOpener(tab: open))
    }
}

private struct SettingsOpener: ViewModifier {
    @Binding var tab: AppSettingsView.Tab?
    @Environment(\.openSettings) private var openSettings
    func body(content: Content) -> some View {
        content.onChange(of: tab) { _, requested in
            guard let requested else { return }
            SettingsRequest.shared.show(requested)
            openSettings()
            tab = nil
        }
    }
}

/// Settings in the same card language as the app's pages: rounded titles,
/// quiet card surfaces and the shared button vocabulary.
struct AppSettingsView: View {
    enum Tab: String, CaseIterable { case general = "Allgemein", appearance = "Darstellung", shelf = "Regal", discogs = "Discogs"
        case export = "Export", backup = "Sicherung", data = "Daten", shortcuts = "Tastenkürzel"
        var title: String {
            switch self {
            case .general: String(localized: "Allgemein")
            case .appearance: String(localized: "Darstellung")
            case .shelf: String(localized: "Regal")
            case .discogs: String(localized: "Discogs")
            case .export: String(localized: "Export")
            case .backup: String(localized: "Sicherung")
            case .data: String(localized: "Daten")
            case .shortcuts: String(localized: "Tastenkürzel")
            }
        }
    }
    @State private var tab: Tab = {
        #if DEBUG
        // Screenshots of a tab without clicking there: --settings-tab=Regal
        if let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--settings-tab=") }),
           let tab = Tab(rawValue: String(raw.dropFirst("--settings-tab=".count))) { return tab }
        #endif
        return SettingsRequest.shared.take() ?? .general
    }()
    @State private var request = SettingsRequest.shared
    @Environment(\.dismiss) private var dismiss
    /// A form in the page has its own "Abbrechen" on Esc (see `SettingsEscapeKey`).
    @State private var escapeTaken = false

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
            case .shortcuts: ShortcutSettingsView()
            }
        }
        // Tall enough for "Allgemein" without a gap below, longer tabs scroll.
        .frame(width: 760, height: 510)
        // Only the area switch in the title bar: no window buttons next to
        // it. Esc and ⌘W close the window instead.
        .background { WindowButtonsHidden() }
        .background {
            Group {
                Button { dismiss() } label: { EmptyView() }.keyboardShortcut(.cancelAction).disabled(escapeTaken)
                Button { dismiss() } label: { EmptyView() }.keyboardShortcut("w")
            }
            .opacity(0).accessibilityHidden(true)
        }
        .onPreferenceChange(SettingsEscapeKey.self) { escapeTaken = $0 }
        // The chosen ambient color, as in the main window.
        .background { AmbientGlow() }
        // Asked for from the main window while this one is already open.
        .onChange(of: request.count) { if let asked = request.take() { tab = asked } }
        .navigationTitle(tab.title)
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .principal) {
                GlassSegmentedPicker(selection: $tab, options: Tab.allCases, glass: false) { Text($0.title) }
                    .accessibilityLabel("Bereich")
            }
        }
    }
}

/// True while a form in the settings answers Esc itself ("Abbrechen" of a
/// new shelf): then Esc cancels that form instead of closing the window.
struct SettingsEscapeKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// Hides close, minimize and zoom of the window this view sits in.
private struct WindowButtonsHidden: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    private final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window?.standardWindowButton(kind)?.isHidden = true
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
                    AppBanner(message: String(localized: "Demo: Diese Einstellungen gelten nur für die Demo. Deine eigenen bleiben, wie sie sind."), kind: .info,
                              actionTitle: String(localized: "Demo beenden"), action: { DemoMode.end() })
                }
                content
            }
                .padding(AppStyle.pagePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // The edge effect draws a line under the toolbar when hovered.
        .scrollEdgeEffectHidden(true, for: .top)
    }
}

/// One glass card: title (+ subtitle), then its rows.
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
        // The same glass cards as the statistics page.
        .appCardSurface()
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
    @AppStorage(DisplaySettings.collectionOrderKey) private var collectionOrder = OverviewOrder.alphabetical
    @AppStorage(DisplaySettings.wantlistOrderKey) private var wantlistOrder = OverviewOrder.alphabetical

    /// Switching to "Zufällig" shuffles anew, not only each launch.
    private func order(_ stored: Binding<OverviewOrder>, scope: String) -> Binding<OverviewOrder> {
        Binding(get: { stored.wrappedValue }, set: { new in
            if new == .random && stored.wrappedValue != .random { OverviewOrder.reshuffle(scope) }
            stored.wrappedValue = new
        })
    }

    var body: some View {
        @Bindable var preferences = preferences
        SettingsPage {
            SettingsCard(title: String(localized: "Sprache")) {
                SettingsRow(title: String(localized: "Sprache der App"),
                            hint: preferences.language == .system
                                ? String(localized: "Folgt der Sprache von macOS. Plattenregal gibt es auf Deutsch und Englisch.")
                                : String(localized: "Gilt nur für Plattenregal, unabhängig von macOS.")) {
                    GlassSegmentedPicker(selection: $preferences.language, options: AppLanguage.allCases) { Text($0.title) }
                        .accessibilityLabel(String(localized: "Sprache"))
                }
                if preferences.languageNeedsRestart {
                    Divider()
                    SettingsRow(title: String(localized: "Neustart nötig"),
                                hint: String(localized: "Die neue Sprache gilt ab dem nächsten Start von Plattenregal.")) {
                        PrimaryButton(title: String(localized: "Jetzt neu starten")) { DemoMode.relaunchForLanguage() }
                    }
                }
            }
            SettingsCard(title: String(localized: "Start")) {
                SettingsRow(title: String(localized: "Beim Öffnen zeigen"), hint: String(localized: "Die Seite, mit der das Hauptfenster startet.")) {
                    GlassSegmentedPicker(selection: $preferences.startPage, options: StartPage.allCases) { Text($0.title) }
                        .accessibilityLabel("Startseite")
                }
                Divider()
                SettingsRow(title: String(localized: "Reihenfolge Collection"), hint: collectionOrder.hint) {
                    GlassSegmentedPicker(selection: order($collectionOrder, scope: DisplaySettings.collectionOrderKey), options: OverviewOrder.allCases) { Text($0.title) }
                        .accessibilityLabel("Reihenfolge der Collection")
                }
                Divider()
                SettingsRow(title: String(localized: "Reihenfolge Wantlist"), hint: wantlistOrder.hint) {
                    GlassSegmentedPicker(selection: order($wantlistOrder, scope: DisplaySettings.wantlistOrderKey), options: OverviewOrder.allCases) { Text($0.title) }
                        .accessibilityLabel("Reihenfolge der Wantlist")
                }
            }
            SettingsCard(title: String(localized: "Demo"), subtitle: String(localized: "Plattenregal mit einer Beispielsammlung ausprobieren oder vorführen.")) {
                SettingsRow(title: DemoMode.isActive ? String(localized: "Die Demo läuft") : String(localized: "Beispielsammlung"),
                            hint: DemoMode.isActive
                                ? String(localized: "Beim Beenden startet Plattenregal neu mit deiner eigenen Sammlung. Alles, was du in der Demo geändert hast, ist dann weg.")
                                : String(localized: "Rund 50 Platten in zwei Regalen, Wantlist und Wertverlauf. Alles lässt sich ändern, nichts wird gespeichert, deine Sammlung bleibt unberührt. Plattenregal startet dafür neu.")) {
                    if DemoMode.isActive {
                        HStack(spacing: AppStyle.itemSpacing) {
                            GhostButton(title: String(localized: "Neu starten")) { DemoMode.restart() }
                            SecondaryButton(title: String(localized: "Demo beenden")) { DemoMode.end() }
                        }
                    } else {
                        SecondaryButton(title: String(localized: "Demo starten")) { DemoMode.confirmStart() }
                    }
                }
            }
        }
    }
}

// MARK: - Tastenkürzel

/// Every shortcut of the app, one card per place it works.
struct ShortcutSettingsView: View {
    var body: some View {
        SettingsPage {
            ForEach(AppShortcuts.groups) { group in
                SettingsCard(title: group.title) {
                    ForEach(group.entries) { entry in
                        if entry.id != group.entries.first?.id { Divider() }
                        SettingsRow(title: entry.title) {
                            Text(entry.keys).monospacedDigit().foregroundStyle(.secondary)
                        }
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
            SettingsCard(title: String(localized: "Erscheinungsbild")) {
                SettingsRow(title: String(localized: "Modus"), hint: preferences.appearance.hint) {
                    GlassSegmentedPicker(selection: $preferences.appearance, options: AppearanceMode.allCases) { Text($0.title) }
                        .accessibilityLabel("Modus")
                }
                Divider()
                SettingsRow(title: String(localized: "Akzentfarbe")) {
                    HStack(spacing: 6) {
                        ForEach(AccentChoice.allCases) { choice in
                            ColorSwatch(title: choice.title, color: choice.color, rainbow: choice == .system,
                                        selected: preferences.accent == choice) {
                                withAnimation(AppStyle.quickAnimation) { preferences.accent = choice }
                            }
                        }
                    }
                }
                Divider()
                SettingsRow(title: String(localized: "Ambient-Farbe")) {
                    HStack(spacing: 6) {
                        ForEach(AmbientChoice.allCases) { choice in
                            ColorSwatch(title: choice.title, color: choice.color ?? .secondary, off: choice == .off,
                                        selected: preferences.ambient == choice) {
                                withAnimation(AppStyle.quickAnimation) { preferences.ambient = choice }
                            }
                        }
                    }
                }
            }
            SettingsCard(title: String(localized: "Übersicht"),
                         subtitle: String(localized: "Lässt sich auch direkt in der Kopfleiste von Collection und Wantlist umschalten.")) {
                SettingsRow(title: String(localized: "Collection")) { OverviewLayoutPicker(selection: $collectionLayout) }
                Divider()
                SettingsRow(title: String(localized: "Wantlist")) { OverviewLayoutPicker(selection: $wantlistLayout) }
            }
            SettingsCard(title: String(localized: "Cover"),
                         subtitle: String(localized: "Die Spalten füllen die Fensterbreite immer ganz aus.")) {
                SettingsRow(title: String(localized: "Mindestgröße im Raster")) {
                    HStack(spacing: AppStyle.tightSpacing) {
                        if coverSize.wrappedValue != DisplaySettings.defaultCoverSize {
                            IconButton(systemImage: "arrow.counterclockwise",
                                       help: String(localized: "Auf Standard (\(Int(DisplaySettings.defaultCoverSize)) pt) zurücksetzen")) {
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
            SettingsCard(title: String(localized: "Statistik")) {
                SettingsRow(title: String(localized: "Reihenfolge der Abschnitte"),
                            hint: String(localized: "Abschnitte lassen sich auf der Statistikseite per Drag & Drop umsortieren.")) {
                    SecondaryButton(title: String(localized: "Zurücksetzen")) { statisticsOrder = "" }
                        .disabled(StatisticsSection.ordered(from: statisticsOrder) == StatisticsSection.allCases)
                }
            }
        }
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
            .overlay(Circle().strokeBorder(selected ? (off ? Color.secondary : color) : .clear, lineWidth: 2))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
