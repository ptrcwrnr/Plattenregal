# Plattenregal

Native macOS-App für eine private Vinylsammlung: Die Platten kommen aus der eigenen **Discogs-Collection**, Plattenregal weiß zusätzlich, **wo jede Platte im Regal steht**. Swift 6, SwiftUI, SwiftData und Swift Charts, ohne externe Abhängigkeiten. Deployment Target macOS 27.0.

## In Xcode starten

1. `Plattenregal.xcodeproj` öffnen.
2. Scheme **Plattenregal**, Ziel **My Mac** wählen.
3. Mit **⌘R** starten, mit **⌘U** die Tests ausführen.

Das Projekt ist für lokales Ad-hoc-Signing eingerichtet und braucht kein bezahltes Entwicklerkonto. Für Weitergabe oder Notarisierung unter „Signing & Capabilities“ ein eigenes Team eintragen. Die Bundle-ID `de.private.Plattenregal` beibehalten – an ihr hängen Sandbox-Ordner, Datenbank und Schlüsselbund-Eintrag.

## Was die App kann

- **Collection und Wantlist aus Discogs.** Es gibt keine manuell angelegten Platten: Alles kommt aus dem Discogs-Konto. Abgeglichen wird auf Wunsch: die Collection auf ihrer Seite (nach unten ziehen oder ⌘R) oder in den Einstellungen, die Wantlist in ihrer eigenen Ansicht. Danach werden die Tracklisten im Hintergrund nachgeladen; ein unterbrochener Download läuft beim nächsten Start weiter.
- **Regale und Fächer.** Beliebig viele Regale (IKEA-KALLAX-Größen oder eigene, 1–6 Spalten und Reihen), jedes Fach zeigt, wie viele Platten darin stehen. Platten einsortieren, verschieben, herausnehmen, Fächer alphabetisch sortieren, Fächer sperren (z. B. für Deko) und Platten als „Nicht im Regal“ markieren. Fächer heißen nach Buchstabenbereich („A – Be“) oder Nummer.
- **„Nicht auffindbar“ beim Einsortieren.** Nur auf der Regalseite: Eine Platte, die gerade nicht zu finden ist, lässt sich zurückstellen (Pause-Knopf in „Platte hinzufügen“, Rechtsklick in der Fach-Tabelle) und später als „Wieder gefunden“ markieren. Eine rote Übersicht neben der Suche listet alle markierten Platten; im Streifen der Plattenrücken erscheinen sie als roter Umriss. Einsortieren von Hand gilt als gefunden. Collection, Statistik und Export bleiben davon unberührt.
- **Eigene Angaben pro Exemplar:** Zustand, Kaufpreis und -datum. Discogs überschreibt diese nie.
- **Suche und Sortierung** über Interpret, Titel, Label, Katalognummer, Genre, Style und mehr; Raster oder Liste mit einstellbarer Covergröße.
- **Statistik** mit Verteilungen und dem Verlauf des Sammlungswerts (Details in [STATISTIK.md](STATISTIK.md)).
- **Sicherung** der Regal-Belegung, **Export** als CSV oder PDF, **Protokoll** für die Fehlersuche – siehe unten.
- **Demo** mit einer Beispielsammlung zum Ausprobieren und Vorführen – siehe unten.

## Discogs einrichten

Unter **Einstellungen → Discogs** einen persönlichen Token eintragen und die Verbindung testen. Den Token gibt es unter https://www.discogs.com/settings/developers. Er liegt ausschließlich im macOS-Schlüsselbund, nie in Quelldateien, Einstellungen oder im Protokoll; lokal gespeichert wird nur ein SHA-256-Fingerabdruck, um Daten dem richtigen Konto zuzuordnen.

Die App liest nur aus Discogs und ändert dort nichts. Discogs erlaubt mit Token 60 Anfragen pro Minute; Plattenregal taktet seine Anfragen, beachtet `Retry-After` und wartet bei einer Bremse von selbst. Der Abgleich speichert erst, wenn alle Seiten vollständig geladen sind – in einem eigenen Hintergrund-Kontext und einem einzigen Speichervorgang. Abbruch, unvollständige Daten oder ein Tokenwechsel mittendrin verwerfen den Abgleich, statt halbe Daten zu speichern. Fach, Position und eigene Angaben schreibt der Abgleich nie.

This application uses Discogs’ API but is not affiliated with, sponsored or endorsed by Discogs. ‘Discogs’ is a trademark of Zink Media, LLC.

## Einstellungen

| Tab | Inhalt |
|---|---|
| Allgemein | Startseite des Hauptfensters, Demo starten/beenden |
| Darstellung | Hell/Dunkel, Akzentfarbe, Raster oder Liste, Covergröße, Reihenfolge der Statistik |
| Regal | Regale anlegen, Größe ändern, umbenennen, (de)aktivieren, löschen; Fächer sperren; Beschriftung |
| Discogs | Token, Verbindungstest, Synchronisierung |
| Export | CSV/PDF von Collection oder Wantlist, automatischer Export in einen Ordner |
| Sicherung | Belegung sichern und wiederherstellen, automatische Sicherung, Aufbewahrung, Speicherort |
| Daten | Speicherplatz, Cover-Cache, Protokoll, Discogs-Anfragen, Zurücksetzen |

## Daten, Sicherung und Export

Alle Daten liegen in der App-Sandbox unter

```text
~/Library/Containers/de.private.Plattenregal/Data/Library/Application Support/Plattenregal/
```

| Ordner/Datei | Inhalt |
|---|---|
| `Collection.store` (+ `-wal`, `-shm`) | Datenbank (Schema V13): Platten, Standorte, „Nicht auffindbar“, Wantlist, Statistik-Verlauf |
| `Covers/` | Cover-Cache; wird bei Bedarf neu von Discogs geladen |
| `Sicherungen/` | Automatische Sicherungen der Belegung, falls kein eigener Ordner gewählt ist |
| `Logs/Plattenregal.log` | Protokoll (dazu `Plattenregal.old.log` ab 2 MB) |

Die Datenbank wird beim Start nur geöffnet, nie neu angelegt oder automatisch geleert – auch nicht nach einem Fehler; dann zeigt die App eine Fehlerseite mit Hinweis auf das Protokoll.

**Sicherung.** Die Platten selbst kommen jederzeit wieder aus Discogs – wo sie stehen, gibt es nur lokal. Die Sicherung hält genau das fest: Regale, Fach und Position jedes Exemplars, gesperrte Fächer und „Nicht im Regal“, als JSON. „Nicht auffindbar“ gehört nicht dazu: Es beschreibt die Suche im Moment, nicht die Belegung, und bleibt beim Wiederherstellen stehen (außer bei Platten, die laut Sicherung „Nicht im Regal“ sind). Automatisch einige Sekunden nach jeder Regal-Änderung und beim Beenden (Standard: die letzten 10 Stände plus der letzte Stand jedes Tages der vergangenen 14 Tage), auf Wunsch in einem eigenen Ordner, z. B. in iCloud Drive. Ein leeres Regal wird nie automatisch gesichert, damit es nach einem Datenverlust keine guten Stände verdrängt. Wiederhergestellt wird über die Discogs-Exemplar-ID; vorher zeigt eine Vorschau, was passiert, und der aktuelle Stand wird gesichert.

**Export.** CSV (Spalten wählbar, Semikolon oder Komma, UTF-8 mit BOM für Excel, Formel-Schutz) oder druckfertige PDF-Liste, in Regal- oder alphabetischer Reihenfolge. Der automatische Export schreibt täglich, wöchentlich oder monatlich in einen Ordner und ersetzt dort immer dieselbe Datei – außer die Liste wäre leer.

**Zurücksetzen** (Tab „Daten“): Standorte (samt „Nicht im Regal“ und „Nicht auffindbar“), Einstellungen oder alles. Vor jedem Zurücksetzen, das die Belegung betrifft, wird gesichert; Sicherungen samt Speicherort und Aufbewahrung bleiben immer erhalten.

## Demo

**Plattenregal → Demo starten …** (oder **Einstellungen → Allgemein**) startet die App neu mit einer Beispielsammlung: rund 50 bekannte Alben mit gezeichneten Covern, zwei Regale („Wohnzimmer“, „Flur“ mit gesperrtem Deko-Fach), einige Platten ohne Fach, eine als „Nicht auffindbar“ markierte Platte, Wantlist und 18 Monate Wertverlauf. Alles lässt sich ausprobieren – einsortieren, verschieben, Regale anlegen, Einstellungen ändern, exportieren, zurücksetzen. Ein Banner auf jeder Seite zeigt die Demo an; **Demo beenden** startet wieder mit der eigenen Sammlung, **Demo neu starten** holt die Beispielsammlung im Ausgangszustand zurück (etwa nach „Alles zurücksetzen“).

Die Demo ist vollständig von den echten Daten getrennt: Die Sammlung liegt nur im Arbeitsspeicher, Einstellungen in einer eigenen Domäne (`de.private.Plattenregal.demo`, bei jedem Start leer), Sicherungen und Cover in einem temporären Ordner. Discogs ist ausgeschaltet, der Schlüsselbund wird nicht gelesen. Gemeinsam ist nur das Protokoll; jede Zeile aus der Demo trägt dort „Demo ·“ vor ihrer Kategorie. Außerdem in der Demo: keine Discogs-Links und -Aktualisierungen (die Beispiel-IDs gehören bei Discogs zu fremden Releases), keine Tracklisten, keine automatische Sicherung; Speicherort und Aufbewahrung der Sicherungen sind gesperrt, damit die Demo nie echte Sicherungen aufräumt. Dateien, die die Demo vorschlägt oder schreibt, tragen „(Demo)“ im Namen – ein Export in denselben Ordner ersetzt so nie die echte Datei.

Läuft Plattenregal noch ein zweites Mal, wird der Wechsel abgelehnt, damit nie zwei Instanzen auf derselben Sammlung arbeiten. Der Neustart kann aus der Sandbox keine Startargumente übergeben; die alte Instanz hinterlegt deshalb eine Minute gültige Anfrage in den Einstellungen, die die neue beim Start übernimmt und löscht. Aus Xcode oder dem Terminal startet `--demo` die Demo direkt.

## Fehlermeldungen und Protokoll

Meldungen sind kurz, auf Deutsch und sagen, was passiert ist und was zu tun ist – ohne englische Systemtexte. Die technischen Details landen im Protokoll: Jede angezeigte Fehlermeldung wird dort mit Ursache und Code-Stelle festgehalten, außerdem Starts, Abgleiche, Regal-Änderungen (auch „Nicht auffindbar“ und „Wieder gefunden“ mit Plattenname), Sicherungen, Exporte und Zurücksetzen. Der Discogs-Token steht nie darin.

Beispiele: Schlägt das Speichern einer Markierung fehl, heißt es „„Nicht auffindbar“ konnte nicht gespeichert werden – die Platte ist unverändert. Bitte versuche es noch einmal …“; ein Einsortieren in ein gesperrtes Fach erklärt, wo sich die Sperre aufheben lässt. Werden im Einstellungsfenster Regale umgebaut, während „Platte hinzufügen“ offen ist, schließt es sich, statt in ein gelöschtes Fach zu schreiben – auch das steht im Protokoll.

Das Protokoll lässt sich unter **Einstellungen → Daten → Diagnose** im Finder zeigen oder als Datei sichern.

**Abstürze.** Bei einem Absturz schreibt die App einen Block `==== ABSTURZ … ====` mit Signal, Uhrzeit, Version und Aufrufliste ins Protokoll (auch bei einem Stack-Überlauf). Beim nächsten Start steht darunter in Klartext, welcher Absturz es war und wann. Endete eine Sitzung ohne Absturz-Eintrag unerwartet (in Xcode gestoppt, zwangsweise beendet), wird auch das vermerkt. Die Startzeile enthält die Ladeadresse, damit sich die Adressen der Aufrufliste auflösen lassen:

```sh
atos -o Plattenregal.app/Contents/MacOS/Plattenregal -l <Ladeadresse> <Adresse> …
```

## Wichtige Dateien

| Bereich | Datei | Aufgabe |
|---|---|---|
| Start | `PlattenregalApp.swift` | Szenen, Öffnen der Datenbank, Fehlerseite, Protokollstart |
| Modelle | `Models/LibraryModels.swift`, `Models/LibrarySchemas.swift` | Versioniertes SwiftData-Schema und Migrationen |
| Speicherung | `Storage/LibraryStorage.swift`, `Storage/KeychainStore.swift` | Datenbank-Container, Fächer, Token im Schlüsselbund |
| Regal | `Services/PositionService.swift`, `Services/CabinetService.swift`, `Views/KallaxView.swift` | Positionen, Regale, „Nicht im Regal“ und „Nicht auffindbar“, jede Änderung als eine Transaktion; Regalseite |
| Sicherung | `Services/ShelfBackupService.swift` | Sichern, Wiederherstellen, automatische Sicherung |
| Export | `Services/CollectionExportService.swift`, `Services/ScheduledExportService.swift` | CSV/PDF, automatischer Export |
| Zurücksetzen | `Services/ResetService.swift` | Standorte, Einstellungen, alles |
| Discogs | `Discogs/DiscogsAPIClient.swift`, `Discogs/DiscogsSyncService.swift` | API, Taktung, Abgleich, Tracklisten |
| Statistik | `Statistics/` | Auswertungen und Wertverlauf |
| Fehler & Protokoll | `Utilities/ErrorMessages.swift`, `Utilities/AppLog.swift` | Verständliche Meldungen, Protokoll, Absturz-Handler |
| Oberfläche | `Views/`, `Utilities/AppAppearance.swift` | Fenster, Regalansicht, Einstellungen, gemeinsames Design |
| Tests | `PlattenregalTests/` | Regal, Sicherung, Export, Discogs-Abgleich, Statistik, Einstellungen |

## Entwicklung und Prüfung

```sh
xcodebuild -project Plattenregal.xcodeproj -scheme Plattenregal -destination 'platform=macOS' build
xcodebuild -project Plattenregal.xcodeproj -scheme Plattenregal -destination 'platform=macOS' test
```

Die Tests laufen mit einer Datenbank im Arbeitsspeicher, schreiben nicht ins echte Protokoll und brauchen weder Internet noch Token: Discogs-Antworten kommen aus lokalen `URLProtocol`-Attrappen.

Für einen Demo-Lauf aus Xcode unter **Edit Scheme → Run → Arguments** `--demo` ergänzen; `--statistics-demo` öffnet die Demo direkt auf der Statistik. `--settings-tab=Daten` zeigt im Debug-Build einen Einstellungs-Tab im Hauptfenster – zusammen mit `--demo`, sonst mit der echten Sammlung.

Änderungen im Detail: [AENDERUNGEN.md](AENDERUNGEN.md). Build- und Teststände: [VALIDIERUNG.md](VALIDIERUNG.md).
