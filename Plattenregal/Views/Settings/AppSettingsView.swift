import SwiftUI

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
    enum Tab: String, CaseIterable { case general = "Allgemein", appearance = "Darstellung", shelf = "Regal", lists = "Listen", discogs = "Discogs"
        case export = "Export", backup = "Sicherung", data = "Daten", shortcuts = "Tastenkürzel"
        var title: String {
            switch self {
            case .general: String(localized: "Allgemein")
            case .appearance: String(localized: "Darstellung")
            case .shelf: String(localized: "Regal")
            case .lists: String(localized: "Listen")
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
        // Another tab fades and settles in like a page of the main window.
        ZStack {
            Group {
                switch tab {
                case .general: GeneralSettingsView()
                case .appearance: AppearanceSettingsView()
                case .shelf: ShelfSettingsView()
                case .lists: ListsSettingsView()
                case .discogs: DiscogsSettingsView()
                case .export: ExportSettingsView()
                case .backup: BackupSettingsView()
                case .data: DataSettingsView()
                case .shortcuts: ShortcutSettingsView()
                }
            }
            .id(tab)
            // Brings its own timing: an animation around it would replace it.
            .transition(AppStyle.pageTransition)
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
        // No separator line under the toolbar, not even on hover.
        // Klassisch shows its petrol toolbar instead (see `SignatureToolbarAppearance`).
        .toolbarBackgroundVisibility(AppStyle.isAtelier ? .visible : .hidden, for: .windowToolbar)
        .background { SignatureToolbarAppearance() }
        .toolbar {
            ToolbarItem(placement: .principal) {
                GlassSegmentedPicker(selection: $tab, options: Tab.allCases, glass: false) { Text($0.title) }
                    .toolbarBar()
                    .accessibilityLabel("Bereich")
            }
            // The bar brings its own background, as in the main window.
            .sharedBackgroundVisibility(.hidden)
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
