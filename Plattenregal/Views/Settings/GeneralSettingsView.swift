import SwiftUI

// MARK: - Allgemein

struct GeneralSettingsView: View {
    @State private var preferences = AppPreferences.shared

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
