# Plattenregal

Native macOS-App für eine private Vinylsammlung: Die Platten kommen aus der eigenen **Discogs-Collection**, Plattenregal weiß zusätzlich, **wo jede Platte im Regal steht**. Swift 6, SwiftUI, SwiftData und Swift Charts, ohne externe Abhängigkeiten. Deployment Target macOS 27.0.

## In Xcode starten

1. `Plattenregal.xcodeproj` öffnen.
2. Scheme **Plattenregal**, Ziel **My Mac** wählen.
3. Mit **⌘R** starten, mit **⌘U** die Tests ausführen.

Das Projekt ist für lokales Ad-hoc-Signing eingerichtet und braucht kein bezahltes Entwicklerkonto. Für Weitergabe oder Notarisierung unter „Signing & Capabilities“ ein eigenes Team eintragen. Die Bundle-ID `de.private.Plattenregal` beibehalten – an ihr hängen Sandbox-Ordner, Datenbank und Schlüsselbund-Eintrag.

## Was die App kann

- **Vier Rubriken** oben in der Toolbar: Collection · Wantlist · Regal · Statistik (⌘1–⌘4). Rechts daneben Raster/Liste (nur Collection und Wantlist); eine Lupe gibt es nicht, **⌘F** blendet die Suche der aktiven Seite mittig unter den Rubriken ein. Die Toolbar hat kein Rechtsklick-Menü („Nur Text“ usw.). Einstellungen über das App-Menü oder ⌘,. Es gibt genau ein Hauptfenster (kein ⌘N): Wird es geschlossen, läuft die App weiter (automatischer Export, Tracklisten, Sicherungen), ein Klick aufs Dock-Symbol holt es zurück. **Über Plattenregal** im App-Menü zeigt eine kleine Karte mit Symbol, Version samt Build-Nummer und Autor (Patrice Werner). Die Oberfläche ist durchgehend Liquid Glass: Umschalter, Knöpfe, Menüs, Suchleisten und Karten aus Glas, dahinter ein dezenter Hauch der Cover und die Ambient-Farbe. Im inaktiven Fenster flacht macOS das Glas ab – das ist Systemverhalten und bleibt so.
- **Fenster über der Seite.** Plattenliste und Plattendetails der Statistik, „Platte hinzufügen“ und „Sortierung prüfen“ öffnen als Glasfenster über der Seite, oben verankert und ohne Ampel oder Abdunklung (ein weicher Schatten setzt sie ab). Geschlossen wird mit einem Klick daneben oder **Esc** (`appPanel`).
- **Collection und Wantlist aus Discogs.** Es gibt keine manuell angelegten Platten: Alles kommt aus dem Discogs-Konto. Abgeglichen wird auf Wunsch: die Collection auf ihrer Seite (nach unten ziehen oder ⌘R) oder in den Einstellungen, die Wantlist in ihrer eigenen Ansicht. Danach werden die Tracklisten im Hintergrund nachgeladen; ein unterbrochener Download läuft beim nächsten Start weiter. Ohne Token führt eine leere Collection oder Wantlist mit „Token eintragen“ direkt ins Token-Feld der Einstellungen.
- **Platten ansehen.** Ein Klick auf ein Cover (in der Liste ein Doppelklick) zeigt ein kleines Popover mit Cover, Angaben und Tracklist – in Collection und Wantlist. Rechtsklick öffnet ein App-eigenes Menü: in der Collection „Im Regal anzeigen“ bzw. „Platz im Regal finden“, „Auf Discogs öffnen“, „Discogs-Daten aktualisieren“ und „Nicht im Regal“ bzw. „Wieder einsortieren“; in der Wantlist „Auf Discogs öffnen“. Mehrfachauswahl und die große Detailansicht gibt es in Collection und Wantlist nicht mehr.
- **Reihenfolge** von Collection und Wantlist, je getrennt: alphabetisch (mit Alphabet am Rand), zufällig (bei jedem Start und beim Umschalten neu gemischt, sonst stabil) oder neueste zuerst (nach Discogs-Hinzufügedatum).
- **Regale und Fächer.** Beliebig viele Regale (IKEA-KALLAX-Größen oder eigene, 1–6 Spalten und Reihen), oben als Reiter mit feinen Trennlinien; jedes Fach zeigt, wie viele Platten darin stehen. Platten einsortieren, verschieben, herausnehmen, Sortierung prüfen, Fächer sperren (z. B. für Deko; per Rechtsklick auf das Fach, gesperrte Fächer bekommen dort auch einen Namen) und Platten als „Nicht im Regal“ markieren. Fächer heißen nach Buchstabenbereich („A – Be“) oder Nummer. Das Regal ist ein Glaskörper mit Mulden: Das Fach unter dem Zeiger hellt sich auf, das gewählte hebt sich heraus und blendet dabei im eigenen Fach ein (es gleitet nicht übers Regal). Fach-Tabelle und Rückenleiste stehen darunter (Cover erscheint beim Überfahren eines Rückens). Sind Platten da, aber keine einsortiert, bietet die Seite „Belegung wiederherstellen …“ an.
- **„Platte hinzufügen“** über das kleine Glas-„+“ oben rechts im Fach – es erscheint beim Überfahren und im gewählten Fach an der Stelle der Plattenanzahl und blendet beim Fachwechsel ein und aus – oder per Rechtsklick. Die Liste zeigt zuerst die Platten, die alphabetisch in das Fach passen, dann die übrigen (mit „gehört in …“ und einem Pfeil, der ihren Platz dort zeigt). Die nächste passende Platte trägt „Als Nächstes“. „+“ setzt eine Platte an ihre alphabetische Stelle; die Zielkarte zeigt, zwischen welche beiden Platten sie kommt.
- **„Vermisst“ beim Einsortieren.** Nur auf der Regalseite: Eine Platte, die gerade nicht zu finden ist, lässt sich zurückstellen (Pause-Knopf in „Platte hinzufügen“, Rechtsklick in der Fach-Tabelle). Sie wandert dann animiert aus der Liste in die Spalte **Vermisst** rechts daneben – nach Fach gruppiert, mit Cover, „Zeigen“ und „Wieder gefunden“; wieder gefunden kehrt sie an ihre Stelle in der Liste zurück. Die Spalte gibt es nur, solange etwas vermisst wird, und sie lässt sich einklappen (dann steht oben „x vermisst ‹“). Im Streifen der Plattenrücken erscheinen vermisste Platten als roter Umriss. Einsortieren von Hand gilt als gefunden. Unter **Einstellungen → Regal → Einsortieren** lässt sich die Vermisst-Liste ganz abschalten; die Markierungen bleiben dabei gespeichert. Collection, Statistik und Export bleiben davon unberührt.
- **„Sortierung prüfen“** (Rechtsklick auf ein Fach) prüft die gespeicherte Reihenfolge des Fachs – immer zuerst nach Interpret, bei gleichem Interpreten wahlweise nach Titel, Jahr oder Label/Katalognummer. Stimmt etwas nicht, zeigt es die kleinstmögliche Zahl an Umstellungen als nummerierte Schritte („Platz 17 → hinter „Ian Van Dahl – Ace““, mit Cover von Platte und Nachbar). Jeder Schritt bezieht sich nur auf Platten, die dann schon richtig stehen; abgehakt wird per Klick. „Reihenfolge übernehmen“ speichert danach die neue Reihenfolge. Die App kennt nur die gespeicherte Reihenfolge, nicht das echte Regal.
- **Reihenfolge bei gleichem Interpreten** (Einstellungen → Regal → Einsortieren: Titel, Jahr oder Label) gilt für Platzsuche, „Platte hinzufügen“, „Sortierung prüfen“ und die alphabetische Reihenfolge der Collection. Der Interpret bleibt immer der erste Schlüssel, deshalb bleiben Fachnamen wie „He – La“ gültig.
- **Suche und Sortierung** über Interpret, Titel, Label, Katalognummer, Genre, Style und mehr; Raster oder Liste mit einstellbarer Covergröße.
- **Statistik** mit Verteilungen und dem Verlauf des Sammlungswerts (Details in [STATISTIK.md](STATISTIK.md)).
- **Sicherung** der Regal-Belegung, **Export** als CSV oder PDF, **Protokoll** für die Fehlersuche – siehe unten.
- **Demo** mit einer Beispielsammlung zum Ausprobieren und Vorführen – siehe unten.

## Discogs einrichten

Unter **Einstellungen → Discogs** einen persönlichen Token eintragen und die Verbindung testen. Den Token gibt es unter https://www.discogs.com/settings/developers. Er liegt ausschließlich im macOS-Schlüsselbund, nie in Quelldateien, Einstellungen oder im Protokoll; lokal gespeichert wird nur ein SHA-256-Fingerabdruck, um Daten dem richtigen Konto zuzuordnen.

Die App liest nur aus Discogs und ändert dort nichts. Discogs erlaubt mit Token 60 Anfragen pro Minute; Plattenregal taktet seine Anfragen, beachtet `Retry-After` und wartet bei einer Bremse von selbst. Der Abgleich speichert erst, wenn alle Seiten vollständig geladen sind – in einem eigenen Hintergrund-Kontext und einem einzigen Speichervorgang. Abbruch, unvollständige Daten oder ein Tokenwechsel mittendrin verwerfen den Abgleich, statt halbe Daten zu speichern. Fach und Position schreibt der Abgleich nie.

This application uses Discogs’ API but is not affiliated with, sponsored or endorsed by Discogs. ‘Discogs’ is a trademark of Zink Media, LLC.

## Einstellungen

Die Tabs stehen als Glas-Umschalter in der Toolbar des Einstellungsfensters.

| Tab | Inhalt |
|---|---|
| Allgemein | Startseite des Hauptfensters, Reihenfolge von Collection und Wantlist, Demo starten/beenden |
| Darstellung | Hell/Dunkel, Akzentfarbe, Raster oder Liste, Covergröße, Reihenfolge der Statistik |
| Regal | Regale anlegen, Größe ändern, umbenennen, (de)aktivieren, löschen; Fächer sperren und benennen (Klick aufs Fach öffnet dasselbe Menü wie im Regal); Einsortieren (Reihenfolge bei gleichem Interpreten, Vermisst-Liste an/aus); Beschriftung |
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
| `Collection.store` (+ `-wal`, `-shm`) | Datenbank (Schema V15): Platten, Standorte, „Vermisst“, Wantlist, Statistik-Verlauf |
| `Covers/` | Cover-Cache; wird bei Bedarf neu von Discogs geladen |
| `Sicherungen/` | Automatische Sicherungen der Belegung, falls kein eigener Ordner gewählt ist |
| `Logs/Plattenregal.log` | Protokoll (dazu `Plattenregal.old.log` ab 2 MB, auch während einer Sitzung) |
| `.Plattenregal.lock` | Sperrdatei: nur die Instanz, die sie hält, öffnet die Sammlung; das System gibt sie beim Beenden frei, auch nach einem Absturz |

Die Datenbank wird beim Start nur geöffnet, nie neu angelegt oder automatisch geleert – auch nicht nach einem Fehler; dann zeigt die App eine Fehlerseite mit Hinweis auf das Protokoll. Nur eine Instanz öffnet die Sammlung (Sperrdatei `.Plattenregal.lock` im selben Ordner): Läuft Plattenregal schon, etwa aus Xcode, zeigt eine zweite Instanz einen Hinweis statt die Datenbank zu öffnen.

**Sicherung.** Die Platten selbst kommen jederzeit wieder aus Discogs – wo sie stehen, gibt es nur lokal. Die Sicherung hält genau das fest: Regale, Fach und Position jedes Exemplars, gesperrte Fächer und „Nicht im Regal“, als JSON. „Vermisst“ gehört nicht dazu: Es beschreibt die Suche im Moment, nicht die Belegung, und bleibt beim Wiederherstellen stehen (außer bei Platten, die laut Sicherung „Nicht im Regal“ sind). Automatisch einige Sekunden nach jeder Regal-Änderung und beim Beenden (Standard: die letzten 10 Stände plus der letzte Stand jedes Tages der vergangenen 14 Tage), auf Wunsch in einem eigenen Ordner, z. B. in iCloud Drive. Ein leeres Regal wird nie automatisch gesichert, damit es nach einem Datenverlust keine guten Stände verdrängt. Wiederhergestellt wird über die Discogs-Exemplar-ID; vorher zeigt eine Vorschau, was passiert, und der aktuelle Stand wird gesichert.

**Export.** CSV (Spalten wählbar, Semikolon oder Komma, UTF-8 mit BOM für Excel, Formel-Schutz) oder druckfertige PDF-Liste, in Regal- oder alphabetischer Reihenfolge. Der automatische Export schreibt täglich, wöchentlich oder monatlich in einen Ordner und ersetzt dort immer dieselbe Datei – außer die Liste wäre leer.

**Zurücksetzen** (Tab „Daten“): Standorte (samt „Nicht im Regal“ und „Vermisst“), Einstellungen oder alles. Vor jedem Zurücksetzen, das die Belegung betrifft, wird gesichert; Sicherungen samt Speicherort und Aufbewahrung bleiben immer erhalten.

## Demo

**Plattenregal → Demo starten …** (oder **Einstellungen → Allgemein**) startet die App neu mit einer Beispielsammlung: rund 50 bekannte Alben mit gezeichneten Covern, zwei Regale („Wohnzimmer“, „Flur“ mit gesperrtem Deko-Fach), einige Platten ohne Fach, eine als „Vermisst“ markierte Platte, Wantlist und 18 Monate Wertverlauf. Alles lässt sich ausprobieren – einsortieren, verschieben, Regale anlegen, Einstellungen ändern, exportieren, zurücksetzen. Ein Banner auf jeder Seite zeigt die Demo an; **Demo beenden** startet wieder mit der eigenen Sammlung, **Demo neu starten** holt die Beispielsammlung im Ausgangszustand zurück (etwa nach „Alles zurücksetzen“).

Die Demo ist vollständig von den echten Daten getrennt: Die Sammlung liegt nur im Arbeitsspeicher, Einstellungen in einer eigenen Domäne (`de.private.Plattenregal.demo`, bei jedem Start leer), Sicherungen und Cover in einem temporären Ordner. Discogs ist ausgeschaltet, der Schlüsselbund wird nicht gelesen. Gemeinsam ist nur das Protokoll; jede Zeile aus der Demo trägt dort „Demo ·“ vor ihrer Kategorie. Außerdem in der Demo: keine Discogs-Links und -Aktualisierungen (die Beispiel-IDs gehören bei Discogs zu fremden Releases), keine Tracklisten, keine automatische Sicherung; Speicherort und Aufbewahrung der Sicherungen sind gesperrt, damit die Demo nie echte Sicherungen aufräumt. Dateien, die die Demo vorschlägt oder schreibt, tragen „(Demo)“ im Namen – ein Export in denselben Ordner ersetzt so nie die echte Datei.

Läuft Plattenregal noch ein zweites Mal, wird der Wechsel abgelehnt, damit nie zwei Instanzen auf derselben Sammlung arbeiten. Unabhängig davon öffnet eine zweite Instanz (etwa aus Xcode neben der installierten App) die Sammlung gar nicht erst, sondern zeigt „Plattenregal ist bereits geöffnet“ – die Demo braucht die Sperre nicht, deshalb funktioniert der Wechsel, während die alte Instanz noch beendet wird. Der Neustart kann aus der Sandbox keine Startargumente übergeben; die alte Instanz hinterlegt deshalb eine Minute gültige Anfrage in den Einstellungen, die die neue beim Start übernimmt und löscht. Aus Xcode oder dem Terminal startet `--demo` die Demo direkt.

## Fehlermeldungen und Protokoll

Meldungen sind kurz, auf Deutsch und sagen, was passiert ist und was zu tun ist – ohne englische Systemtexte. Die technischen Details landen im Protokoll: Jede angezeigte Fehlermeldung wird dort mit Ursache und Code-Stelle festgehalten, außerdem Starts, Abgleiche, Regal-Änderungen (auch „Vermisst“ und „Wieder gefunden“ mit Plattenname), Sicherungen, Exporte und Zurücksetzen. Der Discogs-Token steht nie darin.

Beispiele: Schlägt das Speichern einer Markierung fehl, heißt es „„Vermisst“ konnte nicht gespeichert werden – die Platte ist unverändert. Bitte versuche es noch einmal …“; ein Einsortieren in ein gesperrtes Fach erklärt, wo sich die Sperre aufheben lässt. Werden im Einstellungsfenster Regale umgebaut, während „Platte hinzufügen“ oder „Sortierung prüfen“ offen ist, schließt es sich, statt in ein gelöschtes Fach zu schreiben – auch das steht im Protokoll.

Weitere Fälle:

- **Discogs-Daten aktualisieren** (Collection-Menü): Scheitert der Abruf, heißt das Fenster „Discogs-Daten nicht aktualisiert“ statt „Änderung nicht gespeichert“, die Meldung nennt den Grund (etwa keine Verbindung). Beginn und Ergebnis stehen im Protokoll.
- **Sortierung prüfen:** Lässt sich „Reihenfolge übernehmen“ nicht speichern, heißt es „Die neue Reihenfolge konnte nicht gespeichert werden – das Fach ist unverändert …“ (`LibraryError.orderNotSaved`). Im Protokoll stehen jede Prüfung („Sortierung geprüft: KALLAX · Fach 5, Interpret, dann Jahr – 6 von 81 Platten umzustellen“), das Übernehmen mit der Zahl geänderter Positionen und jede Änderung der Reihenfolge bei gleichem Interpreten. Auch das Ab- und Einschalten der Vermisst-Liste wird protokolliert, damit sich später nachvollziehen lässt, warum Markierungen nicht zu sehen waren.
- **Name eines gesperrten Fachs:** Lässt er sich nicht speichern, bleibt das kleine Fenster bei Return offen und zeigt die Meldung, statt sich darüber zu schließen. Wird es durch einen Klick daneben geschlossen, bleibt der alte Name; der Fehler steht im Protokoll.
- **Schlüsselbund nicht lesbar:** Die leere Collection bietet dann „Jetzt synchronisieren“ statt „Token eintragen“ an; der Abgleich sagt, was nicht stimmt. Im Protokoll eine Warnung.
- **Zweite Instanz:** Statt einer Fehlerseite „Sammlung konnte nicht geöffnet werden“ erklärt „Plattenregal ist bereits geöffnet“, dass die andere Instanz beendet werden muss; Daten sind davon nie betroffen. Im Protokoll: „Sammlung nicht geöffnet: eine andere Instanz hält sie offen“.
- **Alles zurücksetzen:** Die Datenbankinhalte werden in einem einzigen Speichervorgang gelöscht. Scheitert er, bleibt alles, wie es war, und die Meldung sagt, dass die Änderung nicht gespeichert werden konnte. Lässt sich danach nur der Token nicht aus dem Schlüsselbund löschen, heißt es „Alles andere ist zurückgesetzt, aber der Discogs-Token ließ sich nicht … löschen“.
- **Seiten mit zwischengespeicherten Platten** (Regal, Statistik) lassen sie beim Zurücksetzen sofort los, bevor neu gezeichnet wird. Die Statistik liest ihre Platten in einem eigenen Datenbank-Kontext; ohne das stürzte SwiftData beim Nachladen einer gelöschten Platte ab („backing data could no longer be found“).

Alle Fehlertypen der App (`DiscogsError`, `LibraryError`, `CabinetError`, `ResetError`, `StorageError`, `ShelfBackupError`, `FileTransferError`, `KeychainError`) sind als nutzerlesbar markiert (`UserFacingError`); ein Test prüft, dass keiner auf „Da ist etwas schiefgelaufen“ zurückfällt.

Das Protokoll lässt sich unter **Einstellungen → Daten → Diagnose** im Finder zeigen oder als Datei sichern. Wer einen Fehler meldet, gibt am besten diese Datei und die Version aus **Über Plattenregal** mit („Version 1.0 (092026)“, auswählbar zum Kopieren) – dieselbe Angabe steht in jeder Startzeile des Protokolls und in jedem Absturz-Block.

**Abstürze.** Bei einem Absturz schreibt die App einen Block `==== ABSTURZ … ====` mit Signal, Uhrzeit, Version und Aufrufliste ins Protokoll (auch bei einem Stack-Überlauf). Beim nächsten Start steht darunter in Klartext, welcher Absturz es war und wann. Endete eine Sitzung ohne Absturz-Eintrag unerwartet (in Xcode gestoppt, zwangsweise beendet, Stromausfall), wird auch das vermerkt – erkannt an einer Laufmarkierung (`Logs/.running` mit der Prozess-ID), die nur ein reguläres Beenden entfernt. Eine zweite Instanz, die die Sammlung nicht öffnen darf, gibt diese Markierung an die laufende Instanz zurück, damit deren Ende weiter richtig erkannt wird.

Das Protokoll wird ab 2 MB zu `Plattenregal.old.log` – beim Start und inzwischen auch während einer langen Sitzung. Der Absturz-Handler schreibt über einen beim Start geöffneten Dateideskriptor (im Signal-Handler darf nichts anderes passieren); nach einem Wechsel der Datei wird er per `dup2` auf die neue umgestellt, sodass ein Absturz immer im aktuellen Protokoll landet. Die Startzeile enthält die Ladeadresse, damit sich die Adressen der Aufrufliste auflösen lassen:

```sh
atos -o Plattenregal.app/Contents/MacOS/Plattenregal -l <Ladeadresse> <Adresse> …
```

## Wichtige Dateien

| Bereich | Datei | Aufgabe |
|---|---|---|
| Start | `PlattenregalApp.swift`, `Views/AboutView.swift` | Szenen (Hauptfenster, Einstellungen, „Über Plattenregal“), Öffnen der Datenbank, Fehlerseite, Protokollstart |
| Modelle | `Models/LibraryModels.swift`, `Models/LibrarySchemas.swift` | Versioniertes SwiftData-Schema und Migrationen |
| Speicherung | `Storage/LibraryStorage.swift`, `Storage/KeychainStore.swift` | Datenbank-Container, Einzelinstanz-Sperre, Fächer, Token im Schlüsselbund |
| Regal | `Services/PositionService.swift`, `Services/CabinetService.swift`, `Views/Shelf/` | Positionen, Regale, „Nicht im Regal“ und „Vermisst“, jede Änderung als eine Transaktion; Regalseite, „Platte hinzufügen“ mit Vermisst-Spalte und „Sortierung prüfen“ (`Views/Shelf/ShelfAssignment.swift`) |
| Sortierung | `Sorting/SortingService.swift` | Sortierschlüssel (Interpret, dann `ShelfSecondaryOrder`), Platzsuche (`AlphabeticalPlacement`), Umstellschritte (`ShelfSortCheck`: alle außer einer längsten schon richtig stehenden Folge) |
| Sicherung | `Services/ShelfBackupService.swift` | Sichern, Wiederherstellen, automatische Sicherung |
| Export | `Services/CollectionExportService.swift`, `Services/ScheduledExportService.swift` | CSV/PDF, automatischer Export |
| Zurücksetzen | `Services/ResetService.swift` | Standorte, Einstellungen, alles |
| Änderungen | `Services/LibraryChanges.swift` | Zähler, an denen Seiten ihre zwischengespeicherten Listen, Suchindizes und Fach-Beschriftungen neu aufbauen |
| Discogs | `Discogs/DiscogsAPIClient.swift`, `Discogs/DiscogsSyncService.swift`, `Discogs/DiscogsSyncDTO.swift`, `Discogs/DiscogsSettingsModel.swift`, `Discogs/MetadataRefreshService.swift` | API, Taktung, Abgleich, Tracklisten; Umsetzung der Discogs-Daten (ein gemeinsamer Weg für Sync und Einzel-Nachladen); Token-Verwaltung; Nachladen einzelner Releases |
| Statistik | `Statistics/` | Auswertungen und Wertverlauf |
| Fehler & Protokoll | `Utilities/ErrorMessages.swift`, `Utilities/AppLog.swift` | Verständliche Meldungen, Protokoll, Absturz-Handler |
| Oberfläche | `Views/`, `Views/Shelf/`, `Views/Settings/`, `Utilities/AppAppearance.swift` | Fenster, Regalseite (Seite, Suche, Regalbild, Fach-Tabelle, „Platte hinzufügen“), ein Einstellungs-Tab pro Datei, gemeinsame Glas-Bausteine (`GlassSegmentedPicker`, `GlassMenuPicker`, `AppMenu`, `AppSearchField`, `AmbientBackdrop`, `appPanel` mit eigener Esc-Abfrage, `appCardSurface`, Knöpfe) |
| Seiten | `Views/RootView.swift`, `Views/PageStack.swift` | Rubriken in der Toolbar, ⌘1–⌘4, ⌘F; jede Seite bleibt in einer eigenen Hosting-View eingehängt und wird nur überblendet (ruckelfreier Wechsel) |
| Tests | `PlattenregalTests/` | Regal, „Platte hinzufügen“, „Sortierung prüfen“, Sicherung, Export, Discogs-Abgleich, Statistik, Einstellungen, Reihenfolge |

## Entwicklung und Prüfung

```sh
xcodebuild -project Plattenregal.xcodeproj -scheme Plattenregal -destination 'platform=macOS' build
xcodebuild -project Plattenregal.xcodeproj -scheme Plattenregal -destination 'platform=macOS' test
```

Die Tests laufen mit einer Datenbank im Arbeitsspeicher, schreiben nicht ins echte Protokoll und brauchen weder Internet noch Token: Discogs-Antworten kommen aus lokalen `URLProtocol`-Attrappen.

Für einen Demo-Lauf aus Xcode unter **Edit Scheme → Run → Arguments** `--demo` ergänzen; `--statistics-demo` öffnet die Demo direkt auf der Statistik. `--settings-tab=Daten` zeigt im Debug-Build einen Einstellungs-Tab im Hauptfenster – zusammen mit `--demo`, sonst mit der echten Sammlung.

Änderungen im Detail: [AENDERUNGEN.md](AENDERUNGEN.md). Build- und Teststände: [VALIDIERUNG.md](VALIDIERUNG.md).
