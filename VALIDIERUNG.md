# Aktueller Stand · 31.10.2026 (Widget „Platte des Tages“)

Projektversion **1.0.0 (102026)**, Schema **V18** (unverändert).

- **Geändert seit der letzten DMG:** Widget „Platte des Tages“ (neues Erweiterungsziel, klein/mittel/groß, Klassisch und Modern, Klick öffnet die Platte im Regal), gemeinsame Designstufen für App und Widget (siehe AENDERUNGEN).
- **Verifikation:** Debug- und Release-Build ohne Warnung, nur arm64, Signatur und Berechtigungen geprüft; 263 Tests bestanden; Erweiterung bei macOS registriert; Klick-Weg in der Demo geprüft; Sandbox-Ausnahme im echten Ordner geprüft (Nachbarordner verweigert); Widget-Ansichten als Bilder angesehen; Laufzeit mit 5 000 Platten gemessen (20 ms ohne neue Auswahl).
- **Lokalisierung:** 938 Einträge, alle mit Englisch, 6 neu; jeder Text im Code von App und Widget hat einen Eintrag.
- **App-Protokoll** 31.10.: kein `ERROR`. **macOS-Absturzberichte:** keine.
- **DMG:** noch nicht neu gebaut; die Handbuch-PDFs im Repository sind noch ohne die neue Zeile.
- **Nicht geprüft:** das Widget auf dem Schreibtisch mit der echten Sammlung (braucht die neue App installiert).

# Aktueller Stand · 31.10.2026 (Im Hintergrund weiterlaufen, DMG)

Projektversion **1.0.0 (102026)**, Schema **V18** (unverändert).

- **Geändert seit der letzten DMG:** Im Hintergrund weiterlaufen: Nach ⌘Q bleibt die Schallplatte in der Menüleiste, ohne Dock-Symbol. Ganz beenden mit ⌥⌘Q oder über das neue Menü der Schallplatte. Neu ist auch „Bei der Anmeldung öffnen“. Fensterinhalt und Cover-Speicher werden im Hintergrund freigegeben (siehe AENDERUNGEN).
- **Verifikation:** Debug-Build ohne Warnung, 248 Tests bestanden (neu: `runningInTheBackgroundIsOnByDefaultAndPersists`, `quitRequestsGoIntoTheBackgroundOnlyWhenTheyMay`). In der Demo alle Wege zwischen Vorder- und Hintergrund geprüft, Speicher mit der echten Sammlung gemessen (242 → 110 MB).
- **Lokalisierung:** 932 Einträge, alle mit Englisch, 15 neu; jeder Text im Code hat einen Eintrag.
- **App-Protokoll** 31.10.: kein `ERROR`. **macOS-Absturzberichte:** keine.
- **DMG:** neu gebaut und geprüft (Abbild gültig, 1.0.0 (102026), nur arm64, ab macOS 27.0, Signatur gültig, Berechtigungen aus den unveränderten Build-Einstellungen, beide Handbücher identisch, kein Prüfcode, neuer Stand im Programm). Release-App aus der DMG mit der echten Sammlung gestartet (852 Exemplare) und mit echten Tastendrücken über System Events bedient: ⌘Q → im Hintergrund, ⌥ Leertaste und Tippen ohne Fehler, erneutes Öffnen → Vordergrund, ⌥⌘Q → beendet.
- **Nicht geprüft:** echte Mausklicks auf das Menü der Schallplatte, eine echte Anmeldung nach Neustart des Macs, echtes Abmelden. Das Suchfenster aus der DMG wurde nicht per Bild angesehen.

# Aktueller Stand · 30.10.2026 (Suche in der Menüleiste, DMG)

Projektversion **1.0.0 (102026)**, Schema **V18** (unverändert).

- **Geändert seit der letzten DMG:** Regal-Reiter unten links über dem Fachinhalt, bündig mit den Covern; Suche in der Menüleiste (Schallplatte, ⌥ Leertaste, Mini-Regal, ↩ zur Regalseite), abschaltbar unter Allgemein (siehe AENDERUNGEN).
- **Verifikation:** Debug-Build ohne Warnung, 246 Tests bestanden (neu: `firstMatchesAreTheStartOfTheSortedList`, `menuBarSearchAndShortcutAreOnByDefaultAndPersist`). Demo in Klassisch per Schnappschuss, Modern hell und dunkel per Bildschirmaufnahme; Tasten, Wiederöffnen, Hauptfenster offen/im Dock/geschlossen, echtes ⌥ Leertaste, Ein- und Ausschalten, zwei Instanzen.
- **Lokalisierung:** 917 Einträge, alle mit Englisch, 16 neu; jeder Text im Code (1187) hat einen Eintrag.
- **App-Protokoll** 30.10.: kein `ERROR`. **macOS-Absturzberichte:** keine.
- **DMG:** neu gebaut und geprüft (Abbild gültig, Version, arm64, ab macOS 27.0, Signatur, Berechtigungs-Einstellungen unverändert, beide Handbücher identisch, kein Prüfcode, neuer Stand im Programm). Release-App aus der DMG mit der echten Sammlung gestartet, Suche per ⌥ Leertaste ausprobiert, sauber beendet.
- **Nicht geprüft:** echte Mausklicks auf das Menüleisten-Symbol, mehrere Bildschirme, Vollbild-Apps.

# Aktueller Stand · 26.10.2026 (Modern unter der Leiste, DMG)

Projektversion **1.0.0 (102026)**, Schema **V18** (unverändert).

- **Geändert seit der letzten DMG:** Leiste wird beim Wechsel zur Statistik fließend schmaler; Modern: Collection, Wantlist und Statistik laufen unter die Leiste und blenden weich aus, Seiten beginnen an der Toolbar-Kante; gewählte Option halbfett in Textfarbe, ohne Rand; Einstellungen in Modern ohne durchscheinende Karten (siehe AENDERUNGEN).
- **Verifikation:** Debug-Build ohne Warnung, 244 Tests bestanden. In der Demo Bild für Bild bzw. per Aufnahme geprüft (Modern hell und dunkel, Klassisch hell).
- **Lokalisierung:** 901 Einträge, alle mit Englisch; zehn verwaiste Einträge entfernt (keiner mehr in der Oberfläche).
- **App-Protokoll** 26.10.: kein `ERROR`. **macOS-Absturzberichte:** keine.
- **DMG:** neu gebaut und geprüft (Abbild gültig, 1.0.0 (102026), nur arm64, ab macOS 27.0, Signatur gültig, Berechtigungen unverändert, beide Handbücher identisch, kein Prüfcode, neue Bausteine im Programm). Release-App aus der DMG mit der echten Sammlung gestartet (852 Exemplare, Klassisch), sauber beendet, Fenstergröße zurückgeschrieben. Danach nur noch der Katalog bereinigt und die DMG damit ein zweites Mal gebaut.
- **Nicht geprüft:** Herunterziehen zum Aktualisieren, Vollbild, Modern mit der echten Sammlung.

# Aktueller Stand · 26.10.2026 (runde Knöpfe der Regalseite schalten um)

Projektversion **1.0.0 (102026)**, Schema **V18** (unverändert).

- **Geändert:** Regalseite mit einem einzigen Fenster-Zustand (`ShelfPanel`); runde Knöpfe öffnen, schließen und wechseln, mit Auswahlrand solange offen; `appPanel.onDismiss` auch beim Ersetzen (siehe AENDERUNGEN).
- **Verifikation:** Debug-Build ohne Warnung, 244 Tests bestanden (neu: `ShelfPanelTests`). Demo in Klassisch und Modern über die Bedienungshilfen geprüft, Zustand und Bild nach jedem Schritt.
- **Lokalisierung:** 911 Einträge, alle mit Englisch, zwei neu.
- **App-Protokoll** 26.10.: kein `ERROR`. **macOS-Absturzberichte:** keine.
- **DMG:** neu gebaut und geprüft (Abbild, Version, arm64, Signatur, Berechtigungen, PDFs, neuer Stand im Programm, Start aus der DMG im Demo-Modus mit den Umschalt-Fällen). Nicht mit der echten Sammlung gestartet, weil die echte App lief.
- **Nicht geprüft:** echte Mausklicks, Dunkelmodus.

# Aktueller Stand · 26.10.2026 (Toolbar als eine Leiste)

Projektversion **1.0.0 (102026)**, Schema **V18** (unverändert).

- **Geändert:** Rubriken und Suche als eine Leiste, Suche hinter einer Lupe, die federnd aufklappt (siehe AENDERUNGEN).
- **Verifikation:** Debug-Build, 240 Tests bestanden; Demo in Klassisch und Modern angesehen, Öffnen per ⌘F und Schließen per Esc in Einzelbildern geprüft.
- **Lokalisierung:** kein neuer Text; „Suchen“ ist übersetzt, der Tooltip „Suchen (⌘F)“ wird daraus gebaut.
- **App-Protokoll** 26.10.: kein `ERROR`. **macOS-Absturzberichte:** keine.
- **Handbuch:** Bilder (de/en) und beide PDFs neu erzeugt, mit der neuen Leiste.
- **DMG:** neu gebaut und geprüft (Abbild, Version, arm64, Signatur, Berechtigungen, PDFs, Start aus der DMG mit der echten Sammlung).
- **Nicht geprüft:** Dunkelmodus in Modern, Vollbild, Klick auf die Lupe mit der Maus. Das „shog“ im Suchfeld beim Start aus der DMG war eine Eingabe des Nutzers.
- **Code-Prüfung danach:** Suchleiste sprang bei Änderungen ohne Klick, Lupe hüpfte bei Rubrikwechseln – behoben; zwölf Randfälle in der Demo durchgespielt (siehe AENDERUNGEN).
- **Danach:** zentrale Öffnen-Animation (`openAnimation`), auch der Fächer des runden Knopfs federt; Debug-Build und 240 Tests bestanden, in der Demo geprüft. Die DMG in `dist/` ist danach neu gebaut und geprüft (Stand nach der Code-Prüfung).

# Aktueller Stand · 26.10.2026 (öffentliches Repository)

Projektversion **1.0.0 (102026)**, Schema **V18** (unverändert). Kein App-Code geändert.

- **Lizenz:** MIT (`LICENSE`).
- **Historie:** `outputs/`, `Marketing/` und `.claude/settings.local.json` aus allen Commits von `main` entfernt; Sicherung als Bundle auf dem Schreibtisch.
- **Geprüft am frischen Klon:** keine lokalen Pfade, keine Token-Muster, nur Demo-Bilder, Build und 240 Tests bestanden.
- **Nicht geprüft:** das Hochladen zu GitHub selbst (noch kein Remote eingerichtet).

# Aktueller Stand · 26.10.2026 (Prüfung der ganzen App, GitHub-Bereitschaft)

Projektversion **1.0.0 (102026)**, Schema **V18** (unverändert). Ein erfolgreicher Testlauf beweist keine allgemeine Absturzfreiheit.

## Umfang und Befunde

- **Gelesen:** `DiscogsAPIClient`, `DiscogsSyncService` (+`Merge`), `LibrarySchemas`, `LibraryStorage`, `KeychainStore`, `ShelfBackup`, `ShelfBackupService`, `ShelfAutoBackup`, `ExportWriters`, `ScheduledExportService`, `FolderAccess`, `PositionService` (Verschieben, Herausnehmen, Markierungen), `CabinetService.resize`, `TVLink`, `AppleTVLink`, Absturz-Handler in `AppLog`. Ansichten nur per Mustersuche (Absturzmuster, Divisionen, Bereiche).
- **Befunde (behoben):** Tracklisten-Download lief bei dauerhaft abgelehnten oder unlesbaren Antworten durch alle Releases; Abbruch der Kopplung während der Code-Prüfung meldete einen Fehler und ließ den Dienst an.
- **Befund (offen, beschrieben):** Kopplung Mac ↔ Apple TV ohne PAKE (siehe README „Apple TV“).
- **Fehlermeldungen:** eine neue Meldung nutzt den vorhandenen, übersetzten Text „Noch nicht alle Tracklisten geladen …“.
- **Lokalisierung:** kein neuer Text, Katalog vom Release-Build unverändert.
- **App-Protokoll** 26.10.: kein `ERROR`. **macOS-Absturzberichte:** keine.
- **Nicht geprüft:** Ansichten Zeile für Zeile; die Kopplung mit einem echten Apple TV nach der Korrektur.

## Verifikation

- Debug- und Release-Neubau ohne Warnung, 240 Tests bestanden, Thread Sanitizer ohne Befund.
- Frischer Klon des Repos baut und besteht die Tests.

# Aktueller Stand · 26.10.2026 (Gezeichnete Cover, Hinweise auf der Regalseite)

Projektversion **1.0.0 (102026)**, Schema **V18** (unverändert, die Einstellung liegt in den User Defaults). Ein erfolgreicher Testlauf beweist keine allgemeine Absturzfreiheit.

## Umfang und Befunde

- **Gelesen und geändert:** `AppPreferences`, `CoverView` (`Release.shownCoverURL`), `AppearanceSettingsView`, `KallaxView` (Hinweise als ein Block), alle Ansichten mit `CoverView` bzw. Ambient-Covern, `SettingsTests`, `Localizable.xcstrings`.
- **Gelesen, unverändert:** `CoverCache` (zeichnet `plattenregal-demo://`-Adressen ohne Download), `DemoData`/`DemoCover`, `TVLink`/`AppleTVLink` (übertragen keine Cover).
- **Fehlermeldungen:** keine neuen.
- **Lokalisierung:** 909 Einträge, alle mit Englisch, drei neu.
- **App-Protokoll** 26.10.: kein `ERROR`; eine Warnung „nicht normal beendet“ stammt von einem Prüflauf, der hart beendet wurde. **macOS-Absturzberichte:** keine.
- **Befunde (behoben, Nachprüfung):** Farbton gezeichneter Cover lief bei sehr großen IDs über (`DemoCover.hueDegrees`); gezeichnete Cover entstanden nacheinander im Actor statt parallel.
- **Nicht geprüft:** der Schalter in den Einstellungen im Bild; die Cover der Statistik beim Umschalten.

## Verifikation

- Debug-Build, 239 Tests bestanden.
- Demo-Regalseite und echte Collection mit gezeichneten Covern im Bild geprüft; Umschalten zur Laufzeit in Collection (Raster, Liste), Fach (Raster, Tabelle) und Wantlist in beide Richtungen.

# Aktueller Stand · 24.10.2026 (Tooltips in Collection und Wantlist)

Projektversion **1.0.0 (102026)**, Schema **V18** (unverändert). Prüfung nach dem Verstecken verborgener Seiten im `PageStack` und dem Entfernen der Tooltips in Collection und Wantlist. Ein erfolgreicher Testlauf beweist keine allgemeine Absturzfreiheit.

## Umfang und Befunde

- **Gelesen und geändert:** `PageStack` (verborgene Seiten `isHidden` nach dem Ausblenden), `CollectionView`, `WantlistView`, `RecordCard` (`MatchedTrackLine`), `CoverView`, `Localizable.xcstrings`.
- **Gelesen, unverändert:** `ShelfContentsView`, `StatisticsFacts`, `StatisticsMovableArea` (Herkunft der durchscheinenden Tooltips), `SecondaryClicks`.
- **Befund (behoben):** Tooltips verborgener Seiten (Regalfach, Statistik) erschienen über Collection und Wantlist.
- **Fehlermeldungen:** keine neuen.
- **Lokalisierung:** 904 Einträge, alle mit Englisch; drei verwaiste gelöscht, keine neuen Texte.
- **Nicht geprüft:** Maustest mit der endgültigen Fassung; die echte App mit der eigenen Sammlung.

## Verifikation

- Debug-Build ohne Warnungen, alle Tests bestanden.
- Demo: Maustest (64 Punkte) vorher 17 Treffer auf der Collection; Zwischenstände siehe AENDERUNGEN. Seitenwechsel-Zeit gemessen, ohne spürbaren Unterschied.

# Aktueller Stand · 24.10.2026 (Rechtsklick im Cover-Raster)

Projektversion **1.0.0 (102026)**, Schema **V18** (unverändert). Prüfung nach der Korrektur von `GridSecondaryClicks`. Ein erfolgreicher Testlauf beweist keine allgemeine Absturzfreiheit.

## Umfang und Befunde

- **Gelesen und geändert:** `SecondaryClicks.swift` (`GridSecondaryClicks`, neu `GridSecondaryClickCell`), `UtilityTests`.
- **Gelesen, unverändert:** `CollectionView`, `PullToRefresh`, `PageStack` (verborgene Seiten nehmen keine Klicks an), `FloatingControls` (Klick-Beobachter gibt jedes Ereignis weiter), `DiscogsSyncView`, `DiscogsSyncService` samt Merge, `LibraryRecords`.
- **Befund (behoben):** Beim Neuaufbau eines Cover-Rasters in einem Rutsch löschte das späte Verschwinden der alten Zellen die Einträge der neuen; der Rechtsklick fand danach keine Zelle mehr (in der Demo nachgestellt: 0 von 18).
- **Fehlermeldungen:** keine neuen.
- **macOS-Absturzberichte:** keine.
- **App-Protokoll** 24.10.: kein `ERROR` (Zeilen „EXPERIMENT“ stammen von den Demo-Prüfläufen).
- **Lokalisierung:** 907 Einträge, alle mit Englisch; keine neuen Texte.
- **Nicht geprüft:** der auslösende Sync in der echten App.

## Verifikation

- Debug-Build ohne Warnungen, alle 236 Tests bestanden.
- Demo mit vorübergehendem Prüfcode: Rechtsklick nach Neuaufbau des Rasters, nach Scrollen und nach Überziehen oben jeweils mit Menü auf der richtigen Platte.
- DMG 1.0.0 (Build 102026) mit dieser Korrektur: Prüfsumme gültig, arm64, Signatur in Ordnung, Mindestsystem 27.0, Handbücher enthalten, kein Prüfcode im Programm.

# Aktueller Stand · 24.10.2026 (Version 1.0.0, Altlasten)

Projektversion **1.0.0 (102026)**, Schema **V18**. Prüfung nach Umstellung der Fenster-Kennung, `LegacyDefaults`, Aufräumen des Demo-Ordners, festen Test-Einstellungsnamen und der Versionsnummer. Ein erfolgreicher Testlauf beweist keine allgemeine Absturzfreiheit.

## Umfang und Befunde

- **Gelesen und geändert:** `PlattenregalApp`, `DemoMode`, `WelcomeView`, neu `LegacyDefaults`, `SettingsTests`, `guide-screenshots.swift`, Projektdatei, Handbuch-HTML, Webseite.
- **Gelesen, unverändert (räumen selbst auf):** `AppLog` (Rollen), `CoverCache.prune` (Alter und Größe), `ShelfAutoBackup` (Anzahl und Tage), `ScheduledExport` (ersetzt dieselbe Datei), `AppleTVLink` (Geräteliste).
- **Befunde (behoben):** Demo und echte App teilten die Fenstergröße. Hunderte veraltete Einstellungen früherer Versionen, 459 leere Einstellungsdateien aus Tests, Debug-Schnappschüsse und alte Test-Datenbanken im temporären Ordner, verwaiste Build-Ordner.
- **Fehlermeldungen:** keine neuen. Neue Protokollzeile „N veraltete Einträge früherer Versionen entfernt“ (nur wenn N > 0; in Testläufen schweigt das Protokoll, daher nicht im Protokoll gesehen).
- **macOS-Absturzberichte:** keine.
- **App-Protokoll** 24.10.: kein `ERROR`.
- **Lokalisierung:** 907 Einträge, alle mit Englisch; keine neuen Texte.
- **Nicht geprüft:** die echte App mit der echten Sammlung gestartet, `marketing-shots.sh` und `guide-screenshots.swift` ausgeführt.

## Verifikation

- Sauberer Debug-Build ohne Warnungen, alle 234 Tests bestanden.
- Demo-Fenster verändert und neu gestartet: eigene Größe unter `demo`, `main` unverändert. Probe-Einträge in den echten Einstellungen beim Start entfernt. Demo-Ordner beim normalen Start entfernt.
- DMG 1.0.0 (Build 102026): Prüfsumme gültig, arm64, Signatur in Ordnung, Mindestsystem 27.0, Handbücher mit 1.0.0, keine Debug-Schalter.

# Aktueller Stand · 24.10.2026 (Top 10 in der Statistik, erstes Vollbild)

Projektversion **1.1.2 (102026)**, Schema **V18** (unverändert). Prüfung nach den Änderungen vom 24.10. morgens: Top-Künstler und Labels als gemeinsamer Baustein mit genau 10 Kacheln; Petrol-Streifen unter der Toolbar gegen den hellen Streifen beim ersten Vollbild. Ein erfolgreicher Testlauf beweist keine allgemeine Absturzfreiheit.

## Umfang und Befunde

- **Gelesen und geändert:** `RankingBoard` (vorher `LabelBoard`), `StatisticsLayout`, `StatisticsView`, `StatisticsCharts` (`GroupStatisticsList` entfernt), `ArtistPodium` (entfernt), `AmbientGlow`, Projektdatei, `Localizable.xcstrings`.
- **Befund (behoben):** Der helle Streifen beim ersten Vollbild war keine Systemfläche, sondern die fehlende Toolbar: macOS zeigt ihr Vollbild-Fenster beim ersten Mal erst rund 0,5 s nach dem Übergang. Ein erster Versuch mit dem Streifen wirkte nicht, weil die Höhe innerhalb von `ignoresSafeArea` als 0 gemeldet wird; per Protokollausgabe gefunden und behoben (52 pt).
- **Fehlermeldungen:** keine neuen.
- **macOS-Absturzberichte:** keine Berichte `Plattenregal-*.ips` vorhanden.
- **App-Protokoll** 24.10.: kein `ERROR`. 7 Warnungen „vorige Sitzung nicht normal beendet“, alle Demo, 07:26–07:30 – von meinen Prüfläufen, die ich mit `kill` beendet habe.
- **Lokalisierung:** 907 Einträge (5 ungenutzte entfernt), alle mit Englisch, Platzhalter passen (im Englischen teils nummeriert). 8 als veraltet markierte Einträge wie am 23.10., nicht angefasst.
- **Nicht geprüft:** Vollbild in Klassisch dunkel und in Modern als Video, die Anordnung 5 × 2 bei 3 Spalten (kommt im Hauptfenster nicht vor), ein zweiter Bildschirm.

## Verifikation

- Sauberer Debug-Build ohne Warnungen, alle 233 Tests in 15 Suites bestanden.
- Bildschirmvideo des Wechsels ins Vollbild (Demo, Klassisch hell) vor und nach der Korrektur, Bild für Bild: vorher 0,5 s Creme unter der fehlenden Toolbar, nachher Petrol von Anfang an.
- Per `--snapshot`: Statistik mit Top-Künstlern und Labels oben (Klassisch hell, Modern dunkel), Collection in Klassisch dunkel und Modern hell; Fenster bei 1050 pt Breite.
- DMG 1.1.2 (Build 102026) neu ausgegeben: Prüfsumme gültig, arm64, Signatur in Ordnung, Mindestsystem 27.0, beide Handbücher, neue Bausteine enthalten, keine Debug-Schalter.

# Aktueller Stand · 23.10.2026 (Einheitliche Maße, Verlauf, Demo, Ranglisten)

Projektversion **1.1.2 (102026)**, Schema **V18**. Prüfung nach den Änderungen vom 23.10. abends: einheitliche Höhen, Linien, Schriftrollen und Bausteine; Verlauf wie „Platte hinzufügen“; Demo mit Beispiel für jeden Zustand; Ranglisten der Statistik bis Platz 20. Ein erfolgreicher Testlauf beweist keine allgemeine Absturzfreiheit.

## Umfang und Befunde

- **Gelesen und geändert:** `AppStyle` (Höhen, Linien, Schriftrollen, Symbole), alle Design-Bausteine mit festen Höhen, `SymbolTile`, `StepNumber`, `SmallRoundButton`, Statistik-Kacheln und Kurven, `ShelfHistoryView`, `AssignmentCard`, `DemoData`, `ArtistPodium`, `LabelBoard`, `StatisticsLayout`.
- **Befunde (behoben):** Rubriken-Leiste 30 pt, Suchfeld 34 pt; `controlHeight` stand veraltet auf 26. Auswahlränder 1/1,5/2 pt gemischt. Sparkline und Wertverlauf verschieden gezeichnet. Symbol-Plättchen, kleine runde Knöpfe und Schrittnummern je zwei- bis dreimal leicht anders nachgebaut. Der ganze Verlauf (seit 22.10.) war im Englischen unübersetzt (28 Texte), dazu die zwei neuen Texte von heute.
- **Fehlermeldungen:** keine neuen. Die Gründe im Verlauf („Seitdem bewegt“ usw.) sind unverändert, stehen jetzt als Marke statt als grauer Text.
- **macOS-Absturzberichte:** keine Berichte `Plattenregal-*.ips` vorhanden.
- **App-Protokoll** 23.10.: kein `ERROR`. 36 Warnungen „vorige Sitzung nicht normal beendet“, alle zwischen 17:46 und 18:05 (33 Demo, 3 echte App) aus früheren, abgebrochenen Läufen; die Demo-Läufe ab 22:11 für die Bildschirmfotos endeten alle normal („Beendet“).
- **Lokalisierung:** 912 Einträge, alle mit Englisch, Platzhalter passen. Acht Einträge sind als veraltet markiert und stammen von vor heute („ und “, „Cover“, „Die Spalten füllen …“, „In: “, „Speichern“, „von %lld“, „Weiter“, „Zurück“); nicht entfernt.
- **Nicht geprüft:** Modern am Bildschirm (`--snapshot` zeichnet kein Glas), „Rückgängig“ in der laufenden App angeklickt, die aufgeklappte Rangliste (lässt sich per Startargument nicht öffnen), Willkommensseite und „Sortierung prüfen“ mit den neuen Schrittnummern.

## Verifikation

- Debug-Build ohne Fehler, alle 233 Tests bestanden (der Demo-Test prüft jetzt jeden Zustand der Beispielsammlung).
- Per `--snapshot` angesehen: Collection, Regal, Statistik, Verlauf und „Platte hinzufügen“ in Klassisch hell; Collection hell und Verlauf dunkel in Modern.
- DMG 1.1.2 (Build 102026) neu ausgegeben: Prüfsumme gültig, arm64, Signatur in Ordnung, Mindestsystem 27.0, beide Handbücher, neue Texte (Deutsch und Englisch) enthalten, keine Debug-Schalter.

# Aktueller Stand · 20.10.2026 (Übergänge, Toolbar, Reihenfolge der Designs)

Projektversion **1.1.2 (102026)**, Schema **V16**. Prüfung nach den Änderungen vom 20.10. (Auswahl in den Umschaltern, Seiten-, Tab- und Regalwechsel, Toolbar im Takt der Seite, Klassisch oben in Darstellung, zwei Debug-Startargumente). Ein erfolgreicher Testlauf beweist keine allgemeine Absturz- oder Datenverlustfreiheit.

## Umfang und Befunde

- **Gelesen und geändert:** `GlassSegmentedPicker` (`Design/AppPickers.swift`), Übergangswerte in `AppStyle`, `PageStack`, `ToolbarSearchField`, `AppSearchField` (eigener Platzhalter), Tab-Wechsel in `AppSettingsView`, Regalwechsel in `KallaxView`, Reihenfolge in `SignatureDesign`, Debug-Startargumente in `RootView` und `AppSettingsView`.
- **Befunde beim Ansehen (behoben):** Die Seite kam zunächst von unten statt von oben (die Ebenen zählen nach unten). In den Einstellungen überschrieb eine äußere Animation die Zeiten des Übergangs, alter und neuer Tab lagen kurz übereinander. Im Umschalter verschwand die Beschriftung kurz ganz, später stand beim Abwählen kurz eine leere Pill. Das Suchfeld sprang zur Statistik ohne Ausblenden weg, weil macOS die Toolbar neu aufbaute. Alle Fälle sind behoben und in Bildfolgen nachgesehen.
- **Prüfmethode geändert:** Simulierte Klicks und Tastendrücke landeten im jeweils vorderen Fenster, auch wenn der Nutzer gerade am Mac arbeitete. Ein verdecktes Fenster zeichnet macOS nicht weiter, was im Bild wie ein Hänger aussah (Prozess bei 0 % CPU, Hauptthread wartend). Wechsel werden jetzt über `--preview-switch` und `--preview-switch-tab` (nur Debug) ausgelöst. Das Fenster bleibt dabei im Hintergrund.
- **Nicht geprüft:** Modern für Einstellungs-Tabs und Regalwechsel, Dunkel-Modus, „Bewegung reduzieren“ (nur im Code: dann nur Blenden), VoiceOver am Suchfeld in der Statistik (im Code verborgen), das DMG-Fenster im Finder.
- **macOS-Absturzberichte:** keine Berichte `Plattenregal-*.ips` vorhanden.
- **App-Protokoll** 20.10.: kein `ERROR`, kein Absturzblock. 14 Warnungen „vorige Sitzung nicht normal beendet“: 12 nach Demo-Läufen, die ich mit `pkill` beendet habe. 2 in der echten App (22:54 und 23:39), jeweils kurz nach dem DMG-Bau. Demo und echte App teilen die Laufmarkierung, deshalb meldet die echte App die beendete Demo als vorige Sitzung. Bekannt, nicht geändert.
- **Fehlermeldungen:** keine neuen Meldungen oder Protokollzeilen.
- **Lokalisierung:** per Skript – 856 Einträge, 8 veraltet, jeder aktive Eintrag mit englischer Übersetzung. Gegenüber dem Stand vor diesen Änderungen kein Eintrag neu, entfernt oder neu veraltet. Der selbst gezeichnete Platzhalter nutzt die vorhandenen übersetzten Texte.

## Verifikation

- `xcodebuild -scheme Plattenregal test` (Xcodes DerivedData): **206 Tests in 13 Suites bestanden**, 24 s, keine Compilerwarnung. Angepasst: `designsKeepTheirStoredValuesUnderTheNewNames` (Reihenfolge Klassisch, Modern).
- Bildfolgen aus der Demo: Regal → Collection, Collection → Statistik (Klassisch), Regal → Statistik (Modern), Wohnzimmer → Flur, Allgemein → Darstellung. Darstellung zeigt Klassisch oben.
- `Scripts/make-dmg.sh`: `hdiutil verify` in Ordnung, Signatur gültig, App-Binärdatei gleich dem Release-Build vom Stand `7184f77`, ohne Debug-Startargumente, PDFs byte-gleich.

# Aktueller Stand · 18.10.2026 (Handbuch, Tooltips, Demo-Cover, Startargumente)

Projektversion **1.1.2 (102026)**, Schema **V16**. Prüfung nach den Änderungen vom 17. und 18.10. (Handbuch in App und DMG, Hilfe-Menü, Discogs-Links in Klassisch, Tooltips, Demo-Cover, Aufnahme-Skript). Ein erfolgreicher Testlauf beweist keine allgemeine Absturz- oder Datenverlustfreiheit.

## Umfang und Befunde

- **Gelesen und geändert:** Hilfe-Menü und `Handbook` (`Views/WelcomeView.swift`), Discogs-Einstellungen, Tooltips in `RootView`, `DiscogsSyncView`, `StatisticsCards` und den Bausteinen in `AppAppearance` (Banner, Suchfeld, Stepper), `AppShortcuts.help`, Demo-Cover (`DemoData.swift`), Debug-Fenstergröße bei `--settings-tab` (`PlattenregalApp.swift`), Skripte für Handbuch, Bilder und DMG.
- **Befund (geklärt):** „Schnappschuss … nach 30 s kein Fenster“ (offen seit 09.10.) kam von der Reihenfolge der Startargumente: Ein Paar nach einem Schalter (`--demo -signatureDesign atelier`) lässt macOS `atelier` als zu öffnende Datei lesen, und die App zeigt dann kein Startfenster. Gegenprobe: dieselben Argumente mit Paaren zuerst – jedes Mal ein Fenster nach 4 s; `--demo` allein ebenfalls. Kein Fehler der App; README und Aufnahme-Skript ordnen die Argumente jetzt richtig.
- **Nebenwirkung (behoben):** Ein Schnappschuss mit `--settings-tab` stellte die gespeicherte Fenstergröße der echten App (`NSWindow Frame main`) auf 1050 × 772; wiederhergestellt auf 1223 × 793. Das Aufnahme-Skript sichert und stellt den Wert jetzt selbst zurück.
- **Bekannt, nicht geändert:** `--snapshot` zeichnet Schalter immer grau (auch mit App im Vordergrund ausprobiert); die Bilder meiden deshalb Schalter. Englische Menütexte setzen „…“ uneinheitlich („Enter Token …“ mit, „Start Demo…“ ohne Leerzeichen).
- **Nicht geprüft:** die neuen Tooltips in der laufenden App (der Bildschirm war gesperrt, nur im Code und per Build); das DMG-Fenster im Finder (Inhalt, Positionen und Signatur geprüft, Aufbau nachgebaut); ein echter Abgleich mit Discogs.
- **macOS-Absturzberichte:** keine neuen.
- **App-Protokoll** 17.–18.10.: kein Absturzblock. 14 `ERROR`, alle „Schnappschuss … nach 30 s kein Fenster“ aus den Versuchen zur Startargument-Reihenfolge; Warnungen „vorige Sitzung nicht normal beendet“ nach beendeten Demo-Läufen. „Handbuch geöffnet (Handbook.pdf)“ und „(Handbuch.pdf)“ aus der Prüfung des Hilfe-Menüs.
- **Fehlermeldungen:** Neu nur Protokollzeilen („Handbuch.pdf fehlt in der App“ als Warnung mit Signalton – kommt bei korrektem Build nicht vor). Die Skripte melden auf Deutsch (Plattenregal läuft noch, kein Schnappschuss, kein Handbuch in der App).
- **Lokalisierung:** per Skript – 909 Einträge, 59 veraltet, jeder aktive Eintrag mit englischer Übersetzung. Neu: „Handbuch“ (User Guide), „Erste Schritte“ (Getting Started, statt „Erste Schritte …“), „Verringern“/„Erhöhen“; entfernt: „Einstellungen (⌘,)“, „Neue Platte ziehen (⇧⌘R)“.

## Verifikation

- `xcodebuild -scheme Plattenregal test` (Xcodes DerivedData): **210 Tests in 13 Suites bestanden**, 25 s.
- Demo: Hilfe-Menü „Handbuch, Erste Schritte“ bzw. „User Guide, Getting Started“; Handbuch öffnet in der Sprache der App. Discogs-Links in Klassisch petrol, in Modern blau (Bildschirmfotos).
- `swift Scripts/guide-screenshots.swift`: 14 Bilder, alle angesehen; danach `NSWindow Frame main` wieder 1223 × 793.
- `Scripts/make-dmg.sh`: DMG mit App, Programme, „Handbuch“ und „User Guide“; `hdiutil verify` in Ordnung, PDFs byte-gleich, Signatur gültig.

# Aktueller Stand · 12.10.2026 (Durchsicht der ganzen App, Dokumentation, Fehlermeldungen, Fehlerprotokoll, Lokalisierung)

Projektversion **1.1.2 (102026)**, Schema **V16**. Alle Quelltexte der App gelesen. Ein erfolgreicher Testlauf beweist keine allgemeine Absturz- oder Datenverlustfreiheit.

## Umfang und Befunde

- **Gelesen:** alle Swift-Dateien der App – Modelle und Migrationen, Speicher, Discogs-Client und -Sync, alle Dienste (Positionen, Regale, Sicherung, Export, Zurücksetzen, Cover), Statistik, alle Seiten und Einstellungen, das Design-Modul.
- **Fehler (behoben):** „Alles zurücksetzen“ benachrichtigte die Seiten erst nach dem Leeren des Cover-Caches – in der Wartezeit konnte das Hauptfenster eine gelöschte Platte anfassen. „x“ nach dem Speichern eines Syncs (während des Sammlungswerts) zeigte eine Fehlermeldung und ließ die Tracklisten unsichtbar weiterladen. Einzelheiten in AENDERUNGEN.md.
- **Toter Code (entfernt):** Einzel-Neuladen eines Release samt seiner Felder, ungenutzte Parameter und Felder; per Skript zusätzlich nach nur einmal vorkommenden Deklarationen gesucht (keine weiteren).
- **Randfälle (gehärtet):** Überlauf bei unsinniger Paginierung, Monatsbalken der „Neuzugänge“ bei Zeitumstellung zum Monatsanfang, Positionsregler bei gelöschter Platte, Meldung beim Merken des Export-Ordners.
- **Geprüft, unverändert gelassen:** Abgleich (Merge schreibt nur Geändertes, ein Speichervorgang, Abbruch vor dem Speichern), Positionen 1…n je Fach, Sicherung und Wiederherstellung samt Regal-Neuaufbau, automatischer Export (leere Liste ersetzt keine Datei), Taktung und `Retry-After`, Protokoll und Absturz-Handler.
- **Bekannt, nicht geändert:** Eine Sicherung ganz ohne Platten (nur gesperrte Fächer) lässt sich nicht wiederherstellen – die Meldung spricht dann von fehlenden Platten. Automatische Sicherungen schreiben so etwas nie.
- **Nicht geprüft:** „Alles zurücksetzen“ und der Abbruch während des Sammlungswerts in der laufenden App mit echter Sammlung; ein echter Abgleich mit Discogs. Das Zurücksetzen ist bewusst nicht automatisiert (es löscht den echten Token).
- **Doku:** README (Abbruch nach dem Speichern, Zurücksetzen, Discogs-Dateien ohne „Einzel-Nachladen“), STATISTIK.md (Prüfdatum, Zurücksetzen, Neuzugänge, Schema V16), AENDERUNGEN.md.
- **macOS-Absturzberichte:** kein neuer seit `Plattenregal-2026-10-08-101207.ips`.
- **App-Protokoll** 12.10.: kein Absturzblock, kein `ERROR`. Mehrere Warnungen „vorige Sitzung nicht normal beendet“ nach gestoppten Läufen aus Xcode bzw. der Demo. Die beiden Prüfläufe in der Demo (Schnappschuss Statistik, Collection mit Suche) starteten und endeten normal.
- **Fehlermeldungen:** Kein neuer Text. Der Abbruch nach dem Speichern zeigt bewusst keine Meldung mehr (vorher „… Der Vorgang wurde abgebrochen.“); neu im Protokoll: „Nach dem Speichern abgebrochen, Tracklisten folgen später (…)“. Lässt sich der Export-Ordner nicht merken, erscheint die vorhandene, getestete Meldung „Der gewählte Ordner ist nicht erreichbar …“ statt „Die Datei konnte nicht geöffnet werden“; die technische Ursache steht als `ERROR` im Protokoll („Ordner für den automatischen Export nicht übernommen“).
- **Lokalisierung:** per Skript – 909 Einträge, 59 veraltet, jeder aktive Eintrag mit englischer Übersetzung, Platzhalter gleich. Ein Text geändert (Hinweis unter Einstellungen → Discogs), deutsch und englisch.

## Verifikation

- `xcodebuild -scheme Plattenregal test` (Xcodes DerivedData): **210 Tests in 13 Suites bestanden**, 24 s, keine Compilerwarnung (zwei im Cover-Raster behoben).
- Gegenprobe: `DiscogsSyncTests.cancellingAfterTheMergeIsNoErrorAndLoadsNoTracklists` schlägt ohne die Korrektur mit drei Befunden fehl.
- Demo gestartet, Statistik und Collection mit Suche als Bild angesehen.

# Stand · 10.10.2026 (Version 1.0.7: Logik, Tests, Dokumentation, Fehlerprotokoll, Lokalisierung)

Projektversion **1.0.7 (102026)**, Schema **V15**. Durchsicht der Logik unterhalb der Oberfläche. Ein erfolgreicher Testlauf beweist keine allgemeine Absturz- oder Datenverlustfreiheit.

## Umfang und Befunde

- **Gelesen:** Modelle und Migrationen, `PositionService`, `CabinetService`, `LibraryChanges`/`LibraryRecords`, Sortierung und Platzsuche, Fachnamen, Discogs-Client und -Sync samt Tracklisten, Sicherung/Wiederherstellung, Zurücksetzen, Export (CSV, PDF, automatisch), Statistik und Sammlungswert, Cover-Cache, dazu die Logik in Collection, Wantlist und Regalseite.
- **Fehler:** Sortierung nach „Jahr“ und „Label“ bei gleichem Interpreten – Platten ohne Jahr bzw. Label standen vorn statt hinten, Labels mit Ziffer am Anfang hinter allen anderen. Behoben, siehe AENDERUNGEN.md.
- **Unnötige Arbeit:** Jeder Sync schrieb alle Einträge neu, auch ohne Änderung. Behoben; gemessen per Test an der Speicher-Mitteilung (`ModelContext.didSave`): vorher 8 geschriebene Einträge bei 2 Exemplaren, 3 Releases, 1 Ordner und 1 Wantlist-Eintrag, jetzt 1 (das Konto).
- **Geprüft, unverändert gelassen:** Sortierschlüssel „Interpret + Tab + Titel“ (Tab sortiert vor Leerzeichen und Satzzeichen, per Skript gemessen). Datumsauswertung der Hinzufügedaten (10 000 Zeitstempel in 11 ms). Fachnummern gelöschter Regale werden neu vergeben; Sicherungen bauen ihre Regale samt Nummern selbst wieder auf, daher ohne Folgen.
- **Nicht geprüft:** ein echter Abgleich mit Discogs und die App mit der echten Sammlung – nur Tests mit Speicher-Datenbanken.
- **Tests:** alle 208 gelesen; 6 entfernt (5 doppelt, 1 für toten Code), 8 neu, 5 zu einem mit Argumenten zusammengefasst, 3 an ihren Platz verschoben – Einzelheiten in AENDERUNGEN.md.
- **Doku:** README (Abgleich schreibt nur Geändertes, Platten ohne Jahr/Label hinten, Tests und ihre Dauer, Prüfdatum), STATISTIK.md (Prüfdatum, Testzahl; an der Neuberechnung ändert der sparsamere Abgleich nichts, sie hängt am Ende des Syncs), AENDERUNGEN.md je Commit ein Eintrag.
- **macOS-Absturzberichte:** kein neuer seit `Plattenregal-2026-10-08-101207.ips`.
- **App-Protokoll** 09.–10.10.: kein Absturzblock. Seit der letzten Durchsicht nur ein bekannter `ERROR` („Schnappschuss snap-page.png: nach 30 s kein Fenster“, Debug-Werkzeug in der Demo) und eine Warnung „vorige Sitzung nicht normal beendet“ nach einem gestoppten Lauf. Version 1.0.7 lief am 10.10. zweimal kurz mit der echten Sammlung (845 Exemplare, 876 Wantlist-Einträge geöffnet, „Tracklisten geladen“, normal beendet), ohne Sync.
- **Fehlermeldungen:** Die Änderungen haben keine neuen Fehlerpfade und keine neuen Texte; die vorhandenen Meldungen zu Sync, Sortierung und Einsortieren gelten unverändert und sind getestet (`errorsReachTheUserInPlainGerman`, neu „… ist nicht mehr in der Collection“ in `recordThatLeftTheCollectionIsNotSortedIn`). Protokollzeilen des Syncs unverändert („Gespeichert …“, „Keine Änderungen, Seiten bleiben unverändert“).
- **Lokalisierung:** per Skript – 903 Einträge, 58 veraltet, jeder aktive Eintrag mit englischer Übersetzung, Platzhalter gleich. Seit 1.0.6 kam kein Text hinzu.

## Verifikation

- `xcodebuild -scheme Plattenregal test` (Xcodes DerivedData): **208 Tests in 13 Suites bestanden**, keine Compilerwarnung im Code der App.
- Nach der Durchsicht der Tests am selben Tag (siehe AENDERUNGEN.md): **205 Tests in 13 Suites bestanden**, 24 s. Nicht mit Tests abgedeckt bleiben die Ansichten selbst (Regalseite, Collection, Einstellungen), der Schlüsselbund und die Ordner-Lesezeichen.
- `git diff --check` ohne Befund.

# Stand · 09.10.2026 (Version 1.0.5, Dokumentation, Fehlerprotokoll, Lokalisierung)

Projektversion **1.0.5 (102026)**, Schema **V15**. Prüfung nach den Änderungen vom 09.10. (Regal, Statistik, Start, Scrollen, Einstellungen, DMG, Willkommensseite). Ein erfolgreicher Testlauf beweist keine allgemeine Absturz- oder Datenverlustfreiheit.

## Umfang und Befunde

- **Doku:** AENDERUNGEN.md gegen alle Commits seit der letzten Durchsicht (`ddffd5c`) abgeglichen, jeder hat einen Eintrag. README nachgetragen: Ziehen zum Aktualisieren nur mit zwei Fingern auf dem Trackpad, Covergröße in drei Stufen, Version und Prüfdatum. STATISTIK.md: nur die Version, die Änderungen an der Statistik vom 09.10. standen schon darin.
- **macOS-Absturzberichte:** kein neuer seit `Plattenregal-2026-10-08-101207.ips` (der absichtlich erzeugte aus der Prüfung vom 08.10.).
- **App-Protokoll** 08.–09.10.: kein Absturzblock. `ERROR` nur „Schnappschuss … nach 30 s kein Fenster“ aus Aufnahmen der Willkommensseite in der Demo (`--snapshot`, per `open -n` neben der laufenden installierten App). Dieselbe Demo öffnete ihr Fenster ohne `--snapshot` normal; das zeitweise fehlende Fenster beim Schnappschuss ist damit weiter offen, betrifft aber nur das Debug-Werkzeug. Die Warnungen „Die vorige Sitzung wurde nicht normal beendet …“ stammen von per `kill` beendeten Demo-Läufen.
- **Fehlermeldungen:** Die neuen Teile (Willkommensseite, Hilfe-Menü, Panel-Ausrichtung) haben keine Fehlerpfade. `Scripts/make-dmg.sh` meldet auf Deutsch, was zu tun ist (DMG schon eingehängt, App nicht gefunden, Finder hat das Layout nicht gespeichert).
- **Lokalisierung:** per Skript – 892 Einträge, 58 veraltet (darunter die Tour-Texte), jeder aktive Eintrag mit englischer Übersetzung, auch Pluralformen; Platzhalter gleich (englisch teils mit Positionsangabe). Alle Texte der Willkommensseite stehen im Katalog. „Cover“ ist veraltet und kommt im Code nur noch als Kategorie des Protokolls vor, das nicht übersetzt wird.
- **Willkommensseite** in der Demo angesehen: Deutsch hell (noch oben verankert) und Englisch dunkel (mittig), Klassisch. Die Knöpfe außerhalb der Demo („Später“, „Demo starten …“, „Token eintragen …“) nicht angesehen, um die echte Sammlung nicht zu öffnen.

## Verifikation

- `xcodebuild -scheme Plattenregal test` (Xcodes DerivedData): **205 Tests in 13 Suites bestanden**, keine Compilerwarnung im Code der App.
- Release-Build und DMG mit `Scripts/make-dmg.sh` (`dist/Plattenregal-1.0.5.dmg`).
- `git diff --check` ohne Befund.

# Stand · 08.10.2026 (Dokumentation, Fehlermeldungen, Fehlerprotokoll, Lokalisierung)

Projektversion **1.0.3 (102026)**, Schema **V15**. Prüfung nach den Scroll- und Datenänderungen vom Vormittag. Ein erfolgreicher Testlauf beweist keine allgemeine Absturz- oder Datenverlustfreiheit.

## Umfang und Befunde

- **Doku:** README, STATISTIK.md und AENDERUNGEN.md gegen alle Commits seit der letzten Durchsicht (`16e1494`) abgeglichen. AENDERUNGEN war vollständig; README und STATISTIK ergänzt (Einzelheiten in AENDERUNGEN.md).
- **macOS-Absturzberichte:** neu `Plattenregal-2026-10-08-093425.ips` (Version 1.0.3 (102026), Debug-Build, `EXC_BREAKPOINT/SIGTRAP` in SwiftData aus `LibraryRecords.reloadSmallLists`, ausgelöst im Test `StatisticsTests.snapshotReplacementSameCountAndCurrencyIsolation` beim Anlegen eines neuen Containers). Ursache: Bestände wurden über die Adresse ihres Containers zugeordnet, die nach Freigabe neu vergeben wird. **Korrigiert**; neuer Test `sharedRecordsOfReleasedContainersStayOut` stellt den Absturz mit dem alten Code nach (zweiter Bericht `Plattenregal-2026-10-08-101207.ips`, gleiche Aufrufliste, absichtlich erzeugt) und läuft mit dem neuen durch. Die Berichte vom 04.10. sind unverändert die bekannten aus älteren Tests.
- **App-Protokoll** vom 08.10.: kein `ERROR`, kein Absturzblock. Die vielen Warnungen „Die vorige Sitzung wurde nicht normal beendet …“ stammen von den Messläufen der Demo (per `kill` beendet) – kein App-Fehler. Der Testabsturz steht erwartungsgemäß nicht darin (Tests schreiben nicht ins App-Protokoll).
- **Fehlermeldungen:** neue Pfade seit der letzten Durchsicht durchgesehen (gemeinsamer Bestand, Sicherung im Hintergrund, Sammlungswert während eines Syncs). Die Sicherung im Hintergrund meldet und protokolliert Fehler wie zuvor. Der gemeinsame Bestand verschluckte Lesefehler und hätte eine leere Sammlung gezeigt – **korrigiert**: letzter Stand bleibt, Protokollzeile in „Datenbank“.
- **Lokalisierung:** per Skript – 871 Einträge, 34 veraltet und nicht mehr im Code, jeder aktive Eintrag mit englischer Übersetzung (Status „translated“) und gleichen Platzhaltern; kein im Code benutzter UI-Text fehlt im Katalog (Demo-Albentitel sind bewusst nicht übersetzt).

## Verifikation

- `xcodebuild … -scheme Plattenregal -destination 'platform=macOS' test` (Xcodes DerivedData): **203 Tests in 13 Suites bestanden**; geänderte Dateien neu übersetzt ohne Compilerwarnung.
- Nicht geprüft: Verhalten der App bei einem echten Lesefehler (lässt sich nicht ohne Eingriff in SwiftData erzeugen); nur am Code nachvollzogen.

# Stand · 07.10.2026 (Dokumentation, Fehlermeldungen, Fehlerprotokoll)

Projektversion **1.0.3 (102026)**, Schema **V15**. Dieser Abschnitt beschreibt die Prüfung vom 07.10. Die Abschnitte darunter sind historische Prüfstände; ihre Testergebnisse und damaligen Einschätzungen gelten nur für den jeweiligen Stand. Ein erfolgreicher Testlauf beweist keine allgemeine Absturz- oder Datenverlustfreiheit.

## Umfang und Befunde

- README, STATISTIK.md und AENDERUNGEN.md mit dem aktuellen Code und den bereits vorhandenen Änderungen abgeglichen: Fach-Raster/Liste, Exemplar-Positionsregler, Sitzungs-Scrollstellen, Suchplaketten, entfernte Trefferzahl im Suchfeld und Version nachgetragen. Bestehende Änderungen nicht zurückgesetzt.
- Fehlerpfade in `ErrorMessages`, App-Start, Schlüsselbund, Discogs, Dateiimport/-export, Regal und Statistik durchgesehen. Startfehler zeigen keine rohen Systemtexte mehr; Schlüsselbund-Status bleibt im technischen Fehler. Abbrüche von Aufgaben, URL-Anfragen und Dateidialogen werden einheitlich erkannt und von `reportedMessage` nicht als Fehler protokolliert. Neuer Test `cancellationAndKeychainErrorsStayReadable` prüft Meldungen, Lesefehler-Weitergabe und erhaltenen technischen Schlüsselbundcode.
- App-Protokoll zum Prüfzeitpunkt gelesen: am 7. Oktober zwei Meldungen über eine andere offene Instanz, kein Absturzblock. Die Fehler vom 6. Oktober betreffen bis auf eine Zweitinstanz Debug-Schnappschüsse ohne verfügbares Fenster. Das allein erklärt keine Ursache für das fehlende Fenster.
- Drei vorhandene macOS-Berichte vom **04.10.2026, 10:45:35 / 10:47:14 / 10:48:52**: jeweils Version **1.0 (092026)**, `EXC_BREAKPOINT/SIGTRAP`, Hauptthread, `PositionService.insert` aus `AllTests.LibraryTests.sharedSearchIndexFollowsChanges`. Sie stammen aus Tests des älteren Stands. Sie sind kein Beleg für einen aktuellen Absturz; umgekehrt beweist ein fehlender neuer Bericht keine Absturzfreiheit.
- App-Protokoll, Rotation, Export, Laufmarkierung und Crash-Erkennung im Code geprüft. `previousCrash` wird im bestehenden Regressionstest geprüft. README unterscheidet nun App-Protokoll und separate macOS-Berichte; ein Export enthält beide App-Logdateien, keine `.ips`-Dateien. Stack-Aufzeichnung im Signal-Handler bleibt bestmöglich und ist nicht garantiert signal-sicher. Hier wurde nur der Kommentar präzisiert, nicht der Handler umgebaut.

## Verifikation

- **Debug-Build und Gesamttest:** erfolgreich, **196 Tests in 13 Suites, 0 Fehler**, auf dem endgültigen Codestand. Enthalten sind `errorsReachTheUserInPlainGerman`, `cancellationAndKeychainErrorsStayReadable`, `crashOfThePreviousSessionIsFoundInTheLog` und der in den alten Crashberichten genannte `sharedSearchIndexFollowsChanges`.
- **Release-Build:** erfolgreich (`BUILD SUCCEEDED`), keine Compilerwarnungen im Buildprotokoll.
- **Dokumente/Katalog:** `git diff --check` ohne Befund; String-Katalog als JSON gültig; die drei geänderten UI-Texte haben englische Übersetzungen; lokale Markdown-Links in allen vier Dokumenten vorhanden.

Ausgeführte Build-/Testbefehle:

```sh
xcodebuild -project Plattenregal.xcodeproj -scheme Plattenregal -destination 'platform=macOS' -derivedDataPath /tmp/Plattenregal-Doku-20261007 test
xcodebuild -project Plattenregal.xcodeproj -scheme Plattenregal -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/Plattenregal-Doku-20261007 build
```

Testnachweis: `/tmp/Plattenregal-Doku-20261007/Logs/Test/Test-Plattenregal-2026.10.07_12-05-49-+0200.xcresult`; vollständige Terminalausgaben: `/tmp/Plattenregal-Doku-20261007-final-test.log` und `/tmp/Plattenregal-Doku-20261007-release.log`. Diese temporären Dateien sind keine mitgelieferten Projektdateien.

## Nachprüfung der UI-Änderungen (später am 07.10.2026)

- Fachinhalt (Raster/Liste, Positionsregler, Scrollbrücke der Tabelle), Suchplaketten und Fehlermeldungen im Code geprüft. Korrigiert: Goldrand der Auswahl in Klassisch, fehlende englische Texte (5) und veraltete Katalogeinträge, irreführender Tooltip, Reglerzählung und Schutz vor gelöschtem Exemplar, Auswahl nach „Nicht im Regal“, endlose Wiederherstellung bei verschwundenem Scrollziel. Einzelheiten in AENDERUNGEN.md.
- Die obige Angabe „die drei geänderten UI-Texte haben englische Übersetzungen“ galt nur für die Fehlertexte; die neuen Texte des Fachinhalts waren nicht übersetzt. Jetzt hat jeder nicht veraltete Katalogeintrag eine englische Übersetzung (per Skript geprüft).
- `xcodebuild … -scheme Plattenregal -destination 'platform=macOS' test` (Xcodes DerivedData): **196 Tests in 13 Suites bestanden**, 0 Compilerwarnungen.
- Visuell (zweite Durchsicht): Fachraster in Klassisch hell und dunkel per `--snapshot` in der Demo geprüft (Start über `open`, aus einer Shell direkt gestartet entsteht kein Fenster). Nicht geprüft: Modern, Bedienung des Reglers und Rechtsklick-Menü in der laufenden App.

## Collection, Wantlist und Regal (dritte Durchsicht, 07.10.2026)

- Code von Collection, Wantlist, Regalseite und Fachinhalt samt Animationen durchgesehen. Korrigiert: abgeschnittene Coverschatten am Rasterrand, gestauchtes Fach beim Umschalten Raster/Liste und beim Wechsel leeres/belegtes Fach, fehlende Überblendung beim Fachwechsel in der Liste, wirkungslose Plakette der aktuellen Rubrik, fehlender Track-Treffer in der Collection (Klassisch). Einzelheiten in AENDERUNGEN.md.
- Schnappschüsse der Demo (Klassisch hell, Hülle): Collection-Suche „Radiohead“ und Fachraster vor/nach der Korrektur verglichen; Schatten vollständig, Cover weiter bündig mit dem Regal.
- 196 Tests bestanden, 0 Compilerwarnungen. Nicht geprüft: Modern im Bild, Überblendungen in Bewegung (nur am Aufbau der Ansichten).

## Modern an Klassisch angeglichen (07.10.2026)

- Alle Design-Weichen im Code durchgesehen und Aufbau, Abstände, Beschriftung, Auswahlmarkierung und Animationen vereinheitlicht (Einzelheiten in AENDERUNGEN.md).
- Prüfung mit echten Fensterfotos (`screencapture -l` auf das Demo-Fenster, da `--snapshot` kein Liquid Glass zeichnet): Collection mit Suche, Wantlist, Regal und Statistik in Modern hell/dunkel sowie Klassisch hell. 196 Tests bestanden, 0 Compilerwarnungen.
- Nicht geprüft: die unteren Statistik-Bereiche (Künstler, Zufallsfund, Labels) im Bild, die gleitende Kapsel in Bewegung (nur Endzustand), das Einstellungsfenster in Modern.

## Nachprüfung mit echten Fensterfotos (07.10.2026, später)

- Vorgehen: Demo starten, Fenster über seine Prozess-ID finden, Scrollen und Klicks als Ereignisse an das Demo-Fenster, Fotos mit `screencapture -l`. So sind auch Glas, Popover und Zwischenstände einer Animation sichtbar.
- Geprüft: Statistik vollständig (beide Designs), Listen von Collection, Wantlist und Fach, Popover und Rechtsklick-Menü, Einstellungen, Klassisch dunkel, Regalsuche, Positionsregler, Auswahlkapsel in Bewegung. Befunde und Korrekturen in AENDERUNGEN.md.
- Die im Abschnitt darunter als offen vermerkten **Tour-Bilder sind erneuert** (Deutsch/Englisch, hell/dunkel) und zeigen den aktuellen Aufbau.
- 196 Tests bestanden, 0 Compilerwarnungen.

## Platte hinzufügen, Vermisst und Rechtsklick-Menüs (07.10.2026, abends)

- Änderungen siehe AENDERUNGEN.md. Fensterfotos der Demo (`--preview-page=Regal --preview-add`) in Klassisch hell und dunkel sowie Modern dunkel; Modern hell nur vor dem Umbau der Vermisst-Spalte. Lage des ersten Covers links und rechts auf dem Foto nachgemessen: gleiche Pixelzeile. Rechtsklick-Menüs nur gebaut, nicht im Bild geprüft.
- **Lokalisierung:** per Skript gegen den Quelltext geprüft – jeder aktive Katalogeintrag hat eine englische Übersetzung mit gleicher Zahl an Platzhaltern, kein als veraltet markierter Eintrag wird noch benutzt, kein neuer Text fehlt im Katalog. Ergänzt: „Beim Einsortieren nicht gefunden“, „Vermutlich noch in einem anderen Fach“, „Exemplar bearbeiten“.
- **Fehlermeldungen:** In den geänderten Ansichten keine neuen Fehlerpfade. Mit dem Suchfeld entfällt nur der Leerzustand „Keine Treffer“ in „Platte hinzufügen“; Fehlerbanner und Meldungen des Fachinhalts sind unverändert.
- **Protokoll:** App-Protokoll vom 07.10. ohne `ERROR` und ohne Absturzblock. Die Warnungen „Die vorige Sitzung wurde nicht normal beendet …“ stammen von den Foto-Läufen, die die Demo per `kill` beenden, und einmal von einer Xcode-Sitzung, die dabei versehentlich mit beendet wurde – kein App-Fehler. Keine neuen macOS-Absturzberichte (zuletzt 04.10.2026, siehe oben).
- `xcodebuild … -scheme Plattenregal -destination 'platform=macOS' test` (Xcodes DerivedData): **196 Tests in 13 Suites bestanden**, 0 Compilerwarnungen; `git diff --check` ohne Befund.
- **Offen:** Das Tour-Bild „Platte hinzufügen“ zeigt noch den alten Aufbau (Suchfeld, Goldrand, Vermisst mit Fach-Zwischentiteln); die Tour wurde auf Wunsch nicht neu aufgenommen.

## Grenzen dieser Prüfung

- Keine visuelle oder interaktive Prüfung der Fehlerseiten, kein absichtlich ausgelöster Absturz und kein echter Schlüsselbundfehler. Automatisierte Tests laufen mit lokalen Attrappen und Datenbanken im Arbeitsspeicher.
- Kein echter Discogs-Abgleich, kein zerstörender Datenbanktest, keine Notarisierung oder Veröffentlichung.
- Die bereits vorhandenen Änderungen an Regal und Suche wurden für den Doku-Abgleich gelesen und vom Gesamttest erfasst; ihre vollständige visuelle und interaktive Prüfung gehört nicht zu dieser Dokumentationsprüfung.
- Vorhandene App-Protokolle, Crashberichte und Nutzerdaten wurden nicht verändert oder gelöscht. Die zuvor dokumentierten offenen Tour-Bilder und das zeitweise fehlende Demo-Fenster sind durch diese Prüfung nicht als behoben bestätigt.

---

# Aktueller Stand · 06.10.2026 (Prüfung Robustheit, Klassisch durchgehend)

## Vorgehen

1. Build und alle Tests vor und nach den Änderungen: 193 Tests, 0 Fehler.
2. Kern-Code gelesen (Discogs-Client und Abgleich, Positionen, Regale, Sicherung, Zurücksetzen, Export, Schlüsselbund, Ordnerzugriff, Cover-Cache, Protokoll) und die Diffs seit der letzten Prüfung (Toolbar-Suche, Aktionsfächer, Tour, Klassisch).
3. Demo in **Klassisch** per `--snapshot` aufgenommen (Design per Startargument `-signatureDesign atelier`): Collection (Raster, Liste mit Suche), Wantlist dunkel mit aufgefächerten Aktionen, Regal, „Platte hinzufügen“, Einsortier-Karte dunkel, Statistik, alle Einstellungs-Tabs, Tour. Nach den Farbänderungen Darstellung, Regal (dunkel) und Statistik erneut.

## Ergebnis

| Prüfung | Ergebnis |
|---|---|
| Robustheit | ✅ keine Datenverlust- oder Absturzgefahr; ein Darstellungsfehler (Tabellenkopf beim Designwechsel) behoben |
| Auswahl | ✅ Goldrand auf tieferem Creme bei Fach, Regal-Karte und Design-Karte |
| Signalfarben | ✅ Wertveränderung moosgrün, Aktiv-Punkte moosgrün, in Hell und Dunkel lesbar |
| Glas in Klassisch | ✅ keine ungeschützte Glas-Stelle mehr im Code (alle über `AppStyle.isAtelier`) |
| Vorbelegte Suche in Klassisch | ✅ Fenster erscheint (`--preview-search=da`), der früher notierte Fehler trat nicht auf |

## Nicht geprüft

- **Designwechsel zur Laufzeit** mit offener Fach-Tabelle nicht von Hand ausprobiert; die Korrektur folgt dem dokumentierten AppKit-Weg (`needsDisplay`).
- **Tour-Bilder** zeigen Modern, auch in Klassisch (offen, siehe AENDERUNGEN.md).
- Dreimal erschien bei `--snapshot` innerhalb von 30 s kein Fenster (Statistik, Allgemein, Darstellung); beim zweiten Versuch jeweils schon. Wie der Hinweis im vorigen Stand: Startverhalten der Demo direkt nach dem Beenden der vorigen Instanz, kein Absturz (Protokoll ohne Absturz-Block).

# Aktueller Stand · 06.10.2026 (Aktionsknopf nur Collection/Wantlist, Suche oben, Statistik bündig)

## Vorgehen

1. Build und alle Tests: erfolgreich.
2. Demo in **Klassisch** fotografiert (`screencapture`): Collection, Collection aufgefächert, Regal mit Suche „Daft“, Statistik. Kanten in der Collection pixelweise gemessen.

## Ergebnis

| Prüfung | Ergebnis |
|---|---|
| Suche bündig | ✅ rechte Kante von Suchfeld und Cover-Hülle beide bei x = 2390 px (vorher Feld bei 2430) |
| Regal | ✅ Feld endet mit dem Regal, Trefferliste rechtsbündig darunter, kein Knopf unten |
| Statistik | ✅ Titel, „Sammlungswert · Median“, Betrag und Kacheln an einer Kante, kein Knopf unten |
| Fächer | ✅ Liste, Sync (in der Demo gesperrt), Zahnrad |

## Nicht geprüft

- **Modern** nicht fotografiert; der Toolbar-Rand ist dort derselbe, die Statistik-Änderung designunabhängig.
- **Klicks** (⌘F, Esc, Fächer) nicht von Hand.
- Hinweis: Nach hartem Beenden öffnete die Demo beim nächsten Start kein Fenster (auch mit dem alten Stand); ein zweites `open` (Reopen) holt es. Kein Code-Fehler dieser Änderung.

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

1. Die zehn PNG-Dateien im `AppIcon.appiconset` auf Pixelgröße und Alphakanal geprüft und mit der finalen Vorlage `outputs/AppIcon-Vinyl-2026-10-05/AppIcon-Vinyl-1024.png` verglichen (Ordner inzwischen gelöscht, in der Git-Historie bis Commit `2b2152e`): Die 1.024-Pixel-Datei ist byte-gleich mit der Vorlage.
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
