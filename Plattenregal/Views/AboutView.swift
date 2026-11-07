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
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: AppStyle.aboutIconSize, height: AppStyle.aboutIconSize)
                .accessibilityHidden(true)
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

    static var entries: [Entry] {
        [
            Entry(version: "1.0.4", date: day(2026, 11, 6), changes: [
                String(localized: "Die Rubriken oben im Fenster lassen sich umbenennen: Einstellungen → Darstellung → Rubriken, höchstens zwölf Zeichen je Name."),
                String(localized: "Was ein Klick auf einen Treffer in der Suche in der Menüleiste tut, wählst du jetzt unter Einstellungen → Allgemein: markieren wie bisher, die Platte in der App zeigen oder sie auf Discogs öffnen."),
                String(localized: "Wie oft Plattenregal nach Updates sucht, wählst du jetzt unter Einstellungen → Allgemein: wöchentlich, monatlich oder nie. Hattest du die tägliche Suche eingeschaltet, sucht Plattenregal jetzt wöchentlich."),
                String(localized: "Im Menü der Schallplatte in der Menüleiste heißt es jetzt „Plattenregal beenden“ statt „Plattenregal ganz beenden“, und „Einstellungen …“ ist dort weggefallen – die Einstellungen öffnest du im Hauptfenster mit ⌘,."),
                String(localized: "Plattenregal nimmt keine Verbindungen aus dem Netzwerk mehr an; die Einstellungen für Apple TV sind dafür vorerst ausgeblendet. Discogs und die Suche nach Updates funktionieren wie bisher."),
                String(localized: "Beim Herunterziehen zum Aktualisieren erscheint der Ring jetzt unterhalb der Toolbar statt halb dahinter."),
                String(localized: "Einen Bereich der Statistik auf den direkt darunter liegenden zu ziehen, verschiebt ihn jetzt auch – vorher blieb dann alles, wie es war."),
                String(localized: "Beim Einsortieren schlägt Plattenregal jetzt einen Platz im gerade gezeigten Regal vor – im Fach, in das die Platte alphabetisch am besten passt. Ein Fach mit Platten quer durchs Alphabet zieht nicht mehr jede neue Platte an. Wechselst du das Regal, zieht die Karte mit."),
                String(localized: "„Sortierung prüfen“ ist aufgeräumt: Eine Leiste zeigt das Fach von links nach rechts mit den Platten, die umziehen, jeder Schritt sagt „Platz 64 herausnehmen → hinter …“, und die Reihenfolge wählst du oben im Menü. Steht alles richtig, genügt ein Haken."),
                String(localized: "Neues Design „Vinyl“: matte Flächen wie Klassisch, in kühlem Graphit mit hellblauen Akzenten und immer dunkel. Einstellungen → Darstellung → Design."),
                String(localized: "Die Statistik scrollt jetzt so flüssig wie die Collection: Kacheln und Diagramme, die beim Scrollen unter dem Mauszeiger durchziehen, leuchten erst auf, wenn die Seite steht."),
                String(localized: "In „Sortierung prüfen“ fällt die nächste Platte leichter ins Auge: In der Leiste leuchten ihr Platz und danach ihr Ziel kurz nacheinander auf."),
                String(localized: "Legst du das Fenster an einen Bildschirmrand an oder zoomst es, gleitet es jetzt flüssig, statt zu ruckeln."),
                String(localized: "Die Einstellungen sind aufgeräumter: Synchronisieren und „Alle verkauft“ stehen als Zeilen mit Erklärung, die automatische Sicherung sagt, wie viele Stände höchstens bleiben, Knöpfe tragen keine Auslassungspunkte mehr, und das Fenster schließt auch mit dem roten Knopf."),
            ]),
            Entry(version: "1.0.3", date: day(2026, 11, 4), changes: [
                String(localized: "Die Einstellungen sagen jetzt genau, wie man die Bereiche der Statistik umsortiert: einen Bereich am Titel greifen und auf einen anderen ziehen."),
                String(localized: "Der rote Knopf am Fenster beendet Plattenregal jetzt wie ⌘Q, statt die App ohne Fenster im Dock zu lassen – oder schickt sie in den Hintergrund, wenn das eingeschaltet ist."),
                String(localized: "„Zufällig“ in Collection und Wantlist mischt jedes Mal neu, wenn du Plattenregal öffnest – auch aus dem Hintergrund."),
            ]),
            Entry(version: "1.0.2", date: day(2026, 11, 3), changes: [
                String(localized: "Plattenregal sucht einmal am Tag selbst nach einer neuen Version und zeigt dann, was neu ist – mit Download und kurzer Anleitung."),
                String(localized: "„Nach Updates suchen“ im Menü Plattenregal prüft sofort; einschalten, ausschalten und von Hand prüfen unter Einstellungen → Allgemein."),
                String(localized: "Klappt die Prüfung nicht, sagt Plattenregal, woran es liegt, etwa ohne Internet oder wenn GitHub gerade nicht antwortet."),
                String(localized: "Label, Katalognummer und Format stehen auf der Plattenkarte und im Zufallsfund aufgeräumt: jeder Wert nur einmal, ohne das „none“ von Discogs und ohne „1 ·“ vor dem Format."),
                String(localized: "Schnelle Klicks auf ein Cover gehen nicht mehr verloren: Jeder Klick öffnet oder schließt das Popover – in Collection, Wantlist und Regal."),
                String(localized: "Die Einstellungen schließen sich, wenn du daneben ins Hauptfenster klickst, statt dahinter zu verschwinden."),
            ]),
            Entry(version: "1.0.1", date: day(2026, 11, 2), changes: [
                String(localized: "Die Plattenkarte ist aufgeräumt: die Angaben als ruhige Liste, die Styles ohne Plaketten und „Auf Discogs öffnen“ oben rechts."),
                String(localized: "Der Standort auf der Plattenkarte ist im dunklen Design gut lesbar und hat keinen Blaustich mehr."),
                String(localized: "„Im Regal anzeigen“ kommt ruhig bei der Platte an, statt hastig durch das Fach zu scrollen."),
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
