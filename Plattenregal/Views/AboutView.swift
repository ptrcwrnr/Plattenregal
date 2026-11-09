import SwiftUI
import AppKit

/// "Über Plattenregal": a small card with icon, name, version and author
/// instead of the system panel, whose empty credits area made it tall.
/// Below them what changed, newest version first (`Changelog`).
struct AboutView: View {
    static let windowID = "about"
    static let author = "Patrice Werner"

    /// "Version 1.0 (092026)" from the bundle, as in the protocol header.
    static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return String(localized: "Version \(version) (\(build))")
    }

    var body: some View {
        VStack(spacing: AppStyle.itemSpacing) {
            CurrentAppIcon(size: AppStyle.aboutIconSize)
            Text("Plattenregal").font(AppStyle.dialogTitle)
            Text(Self.versionLine)
                .font(.callout).foregroundStyle(.secondary)
                .monospacedDigit().textSelection(.enabled)
            Text("© 2026 \(Self.author)")
                .font(.caption).foregroundStyle(.tertiary)
                .padding(.top, AppStyle.tightSpacing)
            if !Changelog.entries.isEmpty {
                Divider().padding(.vertical, AppStyle.itemSpacing)
                changes
            }
        }
        .padding(.horizontal, AppStyle.pagePadding)
        .padding(.top, AppStyle.pagePadding + AppStyle.itemSpacing)
        .padding(.bottom, AppStyle.pagePadding)
        .frame(width: Changelog.entries.isEmpty ? 260 : 340)
    }

    /// Newest version first, without a heading: the version lines say what
    /// it is. As tall as its content up to a limit, then it scrolls – like
    /// the tracklist in a cover's popover.
    private var changes: some View {
        // The same steps as the update window: point to point `itemSpacing`,
        // version line to its points `tightSpacing`, version to version
        // `sectionSpacing`.
        ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                ForEach(Changelog.entries) { entry in
                    VStack(alignment: .leading, spacing: AppStyle.tightSpacing) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Version \(entry.version)").font(AppStyle.strongCallout).monospacedDigit()
                            Spacer(minLength: AppStyle.itemSpacing)
                            Text(entry.date, format: .dateTime.day().month(.abbreviated).year())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: AppStyle.itemSpacing) {
                            ForEach(entry.changes, id: \.self) { change in ChangeItem(change) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: AppStyle.changesMaxHeight)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

/// What changed in each version since 1.0.0, newest first, as shown in
/// "Über Plattenregal". A new version gets its entry at the top – in plain
/// words for people using the app, not the technical changelog
/// (AENDERUNGEN.md). Its version must match `MARKETING_VERSION`.
enum Changelog {
    struct Entry: Identifiable {
        let version: String
        let date: Date
        let changes: [String]
        var id: String { version }
    }

    /// Style of every entry (see README, „Was ist neu“): one short sentence
    /// „Bereich: was sich ändert.“ with a fixed area (Design, Listen, Tags,
    /// Einsortieren, Einstellungen, Updates, Plattenkarte, Fenster, Leistung,
    /// Netzwerk, Korrekturen), at most eight per version, new things first and
    /// „Korrekturen“ last; no „jetzt“, no „vorher“, nothing technical.
    static var entries: [Entry] {
        [
            Entry(version: "1.0.4", date: day(2026, 11, 9), changes: [
                String(localized: "Design: neues Design „Vinyl“ in kühlem Graphit, immer dunkel; dazu 18 App-Symbole fürs Dock (experimentell)."),
                String(localized: "Listen: füllen das Fenster, leuchten unter der Maus auf, Spalten lassen sich verschieben und ausblenden; Tags als farbige Punkte."),
                String(localized: "Einsortieren: Vorschlag im gezeigten Regal, „Sortierung prüfen“ mit übersichtlicher Leiste."),
                String(localized: "Einstellungen: aufgeräumt, mit eigenen Namen für die Rubriken, Intervall für Updates und Klick in der Menüleisten-Suche."),
                String(localized: "Fenster: der runde Knopf unten rechts auf jeder Seite, seine Aktionen klappen nach oben auf."),
                String(localized: "Leistung: flüssigere Statistik und Designwechsel, ruhiges Anlegen des Fensters an den Bildschirmrand."),
                String(localized: "Netzwerk: keine eingehenden Verbindungen mehr, Apple TV vorerst ausgeblendet."),
                String(localized: "Korrekturen: Fenster in Klassisch wieder verschiebbar, Ring beim Aktualisieren, Verschieben der Statistik-Bereiche, Menü in der Menüleiste."),
            ]),
            Entry(version: "1.0.3", date: day(2026, 11, 4), changes: [
                String(localized: "Fenster: der rote Knopf beendet Plattenregal wie ⌘Q oder schickt es in den Hintergrund."),
                String(localized: "Listen: „Zufällig“ mischt bei jedem Öffnen neu."),
                String(localized: "Einstellungen: erklären, wie man Statistik-Bereiche umsortiert."),
            ]),
            Entry(version: "1.0.2", date: day(2026, 11, 3), changes: [
                String(localized: "Updates: Plattenregal sucht selbst nach neuen Versionen und zeigt, was neu ist, mit Download."),
                String(localized: "Plattenkarte: Label, Katalognummer und Format aufgeräumt, auch im Zufallsfund."),
                String(localized: "Korrekturen: schnelle Klicks auf Cover, Schließen der Einstellungen beim Klick ins Hauptfenster."),
            ]),
            Entry(version: "1.0.1", date: day(2026, 11, 2), changes: [
                String(localized: "Plattenkarte: aufgeräumt, der Standort ist auch im Dunkeln gut lesbar."),
                String(localized: "Korrekturen: „Im Regal anzeigen“ scrollt ruhig zur Platte."),
            ]),
        ]
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
    }
}

/// Replaces "Über Plattenregal" in the app menu so it opens `AboutView`.
struct AboutCommand: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Über Plattenregal") { openWindow(id: AboutView.windowID) }
    }
}

/// The icon the Dock shows now – the chosen one or the standard – and it
/// follows a change at once, also in a window open meanwhile:
/// `NSApp.applicationIconImage` alone is nothing SwiftUI watches.
struct CurrentAppIcon: View {
    let size: CGFloat
    @State private var preferences = AppPreferences.shared
    var body: some View {
        Image(nsImage: preferences.dockIcon.assetName.flatMap { NSImage(named: $0) } ?? NSApp.applicationIconImage)
            .resizable()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
