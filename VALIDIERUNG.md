# Aktueller Stand · 06.10.2026 (Aktionen unten rechts, ohne ABC-Leiste)

## Vorgehen

1. Build und alle Tests: 193, 0 Fehler.
2. Demo fotografiert (`screencapture`, Bildschirm entsperrt): Collection in Modern zu und aufgefächert (`--preview-actions`), Collection in Klassisch aufgefächert, Collection-Suche „Daft“, Wantlist-Suche „Kraft“ und „a“.

## Ergebnis

| Prüfung | Ergebnis |
|---|---|
| Toolbar | ✅ nur die Rubriken, mittig, in beiden Designs |
| Fächer Modern | ✅ Suche, Liste, Sync, Zahnrad im Viertelkreis aus Glas |
| Fächer Klassisch | ✅ petrolfarbener Knopf, cremefarbene Aktionen; Sync in der Demo ausgegraut |
| Suche | ✅ Feld links neben dem Knopf, Text, Löschen-Knopf, „2 in der Collection“ dezent im Feld; Raster gefiltert |
| ABC-Leiste | ✅ weg, Raster bis zum rechten Rand |

## Nicht geprüft

- **Klicks** (Fächer öffnen/schließen, Klick daneben, Esc, Aktionen auslösen, Lupe → Feld mit Cursor) nicht von Hand ausprobiert, nur die Zustände per Startargument.
- **Listenansicht** mit dem neuen Platz unten und die **Regal-Trefferliste** über dem Feld nicht fotografiert.
- Einmal zeigte das Feld bei vorbelegter Wantlist-Suche den Platzhalter mit Cursor statt des Texts; bei zwei Wiederholungen nicht mehr – vermutlich ein Klick ins Fenster während der Aufnahme.

# Vorheriger Stand · 06.10.2026 (Durchsicht von Toolbar und Statistik)

## Vorgehen

1. Den Diff seit der Toolbar-Umstellung (14 Swift-Dateien) auf Logik, Randfälle und Nebenwirkungen durchgesehen: Auf- und Zuklappen der Suche (Fokus, Seitenwechsel, ⌘F, Esc, Verschwinden auf der Statistik), Breitenreserve der Leiste, Designwechsel zur Laufzeit, Statistik-Bereiche, neue Bausteine (`toolbarBar`, `statisticsTile`, `appLinkButton`).
2. Korrigiert, mit Schnappschuss bzw. Bildschirmfoto nachgeprüft, Tests: 193, 0 Fehler (Bildschirm wieder entsperrt).

## Korrigiert

| Befund | Korrektur |
|---|---|
| Die Trefferliste der Regalsuche hing noch oben rechts („unter dem Feld“), das Feld sitzt aber jetzt in der zentrierten Leiste | Liste mittig unter der Leiste (`KallaxView`), im Bildschirmfoto direkt unter dem Feld ✅ |
| Erster Statistik-Bereich in Klassisch mit negativem Innenabstand ausgeglichen | oberer Abstand direkt 0 statt Abstand plus Gegenabstand |
| Palette des Klangbilds bei jedem Tortenstück neu gelesen | einmal gelesen |
| Doku versprach „Klick daneben klappt die leere Suche zu“; auf dem Mac nimmt ein Klick auf Cover oder Knöpfe dem Feld den Cursor aber meist nicht | Doku sagt jetzt: Esc, Klick auf die Lupe oder Fokuswechsel bei leerem Feld |
| `--snapshot` scheiterte still, wenn das Fenster später oder gar nicht kam | wartet bis 30 s auf ein sichtbares Fenster und schreibt Erfolg oder Fehler ins Protokoll; `--preview-search` belegt auch die Regalsuche vor |

## Gefunden, nicht behoben

- **Klassisch + vorbelegte Suche beim Start → kein Fenster.** Startet die Demo in Klassisch mit `--preview-search`, erzeugt SwiftUI kein Hauptfenster (in Modern schon, ohne Suche auch in Klassisch). Bestand schon vor dieser Sitzung (mit Commit b7061c2 nachgestellt). Für Nutzer nicht erreichbar, weil die Suche beim Start immer leer ist; als eigene Aufgabe vorgeschlagen.

## Für robust befunden

- Suche: offen = vom Nutzer geöffnet oder Text vorhanden, darum klappt sie bei aktiver Suche nie zu; beim Seitenwechsel schließt sie nur ohne Fokus und ohne Text der neuen Seite; auf der Statistik verschwindet sie samt Fokus-Meldung an `SearchRequests` (⌘Z der Regalseite bleibt richtig).
- Leiste: Breitenreserve aus denselben Bausteinen wie die echte Leiste, ausgeblendet und ohne Bedienungshilfen; ein Designwechsel baut sie neu, weil `AppStyle.isAtelier` beobachtet wird.
- Statistik: Modern unverändert (Bildschirmfoto mit Glas), Klassisch-Zweige nur über `AppStyle.isAtelier`.

# Vorheriger Stand · 06.10.2026 (Statistik in Klassisch)

## Vorgehen

1. Bildschirm war gesperrt, `screencapture` lieferte nichts. Darum `--snapshot=…` gebaut: Die Demo zeichnet ihr Fenster selbst in eine PNG-Datei.
2. Statistik in Klassisch fotografiert, alle Bereiche über `-statisticsSectionOrder` nach oben geholt (Klangbild, Top-Künstler, Labels, Zufallsfund, Zeitreise, Neuzugänge, Deine Sammlung, Auf einen Blick).
3. `build-for-testing` erfolgreich.

## Ergebnis

| Prüfung | Ergebnis |
|---|---|
| Bereiche | ✅ auf Papiergrund, feine Linien dazwischen, keine Linie über dem ersten, bündig mit dem Seitenrand |
| Kacheln | ✅ cremefarbene Hüllen mit Rand und Schatten, Symbole einheitlich Petrol |
| Klangbild | ✅ Palette Petrol/Gold/Erdtöne, „Weitere“ gedeckt grau |
| Cover | ✅ Top-Künstler und Zufallsfund in Hüllen, kein weichgezeichnetes Cover dahinter |
| Links | ✅ „Alle 40 Labels“ in Petrol |

## Nicht geprüft

- **Tests nicht gelaufen**: Bei gesperrtem Bildschirm hing der Test-Runner vor dem Start („hung before establishing connection“), zweimal. Sie kompilieren; beim nächsten entsperrten Bildschirm `xcodebuild test` laufen lassen.
- **Modern** nur im Schnappschuss, der kein Glas zeichnet; der Code für Modern ist bis auf die verschobene Beschneidung der Karte unverändert.
- **Hover** (goldener Rand) nicht von Hand ausprobiert.

# Vorheriger Stand · 06.10.2026 (Toolbar-Leiste, ausklappbare Suche, Modern/Klassisch)

## Vorgehen

1. Build und alle Tests (`xcodebuild test`): 193 Tests, 0 Fehler.
2. Demo gestartet (`--preview-page`, neu `--preview-search`, `-signatureDesign atelier`) und Fenster fotografiert, mit dem Stand davor verglichen.

## Ergebnis

| Prüfung | Ergebnis |
|---|---|
| Collection, Modern, Suche zu | ✅ eine Glas-Kapsel mittig: Rubriken · Raster/Liste · Lupe, kein Symbol und kein Name oben links |
| Collection, Modern, Suche „Daft“ | ✅ Feld in der Leiste aufgeklappt, Text und Löschen-Knopf, Leiste wächst zu beiden Seiten |
| Wantlist, Klassisch, Suche „a“ | ✅ dunkleres Band auf Petrol, „55 in der Collection“ klein und grau im Feld, Sync und Zahnrad rechts in der Leiste |
| Regal, Klassisch | ✅ Rubriken · Lupe · Zahnrad, Umschalter an derselben Stelle wie auf der Collection |
| Statistik, Modern | ✅ nur die Rubriken, links bündig im reservierten Platz (Umschalter wandert nicht) |

## Nicht geprüft

- **Klicks auf die Lupe, ⌘F, Esc und Fokuswechsel** nicht von Hand ausprobiert – nur der aufgeklappte Zustand über `--preview-search`.
- **Einstellungsfenster** mit der neuen Leiste nicht fotografiert.

# Vorheriger Stand · 06.10.2026 (Suche in der Toolbar, Designs in Gruppen, ohne Plattenrücken)

Stand nach dem Umbau (Details in [AENDERUNGEN.md](AENDERUNGEN.md)).

## Vorgehen

1. Debug-Build mit `xcodebuild` im Projektordner, ohne Warnungen.
2. Demo gestartet und Fenster fotografiert (`screencapture`), jeweils mit dem Stand davor verglichen: Collection und Regal in Liquid Glass, Collection in Atelier.
3. Tests ausgeführt.

## Ergebnis

| Prüfung | Ergebnis |
|---|---|
| Collection, Liquid Glass | ✅ Suchfeld rechts neben Raster/Liste in der Toolbar, Cover beginnen auf derselben Höhe wie vorher ohne Suchleiste |
| Regal, Liquid Glass | ✅ Suchfeld in der Toolbar, keine Rückenleiste und keine Legende mehr, Fach-Tabelle direkt unter dem Fachtitel |
| Collection, Atelier | ✅ kein Seitentitel mehr, Cover direkt unter der petrolfarbenen Toolbar, Suchfeld dunkel passend zur Toolbar |
| Übersetzungen | ✅ 11 verwaiste Texte entfernt, 7 neue übersetzt; Format des Katalogs unverändert |
| Tests | ✅ 193 Tests, 0 Fehler |

Nach dem Entsperren des Bildschirms nachgeholt: Atelier-Collection (Sync-Knopf und Zahnrad rechts in der Toolbar, Cover mit gleichem Abstand zur Toolbar wie zum Fensterrand) und die Design-Karte mit „Modern“/„Klassisch“, beiden Vorschauen und ausgegrauter Akzentfarbe ✅. Nebenbei: Nach einem harten Beenden (`kill`) öffnete die Demo beim nächsten Start kein Fenster von selbst (ein Klick aufs Dock-Symbol holte es); nach ⌘Q startete sie zweimal hintereinander normal mit Fenster.

## Nicht geprüft (dieser Durchgang)

- **Tippen ins Suchfeld, ⌘F und Esc** sowie die Trefferliste der Regalsuche nicht von Hand ausprobiert.
- **Tour-Bilder** nicht neu aufgenommen.

# Vorheriger Stand · 06.10.2026 (Signature Design „Atelier“)

Stand nach dem neuen wählbaren Design (Details in [AENDERUNGEN.md](AENDERUNGEN.md)).

## Vorgehen

1. Den gesamten Diff (10 Dateien) auf Aufbau und Nebenwirkungen durchgesehen: Speicherung der Wahl, Rückfall bei unbekannten Werten, Zurücksetzen, Hell/Dunkel, Raster-Berechnung mit größerem Abstand, Toolbar in beiden Designs, Platzhalter bei fehlenden Release-Daten, Demo-Sperren, Übersetzungen.
2. Zwei Fehler behoben (leere Toolbar-Einträge in der bisherigen Gestaltung, abweichende Wantlist-Platzhalter) und die Protokollierung des Designs ergänzt.
3. Debug-Build mit `xcodebuild` im Projektordner, Tests zweimal ausgeführt.

## Ergebnis

| Prüfung | Ergebnis |
|---|---|
| Debug-Build | ✅ erfolgreich, ohne neue Warnungen |
| Bisherige Einstellungen beim Wechsel | ✅ Modus, Akzent, Ambient und Startseite bleiben unverändert (Test) |
| Unbekannter gespeicherter Wert | ✅ fällt auf die aktuelle Gestaltung zurück, Wert bleibt stehen (Test) |
| Cover-Raster | ✅ Spaltenzahl und Spaltenabstand nutzen beide `CoverGrid.spacing`, rechnen also mit 18 pt in Atelier richtig |
| Fehlermeldungen | ✅ „Synchronisieren“ und „Aktualisieren“ im Seitentitel nutzen dieselben Wege wie ⌘R bzw. Ziehen, samt deren Meldungen; keine neuen Fehlerfälle |
| Übersetzungen | ✅ alle neuen Texte englisch; „Signature Designs“ und „Atelier“ bewusst unübersetzt |
| Tests | ✅ 193 Tests, 0 Fehler (beide Läufe) |

## Nicht geprüft (dieser Durchgang)

- **Atelier in der laufenden App** nicht angesehen: Die Demo startet mit leeren Einstellungen, und die Wahl in der echten App sollte nicht verändert werden. Insbesondere offen: petrolfarbene Toolbar im inaktiven Fenster, Popover-Pfeil (bleibt systemfarben, nur der Inhalt ist cremefarben), Tour-Bilder (zeigen weiter die bisherige Gestaltung).
- **Wechsel des Designs bei offenem Glasfenster** (Tour, „Platte hinzufügen“) nicht ausprobiert.

# Vorheriger Stand · 06.10.2026 (Tour beim ersten Start)

Stand nach der Tour (Details in [AENDERUNGEN.md](AENDERUNGEN.md)).

## Vorgehen

1. Bilder mit `Scripts/tour-screenshots.sh` aus der Demo aufgenommen (Deutsch/Englisch, hell/dunkel) und die Ausschnitte als Kontaktbogen angesehen.
2. Debug-Build mit `xcodebuild` im Projektordner.
3. Demo mit `--preview-tour` gestartet und alle sechs Seiten mit der Pfeiltaste durchgeblättert: hell auf Deutsch, dunkel auf Deutsch, hell auf Englisch. Jede Seite angesehen.
4. Tests dreimal ausgeführt.

## Ergebnis

| Prüfung | Ergebnis |
|---|---|
| Debug-Build | ✅ erfolgreich |
| Tour hell/dunkel, Deutsch/Englisch | ✅ richtige Bildvariante, Texte übersetzt, ausgeblendete Kanten samt Rahmen und Schatten |
| Blättern mit → | ✅ genau eine Seite pro Tastendruck |
| Tests | ✅ 190 Tests, 0 Fehler (zweiter und dritter Lauf). Der erste Lauf meldete einen Fehler, ohne dass das Protokoll mitgeschnitten war; er fiel mit dem Beenden einer Demo-Instanz zusammen und ließ sich nicht wiederholen. |

## Nicht geprüft (dieser Durchgang)

- **Erster Start mit der echten Sammlung:** nicht ausprobiert, um die echten Einstellungen nicht zu verändern; der Weg ist derselbe wie mit `--preview-tour`, nur ausgelöst über `tourSeen`.
- **Menüpunkt „Hilfe → Tour durch Plattenregal …“** und „Token eintragen …“ nicht angeklickt.
- **„Bewegung reduzieren“** nicht eingeschaltet.

# Vorheriger Stand · 05.10.2026 (neues App-Symbol, Version 1.0.2)

Stand nach dem neuen App-Symbol und dem Versionssprung auf 1.0.2 (Details in [AENDERUNGEN.md](AENDERUNGEN.md)). Am Code hat sich nichts geändert.

## Vorgehen

1. Die zehn PNG-Dateien im `AppIcon.appiconset` auf Pixelgröße und Alphakanal geprüft und mit der finalen Vorlage `outputs/AppIcon-Vinyl-2026-10-05/AppIcon-Vinyl-1024.png` verglichen: Die 1.024-Pixel-Datei ist byte-gleich mit der Vorlage.
2. Debug-Build mit `xcodebuild` erstellt (DerivedData außerhalb des Schreibtischs).
3. `AppIcon.icns` aus dem gebauten Paket entpackt (`sips`) und angesehen. Es zeigt das neue Motiv.
4. `Info.plist` des gebauten Pakets gelesen und `codesign --verify --deep --strict` ausgeführt.

## Ergebnis

| Prüfung | Ergebnis |
|---|---|
| Symbol-Satz im Projekt | ✅ 10 Größen (16, 32, 32, 64, 128, 256, 256, 512, 512, 1024), alle mit Alphakanal; `Contents.json` unverändert |
| Debug-Build | ✅ erfolgreich, keine Compiler-Warnungen |
| Symbol im gebauten Paket | ✅ `AppIcon.icns` und `Assets.car` enthalten, neues Motiv |
| Version im gebauten Paket | ✅ `Info.plist` meldet 1.0.2, Build 102026 |
| Signatur (Debug, ad-hoc) | ✅ gültig |

## Nicht geprüft (dieser Durchgang)

- **Tests:** nicht erneut ausgeführt, weil sich weder Code noch Tests geändert haben. Es gilt der Stand vom 04.10.: 190 Tests, 0 Fehler.
- **Darstellung im System:** Dock, Finder und die Karte „Über Plattenregal“ wurden nicht angesehen; keine Sichtprüfung der kleinen Größen. macOS zeigt dort unter Umständen noch kurz das alte Symbol aus dem Zwischenspeicher.
- **Release-Build:** nicht gebaut; keine Prüfung von Release-Signatur oder Notarisierung.

# Vorheriger Stand · 04.10.2026 (Englisch, Tastenkürzel, technische Prüfung, weniger Rechenarbeit, Abschlussprüfung)

Stand nach Englisch als zweiter Sprache, den Tastenkürzeln, der technischen Prüfung, der Durchsicht auf unnötige Rechenarbeit und einer abschließenden Prüfung aller Änderungen des Tages (Details in [AENDERUNGEN.md](AENDERUNGEN.md)).

## Ergebnis

- Gesamte Testsuite: **190 Tests in 13 Suites, 0 Fehler** (Debug, `xcodebuild … test`), keine Compiler-Warnungen. Die Meldungen „Discogs JSON decoding failed“ und die CoreData-Hinweise im Testlauf stammen aus Tests, die ungültige Antworten und Migrationen absichtlich prüfen.

| Testdatei | Tests | Schwerpunkt |
|---|---|---|
| `LibraryTests.swift` | 53 | Positionen, Sortierung, Sortierprüfung, Suche (auch die gemeinsamen Suchtexte), Fach-Beschriftungen, Speicherung, Fehlermeldungen, Absturz-Auswertung, Discogs-Mapping, Demo-Sammlung |
| `DiscogsSyncTests.swift` | 40 | Abgleich, Ordner, Wantlist, Pagination, Konten, `Retry-After`, Migration, Doppelte in der Datenbank, Erkennen eines Abgleichs ohne Änderungen |
| `StatisticsTests.swift` | 30 | Auswertungen, Wertverlauf, Migrationen, Zurücksetzen, welche Speichervorgänge neu rechnen lassen |
| `SettingsTests.swift` | 17 | Discogs-Token, Reihenfolge der Statistik, Reihenfolge von Collection und Wantlist, Eingabequellen-Blase |
| `BackupTests.swift` | 15 | Sichern, Wiederherstellen, Aufbewahrung, Dateinamen mit Zeitzone |
| `CabinetTests.swift` | 15 | Mehrere Regale, Größenänderung, Zurücksetzen, Einzelinstanz-Sperre |
| `ExportTests.swift` | 13 | CSV (Maskierung, BOM, Formel-Schutz, Trennzeichen), Reihenfolge, Spalten, PDF |
| `ScenarioTests.swift` | 7 | Abläufe gegen die echten Services: ohne Netz, Bremse, gelöschte Fächer, „Platte hinzufügen“, 10.000 Platten |

- Neu seit dem vorigen Stand (176): u. a. Export- und Sicherungstests aus den Prüfungen vom 27./28.09. und heute `unchangedSyncReportsNoChanges`, `wantlistDetailsCountAsChanges`, `collectionDetailsCountAsChanges`, `anotherAccountCountsAsChange`, `onlyRelevantSavesReloadStatistics`, `sharedSearchIndexFollowsChanges`, `cachedShelfLabelsMatchFullComputation`. `errorsReachTheUserInPlainGerman` prüft zusätzlich die Meldung bei Lesefehlern.
- **Abschlussprüfung** per Code-Durchsicht: Änderungserkennung des Abgleichs (alle Felder, die Seiten zeigen, setzen `hasChanges`; Sync-Zeiten in den Discogs-Kacheln folgen trotzdem, weil die Seite beim Sync-Ende neu zeichnet), Statistik-Filter (keine Zahl der Statistik hängt an Fach oder Position; Detailansicht holt die Platte aus dem Hauptkontext), Beschriftungs-Cache (Beschriftungen hängen nur am Interpreten, nicht an der Reihenfolge bei gleichem Interpreten), gemeinsame Suchdaten (Demo startet die App neu, kein Index wandert zwischen Sammlungen), direkte Speicherwege für Tracklist und Discogs-Daten, paralleles Cover-Laden. Korrigiert: Regal-Einstellungen bemerkten einen Tausch zwischen zwei Fächern nicht (gleiche Plattenzahl). String-Katalog maschinell geprüft: 831 Einträge, alle englisch übersetzt, keine verwaisten.
- **Laufende App**: Demo-Build nach jeder Änderungsrunde gestartet, läuft ohne Absturz und beendet sich regulär. Keine Sichtprüfung der Seiten in diesem Durchgang.
- **Protokoll** der echten App durchgesehen: kein Absturzblock. Einzige Fehlerzeile ist ein Schemafehler beim Öffnen vom 25.09. (Entwicklungsstand, seitdem nicht wieder aufgetreten). Die Warnungen „nicht normal beendet“ gehören zu Testinstanzen, die per Befehl beendet wurden.
- **Fehlermeldungen** per Code-Durchsicht geprüft: alle Fehlertypen mit verständlichem Text in beiden Sprachen; Lesefehler sagen nicht mehr „nicht gespeichert“.

## Nicht geprüft (dieser Durchgang)

- Kein Abgleich mit Discogs: Ob eine Synchronisierung ohne Änderungen die Seiten tatsächlich in Ruhe lässt und Collection und Wantlist danach nur einmal neu aufbauen, ist mit Tests am Abgleich selbst belegt, nicht in der laufenden App. Die Demo hat kein Discogs.
- Paralleles Laden der Cover nicht mit echten Cover-Dateien angesehen (die Demo zeichnet ihre Cover).
- Kein Release-Build, keine Codesign-Prüfung.

# Vorheriger Stand · 27.09.2026 (Über-Karte, ein Hauptfenster, Randfälle)

Stand nach der kleinen Karte „Über Plattenregal“, dem einzelnen Hauptfenster und zwei Prüfrunden auf Randfälle und Logik (Details in [AENDERUNGEN.md](AENDERUNGEN.md)).

## Ergebnis

- Gesamte Testsuite: **176 Tests in 13 Suites, 0 Fehler** (Debug, `xcodebuild … test`), keine Compiler-Warnungen. Die CoreData-Meldungen „Migration was completed by another client“ stammen aus den Migrationstests und sind keine Fehler.

| Testdatei | Tests | Schwerpunkt |
|---|---|---|
| `LibraryTests.swift` | 51 | Positionen, Sortierung, Sortierprüfung, Suche, Speicherung, Fehlermeldungen, Absturz-Auswertung, Discogs-Mapping, Demo-Sammlung |
| `DiscogsSyncTests.swift` | 36 | Abgleich, Ordner, Wantlist, Pagination, Konten, `Retry-After`, Migration, Doppelte in der Datenbank, Sammlungswert nach reiner Wantlist-Synchronisierung |
| `StatisticsTests.swift` | 29 | Auswertungen, Wertverlauf, Migrationen, Zurücksetzen |
| `SettingsTests.swift` | 17 | Discogs-Token, Reihenfolge der Statistik, Reihenfolge von Collection und Wantlist, Eingabequellen-Blase |
| `CabinetTests.swift` | 15 | Mehrere Regale, Größenänderung, Zurücksetzen, Einzelinstanz-Sperre |
| `BackupTests.swift` | 13 | Sichern, Wiederherstellen, Aufbewahrung, Dateinamen |
| `ExportTests.swift` | 8 | CSV (Maskierung, BOM, Formel-Schutz), Reihenfolge, Spalten, PDF |
| `ScenarioTests.swift` | 7 | Abläufe gegen die echten Services: ohne Netz, Bremse, gelöschte Fächer, „Platte hinzufügen“, 10.000 Platten |

- Neu seit dem vorigen Stand: `DiscogsSyncTests.duplicatesAlreadyInTheStoreDoNotStopTheSync`, `DiscogsSyncTests.valueRefreshAfterWantlistOnlySyncIsNoError`.
- **Laufende App** (Debug-Build, Demo): „Über Plattenregal“ aus dem App-Menü öffnet die Karte (260 × 237 pt, mittig) mit Symbol, Name, „Version 1.0 (092026)“ und „© 2026 Patrice Werner“.
- **Fehlermeldungen und Protokoll** per Code-Durchsicht geprüft: alle Fehlertypen mit verständlichem deutschen Text, Startzeile und Absturz-Block mit Version.

## Nicht geprüft (dieser Durchgang)

- Über-Karte nur im hellen Modus angesehen.
- Kein Release-Build, keine Codesign-Prüfung, kein Abgleich mit Discogs für diesen Stand.

# Vorheriger Stand · 27.09.2026 (Fenster ohne Ampel, Vermisst-Spalte, Sortierung prüfen)

Stand nach den Glasfenstern über der Seite, der Vermisst-Spalte in „Platte hinzufügen“, dem Plus im Fach, „Sortierung prüfen“ mit wählbarer Reihenfolge bei gleichem Interpreten und drei Prüfrunden auf Robustheit (Details in [AENDERUNGEN.md](AENDERUNGEN.md)).

## Ergebnis

- Gesamte Testsuite: **174 Tests in 13 Suites, 0 Fehler** (Debug, `xcodebuild … test`), keine Compiler-Warnungen. Die Meldung „Discogs JSON decoding failed“ im Testlauf kommt aus einem Test, der eine ungültige Antwort absichtlich prüft.

| Testdatei | Tests | Schwerpunkt |
|---|---|---|
| `LibraryTests.swift` | 51 | Positionen, Sortierung, Sortierprüfung, Suche, Speicherung, Fehlermeldungen, Absturz-Auswertung, Discogs-Mapping, Demo-Sammlung |
| `DiscogsSyncTests.swift` | 34 | Abgleich, Ordner, Wantlist, Pagination, Konten, `Retry-After`, Migration |
| `StatisticsTests.swift` | 29 | Auswertungen, Wertverlauf, Migrationen, Zurücksetzen |
| `SettingsTests.swift` | 17 | Discogs-Token, Reihenfolge der Statistik, Reihenfolge von Collection und Wantlist, Eingabequellen-Blase |
| `CabinetTests.swift` | 15 | Mehrere Regale, Größenänderung, Zurücksetzen, Einzelinstanz-Sperre |
| `BackupTests.swift` | 13 | Sichern, Wiederherstellen, Aufbewahrung, Dateinamen |
| `ExportTests.swift` | 8 | CSV (Maskierung, BOM, Formel-Schutz), Reihenfolge, Spalten, PDF |
| `ScenarioTests.swift` | 7 | Abläufe gegen die echten Services: ohne Netz, Bremse, gelöschte Fächer, „Platte hinzufügen“, 10.000 Platten |

- Neu bzw. geändert:
  - `LibraryTests.sortCheckMovesFewestRecordsInTargetOrder` – bei einer falsch stehenden Platte genau ein Schritt mit richtigem Platz und richtigen Nachbarn; nach „Reihenfolge übernehmen“ keiner mehr.
  - `LibraryTests.sortCheckByYearWithinArtist` – nach Titel in Ordnung, nach Jahr ein Schritt; Sortieren nach Jahr ordnet die Platten eines Interpreten chronologisch.
  - `LibraryTests.errorsReachTheUserInPlainGerman` – zusätzlich die Meldung für eine nicht gespeicherte Reihenfolge, ohne Fehlercode.
  - `ScenarioTests.addingListsFittingRecordsFirstPausedInPlace` (vorher `…AndPausedLast`) – zurückgestellte Platten behalten ihren Platz in der Liste.
- **Laufende App** (Debug-Build, eigene Sammlung, Klicks und Tasten per Maus- und Tastatur-Ereignissen):
  - „Platte hinzufügen“ über das Plus im Fach für das richtige Fach geöffnet; Vermisst-Spalte ein- und ausgeklappt; eine Platte als „Wieder gefunden“ markiert (rechts heraus, links an ihrer Stelle hinein) und wieder zurückgestellt – Daten danach wie vorher (17 vermisst).
  - „Sortierung prüfen“ auf „He – La“: nach Titel 1 Schritt, nach Jahr 6; ein auffälliger Vorschlag in einer Kopie der Datenbank nachgerechnet und bestätigt. „Reihenfolge übernehmen“ bewusst nicht ausgeführt, um die echten Positionen nicht zu ändern.
  - Esc schließt „Platte hinzufügen“ und die Plattenliste der Statistik (vor der Korrektur nicht); ⌘F öffnet die Suche ohne Lupe; ⌘← / ⌘→ wechseln die Regale; Rechtsklick auf die Toolbar zeigt kein Menü.
  - Statistik: Wertezeile unter der Zeitreise („2000er · 522 Platten“), Plattenliste mit Titel, ohne Suchleiste.
  - Hinzufügen-Knopf war zunächst zu „Hinzufü…“ abgeschnitten, die Abdunklung hinter den Fenstern endete hart an der Toolbar – beides gesehen und behoben.
- **Protokoll** der Testläufe durchgesehen: keine Absturzblöcke, keine Fehlermeldungen; „Wieder gefunden“ und „Vermisst“ des Tests stehen darin. Eine Warnung „nicht normal beendet“ (9:56) gehört zu einer Testinstanz, die während eines Neubaus beendet wurde.

## Nicht geprüft (dieser Durchgang)

- „Als Nächstes“ in „Platte hinzufügen“ nicht gesehen: alle Platten ohne Fach sind in der eigenen Sammlung als vermisst markiert.
- „Reihenfolge übernehmen“ nicht in der laufenden App ausgelöst (würde echte Positionen ändern); abgedeckt durch die Tests.
- Die neue Fehlermeldung und die neuen Protokollzeilen nicht in der laufenden App ausgelöst – ein fehlschlagendes Speichern lässt sich nicht gezielt herbeiführen; geprüft ist der Meldungstext.
- Kein Release-Build, keine Codesign-Prüfung, kein Abgleich mit Discogs für diesen Stand.

# Vorheriger Stand · 26.09.2026 (Liquid-Glass-Oberfläche)

Stand nach dem Umbau auf Rubriken in der Toolbar, einheitliches Liquid Glass, dem eigenen Menü in Collection und Wantlist, der wählbaren Reihenfolge und dem neuen „Platte hinzufügen“ (Details in [AENDERUNGEN.md](AENDERUNGEN.md)).

## Ergebnis

- Gesamte Testsuite: **171 Tests in 13 Suites, 0 Fehler** (Debug, `xcodebuild … test`), keine Compiler-Warnungen. Die CoreData-Meldungen im Testlauf („Migration was completed by another client“, „Persistent History … has to be truncated“) stammen aus den Migrationstests und sind keine Fehler.

| Testdatei | Tests | Schwerpunkt |
|---|---|---|
| `LibraryTests.swift` | 48 | Positionen, Sortierung, Suche, Speicherung, Fehlermeldungen, Absturz-Auswertung, Discogs-Mapping, Demo-Sammlung |
| `DiscogsSyncTests.swift` | 33 | Abgleich, Ordner, Wantlist, Pagination, Konten, `Retry-After`, Migration |
| `StatisticsTests.swift` | 28 | Auswertungen, Wertverlauf, Migrationen, Zurücksetzen |
| `SettingsTests.swift` | 16 | Discogs-Token, Reihenfolge der Statistik, Reihenfolge von Collection und Wantlist |
| `CabinetTests.swift` | 15 | Mehrere Regale, Größenänderung, Zurücksetzen, Einzelinstanz-Sperre |
| `BackupTests.swift` | 13 | Sichern, Wiederherstellen, Aufbewahrung, Dateinamen |
| `ExportTests.swift` | 8 | CSV (Maskierung, BOM, Formel-Schutz), Reihenfolge, Spalten, PDF |
| `ScenarioTests.swift` | 7 | Abläufe gegen die echten Services: ohne Netz, Bremse, gelöschte Fächer, „Platte hinzufügen“, 10.000 Platten |

- Neu:
  - `SettingsTests.overviewOrderShufflesStablyAndSortsNewestFirst` – „Zufällig“ bleibt innerhalb eines Starts gleich und verliert nichts; „Neueste zuerst“ mit Undatierten am Ende.
  - `ScenarioTests.addingListsFittingRecordsFirstAndPausedLast` – „Platte hinzufügen“ zeigt Passende zuerst, Platten für ein anderes Fach mit Hinweis, Vermisste zuletzt; „+“ setzt alphabetisch ein.
- Rubrikwechsel mit dem Time Profiler gemessen (Release, 12 Wechsel): Main-Thread-Last ~4,1 s → ~0,2 s, keine Animation Hitches.
- Fehlerwege der neuen Oberfläche per Code-Durchsicht geprüft: Jede Aktion im neuen Menü (Collection, Wantlist, Fach, Fach-Tabelle) meldet Fehler über `reportedMessage()` und schreibt sie ins Protokoll. Nachgebessert: Fenstertitel bei „Discogs-Daten aktualisieren“, Namens-Popover gesperrter Fächer, Warnung bei nicht lesbarem Schlüsselbund.

## Nicht geprüft (dieser Durchgang)

- Kein Release-Build und keine Codesign-Prüfung für diesen Stand.
- Die Nachbesserungen an den Fehlermeldungen sind nicht in der laufenden App ausgelöst – ein fehlschlagendes Speichern oder ein unlesbarer Schlüsselbund lässt sich nicht gezielt herbeiführen.
- Kein echter Abgleich mit Discogs; „Discogs-Daten aktualisieren“ aus dem neuen Menü nicht gegen Discogs ausgeführt.

# Vorheriger Stand · 25.09.2026 (Robustheitsprüfung und Aufräumen)

Stand nach drei Prüfrunden auf Robustheit, dem Entfernen von totem Code und dem Aufteilen der großen Views (Details in [AENDERUNGEN.md](AENDERUNGEN.md)).

## Ergebnis

- Gesamte Testsuite: **167 Tests in 13 Suites, 0 Fehler** (Debug, `xcodebuild … test`).
- Debug- und Release-Build (`-configuration Release`): erfolgreich, **keine Compiler-Warnungen**.
- Build-Einstellungen: Swift 6, `SWIFT_STRICT_CONCURRENCY = complete`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, App-Sandbox mit ausgehendem Netz und vom Nutzer gewählten Dateien.

| Testdatei | Tests | Schwerpunkt |
|---|---|---|
| `LibraryTests.swift` | 49 | Positionen, Sortierung, Suche, Speicherung, Fehlermeldungen, Absturz-Auswertung, Discogs-Mapping, Demo-Sammlung |
| `DiscogsSyncTests.swift` | 33 | Abgleich, Ordner, Wantlist, Pagination, Konten, `Retry-After`, Migration |
| `StatisticsTests.swift` | 28 | Auswertungen, Wertverlauf, Migrationen, Zurücksetzen |
| `CabinetTests.swift` | 15 | Mehrere Regale, Größenänderung, Zurücksetzen, Einzelinstanz-Sperre |
| `SettingsTests.swift` | 15 | Discogs-Token speichern, testen, abbrechen und entfernen; Reihenfolge der Statistik |
| `BackupTests.swift` | 13 | Sichern, Wiederherstellen, Aufbewahrung, Dateinamen |
| `ExportTests.swift` | 8 | CSV (Maskierung, BOM, Formel-Schutz), Reihenfolge, Spalten, PDF |
| `ScenarioTests.swift` | 6 | Abläufe gegen die echten Services: ohne Netz, Bremse, gelöschte Fächer, 10.000 Platten |

- Neu:
  - `CabinetTests.deleteLibraryLeavesAFreshStoreInOneGo` – „Alles zurücksetzen“ leert die Datenbank in einem Speichervorgang und legt das erste Regal neu an; keine offenen Änderungen bleiben zurück. (Getestet wird der Datenbankteil `deleteLibrary`; `resetEverything` löscht zusätzlich den echten Token und die echten Einstellungen und bleibt deshalb ungetestet.)
  - `CabinetTests.secondInstanceDoesNotOpenALockedStore` – hält eine andere Instanz die Sperrdatei, wird die Sammlung nicht geöffnet (`StorageError.alreadyOpen`).
  - `StatisticsTests.statisticsForgetTheirRecordsOnReset` – nach dem Zurücksetzen hält das Statistik-Modell keine Platte mehr.
  - `LibraryTests.artistLineFollowsDiscogsJoins` – „Moby, Kid“, „A & B“, „A Feat. B“; leere und fehlende Trennzeichen.
- Umgestellt: Die Suchtests prüfen jetzt `SearchIndex`, den Weg der App, statt eigener nur für Tests vorhandener Suchfunktionen; die Token-Tests laufen über `startTest()` und `cancelTest()` wie die Einstellungen.
- **Absturz nachgewiesen und behoben** (vorübergehender Probe-Test, danach entfernt): Ein Exemplar, das ein zweiter Datenbank-Kontext geladen hat, bringt SwiftData nach dem Löschen im Hauptkontext beim Zugriff auf sein Release zum Absturz („This model instance was invalidated because its backing data could no longer be found the store“). Im selben Kontext und bei bereits geladenen Daten (Wantlist nach einem Sync) passiert nichts. Betroffen war die Statistik nach „Alles zurücksetzen“.
- Toter Code: eigene Suche nach Deklarationen ohne Verwendung (ohne Kommentare, auch qualifiziert als `Typ.member`); übrig sind nur Protokoll-Pflichtmethoden und der App-Einstiegspunkt.
- Beim Aufteilen der Views maschinell geprüft, dass der Inhalt Zeile für Zeile erhalten blieb (nur `private` bei dateiübergreifend genutzten Typen entfernt).

## Nicht geprüft (dieser Durchgang)

- In der laufenden App nicht angeklickt – weder die Regalseite nach dem Umbau der Neuberechnung noch Statistik und Regal nach „Alles zurücksetzen“ noch die Hinweisseite einer zweiten Instanz. Die Logik dahinter ist über Tests und Code-Durchsicht abgedeckt.
- Kein echter Abgleich mit Discogs; die korrigierten Interpretennamen („A, B“ statt „A , B“) erscheinen in der eigenen Sammlung erst mit dem nächsten Sync.
- Der Absturz-Handler nach einem Protokollwechsel während der Sitzung wurde nicht mit einem echten Absturz ausgelöst.

# Älterer Stand · 25.09.2026 (Laufzeit-Messungen)

## Ergebnis

- Gesamte Testsuite: **163 Tests in 13 Suites, 0 Fehler** (Debug, `xcodebuild … test`), keine Compiler-Warnungen.
- Gemessen mit einem vorübergehenden Szenario in der Größe der echten Sammlung (841 Platten, 868 Wantlist-Einträge, 12 Fächer, `-O`), vorher → nachher: Einsortieren (Verschieben + Speichern) 13,9 → 2,7 ms; Regalseite danach neu berechnen 104 → 9 ms; Collection aufbauen (warm) 60 → 38 ms; Platz finden 19 → 4,6 ms; Export-Tabelle 183 → 112 ms. Unverändert: Abgleich ohne Änderungen 0,72 s (Hintergrund), Neuladen der Exemplare nach jedem Speichern 19 ms je Ansicht.
- 10.000 Platten (Debug): Sortieren 1,58 → 1,29 s, Platz finden 531 → 115 ms, Export-Tabelle 3,2 → 1,5 s; der Rest entfällt in diesem Test auf das erstmalige Laden der Releases.
- Ursachen per Time Profiler (Instruments) belegt: SwiftData-Lesezugriffe in Sortier-Vergleichen und einzeln nachgeladene Releases nach jedem Neuladen der Exemplare.

# Älterer Stand · 24.09.2026 („Vermisst“ und Regalseite)

Stand nach der neuen Markierung „Vermisst“ und vier Prüfungen der Regalseite auf Grenzfälle (Details in [AENDERUNGEN.md](AENDERUNGEN.md)).

## Ergebnis

- Gesamte Testsuite: **161 Tests in 13 Suites, 0 Fehler** (Debug, `xcodebuild … test`).
- Neu bzw. erweitert:
  - `LibraryTests.missingMarkKeepsPlaceAndCanBeCleared` – Markieren (auch doppelt) legt genau einen Eintrag an, Fach und Position bleiben, „Wieder gefunden“ entfernt ihn.
  - `LibraryTests.missingMarkFollowsShelfActions` – Herausnehmen und Verschieben behalten die Markierung, Einsortieren von Hand, „Nicht im Regal“ und Löschen heben sie auf.
  - `LibraryTests.errorsReachTheUserInPlainGerman` – verständliche Meldung für eine nicht gespeicherte Markierung, ohne Fehlercode.
  - `BackupTests.restoreKeepsMissingMarksExceptOnRecordsKeptOut` – Wiederherstellen behält Markierungen, außer bei Platten, die laut Sicherung „Nicht im Regal“ sind.
  - `CabinetTests.inactiveCabinetsAreSkippedWhenSortingIn` – „Im Regal anzeigen“ für eine Platte in einem deaktivierten Regal nennt das Regal statt eines Platzes.
- Migration V12 → V13 (neues Modell `MissingCopyMark`) über die bestehenden Migrations-Tests, die ältere Datenbanken bis zum aktuellen Schema öffnen.
- **Laufende App** (`--demo`, frischer Build, Klicks per Bedienungshilfen und Maus-Ereignissen):
  - Regalseite: rote Übersicht „1 vermisst“; „Im Fach zeigen“ springt ins Fach „A – Be“ und wählt die Platte.
  - Die markierte Platte trägt in der Tabelle und unter dem Streifen das Etikett und ist im Streifen als roter Umriss gezeichnet.
  - „Platte hinzufügen“: Pause markiert (Zeile blass, Etikett, roter Knopf, Unterzeile „· 1 vermisst“ bleibt sichtbar), ein zweiter Klick hebt auf.
  - Nach dem Schließen steigt die Übersicht auf „2 vermisst“; „+“ bei einer markierten Platte sortiert ein und senkt sie wieder auf 1.
  - Gefunden und behoben dabei: die Übersicht war schwarz statt rot, die Unterzeile schnitt „vermisst“ ab.

## Nicht geprüft (dieser Durchgang)

- In der laufenden App nicht angeklickt: Platzsuche-Karte einer markierten Platte (Hinweis, Nachbar „– vermisst“, „Gefunden“), Rechtsklick-Menü der Fach-Tabelle, Schließen von „Platte hinzufügen“ bei Änderungen im Einstellungsfenster, Regalseite nach „Alles zurücksetzen“. Die Logik dahinter ist über Tests bzw. Code-Durchsicht abgedeckt.
- Das Umstellen der echten Datenbank auf V13 – die eigene Sammlung wurde nicht geöffnet; das passiert beim ersten Start der neuen Version.
- Eine fehlschlagende Datenbank-Speicherung lässt sich nicht gezielt herbeiführen; geprüft ist der Meldungstext.

# Älterer Stand · 24.09.2026 (Grenzfall-Prüfung)

Stand nach drei Grenzfall-Prüfungen: Code-Durchsicht, Szenario-Tests gegen die echten Services und Start der laufenden App (Details in [AENDERUNGEN.md](AENDERUNGEN.md)).

## Ergebnis

- Gesamte Testsuite: **158 Tests in 13 Suites, 0 Fehler** (Debug; die Szenario-Tests zusätzlich mit `-O` gemessen).
- Neu: `ScenarioTests.swift` (6 Tests), jeweils auf einer eigenen Datenbank im Arbeitsspeicher – nie echte Sammlung, Schlüsselbund oder Einstellungen:
  - Abgleich ohne Netz: drei Versuche, dann Meldung „nicht erreichbar“, nichts gespeichert; der nächste Abgleich mit Netz lädt Collection, Sammlungswert und Tracklisten.
  - Netz weg während der Tracklisten: Meldung „2 fehlen …“, nichts falsch als geladen markiert, der nächste Lauf holt sie nach.
  - Discogs bremst (429, `Retry-After: 1`): wird abgewartet, keine Fehlermeldung.
  - Fächer und Exemplare, die woanders gelöscht werden (Regal verkleinert, verkaufte Platte gelöscht, Sicherung ohne das Regal wiederhergestellt), melden das – darauf verlassen sich „Rückgängig“ und „Exemplar bearbeiten“.
  - „Standorte zurücksetzen“ bei offenem „Platte hinzufügen“: Hinzufügen funktioniert danach weiter.
  - 10.000 Platten, 84 Fächer (Zeiten mit `-O`): Abgleich 3,9 s (Hintergrund), Wiederholung 4,0 s, Sortieren 1,5 s, Beschriftungen 1,2 s, Platz finden 0,5 s, Statistik 0,4 s (Hintergrund), Suche pro Tastendruck 35 ms, Export-Tabelle 4,0 s, CSV 0,3 s, PDF 2,5 s, Sicherung 1,5 s.
- Laufende App (`--demo`, frischer Build): Start, Collection mit 56 Beispielplatten, reguläres Beenden; Protokoll ohne Fehler, echte Sicherungen unberührt.

## Nicht geprüft (dieser Durchgang)

- Klicken in der laufenden App (dafür fehlen die Bedienungshilfen-Rechte); die Abläufe dahinter sind über die Szenario-Tests abgedeckt.
- „Alles zurücksetzen“ in Tests: es löscht den echten Discogs-Token aus dem Schlüsselbund und die echten Einstellungen, deshalb bewusst nicht automatisiert.
- Echter Abgleich mit Discogs und echtes Abschalten des Netzes (dafür müssten Systemeinstellungen geändert werden).

# Älterer Stand · 24.09.2026

Stand nach „Mehrere Regale“, Export, Sicherung, Daten-Tab und der Überarbeitung von Fehlermeldungen und Absturz-Protokoll (Details in [AENDERUNGEN.md](AENDERUNGEN.md)).

## Ergebnis

- Debug-Build: erfolgreich, keine Compilerfehler.
- Gesamte Testsuite (`xcodebuild … test`): **148 Tests in 12 Suites, 0 Fehler**; Release-Build kompiliert..

| Testdatei | Tests | Schwerpunkt |
|---|---|---|
| `LibraryTests.swift` | 43 | Positionen, Sortierung, Speicherung, Fehlermeldungen, Absturz-Auswertung, Demo-Sammlung |
| `DiscogsSyncTests.swift` | 32 | Abgleich, Ordner, Wantlist, Pagination, Konten, `Retry-After`, Migration |
| `StatisticsTests.swift` | 27 | Auswertungen, Wertverlauf, Migrationen |
| `CabinetTests.swift` | 13 | Mehrere Regale, Größenänderung, Standorte zurücksetzen |
| `SettingsTests.swift` | 13 | Discogs-Token speichern, testen und entfernen; Reihenfolge der Statistik |
| `BackupTests.swift` | 12 | Sichern, Wiederherstellen, Aufbewahrung, Dateinamen |
| `ExportTests.swift` | 8 | CSV (Maskierung, BOM, Formel-Schutz), Reihenfolge, Spalten, PDF |

Beim Start des Test-Hosts erscheinen systemseitige Meldungen zu `com.apple.linkd.autoShortcut` und ein CoreData-Hinweis „Persistent History … has to be truncated“ aus den Migrationstests; beides sind keine Testfehler.

- Demo in der laufenden App (Debug-Build, `--demo`) geprüft: Collection mit gezeichneten Covern, Statistik mit Wertverlauf, Regal mit zwei Regalen; das Banner schließt auf allen drei Seiten bündig mit dem Inhalt ab.

## Nicht geprüft

- „Demo neu starten“ in der laufenden App ausgelöst: neue Instanz startet als Demo, alte beendet sich, keine falsche Meldung „nicht normal beendet“, echte Einstellungen ohne Demo-Einträge. Mit einer zweiten laufenden Instanz wird der Neustart abgelehnt (Hinweis und Protokolleintrag geprüft). Vollständiger Weg in der laufenden App: echte App geöffnet (841 Exemplare) → „Demo starten …“ bestätigt → Demo mit 56 Beispielplatten, echte Instanz regulär beendet → „Demo beenden“ → wieder 841 Exemplare / 868 Wantlist-Einträge → mit ⌘Q beendet. Keine falsche Meldung „nicht normal beendet“, Laufmarkierung am Ende entfernt, keine Demo-Einträge in den echten Einstellungen, Demo-Zeilen im Protokoll mit „Demo ·“ markiert.
- Keine Codesign-Prüfung und kein Live-Sync mit Discogs für diesen Stand.
- Nicht in der laufenden App durchgespielt: Zurücksetzen während des Tracklisten-Downloads, automatischer Export und Sicherung in iCloud Drive, nicht erreichbare Ordner.
- Der Absturz-Handler (eigener Signal-Stack, Versionsangabe im Absturzblock) wurde nicht mit einem echten Absturz ausgelöst; getestet ist, dass der nächste Start einen Absturzblock im Protokoll richtig erkennt.

# Frühere Prüfstände

Die folgenden Abschnitte dokumentieren ältere Versionen und bleiben als Verlauf stehen. Einzelne Angaben gelten nicht mehr: Favoriten, manuell angelegte Exemplare und Fach-Kapazitäten wurden entfernt, das Deployment Target ist heute macOS 27.0, und die Einzelpreis-Abfragen der Statistik gibt es nicht mehr.

# Wantlist-Überarbeitung · 21.09.2026

- Vollständiger Debug-Build und XCTest erfolgreich: **74 Tests, 0 Fehler**.
- Finaler Release-Build für Apple Silicon und Intel erfolgreich; Codesign-Prüfung bestanden.
- Drei neue Tests prüfen chronologische Sortierung trotz unterschiedlicher ISO-8601-Zeitzonen, Groß-/Kleinschreibung und Akzente in der Wantlist-Suche sowie bereichsspezifische Sync-Statusmeldungen.
- Quellpfade für Appstart, Metadatenabgleich, Sammlung und Einstellungen geprüft: Kein automatischer oder bereichsfremder Wantlist-Sync bleibt erreichbar; der einzige UI-Aufruf von `.wantlist` liegt in `WantlistView`.
- Debug-Demo mit In-Memory-Daten visuell geprüft: zwei Spalten bei normaler Fenstergröße, drei Spalten bei maximiertem Fenster, korrekte Reihenfolge und Suche „4 strings“ mit zwei Treffern.
- Kein Live-Sync und keine Änderung der produktiven Discogs- oder SwiftData-Daten für diese Überarbeitung.

# Statistik-Erweiterung · 20.09.2026

Finale Version: 66 Tests ohne Fehler; Debug- und Release-Build erfolgreich. Details zur Erweiterung, Migration und Abgrenzung der Live-API-Prüfung stehen in [STATISTIK.md](STATISTIK.md). Die folgenden Abschnitte dokumentieren die vorherige Projektversion.

# Discogs-Erweiterung – Validierung am 20.09.2026

## Ergebnis

- Debug-Build und XCTest: erfolgreich, **43 Tests, 0 Fehler**.
- Release-Build (arm64): erfolgreich.
- Beide finalen Builds: **keine Compiler-/Build-Warnungen oder -Fehler**.
- Xcode 27.0 (27A266a), Swift 6, macOS auf Apple Silicon.
- Der ungenutzte App-Intents-Extraktionsschritt ist mit `LM_SKIP_METADATA_EXTRACTION = YES` ausgeschaltet. Es werden keine App Intents angeboten. Die Einstellung folgt dem [Swift-Build-Task-Producer](https://github.com/swiftlang/swift-build/blob/main/Sources/SWBApplePlatform/AppIntentsMetadataTaskProducer.swift).
- Beim XCTest-Hoststart erscheinen systemseitige `com.apple.linkd.autoShortcut`-Verbindungsdiagnosen. Die Tests laufen dennoch erfolgreich; dies sind keine Compilerdiagnosen.

## Neue Tests

24 zusätzliche Tests in `PlattenregalTests/DiscogsSyncTests.swift` prüfen:

1. Erstimport der Collection und Release-Metadaten.
2. Wiederholung ohne Änderungen, stabile Exemplar-UUID und unveränderte Anzahl.
3. Neue Releases.
4. Entfernte Collection-Mitgliedschaft bei erhaltenem Exemplar und Release.
5. Ordnerwechsel.
6. Neue Ordner.
7. Umbenannte Ordner bei stabiler externer ID.
8. Gelöschte Ordner ohne Verlust lokaler Exemplare.
9. Wantlist hinzufügen und gemeinsame Release-Entität.
10. Wantlist entfernen ohne Löschung des Releases.
11. Zwei Instanzen einer identischen Release-ID.
12. Pagination-Abbruch auf Seite 2 ohne lokale Änderungen.
13. Fach und Position bleiben bei Update, Verschiebung und Entfernung erhalten.
14. Einzelordner-Sync entfernt keine Collection-Mitgliedschaft anderer/verschobener Exemplare.
15. Wechsel Wantlist → Collection.
16. Isolation verschiedener Accounts.
17. Migration einer realen V1-Dateidatenbank nach V2, anschließend Sync mit Erhalt lokaler Daten.
18. Vollständige Collection-Pagination und Ablehnung doppelter Instanz-IDs.
19. Vollständige Wantlist-Pagination.
20. `Retry-After` als Sekunden und HTTP-Datum.
21. 2.000 Exemplare importieren und erneut synchronisieren: keine Duplikate oder falschen Updates.
22. Abgebrochener Merge ohne Änderungen.
23. Unplatziertes Exemplar bearbeiten und anschließend im KALLAX platzieren.
24. Fehler der Wantlist nach bereits vollständig geladener Collection: kein Teil-Commit.

Die 19 bestehenden Positions-, Sortierungs-, Speicher-, Mapping- und Netzwerkfehler-Tests bestehen ebenfalls. Der bestehende Wiederöffnungstest verwendet nun das aktuelle Schema V2; der neue Migrationstest erzeugt explizit V1.

## Interaktiver Live-Test

Der vorhandene persönliche Keychain-Token wurde über die App benutzt, ohne ihn auszulesen oder auszugeben. Die Test-App lief mit `--demo` und ausschließlich einer In-Memory-Datenbank. Die produktive Sammlung und Discogs selbst wurden nicht verändert.

- Identity erkannt.
- Vollständiger Import: **839 Collection-Instanzen**, **868 Wantlist-Einträge**, **7 Ordner**.
- Collection und Wantlist jeweils über **9 Seiten** geladen.
- Vollständiger Wiederholungssync im finalen Build: **0 hinzugefügt, 0 aktualisiert, 0 entfernt; 0 Ordneränderungen**.
- Neue Exemplare werden ohne KALLAX-Zuweisung angezeigt; die vier lokalen Demo-Exemplare bleiben zusätzlich erhalten.
- Ordnerfilter „Trance/Dance“ zeigt **413 Exemplare**.
- Mehrfach vorhandene Release-IDs werden als separate Karten angezeigt.
- Navigation und Ordnerfilter funktionieren während laufender Requests.
- Settings zeigen Account, letzte Sync-Zeiten, Mengen, Ordner und die separaten Sync-Aktionen.

## Speicherung und Sicherheit

V1 bleibt eingefroren. V2 ergänzt optionale Discogs-Felder an `Release` und `RecordCopy` sowie `DiscogsFolder`, `WantlistEntry` und `DiscogsAccount`. Die existierende Store-Datei wird migriert, niemals zurückgesetzt.

Alle Seiten werden zuerst vollständig im Speicher gesammelt und validiert. Beim Full Sync werden auch Ordner und Wantlist vor dem ersten Schreibvorgang geladen. Der eigentliche Merge läuft in einem Worker-Task mit eigenem SwiftData-Kontext; sämtliche Änderungen werden mit einem Save atomar gespeichert. Fehler oder Abbruch vor diesem Save verwerfen die Änderungen. Der Kontext einer geöffneten Bearbeitung wird nicht zurückgerollt.

Entfernte Collection-Instanzen bleiben als lokale Exemplare erhalten, verlieren aber ihre aktive Discogs-Zuordnung. Der Filter „Alle lokalen Exemplare“ zeigt sie weiterhin; Discogs-Filter blenden sie aus. Ein einzelner Ordner-Sync kann nur das Verlassen dieses Ordners feststellen, nicht eine Entfernung aus der gesamten Collection.

## Grenzen der Prüfung

- Nicht zusätzlich auf Intel-Hardware oder macOS 14 ausgeführt.
- Keine Notarisierung oder App-Store-Auslieferung.
- Die offizielle Discogs-Developer-Webseite lieferte beim Dokumentationsabruf HTTP 403. Die verwendeten Endpunkte, Authentifizierung, Nutzdaten und Pagination wurden zusätzlich über den authentifizierten Live-Test verifiziert.
- Die Discogs-API liefert keinen transaktionalen Snapshot über mehrere Seiten. Geänderte Gesamtzahlen, Seitenzahlen und Duplikate werden abgewiesen; parallele Änderungen mit gleichbleibender Anzahl können nicht lückenlos erkannt werden.
