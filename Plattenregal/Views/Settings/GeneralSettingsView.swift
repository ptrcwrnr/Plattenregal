import SwiftUI

// MARK: - Allgemein

struct GeneralSettingsView: View {
    @State private var preferences = AppPreferences.shared
    @State private var quickSearch = ShelfQuickSearch.shared
    @State private var loginItem = LoginItem.shared
    @State private var updates = UpdateChecker.shared
    @Environment(\.openWindow) private var openWindow

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
            // Everything about opening and quitting in one place; the search
            // in the menu bar below keeps only its own choices.
            SettingsCard(title: String(localized: "Starten und Beenden")) {
                SettingsRow(title: String(localized: "Beim Öffnen zeigen"), hint: String(localized: "Die Seite, mit der das Hauptfenster startet.")) {
                    // Long page names of one's own (`PageNames`) don't fit as a
                    // switch beside the title: then a menu with the same choices.
                    ViewThatFits(in: .horizontal) {
                        GlassSegmentedPicker(selection: $preferences.startPage, options: StartPage.allCases) { Text($0.title) }
                        GlassMenuPicker(title: String(localized: "Startseite"), selection: $preferences.startPage,
                                        current: preferences.startPage.title) {
                            ForEach(StartPage.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    .frame(maxWidth: AppStyle.settingsControlMaxWidth, alignment: .trailing)
                    .accessibilityLabel("Startseite")
                }
                Divider()
                SettingsRow(title: String(localized: "Bei der Anmeldung öffnen"), hint: loginHint) {
                    Toggle("Bei der Anmeldung öffnen", isOn: Binding(get: { loginItem.isOn }, set: { loginItem.set($0) }))
                        .labelsHidden().toggleStyle(.switch)
                }
                if loginItem.needsApproval {
                    Divider()
                    SettingsRow(title: String(localized: "Freigabe in macOS"),
                                hint: String(localized: "macOS wartet auf deine Freigabe unter Systemeinstellungen → Allgemein → Anmeldeobjekte.")) {
                        SecondaryButton(title: String(localized: "Systemeinstellungen öffnen")) { loginItem.openSystemSettings() }
                    }
                }
                Divider()
                SettingsRow(title: String(localized: "Im Hintergrund weiterlaufen"), hint: backgroundHint) {
                    Toggle("Im Hintergrund weiterlaufen", isOn: $preferences.keepsRunningInBackground)
                        .labelsHidden().toggleStyle(.switch)
                }
                .disabled(!preferences.menuBarSearch || DemoMode.isActive)
            }
            SettingsCard(title: String(localized: "Menüleiste")) {
                SettingsRow(title: String(localized: "Suche in der Menüleiste"),
                            hint: String(localized: "Eine Schallplatte oben in der Menüleiste. Ein Klick öffnet die Suche im Regal: Treffer mit ihrem Fach, darunter das Regal im Kleinen.")) {
                    Toggle("Suche in der Menüleiste", isOn: $preferences.menuBarSearch).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                SettingsRow(title: String(localized: "Kürzel \(GlobalHotKey.quickSearch.title)"),
                            // macOS accepts a combination another app holds as well and
                            // gives it only to the app that registered it first; only
                            // a refusal can be shown here.
                            hint: quickSearch.hotKeyRefused
                                ? String(localized: "macOS hat \(GlobalHotKey.quickSearch.title) nicht angenommen, das Kürzel ist deshalb aus.")
                                : String(localized: "Öffnet die Suche von überall, auch wenn gerade eine andere App vorn ist. Nutzt eine andere App \(GlobalHotKey.quickSearch.title) ebenfalls, reagiert nur eine von beiden – dann hier ausschalten.")) {
                    Toggle("Kürzel", isOn: $preferences.quickSearchHotKey).labelsHidden().toggleStyle(.switch)
                }
                Divider()
                // Only Modern has a choice; Klassisch shows its paper. Without
                // the record and the shortcut there is no search to show.
                SettingsRow(title: String(localized: "Aussehen der Suche"),
                            hint: AppStyle.isAtelier
                                ? String(localized: "Im Design Klassisch erscheint die Suche auf Papier.")
                                : preferences.quickSearchLook.hint) {
                    GlassSegmentedPicker(selection: $preferences.quickSearchLook, options: QuickSearchLook.allCases) { Text($0.title) }
                        .accessibilityLabel(String(localized: "Aussehen der Suche"))
                }
                .disabled(AppStyle.isAtelier || searchOff)
                Divider()
                // Applies to the record and the shortcut alike; without both there is no search.
                SettingsRow(title: String(localized: "Position der Suche"), hint: preferences.quickSearchPosition.hint) {
                    GlassSegmentedPicker(selection: $preferences.quickSearchPosition, options: QuickSearchPosition.allCases) { Text($0.title) }
                        .accessibilityLabel(String(localized: "Position der Suche"))
                }
                .disabled(searchOff)
                Divider()
                SettingsRow(title: String(localized: "Klick auf einen Treffer"), hint: preferences.quickSearchClick.hint) {
                    GlassSegmentedPicker(selection: $preferences.quickSearchClick, options: QuickSearchClick.allCases) { Text($0.title) }
                        .accessibilityLabel(String(localized: "Klick auf einen Treffer"))
                }
                .disabled(searchOff)
            }
            SettingsCard(title: String(localized: "Updates")) {
                SettingsRow(title: String(localized: "Automatisch nach Updates suchen"),
                            hint: DemoMode.isActive
                                ? String(localized: "In der Demo sucht Plattenregal nicht von selbst nach Updates.")
                                : preferences.updateCheckInterval.hint) {
                    // The demo never checks on its own, whatever the setting says.
                    GlassSegmentedPicker(selection: DemoMode.isActive ? .constant(.never) : $preferences.updateCheckInterval,
                                         options: UpdateCheckInterval.allCases) { Text($0.title) }
                        .accessibilityLabel(String(localized: "Automatisch nach Updates suchen"))
                }
                .disabled(DemoMode.isActive)
                Divider()
                SettingsRow(title: String(localized: "Version \(updates.currentVersion.description)"), hint: updateHint) {
                    SecondaryButton(title: String(localized: "Jetzt prüfen")) { UpdateCommand.check(openWindow) }
                        .disabled(updates.state == .checking)
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
        // Can also be changed under Systemeinstellungen → Anmeldeobjekte.
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginItem.refresh() }
    }

    /// What the last check said, and when.
    /// Neither the record nor the shortcut: there is no search, its choices rest.
    private var searchOff: Bool { !preferences.menuBarSearch && !preferences.quickSearchHotKey }

    private var updateHint: String {
        if case .available(let release) = updates.state {
            return String(localized: "Version \(release.version.description) ist da.")
        }
        guard let lastCheck = updates.lastCheck else { return String(localized: "Noch nicht geprüft.") }
        return String(localized: "Zuletzt geprüft: \(lastCheck.formatted(.relative(presentation: .named)))")
    }

    private var loginHint: String {
        if loginItem.failed { return String(localized: "macOS hat die Änderung nicht angenommen. Unter Systemeinstellungen → Allgemein → Anmeldeobjekte lässt sich Plattenregal auch von Hand eintragen.") }
        return AppLifecycle.shared.keepsRunning
            ? String(localized: "Startet Plattenregal beim Anmelden am Mac, ohne Fenster: nur mit der Schallplatte in der Menüleiste.")
            : String(localized: "Startet Plattenregal beim Anmelden am Mac.")
    }

    private var backgroundHint: String {
        if DemoMode.isActive { return String(localized: "In der Demo beendet ⌘Q Plattenregal wie gewohnt.") }
        if !AppPreferences.shared.menuBarSearch { return String(localized: "Geht nur mit der Schallplatte in der Menüleiste – über sie lässt sich Plattenregal dann ganz beenden.") }
        return String(localized: "⌘Q und das Schließen des letzten Fensters lassen Plattenregal ohne Symbol im Dock weiterlaufen; Schallplatte und Kürzel bleiben. Ganz beenden: Rechtsklick auf die Schallplatte oder ⌥⌘Q.")
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
