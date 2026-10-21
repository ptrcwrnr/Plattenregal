# Einsortier-Karte wechselt das Fach nicht mehr · 21.10.2026

- **Vorher:** Ein Klick auf einen Suchtreffer im Regal öffnete das Fach der Platte und baute dafür dessen ganzes Cover-Raster auf (bei ~85 Platten rund 0,3 s, der größte Rest des Ruckelns).
- **Jetzt:** Die Karte erscheint über dem gerade offenen Fach, das bleibt. Im Regal ist das Fach der Platte hell, die übrigen treten zurück – wie bei den Suchtreffern. Ein Klick auf das markierte Fach öffnet es; die Karte bleibt stehen, eine einsortierte Platte ist dort hervorgehoben. „Passt genauso … – dorthin wechseln“ setzt nur die Markierung um, nach „Gefunden“/„Hier einsortieren“ bleibt das offene Fach. Das Fach öffnet weiterhin gleich mit, wenn die Platte in einem anderen Regal steht (die Markierung wäre sonst nicht zu sehen) und bei „Im Regal anzeigen“ von Collection, Detailkarte oder Statistik.
- README: Absatz zur Suche auf der Regalseite, Architekturzeile „Regal“.
- Geprüft mit Instruments in der Testkopie der Sammlung (Cover-Raster, optimierter Build): Klick auf den Treffer 25–33 ms, einmal 75 ms statt vorher 300 ms Fachaufbau plus Einblendung; Abbrechen ruckelfrei. Bildschirmfotos: offenes Fach bleibt, Ziel-Fach markiert, Karte darüber; Klick aufs Ziel-Fach öffnet es mit hervorgehobener Platte und stehender Karte; Platte im EKET öffnet dessen Fach. Build ohne neue Warnungen, Tests bestanden. DMG 1.1.2 neu ausgegeben.

# Einsortier-Karte im Regal ruckelfrei · 21.10.2026

- **Vorher:** Ein Klick auf einen Suchtreffer im Regal ließ die Karte („Hier steht …“, Abbrechen/Gefunden) ruckelig hereinkommen, vor allem beim ersten Mal. Gemessen mit Instruments (Testsammlung mit ~85 Platten je Fach, Cover-Raster): Aussetzer von 300–390 ms und während der ganzen Einblendung verpasste Bilder.
- **Ursachen:** (1) Das Fach wurde Bild für Bild kleiner gerechnet, und weil das Cover-Raster in einem `GeometryReader` lag, baute es dabei jedes Mal alle Kacheln neu. (2) Die Fachansicht bekam bei jeder Änderung der Seite (Karte, Tippen in der Suche) neue Closures und galt deshalb immer als geändert – das ganze Raster wurde neu aufgebaut. (3) Der Wechsel ins Fach des Treffers baut dessen Raster in einem langen Bild auf, genau während die Karte losanimierte.
- **Jetzt:** Das Raster misst nur noch seine Breite (`onGeometryChange` statt `GeometryReader`). `ShelfContentsView` ist `Equatable` und vergleicht nur ihre Daten. Während die Karte kommt, geht oder ihre Höhe ändert, rückt der Fachinhalt per Versatz und behält seine Größe; danach übernimmt ein Innenabstand dieselbe Lage in einem Schritt, sodass die letzten Platten erreichbar bleiben. Liegt der Treffer in einem anderen Fach, öffnet zuerst das Fach (das Raster ist dabei noch unsichtbar) und die Karte blendet ein, sobald der Hauptthread wieder frei ist. Esc, ein anderes Fach oder „Einsortieren“ verwerfen eine noch wartende Karte.
- README: Architekturzeile „Regal“.
- Geprüft: Ablauf Suchtext → Treffer → Karte → Abbrechen viermal in Folge mit Instruments (Hitches, Zeitmarken als Points of Interest) in einer Kopie der Sammlung (eigener Container), Raster und Liste. Karte rein: vorher 150–390 ms Aussetzer und Dauerruckeln, jetzt ein Bild von 40–75 ms ohne weitere; Abbrechen vorher 50–90 ms, jetzt ruckelfrei; Tippen in der Suche ohne Aussetzer. Der Aufbau eines großen Fachs selbst dauert weiter ~0,3 s, fällt aber in die Zeit, in der das Raster noch unsichtbar ist. In der Liste gibt es beim ersten Öffnen einer Tabelle in der Sitzung noch einen einmaligen Aussetzer. Bildschirmfotos: Karte steht über dem Fach, Inhalt gleitet beim Abbrechen zurück. Build ohne neue Warnungen, Tests bestanden. DMG 1.1.2 neu ausgegeben.

# Produktbilder für App Store und Social Media · 21.10.2026

- **Neu:** `Marketing/Bilder/` mit zehn durchgestalteten Produktbildern aus der echten Sammlung (keine Demo-Platten): sechs fürs Mac-App-Store-Format 2880 × 1800 (Collection, Regal, Plattenkarte mit Standort, Sortierung prüfen, Statistik, Klassisch/Modern hell/dunkel), drei Instagram-Beiträge 1080 × 1350 (Cover-Wand „850 Platten. Ein Regal.“, Regal, Plattenkarte) und eine Story 1080 × 1920. Gestaltung wie Webseite und Handbuch: Petrol, Creme und Gold, Überschriften in New York, die Schallplatte mit goldenem Etikett.
- **Werkzeuge:** `Scripts/marketing-shots.sh` nimmt die Fenster mit `screencapture` auf (echtes Liquid Glass statt des flacheren `--snapshot`) und holt Cover aus dem Cache; `Marketing/Produktbilder.html` ist die Vorlage, `Scripts/make-marketing.swift` rendert sie. Die Rohaufnahmen (`Marketing/Aufnahmen/`) stehen in `.gitignore`.
- Weggelassen: „Einsortieren“ und „Platte hinzufügen“ – in der echten Sammlung ist alles einsortiert, das Fenster zeigt nur „Nur noch gesuchte Platten“.
- README: Abschnitt „Produktbilder“.
- Geprüft: alle zehn Bilder in voller Größe angesehen (Größen 2880 × 1800, 1080 × 1350, 1080 × 1920, ohne Alphakanal). Korrigiert nach dem ersten Durchgang: Platten berührten Überschriften, ein Fensterrand endete knapp über dem Bildrand, die Plattenkarte war im Beitrag zu groß, und eine Karte blieb leer, weil das Foto noch nicht dekodiert war (der Renderer wartet jetzt darauf, mit Zeitlimit). Ein erster Lauf des Aufnahme-Skripts brach an einem leeren Cover-Ordner ab und ließ die Fenstergröße 1280 × 800 stehen; sie ist wieder auf 1203 × 772 gesetzt, das Skript setzt sie jetzt auch bei Fehlern zurück (`TRAPEXIT`). App-Code unverändert, Tests nicht ausgeführt.

# DMG-Fenster kompakter: 500 × 290 · 21.10.2026

- **Vorher:** 540 × 330 pt, Symbole bei x = 140 und 400, y = 120.
- **Jetzt:** 500 × 290 pt, Symbole bei x = 130 und 370, y = 96 (in `make-dmg.sh` und `dmg-background.swift`). Der Pfeil ist 92 statt 104 pt lang, damit er zwischen den näher stehenden Symbolen Luft hat. Papier, gerader Petrolpfeil und die kleine Platte (130 pt Radius, 42 pt unter dem Rand) bleiben, die Platte steht damit im Verhältnis etwas höher. Kleiner habe ich das Fenster nicht gemacht: Darunter würden Pfeil und Platte an Symbole und Beschriftungen stoßen.
- Probiert und verworfen: statt der einen Platte viele kleine mit bunten Etiketten, erst als Haufen, dann als Band über die ganze Breite (an den Rändern höher), zuletzt größer und weniger.
- `dist/Plattenregal-1.1.2.dmg` neu gebaut (`Scripts/make-dmg.sh`), Version bleibt 1.1.2, App und Handbuch-PDFs unverändert.
- README: Fenstergröße der DMG.
- Geprüft: Das DMG-Fenster habe ich im Finder geöffnet und aufgenommen. Symbole, Pfeil, Platte und beide Beschriftungen sitzen frei. `hdiutil verify` gültig. Eingehängt: nur `Plattenregal.app` und `Applications`, Version 1.1.2, Signatur gültig, Binärdatei identisch mit dem Release-Build.

# DMG-Platte kleiner und tiefer · 21.10.2026

- **Vorher:** Die Platte im DMG-Fenster hatte 200 pt Radius und reichte bis kurz unter die Beschriftungen der Symbole. Das war zu groß und zu nah.
- **Jetzt:** 130 pt Radius, Etikett 48 pt, Mitte 42 pt unter dem unteren Rand. Sie reicht in der Mitte bis etwa 242 pt von oben und bleibt weit unter der Schrift. Vom goldenen Etikett ist ein schmaler Rand zu sehen. Papier, Fenstergröße 540 × 330 und der gerade Petrolpfeil bleiben.
- Probiert und verworfen: die Platte in der Ecke unten rechts, nur feine Rillen als Wasserzeichen und ein Petrol-Hintergrund wie auf der Webseite. Beim Petrol schreibt der Finder die Beschriftungen im hellen Modus schwarz, was sich nicht einstellen lässt. Lesbar wurden sie erst mit einem hellen Schein hinter Symbol und Schrift, und der wirkte wie zwei Scheinwerfer.
- `dist/Plattenregal-1.1.2.dmg` neu gebaut (`Scripts/make-dmg.sh`), Version bleibt 1.1.2, App und Handbuch-PDFs unverändert.
- README: Absatz zur DMG.
- Geprüft: Das DMG-Fenster habe ich im Finder geöffnet und aufgenommen. Die Platte sitzt unten mittig, beide Beschriftungen stehen frei auf dem Papier. `hdiutil verify` gültig. Eingehängt: nur `Plattenregal.app` und `Applications`, Version 1.1.2, Signatur gültig, Binärdatei identisch mit dem Release-Build. Nicht geprüft: das Fenster im dunklen Modus. Dort schreibt der Finder die Beschriftungen vermutlich weiß, das gilt aber für jede Papier-Fassung.

# DMG-Fenster kompakter: ohne Petrolband, Pfeil in Petrol, größere Platte · 21.10.2026

- **Vorher:** Das DMG-Fenster war 540 × 380 pt groß. Oben lag ein Petrolband mit dem Titel „Plattenregal“ in New York und einem goldenen Strich. Der Pfeil war petrolfarben mit goldener Spitze, und unten lugte eine Platte mit 150 pt Radius herein.
- **Jetzt:** 540 × 330 pt, nur Papier mit dem leichten Licht hinter der App. Band, Titel und Strich entfallen. Die Symbole stehen 30 pt höher (Mitte bei y = 120 statt 178, in `make-dmg.sh` und `dmg-background.swift`). Der Pfeil ist gerade und ganz petrolfarben, Linie und Spitze in einem Strich. Die Platte hat jetzt 200 statt 150 pt Radius und reicht in der Mitte bis etwa 192 pt von oben statt 230 pt. Das Etikett wächst mit (75 pt). Ihr Rand bleibt mit etwas Luft unter den schwarzen Beschriftungen der Symbole.
- Zwischendurch probiert und verworfen: ein Bogen und ein mehrfach geschwungener, handschriftlicher Pfeil.
- `dist/Plattenregal-1.1.2.dmg` neu gebaut (`Scripts/make-dmg.sh`), Version bleibt 1.1.2, App und Handbuch-PDFs unverändert.
- README: Absatz zur DMG.
- Geprüft: Das eingehängte DMG-Fenster habe ich im Finder geöffnet und aufgenommen. Hintergrund, Symbole und Pfeil sitzen wie gedacht, und beide Beschriftungen stehen vollständig auf dem Papier. Eine erste Fassung mit 6 pt höherer Platte kam den Unterlängen zu nahe. `hdiutil verify` gültig. Eingehängt: nur `Plattenregal.app` und `Applications`, Version 1.1.2, Signatur gültig, Binärdatei identisch mit dem Release-Build.

# Standardgröße des Fensters 1200 × 780; DMG 1.1.2 neu ausgegeben · 21.10.2026

- **Vorher:** Das Hauptfenster öffnete beim ersten Start mit 1300 × 850 pt.
- **Jetzt:** 1200 × 780 pt, nach deinem laufenden Fenster (1203 × 772) auf glatte Werte gebracht. Die Höhe 770 wäre zu knapp: 772 pt sind die Mindesthöhe (720 pt Inhalt unter der 52 pt hohen Toolbar), dein Fenster stand schon dort. `defaultSize` gilt für das ganze Fenster samt Toolbar. Wer das Fenster schon einmal benutzt hat, behält seine gespeicherte Größe; die neue gilt beim ersten Start und wenn macOS keinen Rahmen mehr kennt.
- `dist/Plattenregal-1.1.2.dmg` neu gebaut (`Scripts/make-dmg.sh`), Version bleibt 1.1.2. Die Handbuch-PDFs sind unverändert.
- README: Absatz zum Hauptfenster nennt Standard- und Mindestgröße.
- Geprüft: Debug-Build ohne Warnungen, alle 206 Tests erfolgreich. Die Demo ohne gespeicherten Rahmen gestartet (`-ApplePersistenceIgnoreState YES`, Rahmen überschrieben): Das Fenster öffnet mit 1200 × 780 und sieht unverändert aus. Gegenprobe mit 1200 × 770 ergab 1200 × 772 (Mindesthöhe), mit 1200 × 800 genau 1200 × 800. Die Probeläufe überschrieben den gespeicherten Rahmen der echten App, er ist danach wieder auf 1203 × 772 gesetzt. DMG: `hdiutil verify` gültig, eingehängt nur `Plattenregal.app` und `Applications`, Version 1.1.2, Signatur gültig, Binärdatei identisch mit dem Release-Build, ohne Debug-Startargumente.

# Abschlussprüfung der Doku, Meldungen, Protokolle und Übersetzungen · 20.10.2026

- **README:** Die Tabelle der Einstellungen nennt das Design jetzt in der neuen Reihenfolge („Klassisch oder Modern“). Die übrigen Stellen zu Umschaltern, Seiten, Regalen, Einstellungen und Startargumenten waren schon aktuell. Modern bleibt das Standarddesign. Handbuch und Webseite zeigen die Design-Auswahl nicht als Bild und nennen keine Reihenfolge, sie bleiben unverändert.
- **STATISTIK.md:** Prüfdatum auf 20.10.2026. An Berechnung und Inhalt der Statistik hat sich nichts geändert, ihre Umschalter bewegen sich nur wie alle anderen.
- **VALIDIERUNG.md:** neuer Abschnitt für den 20.10. mit den Befunden beim Ansehen, der geänderten Prüfmethode, Protokoll, Absturzberichten und Übersetzungen.
- **Fehlermeldungen:** keine neuen.
- **Absturzberichte und Protokoll:** keine `.ips`-Berichte, im App-Protokoll kein Fehler und kein Absturz. Die Warnungen „vorige Sitzung nicht normal beendet“ kommen von beendeten Demo-Läufen, auch die zwei in der echten App (gemeinsame Laufmarkierung).
- **Übersetzungen:** 856 Einträge, 8 veraltet, alle aktiven mit Englisch. Nichts neu, nichts entfernt.
- Geprüft: Doku gegen den Code gelesen, Protokoll und Textkatalog per Skript ausgewertet. Code unverändert.

# DMG 1.1.2 mit ruhigerer Toolbar neu ausgegeben · 20.10.2026

- `dist/Plattenregal-1.1.2.dmg` neu gebaut (`Scripts/make-dmg.sh`), Version bleibt 1.1.2. Neu gegenüber der Ausgabe von 22:53: Die Toolbar wechselt im Takt der Seite (Suchfeld blendet aus statt zu springen, Platzhalter blendet über, Pill setzt sich um 2 pt ab, ihre Schrift bleibt stehen). In Einstellungen → Darstellung steht Klassisch oben. Die Handbuch-PDFs sind unverändert.
- Der erste Lauf brach ab, weil die DMG von 22:53 noch unter `/Volumes/Plattenregal` eingehängt war. Von ihr lief nichts, sie ist ausgeworfen.
- Geprüft: `hdiutil verify` gültig. Eingehängt: nur `Plattenregal.app` und `Applications`, Version 1.1.2, Signatur gültig. Die App-Binärdatei ist identisch mit dem Release-Build vom Stand `7184f77` und enthält keine der Debug-Startargumente. Beide PDFs sind byte-gleich mit denen im Repository. Das Finder-Fenster der DMG habe ich nicht geöffnet.

# Toolbar wechselt im Takt der Seite; Klassisch oben in den Designs · 20.10.2026

- **Vorher:** Beim Rubrikenwechsel wirkte die Toolbar grob. Das Suchfeld verschwand zur Statistik schlagartig und kam ebenso zurück: Es wurde aus der Toolbar genommen, macOS baute sie neu auf und übersprang dabei das Ausblenden. Der Platzhalter („Regal durchsuchen“ → „Collection durchsuchen“) sprang um. Die Pill lief gleichmäßig 0,3 s, alte und neue waren kurz beide halb zu sehen, und die Seite darunter wechselte in einem anderen Takt.
- **Jetzt:** Die ganze Toolbar wechselt im Takt der Seite. Was geht, blendet in 0,1 s aus (`AppStyle.pageOutAnimation`), was kommt, blendet nach 0,07 s in 0,22 s ein (`pageInAnimation`).
  - **Suchfeld:** bleibt immer in der Toolbar und wird in der Statistik nur ausgeblendet, ohne Klicks, ohne Fokus und für VoiceOver verborgen. Beim Ausblenden behält es Text und Platzhalter der vorigen Seite.
  - **Platzhalter:** zeichnet `AppSearchField` jetzt selbst, in der Platzhalterfarbe des Systems und an derselben Stelle wie vorher. Er blendet zum neuen Text über und verschwindet beim ersten Tastendruck sofort.
  - **Pill:** Jede Option hat ihre Pill und zeigt sie nur, wenn sie gewählt ist. Animiert werden nur Deckkraft und Versatz, keine Übergänge beim Einfügen und Entfernen; damit ist der Takt fest. Die Fläche setzt sich um 2 pt (`pillSettleDistance` = `hairSpacing`) statt 4 pt ab, die Beschriftung bewegt sich nicht mehr, sie blendet nur. Ein erster Versuch mit getrennten Übergängen für Fläche und Schrift ließ beim Abwählen kurz eine leere Pill stehen.
  - Zentral in `AppStyle`: `pageOutAnimation`, `pageInAnimation`, `pageFadeTransition`, `pillSettleDistance`. `selectionAnimation` und `settleTransition` entfallen.
- **Designs:** In Einstellungen → Darstellung steht Klassisch jetzt oben und Modern darunter (Reihenfolge der Fälle in `SignatureDesign`, gespeicherte Werte unverändert). Der Test zur Reihenfolge ist angepasst.
- **Aufnahmen ohne Klick (nur Debug):** `--preview-switch=<Rubrik>` und `--preview-switch-tab=<Tab>` wechseln 3 s nach dem Start. Die bisherigen Aufnahmen mit simulierten Klicks und Tastendrücken landeten im jeweils vorderen Fenster; ein verdecktes Fenster zeichnet macOS zudem nicht weiter, was wie ein Hänger aussah.
- README: Designs, Code-Übersicht (Seiten) und Startargumente.
- Geprüft: Debug-Build ohne Warnungen, alle 206 Tests erfolgreich. Bildfolgen der Toolbar in der Demo: Regal → Collection und Collection → Statistik in Klassisch, Regal → Statistik in Modern, dazu Allgemein → Darstellung in den Einstellungen (Klassisch). Alte Pill, Suchfeld und Platzhalter sind weg, bevor die neuen kommen. Es entsteht keine leere Pill und kein doppelter Text, und der Platzhalter steht an derselben Stelle wie der alte. Darstellung zeigt Klassisch oben.

# DMG 1.1.2 mit den neuen Übergängen neu ausgegeben · 20.10.2026

- `dist/Plattenregal-1.1.2.dmg` neu gebaut (`Scripts/make-dmg.sh`), Version bleibt 1.1.2. Neu gegenüber der Ausgabe von 22:13: Die Auswahl in den Umschaltern setzt sich von oben ab statt zu gleiten. Rubriken-Seiten, Einstellungs-Tabs und Regalwechsel blenden ein und setzen sich ebenfalls von oben ab, statt seitlich hereinzufahren. Die Handbuch-PDFs sind unverändert.
- Geprüft: `hdiutil verify` gültig. Eingehängt: nur `Plattenregal.app` und `Applications`, Version 1.1.2, Signatur gültig. Die App-Binärdatei ist identisch mit dem Release-Build vom Stand `2566713` und enthält die neue senkrechte Seitenbewegung. Beide PDFs sind byte-gleich mit denen im Repository. Das Finder-Fenster der DMG habe ich nicht geöffnet, an Hintergrund und Fensteraufbau hat sich nichts geändert.

# Seiten, Einstellungs-Tabs und Regale setzen sich ab statt zu schieben · 20.10.2026

- **Vorher:** Beim Rubrikenwechsel schob sich die neue Seite 18 pt von der Seite herein, aus der Richtung des Umschalters. Der Inhalt der Einstellungen sprang beim Tab-Wechsel ohne Animation um. Ein anderes Regal fuhr über die ganze Breite herein (`.push`).
- **Jetzt:** Alle drei laufen gleich ab, wie die Auswahl im Umschalter darüber. Der alte Inhalt blendet in 0,1 s aus, dann blendet der neue in 0,22 s ein und setzt sich dabei um 8 pt (`itemSpacing`) von oben ab. Die Zeiten stehen jetzt zentral in `AppStyle` (`pageFadeOut`, `pageFadeInDelay`, `pageFadeIn`, `pageSettleDistance`), dazu `pageTransition` als SwiftUI-Übergang für Einstellungen und Regal. `PageStack` liest dieselben Werte für seine Core-Animation-Bewegung. Auch das Verlassen einer Suche nimmt diese Zeiten. Bei „Bewegung reduzieren“ wird nur geblendet. Die Zufallsplatte in der Statistik kommt weiter von der Seite.
- **Gefunden beim Ansehen:** Die Ebenen der Seiten zählen nach unten. Mit positivem Versatz kam die Seite deshalb von unten, jetzt ist er negativ. In den Einstellungen überschrieb eine äußere `.animation` die Zeiten des Übergangs, sodass alter und neuer Tab kurz halb übereinander lagen. Sie ist entfernt, der Übergang bringt seine Zeiten selbst mit. Im Umschalter verschwand die helle Beschriftung der neuen Wahl sofort, also bevor die Kapsel da war, und das Wort fehlte kurz. Jetzt blendet sie aus, während die Kapsel einblendet.
- Regal: Altes und neues Regalbild liegen im Übergang in einem gemeinsamen `ZStack`, damit sie nicht kurz untereinander Platz beanspruchen. `cabinetEdge` entfällt.
- README: Regale, Einstellungen und Code-Übersicht (Seiten) beschreiben die neue Bewegung.
- Geprüft: Debug-Build ohne Warnungen, alle 206 Tests erfolgreich. In der Demo (Klassisch, hell) als Bildfolgen aufgenommen: Regal → Collection, Wohnzimmer → Flur (⌘→), Einstellungen Allgemein → Darstellung (Klick). Für die Richtung habe ich den Abstand vorübergehend auf 80 pt gestellt, danach zurück auf 8. In allen drei Fällen ist der alte Inhalt weg, bevor der neue erscheint, und der neue kommt von oben. Modern habe ich bei diesen drei nicht angesehen; dort ändern sich nur Flächen, nicht die Bewegung.

# Umschalter: Auswahl setzt sich ab statt zu gleiten · 20.10.2026

- **Vorher:** Die Auswahlkapsel aller Umschalter (Rubriken oben, Einstellungs-Tabs, Regal-Reiter, Raster/Liste, Optionen in den Einstellungen, Statistik, „Sortierung prüfen“) glitt über die anderen Optionen zur neuen Wahl (`matchedGeometryEffect`).
- **Jetzt:** Die alte Kapsel blendet an Ort und Stelle aus. Die neue blendet ein und setzt sich dabei um `tightSpacing` (4 pt) von oben auf die gewählte Option, in 0,3 s mit `selectionAnimation`. Neu ist dafür die zentrale Stufe `AppStyle.settleTransition`. Bei „Bewegung reduzieren“ wird nur noch geblendet. Das gilt für beide Designs, weil alle Umschalter derselbe Baustein `GlassSegmentedPicker` sind.
- **Beschriftung in der Kapsel:** Die Kapsel bringt die Beschriftung in der Auswahlfarbe selbst mit, und die normale Beschriftung darunter verschwindet beim Wählen sofort. Im ersten Versuch wechselte die Schrift nur ihre Farbe. Mitten im Übergang war sie dann so grau wie die halb sichtbare Kapsel, und „Collection“ verschwand kurz ganz. Für VoiceOver bleibt nur die normale Beschriftung.
- README: Absatz zu den Designs beschreibt die neue Bewegung.
- Geprüft: Debug-Build und alle 206 Tests erfolgreich. Den Wechsel Regal → Collection habe ich in der Demo als Bildfolge aufgenommen, in Klassisch und Modern (hell). Die Kapsel setzt sich von oben ab, die Schrift bleibt in jedem Bild lesbar, und die alte Kapsel blendet sauber aus. Nur die Rubriken habe ich angesehen, nicht die übrigen Umschalter. Die laufen über denselben Baustein.

# DMG 1.1.2 mit unsichtbarem Tracklisten-Nachladen neu ausgegeben · 20.10.2026

- `dist/Plattenregal-1.1.2.dmg` neu gebaut, Version bleibt 1.1.2. Neu gegenüber der Ausgabe von 22:07: Tracklisten werden beim Start unsichtbar nachgeladen. Der erste Versuch brach ab, weil unter `/Volumes/Plattenregal` noch eine andere DMG eingehängt war (eine Kopie aus iCloud Drive). Sie ist ausgeworfen.
- Geprüft: `hdiutil verify` gültig. Eingehängt: nur `Plattenregal.app` und `Applications`, Version 1.1.2, Signatur gültig. Die App-Binärdatei ist identisch mit dem Release-Build, der nach dem letzten Commit entstand, und enthält die neuen Teile (`tracklistsLoading`, `isWorking`). Beide PDFs sind byte-gleich mit denen im Repository.

# Tracklisten beim Start unsichtbar nachladen · 20.10.2026

- **Vorher:** Beim Start lud die App fällige Tracklisten nach (unterbrochene Läufe oder nach 180 Tagen aufzufrischende). Das sollte leise geschehen, zeigte aber trotzdem kurz „Tracklisten werden geladen“ (oft nur 1–6 Stück) und danach „Synchronisierung abgeschlossen“. `loadTracklists` setzte die Anzeige auch im leisen Lauf, und am Ende rief es `finish()` auf.
- **Jetzt:** Das Nachladen beim Start bleibt von Anfang bis Ende unsichtbar, ohne Statuszeile, ohne Fortschritt und ohne Abschlussmeldung. Fehler bleiben wie bisher still und stehen im Protokoll. Ein Abgleich, den man selbst startet (Ziehen, ⌘R, Knöpfe in Collection, Wantlist und Einstellungen), zeigt die Tracklisten unverändert mit Fortschritt und „abgeschlossen“.
- **Statistik unverändert:** Sie hält ihre Neuberechnungen zurück, solange geladen wird, und rechnet danach einmal neu (die Länder kommen mit den Tracklisten). Dafür folgt sie jetzt `DiscogsSyncService.isWorking` (Abgleich oder Tracklisten, sichtbar oder nicht) statt `isRunning` (nur Sichtbares). Sonst hätte sie bei einem größeren unsichtbaren Lauf nach jedem Zwischenspeichern neu gerechnet.
- **Test:** `tracklistsResumedAtLaunchStayInvisible` startet das Nachladen wie beim Start. Er prüft, dass die Tracklist geladen wird, dass zu keinem Zeitpunkt eine Statuszeile erscheint und dass danach keine Abschlussmeldung kommt.
- README: Absatz „Collection und Wantlist aus Discogs“ beschreibt das unsichtbare Nachladen.
- Geprüft: Debug-Build ohne Warnungen, alle 206 Tests erfolgreich. In der echten App beim Start nicht angesehen, ob gerade Tracklisten fällig sind, hängt vom Stand der Sammlung ab.

# DMG 1.1.2 mit dem aufgeräumten Stand neu ausgegeben · 20.10.2026

- `dist/Plattenregal-1.1.2.dmg` neu gebaut (`Scripts/make-dmg.sh`), Version bleibt 1.1.2. Die DMG enthält alles von heute: Schema nur noch V15/V16, die Aufteilung in übersichtliche Dateien, den bereinigten Textkatalog, die zusammengelegten Bausteine und die angeglichenen Animationen und Radien. Die Handbuch-PDFs sind unverändert.
- Geprüft: `hdiutil verify` gültig. Eingehängt: nur `Plattenregal.app` und `Applications`, Version 1.1.2, Signatur gültig. Die App-Binärdatei ist identisch mit dem frischen Release-Build, beide PDFs sind byte-gleich mit denen im Repository. In der Binärdatei kommen die Namen der entfernten Schema-Versionen V10–V14 nicht mehr vor. Das Finder-Fenster der DMG habe ich nicht geöffnet, an Hintergrund und Fensteraufbau hat sich nichts geändert.

# Federn und Klassisch-Radien an die zentralen Stufen angeglichen · 20.10.2026

- **Eine Bewegungskurve:** `AppStyle` sieht für die ganze App `.smooth` vor, ohne Überschwingen. Gefedert (`.spring` mit `bounce`) haben bisher noch der schwebende Knopf unten rechts (Aufklappen, Zuklappen, gestaffeltes Erscheinen der Einträge) und die beiden Statusanzeigen. Der Knopf nimmt jetzt `moveAnimation` (0,3 s, dieselbe Kurve wie `layoutAnimation`, aber auch bei „Bewegung reduzieren“ verfügbar). Die Staffelung der Einträge und das Verhalten bei „Bewegung reduzieren“ bleiben. Die Ladeanzeige der Statistik (vorher 0,45 s gefedert) und die Statusanzeige des Abgleichs (beim Erscheinen 0,5 s gefedert) erscheinen jetzt beide mit `statusAnimation` (0,45 s). In der App steht kein `.spring` mehr.
- **Ein Radius für Klassisch-Bedienelemente:** Neu ist `AppStyle.atelierControlRadius` (10). Bisher hatten Leisten und Suchfeld 10, Knöpfe und Menü-Auswahl 9. Knöpfe und Menü-Auswahl sind damit 1 pt runder. Die Auswahl in einer Leiste nimmt `atelierControlRadius - 3`, weil sie 3 pt eingerückt sitzt. Das war vorher die freie Zahl 7, und beide Ecken laufen damit parallel. Die Hover-Fläche der Menüzeilen heißt jetzt `AppStyle.menuRowRadius` (6, unverändert). In den Design-Bausteinen steht kein freier Eckenradius mehr.
- Geprüft: Debug-Build ohne Warnungen, alle 205 Tests erfolgreich. Mit `--snapshot` habe ich die Demo in Klassisch angesehen: Collection mit Toolbar in hell und dunkel, Einstellungen „Darstellung“ (Auswahlfelder) und „Discogs“ (Knöpfe, Eingabefeld). Seitenauswahl, Suchfeld, Knöpfe und Auswahlfelder haben dieselbe Rundung, und die helle Auswahl läuft parallel zur Leiste. Die neuen Bewegungen habe ich nicht gesehen, ein Standbild zeigt keine Animation. Modern ändert sich nur bei den Bewegungen, nicht bei den Radien.

# Durchsicht der Logik: Herausnehmen einmal, Absturzstellen geprüft · 20.10.2026

- **`PositionService.takeOut`:** „Platten aus ihren Fächern nehmen und die Lücken schließen“ stand dreimal fast wortgleich in `PositionService`: beim Herausnehmen mehrerer Platten, bei „Ohne Regalplatz“ und bei „Alle verkauft“. Jetzt gibt es eine private Funktion dafür. Bei „Alle verkauft“ wurde gegen die IDs der Verkaufsmarken gefiltert statt gegen die der verkauften Platten. Das Ergebnis ist gleich, weil die verkauften Platten genau alle Platten mit diesen IDs sind.
- **Durchgesehen ohne Änderungsbedarf:** Modelle, Speicher, Änderungsverfolgung (`LibraryChanges`, `LibraryRecords`), Suchindex, Fachbeschriftungen und ihre Zwischenspeicher, Positionsdienst, Discogs-Client. Die heißen Stellen sind dort schon gezielt auf Tempo gebaut (gemeinsamer Bestand statt einer Abfrage je Seite, zwischengespeicherte Sortierschlüssel und Fachgrenzen, Suchindex erst bei Bedarf).
- **Mögliche Absturzstellen geprüft:** Jedes `!`, `try!`, `as!` und `fatalError` der App ist durchgesehen. Alle sind abgesichert. Der Discogs-Benutzername wird vor dem Einsetzen in die URL kodiert. `AppLog.directory!` läuft nur nach der Prüfung, dass der Ordner existiert. `labels[$0]!` folgt auf die Schleife, die jeden Eintrag setzt. `fatalError` steht nur in den Xcode-Vorschauen.
- Geprüft: Debug-Build ohne Warnungen, alle 205 Tests erfolgreich, darunter 17, die Herausnehmen, „Ohne Regalplatz“ und „Alle verkauft“ abdecken.

# Durchsicht: gleiche Bausteine zusammengelegt, Animationen zentral · 20.10.2026

- **Namens-Popover:** „Namen ändern …“ (gesperrtes Fach) und „Regal umbenennen …“ waren Zeile für Zeile gleich gebaut. Sie nutzen jetzt einen gemeinsamen Baustein `NamePopoverLayout` (in `ShelfOptionsPopover.swift`, `private`) mit denselben Modifiern in derselben Reihenfolge. Speichern, Fokus und Schließen bleiben bei den beiden Popovern.
- **Rechtsklick-Erkennung:** Die Prüfung „Rechtsklick oder Klick mit Control“ stand in `SecondaryClicks.swift` zweimal wortgleich. Jetzt gibt es sie einmal als `isSecondaryClick` (`private`, dieselbe Datei).
- **Animationen aus `AppStyle`:** Neue Stufen mit genau den bisherigen Werten. `statusAnimation` (0,45 s) für Statuszeilen und Statistik-Ladeanzeige, `progressAnimation` (0,35 s) für Fortschritt, `selectionAnimation` (0,3 s) für die Glaslinse der Auswahlfelder, `growAnimation` (0,7 s, 0,05 s verzögert) für wachsende Balken, `rollAnimation` (0,8 s) für rollende Zahlen. Ein `.smooth(duration:)` steht jetzt nur noch in `AppStyle`. Sichtbar ändert sich nichts.
- **Bewusst nicht geändert:** Doppelt ist auch einiges in Collection und Wantlist (Neuladen, Suche verlassen, Raster-Breite). Zusammenlegen hieße, Teile von `body` in eine andere Datei zu legen, die der Release-Build einzeln übersetzt. Die beiden Statistik-Paare (Hover in Balken und Ring, Zeile und Kachel einer Gruppe) ähneln sich nur im Aufbau. Ein neuer `JSONDecoder` bzw. `JSONEncoder` pro Platte in Statistik und Abgleich kostet laut Messung (10 000 Durchläufe, `-O`) unter 2 % gegenüber einem wiederverwendeten und bleibt.
- Geprüft: Debug-Build ohne Warnungen, alle 205 Tests erfolgreich. Die beiden Popover habe ich nicht geöffnet angesehen. Ihr Inhalt ist derselbe Code, nur an eine Stelle verschoben.

# Test-Attrappen in eigenen Dateien · 20.10.2026

- Die URL-Attrappen von `ScenarioTests` (`ScenarioProtocol`) und `StatisticsTests` (`StatisticsURLProtocol`, `StatisticsRequestLog`, `StatisticsHook`) liegen jetzt wie bei den Abgleich-Tests in eigenen Dateien (`ScenarioTestStubs.swift`, `StatisticsTestStubs.swift`). Nur verschoben, der Zeilenbestand ist gleich.
- Die übrigen App-Dateien über 300 Zeilen bleiben bewusst ganz: `WantlistView`, `PageStack`, `ShelfAutoBackup`, `ShelfFurniture`, `StatisticsCharts`, `AppearanceSettingsView`, `ExportSettingsView`. Jede ist ein geschlossener Typ oder eine zusammengehörige Gruppe. Teilen würde `private` öffnen oder, bei Ansichten, Teile von `body` in andere Dateien verlegen, die der Release-Build einzeln übersetzt.
- Geprüft: alle 205 Tests erfolgreich.

# Toter Code: verwaiste Texte und überflüssige Imports entfernt · 20.10.2026

- **Gesucht:** Jede Deklaration der App ist gegen den gesamten Quelltext gezählt. Jedes `private` Mitglied ist zusätzlich in seiner eigenen Datei gezählt, denn nur dort kann es benutzt werden. Ungenutzte Funktionen, Typen, Werte oder Enum-Fälle gibt es keine. Die Treffer waren Fehlalarme: der App-Einstieg, `applicationShouldTerminateAfterLastWindowClosed` (ruft macOS auf), die Pflichtangaben der Schema-Versionen und `appDelegate` (der Property-Wrapper meldet den Delegate allein durch seine Existenz an).
- **Bewusst behalten:** `DiscogsBasicInformation.resource_url` wird in der App nicht gelesen, steht aber im gespeicherten JSON jeder Platte (`basicInformation`). Ein Abgleich schreibt nur, wenn sich dieses JSON ändert. Ohne das Feld sähe beim nächsten Abgleich jede Platte geändert aus und würde neu geschrieben.
- **Textkatalog:** 53 von 61 als veraltet markierten Einträgen in `Localizable.xcstrings` kommen im Code nicht mehr vor, auch nicht mit eingesetzten Werten (`%@` als `\(…)`). Es sind ältere Fassungen heutiger Texte, etwa „Exemplar bearbeiten …“ neben „Exemplar bearbeiten“. Sie sind entfernt, zusammen mit ihren englischen Übersetzungen. Die übrigen 8 kommen im Code noch vor und bleiben. Die Datei ist im Format von Xcode zurückgeschrieben, der Diff besteht nur aus entfernten Zeilen.
- **Imports:** 102 nicht gebrauchte `import`-Zeilen in 74 Dateien sind entfernt. Die meisten stammen aus der Aufteilung, bei der jede neue Datei alle Imports ihrer Ursprungsdatei bekommen hatte. Zur Laufzeit ändert das nichts.
- Geprüft: Debug- und Release-Build ohne Warnungen, alle 205 Tests erfolgreich. Nach dem Entfernen der Imports brauchte keine Datei einen davon zurück.

# Aufteilung nachgeschärft: Ansichten wieder ganz, Abgleich wieder gekapselt · 20.10.2026

- **Ansichten wieder in einer Datei:** `KallaxView`, `CollectionView` und `ShelfContentsView` sind nicht mehr per Erweiterungen verteilt, sondern stehen wieder je in einer Datei, mit allen ursprünglichen `private`. Grund ist die Geschwindigkeit. Der Release-Build übersetzt die Dateien einzeln (`-enable-batch-mode`, nicht das ganze Modul gemeinsam). Ruft `body` dann Teilansichten aus anderen Dateien auf, sieht der Compiler den Typ hinter `some View` womöglich nicht und optimiert schlechter. Ob das messbar wäre, ist offen, aber es lässt sich nicht ausschließen. Ganze Typen in eigenen Dateien betrifft das nicht, die waren auch vorher schon aus anderen Dateien aufgerufen. `KallaxView.swift` und `ShelfContentsView.swift` sind identisch mit dem Stand vor der Erweiterungs-Aufteilung. `CollectionView.swift` unterscheidet sich nur dadurch, dass `CollectionCoverGroup` als eigener Typ in `CollectionCoverGroup.swift` liegt.
- **`DiscogsSyncService` wieder gekapselt:** Die Tracklisten greifen auf den inneren Zustand des Dienstes zu (laufende Aufgaben, Anzeige, API-Client) und stehen deshalb wieder in `DiscogsSyncService.swift`. Alle 12 `private` sind wieder da. Damit lassen sich `run`, `task` und die Tracklisten-Aufgaben nicht mehr von außen erreichen und die Sperre gegen einen zweiten gleichzeitigen Abgleich nicht umgehen. Nur das Zusammenführen (`merge`) liegt in `DiscogsSyncService+Merge.swift`. Das ist eine eigenständige statische Funktion ohne privaten Zustand, die schon vorher modulweit sichtbar war, weil die Tests sie aufrufen.
- README: Zeilen „Oberfläche“ und „Discogs“ angepasst.
- Geprüft: Debug-Build ohne Warnungen, alle 205 Tests erfolgreich. `KallaxView.swift` und `ShelfContentsView.swift` sind per `git diff` gleich dem Stand vor der Aufteilung, `CollectionView.swift` mit `CollectionCoverGroup.swift` zusammen zeilengleich.

# Code in übersichtliche Dateien aufgeteilt · 20.10.2026

Große Dateien sind entlang ihrer Typen in kleinere zerlegt, große Einzeltypen per Erweiterungen nach Themen. Verschoben werden nur ganze Deklarationen samt ihren Kommentaren, ohne Änderung an der Logik. Wo ein Hilfstyp jetzt aus einer anderen Datei gebraucht wird, verliert er sein `private`; sonst bleibt alles, wie es war. Neue Dateien sind in `project.pbxproj` eingetragen.

- **`Design/` (neu, aus `Utilities/AppAppearance.swift`, vorher 1711 Zeilen):** `AppStyle`, `AtelierPalette`, `AppAppearance` (Grundaussehen, Hintergrund), `AppSurfaces`, `AppButtons` (mit `GlassStepper`), `AppPickers`, `AppMenu`, `AppSearchField`, `AppMessages` (Plakette, Banner, Leerzustand), `AppPanel`, `AppInput` (Fokusringe, Eingabequelle), `RecordCaption`, `CoverGrid`, `ViewObservation`, `ActivityRing`, `PullToRefresh`, `SecondaryClicks`. Die größte Datei hat jetzt 182 Zeilen. `AtelierButtonStyle` ist nicht mehr `private`, weil ihn Knöpfe und Flächen nutzen.
- README: Zeile „Oberfläche“ nennt `Design/` und seine Dateien.
- **`Views/Shelf/`:** `ShelfAssignment.swift` (777) gibt die Sitzung von „Platte hinzufügen“ an `ShelfAssignmentSession.swift`, „Sortierung prüfen“ an `ShelfSortCheckView.swift` und die gemeinsam genutzte Karte an `AssignmentCard.swift` ab. `ShelfCopyTable.swift` (1071) heißt jetzt nach seinem Inhalt `ShelfContentsView.swift` und gibt `ShelfCopyItem`, `ShelfTableScrollBridge`, `ShelfCopyQuickEditor` und `TableRowClickToggle` in eigene Dateien ab. Die Spaltenköpfe ohne Rahmen, die auch Collection und Wantlist nutzen, liegen jetzt in `Design/QuietIconColumnHeaders.swift`. Aus `KallaxView.swift` gehen `ShelfRequests` und `ShelfSearch` nach `ShelfRequests.swift`, aus `ShelfFurniture.swift` die Status-Plaketten nach `ShelfStatusBadges.swift`. `ShelfSearchAndPlacement.swift` ist geteilt in `ShelfSearchResults.swift` und `PlacementCard.swift`. Nicht mehr `private`: `ShelfCopyQuickEditor`, `ShelfTableScrollBridge` und `TableRowClickToggle`. Vier `MARK`-Zeilen, die nach dem Teilen am falschen Ende standen, sind entfernt. Noch groß sind `KallaxView` und `ShelfContentsView` als je ein einzelner Typ, siehe unten.
- README: Zeile „Regal“ nennt `ShelfAssignmentSession.swift` und `ShelfSortCheckView.swift`.
- **`Views/`:** Die Wantlist (`WantlistView` samt Karte und Sortierung) hat eine eigene Datei `WantlistView.swift` statt in `DiscogsSyncView.swift` zu stehen. Aus `CollectionView.swift` geht `RecordCard` mit Cover-Rahmen und Trackzeile nach `RecordCard.swift`. Aus `RootView.swift` gehen der schwebende Knopf mit Aktionen (`FloatingControls.swift`, mit dem Klick-außerhalb-Wächter) und das Suchfeld der Toolbar (`ToolbarSearchField.swift`, mit `LibrarySearch`). `PageStack.swift` (344) bleibt ganz: Brücke, Seitenansicht und Sichtbarkeit sind dort über `fileprivate` absichtlich so verschränkt, dass nur die Brücke Seiten umschaltet. Teilen hieße, diese Sperren zu öffnen.
- **`Views/Settings/`:** Aus `AppSettingsView.swift` (582) gehen die gemeinsamen Bausteine (`SettingsPage`, `SettingsCard`, `SettingsRow`, `SettingsNote`) nach `SettingsComponents.swift`, „Allgemein“ und „Tastenkürzel“ nach `GeneralSettingsView.swift` und „Darstellung“ mit den Design-Vorschauen nach `AppearanceSettingsView.swift`. Aus `ShelfSettingsView.swift` gehen Anlegen und Bearbeiten eines Regals nach `CabinetEditor.swift`.
- **`Statistics/`:** `StatisticsCards.swift` (744) ist je Karte geteilt: `StatisticsHero.swift` (Überblick, umbenannt), `StatisticsFacts`, `SoundDonut`, `ArtistPodium`, `RandomRecordCard`, `LabelBoard`. Aus `StatisticsView.swift` gehen Abschnitte, Spalten, Farben und `RollingNumber` nach `StatisticsLayout.swift` und der Kartenrahmen nach `StatisticsMovableArea.swift`.
- Nicht mehr `private`: `FloatingControls`, `ToolbarSearchField`, `CabinetCreator`, `CabinetEditor`, `StatisticsMovableArea`. Neun `MARK`-Überschriften, die beim Schnitt am Ende der vorigen Datei hingen, stehen jetzt am Anfang der Datei, zu der sie gehören.
- README: Zeile „Seiten“ nennt `ToolbarSearchField.swift` und `FloatingControls.swift`. STATISTIK.md: Dateitabelle mit den neuen Statistik-Dateien.
- **Dienste und Logik:** `ShelfBackupService.swift` (628) teilt sich in das Format (`ShelfBackup.swift`, mit Fehlern und Vorschau), den Dienst und die automatische Sicherung (`ShelfAutoBackup.swift`). `CollectionExportService.swift` (490) gibt die Optionen an `ExportOptions.swift` und die CSV- und PDF-Schreiber an `ExportWriters.swift` ab. `DiscogsSyncService.swift` gibt Umfang, Stand und Zusammenfassung eines Abgleichs an `DiscogsSyncSummary.swift` ab. `SortingService.swift` (438) gibt die Suchindizes (`SearchIndex.swift`), die Platzsuche (`AlphabeticalPlacement.swift`) und die Umstellschritte (`ShelfSortCheck.swift`) ab. `AppPreferences.swift` (401) gibt die Wahlwerte an `DisplayChoices.swift` und `AppearanceChoices.swift` und die Kürzel an `AppShortcuts.swift` ab. `CoverLoader.swift` heißt nach seinem Inhalt jetzt `CoverCache.swift`, die Ansicht `CoverView` liegt in `Views/CoverView.swift`. Hier musste nichts sichtbar gemacht werden. Drei `MARK`-Überschriften stehen jetzt bei ihrem Abschnitt.
- README: Zeilen „Sortierung“, „Sicherung“, „Export“ und „Discogs“ nennen die neuen Dateien.
- **Große Einzeltypen per Erweiterungen:** `KallaxView` (766) ist verteilt auf `KallaxView.swift` (Zustand und `body`, 306) und `KallaxView+Shelf` (Fachdetail, Auswahl, Menü), `+Cabinets` (Regalumschalter), `+Placement` (Platzieren, Herausnehmen, Rückgängig) und `+Search`. `CollectionView` (568) ist verteilt auf `CollectionView.swift`, `+Data` (Liste aufbauen, Suche, Beschriftungen) und `+Actions` (Kontextmenüs, Knöpfe), `CollectionCoverGroup` hat eine eigene Datei. `ShelfContentsView` (492) ist verteilt auf `ShelfContentsView.swift`, `+Grid` und `+Table`. `DiscogsSyncService` (475) ist verteilt auf `DiscogsSyncService.swift` (Abgleich), `+Tracklists` und `+Merge`. `WantlistView` (427, davon rund 350 der Typ selbst) bleibt ganz. Gespeicherte Werte (`@State` usw.) dürfen nicht in Erweiterungen stehen und bleiben im Haupttyp. Was eine andere Datei des Typs braucht, ist nicht mehr `private`. Damit kein Name aus einer Erweiterung heraus versehentlich auf etwas anderes zeigt (passiert wäre das bei `searchFocused`, das sonst den gleichnamigen SwiftUI-Modifier getroffen hätte), ist jedes Mitglied sichtbar gemacht, dessen Name in einer anderen Datei desselben Typs vorkommt. Jeder Name zeigt damit auf dasselbe wie vorher in der einen Datei. Was nur in einer Datei gebraucht wird, bleibt `private`.
- **Tests:** `LibraryTests.swift` (1087) ist geteilt. Gemeinsame Wurzel `AllTests` und `DiscogsAPIClient.stubbed` liegen in `TestSupport.swift`, `DiscogsClientTests` mit seiner Attrappe in eigener Datei, die drei kleinen Suites in `UtilityTests.swift`. Die Suite `LibraryTests` ist nach Themen verteilt: `+Shelves`, `+Marks`, `+App`, `+Sorting`, `+Data`, `+Placement`. `DiscogsSyncTests.swift` (502) gibt `+Merge`, `+Fetching` und die URL-Attrappen (`DiscogsSyncTestStubs.swift`) ab. Die gemeinsamen Hilfsfunktionen der beiden Suites sind nicht mehr `private`. Die übrigen Testdateien bleiben mit 250 bis 380 Zeilen, wie sie sind.
- README: Zeilen „Oberfläche“, „Discogs“ und „Tests“ nennen die Erweiterungen.
- Geprüft: Für jede aufgeteilte Datei ist der Zeilenbestand ohne Leer- und `import`-Zeilen vorher und nachher gleich, abgesehen von den genannten Zugriffsänderungen und den Rahmen der Erweiterungen. Es hängen keine Abschnittskommentare an der falschen Stelle. Kein `private` Name wird aus einer anderen Datei desselben Typs benutzt. Debug- und Release-Build ohne Warnungen, alle 205 Tests in 13 Suites erfolgreich, also dieselbe Zahl wie vorher. Die Oberfläche habe ich nicht eigens angesehen, weil sich am Code nichts außer der Verteilung auf Dateien und der Sichtbarkeit geändert hat.

# Alte Schema-Versionen V1–V14 entfernt · 20.10.2026

- **Schema-Datei gekürzt:** `Models/LibrarySchemas.swift` enthält nur noch V15 und das aktuelle V16, dazu einen einzigen Migrationsschritt V15 → V16. Die Datei hat jetzt 221 statt 1412 Zeilen. Weggefallen sind die eingefrorenen Kopien von V1 bis V14 und die beiden eigenen Migrationsschritte V7 → V8 (reservierte Fächer) und V10 → V11 (Einträge ohne Discogs-IDs). Jede ausgegebene Version ab 1.0.2 hatte schon V15. Auf diesem Mac gibt es nur V15- und V16-Datenbanken, und die App ist bisher nicht weitergegeben worden.
- **Folge:** Eine Datenbank, die älter als V15 ist, lässt sich nicht mehr öffnen. SwiftData meldet dann `unknownDataStoreSchema`, und die App zeigt ihre Fehlerseite „Sammlung konnte nicht geöffnet werden“. Die Datei bleibt dabei unverändert. Sicherungen sind nicht betroffen, denn sie sind JSON mit eigener Versionsnummer.
- **Tests:** Die sechs Migrationstests aus V2, V3, V6, V10, V11 und V13 sind entfernt. Neu ist `v15StoreMigratesToV16KeepingEverything`. Der Test legt eine V15-Datenbank mit Regal, Fach, Platten, „Gesucht“, Ausschluss, Wantlist und Konto an, öffnet sie als V16 und prüft, dass alles erhalten ist und die Verkaufsliste funktioniert.
- Kommentar in `LibraryStorage.prepareShelves` angepasst (keine Datenbanken mehr von vor den Regalen). README, Abschnitte Modelle und Tests, sowie STATISTIK.md (keine Migrationstests mehr, jetzt 27 Tests) nachgezogen.
- Geprüft: Vor dem Umbau habe ich in einer Wegwerf-Kopie mit Kopien der echten Datenbanken verglichen. Die heutige Fassung öffnet V14, V15 und V16. Die gekürzte öffnet V15 (844 Exemplare, wird auf V16 gebracht) und V16 (850 Exemplare, 5 zum Verkauf), eine eigens erzeugte V14-Datenbank aber nicht (`unknownDataStoreSchema`, Daten bleiben unverändert). Danach im Projekt: Debug-Build ohne Warnungen, alle 205 Tests erfolgreich. Die Debug-App öffnete die echte Sammlung laut Protokoll mit 850 Exemplaren und 878 Wantlist-Einträgen.

# DMG kompakt mit Petrolband und Schallplatte, ohne Handbücher · 18.10.2026

- **Neues, kompaktes Fenster** (540 × 380 statt 880 × 400): nur noch die App, der Pfeil und der Programme-Ordner, eng zusammengerückt (Mitten bei 140 und 400, Höhe 178). Grundlage ist das allererste Design (Papier mit hellem Schein, Pfeil petrol mit goldener Spitze, Schallplatte mittig aus dem unteren Rand). Equalizer und Noten bleiben weg. Oben steht wieder das petrolfarbene Band der Handbuch-Titelseite mit „Plattenregal“ in New York und dem Goldstrich. Den Installationshinweis gibt es nicht mehr, ebenso keine Fußzeile. Die Platte ist kleiner (150 statt 168 pt), damit ihr goldenes Etikett im niedrigeren Fenster unter den Beschriftungen noch hervorlugt.
- **Handbücher nicht mehr in der DMG:** Handbuch und User Guide stecken nur noch in der App (Hilfe → Handbuch). `make-dmg.sh` kopiert sie nicht mehr in die DMG, prüft aber weiter, dass beide in der App liegen. Ausprobierte Zwischenstände dieses Abends (Regal-Fächer im Stil der Regalseite, Handbuch-Band mit Fußzeile) sind verworfen.
- **Texte nachgezogen:** Der Installationsschritt in `Handbuch.html` und `Handbook.html` nennt nur noch App-Symbol, Pfeil und Programme-Ordner, die Kopfkommentare sprechen von der Broschüre zur App. Beide PDFs sind neu erzeugt, es bleiben je zehn Seiten. Auf der Webseite (`Webseite/index.html`) steht unter „Installieren“ jetzt, dass das Handbuch in der App steckt (DE/EN). Die Webseite ist unter derselben Adresse neu veröffentlicht (Version 7, nur `index.html`, die Bilder blieben). In der veröffentlichten Datei stehen beide neuen Sätze, der alte nicht mehr. Im Browser habe ich sie nicht angesehen. README: Abschnitte zur DMG und zum Handbuch angepasst.
- **DMG:** `dist/Plattenregal-1.1.2.dmg` neu ausgegeben, Version bleibt 1.1.2. Die PDFs in `dist/` sind erneuert.
- Geprüft: Hintergrund in 2x gerendert und angesehen. Das Finder-Fenster der eingehängten DMG habe ich als Fensteraufnahme angesehen: Band mit Titel, App und Programme mit Pfeil, Beschriftungen frei über der Platte, Etikett sichtbar. `hdiutil verify` gültig, Signatur gültig. Die DMG enthält nur `Plattenregal.app` und `Applications`, die PDFs in der App sind byte-gleich mit denen im Repository. Im Text beider PDFs habe ich den geänderten Installationsschritt geprüft.

# DMG: Schallplatte zurück, ohne Hinweistexte · 18.10.2026

- **Schallplatte:** Beim Umbau auf den Handbuch-Stil heute Morgen war sie zusammen mit Noten und Equalizer entfallen. Jetzt steigt sie wieder mittig aus dem unteren Rand auf: schwarz mit Rillen, Glanz und Schatten, das goldene Etikett lugt hervor, wie früher und wie im App-Symbol. Noten, Equalizer und der helle Schein bleiben weg.
- **Weniger Text:** Der Hinweis „Zum Installieren Plattenregal auf den Programme-Ordner ziehen.“ samt englischer Zeile ist entfernt, ebenso die Kennzeile „Installieren · Install“ im Band. Titel und Goldstrich stehen jetzt mittig im Band. Die Fußzeile mit Version und „macOS 27 · Apple Silicon“ bleibt unten. Kurz stand sie oben im Band, unten wirkt sie aber besser.
- Geändert ist nur `Scripts/dmg-background.swift`; Fenster (880 × 400) und Symbolpositionen in `make-dmg.sh` bleiben gleich.
- **DMG:** `dist/Plattenregal-1.1.2.dmg` neu ausgegeben, Version bleibt 1.1.2.
- README: Beschreibung des DMG-Fensters angepasst.
- Geprüft: Hintergrund in 2x gerendert und angesehen. Das Finder-Fenster der eingehängten DMG habe ich als Fensteraufnahme angesehen: Die Platte steht mittig unter den Symbolen, die Beschriftungen („Plattenregal“, „Applications“, „Handbuch“, „User Guide“) stehen frei auf dem Papier, die Fußzeile ist beidseits frei. `hdiutil verify` gültig, eingehängt Version 1.1.2, Signatur gültig, beide PDFs byte-gleich mit denen im Repository.

# Symbolgrößen als zentrale Stufen · 18.10.2026

- **Neu in `AppStyle`** (Abschnitt „Symbols“): Symbole neben Text nehmen weiter dessen Schrift. Allein stehende Symbole haben jetzt eine von vier Stufen statt eigener Zahlen: `buttonSymbol` (11 pt, semibold) für die Zeichen in kleinen runden Knöpfen, `statusSymbol` (22 pt) vor Statuszeilen und abgehakten Schritten, `cardSymbol` (30 pt) vor einer Karte mit Seitentitel und `emptyStateSymbol` (40 pt, light) für leere Seiten.
- **Umgestellt:** das „+“ am Fach (`ShelfFurniture`), der Knopf „Bei Discogs öffnen“ in der Detailkarte, die Stepper-Pfeile (`GlassStepButton`), das Standort-Symbol der Detailkarte, die Häkchen und Pfeile in „Sortierung prüfen“ (dreimal) und das Symbol des gemeinsamen Leerzustands (`AppEmptyState`). Sichtbare Änderungen: Der Discogs-Knopf hatte `bold` statt `semibold`, die Stepper-Pfeile 10 statt 11 pt. Jetzt haben gleiche Knöpfe dasselbe Gewicht und dieselbe Größe. Alles andere ist zahlengleich. Der Platzhalter im leeren Cover bleibt relativ zur Covergröße, weil er gezeichnet ist.
- **Debug:** `--preview-detail=Interpret` öffnet die Detailkarte dieser Platte von der Statistik aus, damit sie sich ohne Klick aufnehmen lässt.
- README: Zeile „Oberfläche“ nennt die Symbolstufen, die Debug-Argumente nennen `--preview-detail`.
- Geprüft: Debug-Build und alle 210 Tests erfolgreich. In der Demo (hell) in **Klassisch** per `--snapshot` angesehen: „+“ am gewählten Fach, „Sortierung prüfen“ mit „Alles umgestellt“ und abgehaktem Schritt, Detailkarte mit Standort-Symbol, Regal-Einstellungen. In **Modern** dasselbe: Regalseite und Einstellungen per `--snapshot`, „Sortierung prüfen“ und Detailkarte als echte Bildschirmaufnahme, weil `--snapshot` dort die Glas-Panels nicht mitzeichnet. Alles sitzt wie vorher. Nicht gesehen: den Discogs-Knopf (die Demo hat keine Discogs-Links) und die Stepper (sie erscheinen nur bei „Eigene Größe …“, das sich per Startargument nicht öffnen lässt).
- **DMG:** `dist/Plattenregal-1.1.2.dmg` neu ausgegeben, Version bleibt 1.1.2 (102026). Damit enthält sie auch die Code-Durchsicht vom selben Tag (Tracklisten-Start, Radien). Handbuch-PDFs unverändert. Geprüft: Release-Build erfolgreich, `hdiutil verify` gültig. Eingehängt: Version 1.1.2, Signatur gültig, App-Binärdatei identisch mit dem frischen Release-Build dieses Stands, beide PDFs byte-gleich mit denen im Repository. Das Finder-Fenster der DMG habe ich nicht geöffnet.

# Code-Durchsicht: Tracklisten-Start abgesichert, Radien und Kennzahl zentral · 18.10.2026

- **Durchgesehen:** Datenmodell und Migrationen, Speicher und Instanzsperre, Discogs-Client (Ratenbremse, Seitenprüfung, Wiederholungen), Sync und Zusammenführung, Tracklisten, Positionen, Regale, Sicherung und Wiederherstellung, Zurücksetzen, Export (CSV/PDF, automatisch), Cover-Cache, Statistik und die Regalseite. Die Logik ist durchweg transaktional und gegen gelöschte Objekte abgesichert; bis auf die Punkte unten war nichts zu korrigieren.
- **Tracklisten beim Start:** `resumeTracklistsIfNeeded` prüfte „kein Sync läuft“ nur vor dem Warten auf den Discogs-Client. Startete genau in diesem Moment ein Sync, lief der Tracklisten-Download neben dessen Zusammenführung derselben Releases. Die Bedingung wird jetzt nach dem Warten noch einmal geprüft; der Sync lädt die Tracklisten danach ohnehin selbst.
- **Platzierungskarte:** `refreshPlacement` prüft wie die übrigen Stellen der Regalseite neben dem fehlenden Kontext auch `isDeleted`, bevor es die Platte liest.
- **Einheitliches Design:** In den Ansichten standen Eckenradien als freie Zahlen: 8 für Zeilen, kleine Kacheln und ihre Hover-/Auswahlflächen (Regal-Einstellungen, Suchtreffer, Sortierung prüfen, Statistik-Legende und -Kacheln), 16 für die Platzierungskarten. Neu in `AppStyle` sind `rowRadius` (8) und `featureRadius` (16), auch `accentGlassCard` nutzt jetzt `featureRadius`. Die große Kennzahl der Statistik (44 pt, zweimal gleich gebaut) ist jetzt `AppStyle.heroFigure`. Der nach außen reichende Hover der Einsortier-Zeilen heißt `cardRadius + itemSpacing` statt `cardRadius + 8`, die Legende reicht um `itemSpacing` statt um 8 hinaus. Alle Werte sind zahlengleich, das Aussehen bleibt unverändert. Ausgenommen bleiben gezeichnete Geometrie (Farbfelder, Design-Miniaturen in den Einstellungen, Plattenhülle).
- **Noch offen (Hinweis, nicht geändert):** Einige Symbole haben eigene Größen statt einer zentralen Symbolstufe: 30 pt (Standort-Symbol im Detail), 22 pt (Häkchen „Alles in Ordnung“), 11 pt in den kleinen runden Knöpfen (einmal `bold` in 26 pt, einmal `semibold` in 24 pt).
- README: Zeile „Oberfläche“ nennt die zentralen Stufen in `AppStyle`.
- Geprüft: Debug-Build ohne Warnungen in den geänderten Dateien, alle 210 Tests erfolgreich. Da alle Werte gleich geblieben sind, habe ich die Oberfläche nicht eigens angesehen.

# Suche: keine Collection-/Wantlist-Plaketten mehr auf den Covern · 18.10.2026

- Seit die Suche nur noch die Rubrik durchsucht, in der man gerade ist, war die Plakette oben links auf den Treffer-Covern überflüssig. Sie zeigte immer die eigene Rubrik („Collection“ in der Collection, „Wantlist“ in der Wantlist) und nur selten die andere, nämlich wenn genau dieselbe Discogs-Release in beiden steht. Sie ist in beiden Rubriken entfernt, ebenso `PlacementBadge` und die nur dafür geführten Mengen der Release-IDs (`wantedReleaseIDs` in der Collection, `ownedReleaseIDs` in der Wantlist). Die Wantlist baut sich deshalb nicht mehr neu auf, wenn sich die Collection ändert. `WantlistView` braucht den Seitenumschalter nicht mehr.
- Die Texte „In der %@“ und „In der %@ anzeigen“ sind im String-Katalog als veraltet markiert.
- README: Absatz zur Suche angepasst.
- Handbuch (DE/EN) und Webseite erwähnen die Plaketten nicht, und keines ihrer Bilder zeigt ein Suchergebnis. Sie bleiben daher unverändert.
- Geprüft: Debug-Build und Tests erfolgreich. Demo mit Suche „a“ als Schnappschuss in Collection und Wantlist (Klassisch hell): keine Plaketten, Cover und Beschriftung wie bisher.
- Gesamtprüfung vor der DMG: Schnappschüsse aller vier Seiten (Collection, Wantlist, Regal, Statistik) in Klassisch und Modern (hell), dazu die Suche „daft“ in Collection und Regal (Klassisch dunkel). Aufbau, Beschriftung, Regalfächer, Trefferliste und Statistik sind stimmig, es war nichts zu korrigieren. Die Plakette „Gesucht“ im Regal gehört zur App-eigenen Liste vermisster Platten und bleibt. In Modern zeichnet `--snapshot` das Glas flacher als auf dem Bildschirm; das Glas selbst habe ich nicht am Bildschirm angesehen.
- **DMG:** `dist/Plattenregal-1.1.2.dmg` neu ausgegeben, Version bleibt 1.1.2. Handbuch-PDFs unverändert. Geprüft: Release-Build erfolgreich, `hdiutil verify` gültig. Eingehängt: Version 1.1.2, Signatur gültig, App aus dem Stand dieses Commits gebaut (`PlacementBadge` nicht mehr im Programm), beide PDFs byte-gleich mit denen im Repository. Das Finder-Fenster der DMG habe ich nicht geöffnet.

# DMG 1.1.2 mit neuer Startauswahl, Regalbild erneuert · 18.10.2026

- **Handbuch und Webseite geprüft:** Die Texte bleiben, wie sie sind. Sie sprechen nur vom „gewählten Fach (Goldrand)“ und nennen „A – Be“ als Beispiel. Das Bild der Regalseite (`Handbuch/Bilder/de|en/shelf.jpg`, von der Webseite mitbenutzt) zeigte noch „Po – Ra“ unten links ausgewählt. Es ist neu aufgenommen und zeigt jetzt „A – Be“ oben links mit dem Inhalt A Tribe Called Quest bis Beastie Boys.
- **Zuschnitt:** Im neuen Fach trägt Aphex Twin die Plakette „Gesucht“/„Looking for“, die der bisherige Zuschnitt (oberste 75 % des Fensters) halb abschnitt. `Scripts/guide-screenshots.swift` nimmt für dieses Bild jetzt 78 % (1600 × 809 statt 778 px), die Höhenangabe in `Webseite/index.html` ist angepasst. Die übrigen Bilder sind unverändert; das neu aufgenommene Statistikbild unterschied sich nur in der Uhrzeit von „Stand …“ und wurde verworfen.
- **PDFs** `Plattenregal/Handbuch.pdf` und `Handbook.pdf` neu erzeugt (über `make-dmg.sh`), dazu die Kopien in `dist/`.
- **Webseite** unter derselben Adresse neu veröffentlicht (Version 6) mit `index.html` und den beiden Regalbildern.
- **DMG:** `dist/Plattenregal-1.1.2.dmg` neu ausgegeben, Version bleibt 1.1.2.
- Geprüft: Beide Regalbilder angesehen, Plakette vollständig. Seite 6 beider PDFs als Bild angesehen: Bild und Text passen, weiterhin 10 Seiten. Release-Build erfolgreich, `hdiutil verify` gültig. Eingehängt: `Handbuch.pdf` und `User Guide.pdf` sowie das Handbuch in der App byte-gleich mit `Plattenregal/Handbuch.pdf` bzw. `Handbook.pdf`, Signatur gültig, App-Binärdatei frisch gebaut. Auf der Webseite haben die Regalbilder dieselbe Dateigröße wie die lokalen. Die Webseite habe ich nicht im Browser angesehen, das Finder-Fenster der DMG nicht geöffnet.

# Regal: einheitliche Startauswahl ab oben links · 18.10.2026

- Beim Öffnen der Regal-Seite war bisher das Fach **unten links** im ersten Regal aktiv, beim Wechsel zu einem anderen Regal dagegen das erste belegte Fach **oben links**. Begründet war unten links damit, dass dort das Alphabet beginne. Die App sortiert aber in Leserichtung ab Fach 1 oben links ein, dort steht also das A.
- Jetzt gilt für beide Fälle eine Regel (`startShelf(in:)` in `KallaxView`): das erste belegte, nicht gesperrte Fach des Regals in Leserichtung, sonst sein erstes Fach. Ist das erste Regal leer, wird wie bisher das erste belegte Fach eines anderen Regals gewählt. Eine bestehende Auswahl (Klick, „Im Regal zeigen“, Einordnen) bleibt unverändert. Wie das echte Regal eingeräumt ist, spielt für die Auswahl keine Rolle; eine Einstellung zur Füllrichtung gibt es bewusst nicht.
- Geprüft: Debug-Build und 210 Tests erfolgreich. In der Demo (Klassisch, hell) per `--snapshot` angesehen: beim Start ist „A – Be“ oben links mit Goldrand ausgewählt statt „Po – Ra“ unten links. Den Regalwechsel (Wohnzimmer → Flur) habe ich nicht in der laufenden App angeklickt; seine Regel ist inhaltlich dieselbe wie vorher, sie läuft jetzt nur über die gemeinsame Funktion.

# Webseite: Symbol ohne Rand · 18.10.2026

- Um das App-Symbol oben auf der Webseite lag im Browser ein eckiger, dunkler Rand. Ursache: Der Browser schnitt den CSS-Schatten (`drop-shadow`) am Rahmen des Bildes ab. Im Bildschirmfoto bricht der Schatten etwa 17 px neben der Platte hart ab. WebKit, mit dem das Handbuch gerendert wird, tut das nicht, deshalb war das Handbuch nicht betroffen.
- Jetzt trägt das Bild seinen Schatten selbst: `Scripts/web-icon.swift` zeichnet aus `Handbuch/Bilder/icon.png` das Symbol mit demselben Schatten (Versatz 14, Weichzeichnung 22, Schwarz 35 %) auf eine 704 × 768 px große Fläche und schreibt `Webseite/icon.png`. Die Seite rechnet die Ränder heraus, Größe und Lage des Symbols bleiben gleich. Kein CSS-Filter mehr am Symbol.
- Geprüft: Seite mit WebKit gerendert, Symbol vergrößert angesehen und die Farben quer über die Kante gemessen: gleiche Lage wie vorher, Schatten läuft weich aus, ohne Stufe. Neu veröffentlicht. In deinem Browser selbst nicht angesehen, weil der Browser hier nicht bei claude.ai angemeldet ist.

# Webseite im Stil des Handbuchs · 18.10.2026

- **Neu gestaltet:** Die Seite zur App (`Webseite/index.html`, jetzt im Repository; veröffentlicht unter derselben Artifact-Adresse wie bisher) hat das Design des Handbuchs statt Blau und Grotesk: petrolfarbene Titel-Bande mit Symbol, „Plattenregal“ in New York, Goldstrich, Claim und der Schallplatte vom Handbuch-Titel; darunter Papier mit Kapiteln aus Kennzeile, Titel und Goldstrich, Karten, nummerierte Schritte und Tabellen wie im Handbuch, am Ende die Bande der Rückseite. Dunkel mit den dunklen Klassisch-Farben der App.
- **Inhalt auf dem Stand:** Rückenleiste, Spalte „Vermisst“, Pause-Knopf und die alte Zahl der Einstellungsreiter sind raus. Neu: runder Knopf, Einsortieren mit dem +-Knopf, Suchliste „Gesucht“, Verkaufsliste, zwei Designs, Kürzel wie im Handbuch, „Loslegen“ mit Installieren samt einmaligem „Dennoch öffnen“, Token, Synchronisieren, Regal anlegen sowie Voraussetzungen (Apple-Chip, macOS 27) und Demo.
- **Bilder aus der Demo** statt aus der echten Sammlung (die 15 alten Bilder sind aus dem Artifact entfernt), je Sprache die des Handbuchs; der Umschalter DE/EN tauscht Text und Bilder.
- Geprüft: Seite lokal mit WebKit gerendert und angesehen, Desktop (1280 pt, hell, Deutsch und Englisch) und Handy (400 pt, dunkel, Englisch): kein seitliches Scrollen, alle Bilder geladen. Dabei gefunden und behoben: Einblend-Animationen ließen Titel und Symbol unsichtbar, solange sie nicht liefen (entfernt), und zwei Absätze zerfielen in Zeilen (Raster-Stil am Absatz). Die veröffentlichte Seite selbst habe ich nicht angesehen, weil der Browser hier nicht bei claude.ai angemeldet ist.

# Handbuch-Titelseite ohne Equalizer · 18.10.2026

- Die Titelseite beider Handbücher (`Handbuch/Handbuch.html`, `Handbuch/Handbook.html`) zeigt unten nur noch die Schallplatte auf Petrol; die farbigen Equalizer-Balken links und rechts davon sind entfernt (Markup, CSS und Skript), wie zuvor schon im DMG-Hintergrund. `Plattenregal/Handbuch.pdf` und `Handbook.pdf` neu erzeugt.
- Geprüft: beide PDFs mit `make-guide.swift` (Version 1.1.2) gerendert, je 10 Seiten, die Titelseite beider Fassungen als Bild angesehen. App-Code unverändert, keine Tests ausgeführt.
- **DMG neu ausgegeben:** `Scripts/make-dmg.sh` → `dist/Plattenregal-1.1.2.dmg` (Release-Build erfolgreich, PDFs unverändert übernommen). `hdiutil verify` in Ordnung, eingehängt: `Handbuch.pdf` und `User Guide.pdf` byte-gleich mit `Plattenregal/Handbuch.pdf` und `Handbook.pdf`, Signatur der App gültig. Das Finder-Fenster selbst nicht angesehen.

# DMG-Hintergrund im Stil des Handbuchs · 18.10.2026

- **Neuer Hintergrund** (`Scripts/dmg-background.swift`): oben ein petrolfarbenes Band mit dem radialen Licht der Handbuch-Titelseite, darin die goldene Kennzeile „Installieren · Install“, „Plattenregal“ in New York und der goldene Strich. Darunter schlichtes Papier wie auf den Handbuchseiten mit dem Pfeil (petrol, goldene Spitze), dem Hinweis unter den Symbolen (deutsch im Leitstil des Handbuchs, englisch als Nebentext) und einer Fußzeile „Plattenregal · Version …“ / „macOS 27 · Apple Silicon“. Musiknoten, Equalizer, Schallplatte und der helle Schein sind weg. Farben aus dem `:root` des Handbuchs, Abstände aus dessen Skala. Fenstergröße und Symbolpositionen unverändert.
- `make-dmg.sh` gibt dem Hintergrund die Version der App mit. Kommentare in den Handbuch-Quellen verweisen nicht mehr auf Equalizer und Schallplatte im DMG-Hintergrund; die PDFs sind dadurch neu erzeugt (Inhalt gleich).
- Geprüft: Hintergrund in 2x gerendert und angesehen; Release-Build und DMG mit `make-dmg.sh` erfolgreich, eingehängt und das Finder-Fenster als Bildschirmfoto angesehen: Band, Symbole, Beschriftungen („Plattenregal“, „Applications“, „Handbuch“, „User Guide“), Hinweis und Fußzeile stehen frei und lesbar. App-Code unverändert, Tests nicht erneut ausgeführt.

# Tooltips, Demo-Cover, Handbuch auf Englisch, Bilder per Skript · 18.10.2026

- **Tooltips durchgesehen:** Alle reinen Symbolknöpfe haben jetzt einen Tooltip. Neu sind das „x“ in Hinweisbannern („Ausblenden“), das „x“ zum Leeren der Suche („Suche löschen“) und Minus/Plus im Glas-Stepper („Verringern“/„Erhöhen“, englisch „Decrease“/„Increase“). Wo es ein Kürzel gibt, steht es einheitlich in Klammern hinter dem Titel, gebaut von `AppShortcuts.help(_:keys:)`: Raster/Liste im runden Knopf („Als Liste anzeigen (⌥⌘2)“, bisher ohne), Synchronisieren (⌘R), Einstellungen (⌘,), „Synchronisierung abbrechen (⌘.)“ (bisher ohne), Zufallsfund (⇧⌘R). Die Texte „Einstellungen (⌘,)“ und „Neue Platte ziehen (⇧⌘R)“ sind aus dem Katalog entfernt, sie setzen sich jetzt zusammen.
- **Demo-Cover:** Interpret und Titel stehen unten links, die Schallplatte oben rechts. Bisher verdeckten die Positionsnummern im Fach und die Plaketten der Suche (beide oben links) den Anfang des Interpreten („RTISHEAD“). Die Zeilen enden vor der Anzahl der Exemplare unten rechts. Echte Cover sind davon nicht berührt.
- **Englisches Handbuch:** `Handbuch/Handbook.html` → `Plattenregal/Handbook.pdf` mit englischen Bildern und den Begriffen aus `Localizable.xcstrings` bzw. den englischen Systemtexten von macOS („Open Anyway“, „Privacy & Security“). Hilfe → Handbuch öffnet das PDF in der Sprache der App (`Handbook.open()`). Die DMG legt beide bei („Handbuch“, „User Guide“); ihr Fenster ist dafür 880 statt 740 pt breit (App 130, Programme 430, Handbücher 620 und 770; Pfeil und Schallplatte zwischen App und Programme, Noten rechts verschoben). `make-guide.swift --en`, `make-dmg.sh` erneuert und prüft beide PDFs.
- **Intel:** Beide Handbücher begründen jetzt, warum Intel-Macs nicht gehen: macOS 27 gibt es nur für Macs mit Apple-Chip.
- **Bilder per Skript:** `Scripts/guide-screenshots.swift [de|en]` nimmt alle Bilder beider Handbücher aus der Demo auf (`--snapshot`, keine Bildschirmaufnahme-Rechte, keine Klicks), schneidet zu und legt sie nach `Handbuch/Bilder/de|en/`. Es setzt das Hauptfenster für die Aufnahmen auf 1223 × 793 pt, legt es neben den Bildschirm weg vom Mauszeiger (sonst erschienen Zeilen hervorgehoben) und stellt die vorige Fenstergröße danach wieder her. Die Bilder der Einstellungen zeigen jetzt dasselbe wie das echte Fenster: `--settings-tab` gibt dem Hauptfenster (nur Debug) dessen Größe. Das Bild der Regal-Einstellungen endet über dem Schalter „Aktiv“, weil `--snapshot` Schalter immer grau zeichnet.
- **Ursache der „Schnappschuss … nach 30 s kein Fenster“** (offen seit 09.10.): die Reihenfolge der Startargumente. Folgt ein Paar wie `-signatureDesign atelier` auf einen Schalter wie `--demo`, liest macOS `--demo -signatureDesign` als Paar und `atelier` als zu öffnende Datei; mit einer Datei geöffnet zeigt die App kein Startfenster. Mit Paaren zuerst erscheint das Fenster jedes Mal; das Skript ordnet so, das README-Beispiel ist korrigiert. Die App selbst war nie betroffen. Während der Suche stellte ein Testlauf die gespeicherte Hauptfenstergröße der echten App auf 1050 × 772; sie ist wieder 1223 × 793.
- Geprüft: Debug-Build und 210 Tests erfolgreich (mehrfach). In der Demo: Hilfe → Handbuch öffnet auf Englisch `Handbook.pdf`, auf Deutsch `Handbuch.pdf` (Vorschau, Protokoll); Positionsnummern und Suchtreffer verdecken die Demo-Cover nicht mehr (Bilder Regal und Einsortieren). Alle 14 Bilder per Skript aufgenommen und angesehen, beide PDFs Seite für Seite (englisch) bzw. die geänderten Seiten (deutsch). DMG gebaut, `hdiutil verify` in Ordnung, beide PDFs byte-gleich mit denen im Repository, Symbolpositionen aus der `.DS_Store` gelesen, Signatur gültig; den Aufbau habe ich aus Hintergrund und Symbolen nachgebaut und angesehen. **Nicht geprüft**, weil der Bildschirm inzwischen gesperrt war: die neuen Tooltips in der laufenden App (nur im Code) und das DMG-Fenster im Finder selbst.

# Handbuch im Hilfe-Menü, Discogs-Links in Klassisch petrol · 17.10.2026

- **Hilfe → Handbuch** (englisch „User Guide“) öffnet das Handbuch, das jetzt in der App liegt (`Plattenregal/Handbuch.pdf`, Ressource im Projekt), in Vorschau bzw. dem PDF-Programm des Systems (`Handbook.open()` in `Views/WelcomeView.swift`). So ist es auch noch da, wenn die DMG gelöscht ist. Kein Tastenkürzel: ⌘? belegt macOS für die Suche im Hilfe-Menü, SwiftUI zeigt es deshalb gar nicht erst an.
- **„Erste Schritte“** im Hilfe-Menü ohne „…“ (englisch „Getting Started“).
- **Discogs-Links in Klassisch:** „Token erstellen ↗“ und „Discogs API-Nutzungsbedingungen ↗“ (Einstellungen → Discogs) nutzen jetzt den vorhandenen Baustein `appLinkButton()`: petrol in Klassisch statt Systemblau, in Modern weiter der Link-Stil des Systems.
- **Handbuch:** Seite 3 nennt Hilfe → Handbuch und dass der Programme-Ordner in der DMG „Applications“ heißt; Bild der Discogs-Einstellungen mit dem petrolfarbenen Link neu aufgenommen; „Erste Schritte“ ohne Punkte.
- **Erzeugung:** `make-guide.swift` kennt `--if-changed` (neu erzeugt nur, wenn Quelle, Bilder, Skript oder Version neuer sind; die Version steht im PDF-Feld „Betreff“). `make-dmg.sh` erneuert damit vor dem Release-Build `Plattenregal/Handbuch.pdf` und legt der DMG das PDF aus der gebauten App bei.
- Geprüft: Debug-Build und 210 Tests erfolgreich. In der Demo: Hilfe-Menü zeigt „Handbuch, Erste Schritte“ (englisch „User Guide, Getting Started“); „Handbuch“ öffnet `Handbuch.pdf` in Vorschau, Protokoll „Handbuch geöffnet“; Discogs-Einstellungen in Klassisch (Link petrol) und Modern (Link blau) angesehen. `--if-changed` mit gleicher und neuer Version ausprobiert. DMG neu gebaut, `hdiutil verify` in Ordnung, PDF in DMG und App byte-gleich mit `Plattenregal/Handbuch.pdf`, Signatur gültig.

# „Anleitung“ heißt jetzt „Handbuch“ · 17.10.2026

- Die Broschüre in der DMG heißt **Handbuch** statt Anleitung, weil sie über die Installation hinaus alles zum Nachschlagen enthält. „Erste Schritte“ wurde nicht gewählt, so heißt schon die Willkommensseite im Hilfe-Menü. Geändert: Dateiname in der DMG (`Handbuch.pdf`, im Finder „Handbuch“), Quelle `Handbuch/Handbuch.html` mit `Handbuch/Bilder/`, Titelseite, Fußzeilen, Fließtext („Dieses Handbuch …“), PDF-Titel, `make-guide.swift`, `make-dmg.sh`, `dmg-background.swift`, README.
- Geprüft: PDF neu erzeugt (10 Seiten, Seite 2 angesehen), DMG neu gebaut, `hdiutil verify` in Ordnung, eingehängt: Finder zeigt App, Pfeil, Programme und „Handbuch“.

# Anleitung als Broschüre in der DMG · 17.10.2026

- **Neue Broschüre** `Anleitung.pdf` (10 A4-Seiten, Design Klassisch: Petrol, Creme, Gold, Schallplatte und Equalizer wie im DMG-Hintergrund) für Freunde, die die App bekommen: Voraussetzungen (Apple-Chip, macOS 27, Discogs-Konto), Installieren und der einmalige Weg über **Systemeinstellungen → Datenschutz & Sicherheit → „Dennoch öffnen“** (Beschriftung aus den deutschen Systemtexten von macOS geprüft), Discogs-Token, Rundgang, Regal einrichten, Einsortieren, Suchliste und Verkauf, Statistik, Sicherung, Export, Einstellungen, Tastenkürzel (aus `AppShortcuts`), kleine Hilfen, Discogs-Hinweis. Sieben Bildschirmfotos aus der Demo.
- **Quelle und Erzeugung:** `Anleitung/Anleitung.html` mit `Anleitung/Bilder/` (Farben, Schriftstufen und Abstände zentral in `:root`); `Scripts/make-guide.swift` rendert jede Seite mit WebKit als eigene PDF-Seite und setzt die Version ein.
- **DMG:** `make-dmg.sh` legt die Anleitung bei (Endung ausgeblendet). Das Fenster ist jetzt 740 statt 660 pt breit: App bei 140, Programme bei 470, Anleitung bei 640; Pfeil und Schallplatte bleiben mittig zwischen App und Programme, die Noten rechts sind verschoben (`dmg-background.swift`). DMG `dist/Plattenregal-1.1.2.dmg` neu erstellt, Version unverändert.
- Geprüft: Alle zehn Seiten als Bild angesehen (nichts läuft über den Fuß, keine fehlenden Bilder; das Skript bricht bei fehlenden Bildern ab). Release-Build und DMG erfolgreich, `hdiutil verify` in Ordnung; DMG eingehängt und das Finder-Fenster angesehen: App, Pfeil, Programme und „Anleitung“ mit der Titelseite als Vorschau. App-Code unverändert, Tests nicht erneut ausgeführt.

# Version 1.1.2 · 15.10.2026

- Version 1.1.2 (1.1.1 übersprungen), Build bleibt 102026. DMG neu erstellt (`dist/Plattenregal-1.1.2.dmg`), mit dem schnellen „Neue Platte ziehen“ im Zufallsfund. README, STATISTIK.md und VALIDIERUNG.md: Version.
- Geprüft: Release-Build erfolgreich; DMG per `hdiutil verify` in Ordnung; enthält App und Programme-Verknüpfung, App meldet 1.1.2 (102026), nur arm64, Signatur gültig.

# Zufallsfund: „Neue Platte ziehen“ ohne Denkpause · 15.10.2026

- **Ursache der Denksekunde:** Beim Ziehen wurde die bisherige Platte aus der Sammlung herausgefiltert – und für jede Platte dabei die gerade gezeigte erneut durch die ganze Liste gesucht. Bei 2.000 Platten gemessen (Debug-Build): **2,66 s** pro Klick. Jetzt wird einfach neu gewürfelt, bis es eine andere Platte ist (im Mittel ein Wurf): 0,005 ms.
- **Unnötige Mehrarbeit entfernt:** Die Beschriftungen aller Fächer wurden bei jedem Ziehen neu zusammengesetzt (~7 ms), obwohl sich dabei nichts an ihnen ändert. Sie entstehen jetzt nur, wenn sich Fächer, Plätze, Beschriftungsart oder die Sortierung bei gleichem Interpreten ändern (letztere war bisher kein Auslöser). Die gezeigte Platte wird über ihre ID nachgeschlagen statt bei jedem Neuzeichnen die Liste zu durchsuchen (~1,3 ms).
- Geprüft: Messung mit einem vorübergehenden Test (2.000 Platten in 12 Fächern, danach wieder entfernt); Debug-Build und 210 Tests erfolgreich. In der laufenden App nicht angeklickt.

# Version 1.1.0 · 12.10.2026

- Version 1.1.0, Build bleibt 102026. DMG neu erstellt (`dist/Plattenregal-1.1.0.dmg`), mit der einheitlichen Abstandsskala. README, STATISTIK.md und VALIDIERUNG.md: Version.

# Einheitliche Abstandsskala · 12.10.2026

- **Eine Skala für alle Abstände** (`AppStyle`, `Utilities/AppAppearance.swift`): 2 · 4 · 8 · 12 · 16 · 20 · 24 · 28. Neu sind `hairSpacing` (2, Zeilen einer Beschriftung), `pageMargin` (28, Seitenrand; bisher überall `pagePadding + 4`) und `blockSpacing` (28, zwischen den großen Blöcken einer Seite). Rund 180 freie Zahlen in 19 Dateien nehmen jetzt eine Stufe daraus; Werte wie 3, 5, 7, 9, 11, 13 und 14 gibt es bei Abständen nicht mehr. `CoverGrid` und `StatisticsLayout` leiten sich aus der Skala ab.
- **Sichtbar** (jeweils 1–2 pt, beide Designs): Cover-Raster 20 statt 18 (wie die Karten der Statistik), Cover zu Beschriftung 8 statt 9; alle Marken und Positionsnummern 8 × 4 (bisher 10 × 4, 7 × 3, 8 × 3, 5 × 1); Statuskapseln und Menüknopf 16 seitlich statt 14; Symbol zu Text 8 statt 6, Zahl zu Einheit 4 statt 5/6; Spalten der Statistik-Listen im selben Abstand wie die Karten (20 statt 28); Regal-Tabs 12 statt 14 über dem Regal.
- **Bündig:** Im Panel der Regalsuche standen Zwischenüberschrift und „Keine Treffer“ 2 pt neben den Covern; jetzt alles auf einer Linie (16).
- **Unverändert:** Maße innerhalb von Bedienelementen (Höhe der Knöpfe, Pille der Umschalter, Auswahlring der Farbfelder), das Regalbild (Brettstärke 5), die Miniaturen der Designs in den Einstellungen, optische Korrekturen (−3 an der großen Zahl) und der PDF-Export.
- In der Demo angesehen (Klassisch hell): Collection, Regal, Statistik, Regalsuche, „Sortierung prüfen“, „Platte hinzufügen“. Debug-Build und 210 Tests erfolgreich.

# Verkaufsliste: Knopf heißt „Verkauft“ · 12.10.2026

- Der Knopf unter der Verkaufsliste (Einstellungen → Listen) heißt jetzt **„Verkauft“** statt „Alle verkauft …“, ohne die drei Punkte; ebenso der Knopf in der Rückfrage. Die Rückfrage selbst bleibt. Texte de/en, README.

# Version 1.0.8 · 12.10.2026

- Version 1.0.8, Build bleibt 102026. DMG neu erstellt (`dist/Plattenregal-1.0.8.dmg`), mit der Verkaufsliste (Schema V16), dem Export mit eigener Listenauswahl und den Korrekturen aus der Durchsicht vom 12.10. README, STATISTIK.md und VALIDIERUNG.md: Version.

# Abschluss der Durchsicht: Doku, Fehlermeldungen, Protokoll, Lokalisierung · 12.10.2026

- **README:** Abbruch eines Abgleichs beschrieben (vor dem Speichern wird nichts übernommen, danach endet er still und die Tracklisten folgen später); „Alles zurücksetzen“ nennt, dass die Seiten ihre Platten sofort loslassen; die Zeile zu den Discogs-Dateien spricht nicht mehr vom „Einzel-Nachladen“, das es nicht mehr gibt.
- **STATISTIK.md:** Prüfdatum, Zurücksetzen (Mitteilung vor dem Leeren des Cover-Caches), „Neuzugänge“ lückenlos, Tests bis Schema V16 (stand noch auf V15).
- **VALIDIERUNG.md:** neuer Stand 12.10. mit Umfang, Befunden, einem bekannten, nicht geänderten Randfall (Sicherung ganz ohne Platten) und dem, was nicht geprüft ist.
- **Fehlermeldungen:** kein neuer Text. Geprüft: Der stille Abbruch nach dem Speichern, die Ordner-Meldung beim automatischen Export (vorhandener, getesteter Text).
- **Protokoll und Absturzberichte:** kein Absturzblock und kein `ERROR` am 12.10., kein neuer macOS-Absturzbericht seit dem 08.10. Neue Protokollzeilen: „Nach dem Speichern abgebrochen, Tracklisten folgen später“ und „Ordner für den automatischen Export nicht übernommen“.
- **Lokalisierung:** per Skript 909 Einträge, 59 veraltet, jeder aktive mit englischer Übersetzung, Platzhalter gleich.
- Kein Code geändert; es gilt der Teststand von eben (210 Tests).

# Durchsicht der ganzen App: zwei Fehler, toter Code, Randfälle · 12.10.2026

Alle Quelltexte der App gelesen (Modelle, Sync, Dienste, Seiten, Einstellungen, Statistik, Design).

- **Fehler – „Alles zurücksetzen“:** Die Seiten erfuhren erst nach dem Leeren des Cover-Caches, dass alle Platten gelöscht sind. In dieser Wartezeit zeichnete das Hauptfenster weiter und konnte dabei noch eine gelöschte Platte anfassen (offene Platzkarte, ausgewähltes Exemplar, Suchtreffer im Regal) – das beendet die App. Jetzt werden die Seiten sofort nach dem Löschen benachrichtigt, noch bevor irgendetwas neu gezeichnet wird; die Cover werden danach geleert.
- **Fehler – „x“ nach dem Speichern eines Syncs:** Wer die Synchronisierung abbrach, während nur noch der Sammlungswert geladen wurde, bekam die Meldung „… nur der Sammlungswert konnte nicht geladen werden. Der Vorgang wurde abgebrochen.“ – und dahinter lief der Trackliste-Download unsichtbar weiter, ohne dass er sich stoppen ließ (⌘. war aus). Jetzt endet der Sync an dieser Stelle still: Die Sammlung ist gespeichert, es gibt keine Meldung, die Tracklisten holt der nächste Sync oder Start nach. Test `DiscogsSyncTests.cancellingAfterTheMergeIsNoErrorAndLoadsNoTracklists` (schlägt ohne die Korrektur fehl).
- **Veralteter Text:** Unter Einstellungen → Discogs → Hinweise stand, ältere Einträge ließen sich „in der Detailansicht einzeln neu laden“ – das gibt es nicht mehr. Der Hinweis nennt jetzt die Tracklisten, die nach dem Sync im Hintergrund folgen (de/en).
- **Toter Code entfernt:** das vollständige Neuladen eines einzelnen Release (`DiscogsReleaseDTO.apply(to:)` samt aller dafür gelesenen Felder – die App liest von dort nur noch Trackliste und Land); die nie genutzten Fortschritts-Rückrufe von `collection`/`wants`; `ShelfStatistics.shelfID`/`isReserved`; `AppSearchField.accessory`/`onSubmit` und sein Zweig ohne Fokus; `AppBadge.prominent`; `OverviewLayoutPicker.glass`; `GlassStepButton.help`; `pullToRefresh(allowsMouseDrag:)`; `CoverTile.size`/`showsAddedDate`. `AnalyticsItem.init(_ copy:)` nutzten nur die Tests – dort liegt er jetzt.
- **Randfälle gehärtet:**
  - Paginierung von Discogs: unsinnig große Zahlen in einer kaputten Antwort führten in der Prüfung zu einem Überlauf (Absturz) statt zu „Liste hat sich verändert“. Jetzt begrenzt.
  - „Neuzugänge“ in der Statistik: Die Balken wurden Monat für Monat weitergezählt; beginnt ein Monat mit einer Zeitumstellung, lagen alle späteren Balken neben ihren Zählungen (0 Platten). Jeder Balken nimmt jetzt den echten Monatsanfang.
  - Positionsregler im Fach: prüft beim Schließen auch, ob die Platte inzwischen gelöscht und gespeichert ist.
  - Ordner für den automatischen Export lässt sich nicht merken: Die Meldung sprach von einer Datei, die sich nicht öffnen lässt; jetzt vom Ordner.
- Zwei Compiler-Warnungen (Rechtsklick im Cover-Raster) behoben.
- Geprüft: Build ohne Warnungen, 210 Tests. Demo gestartet, Statistik und Collection mit Suche als Bild angesehen. **Nicht angesehen:** „Alles zurücksetzen“ und der Abbruch während des Sammlungswerts in der laufenden App mit echter Sammlung (beides nur über Code und Test belegt; das Zurücksetzen bewusst nicht ausgeführt).

# Automatischer Export: eigene Auswahl der Listen · 12.10.2026

- Bisher schrieb der automatische Export, was unter „Daten“ gewählt war. Wer dort für eine einzelne Datei auf „Verkaufsliste“ oder „Wantlist“ stellte, beendete damit unbemerkt den automatischen Export der Collection.
- Jetzt hat „Automatischer Export“ eigene Schalter: **Collection, Wantlist, Verkaufsliste** – auch mehrere zugleich, jede Liste in ihrer eigenen Datei (der Name steht unter dem Schalter). „Daten“ oben gilt nur noch für „Als … exportieren“. Format, Spalten und Reihenfolge kommen weiter von oben.
- Übernahme: Beim ersten Start wird einmal gespeichert, was der automatische Export bisher schrieb (die unter „Daten“ gewählte Liste) – es ändert sich also nichts von selbst. Nach „Einstellungen zurücksetzen“ ebenso.
- Eine leere Liste wird wie bisher nicht geschrieben und ersetzt keine Datei; die übrigen gewählten Listen werden trotzdem geschrieben. Ist keine Liste gewählt, sagt die Zeile das, und es wird nichts exportiert. Eine unter „Listen“ abgeschaltete Verkaufsliste fehlt bei den Schaltern und wird nicht geschrieben; ihre Wahl bleibt gemerkt.
- Technik: `ScheduledExport.sourcesKey`, `sources`, `adoptSources()`, `nonEmpty(_:in:)`; `run` liefert die geschriebenen Dateinamen. Test `ExportTests.scheduledExportWritesItsOwnChoiceOfLists`.
- Geprüft: Build ohne Warnungen, 208 Tests. **Nicht angesehen:** die neuen Schalter in der laufenden App (in der Demo ist der automatische Export gesperrt) und kein echter Lauf in einen Ordner.

# Export durchgesehen: „Ohne Regalplatz“ mit eigener Überschrift · 12.10.2026

- **Reihenfolge „Wie im Regal“:** Platten ohne Fach standen alle unter „Noch nicht einsortiert“ – auch die bewusst herausgenommenen („Ohne Regalplatz“). Seit der Umbenennung sind das zwei verschiedene Dinge. Jetzt folgen nach den Fächern erst die noch nicht einsortierten, dann die ohne Regalplatz, jede Gruppe alphabetisch und in der PDF mit eigener Überschrift (CSV: dieselbe Reihenfolge; die Spalte „Fach“ nannte den Unterschied schon). Gilt für Collection und Verkaufsliste. Erklärung der Reihenfolge im Export-Reiter angepasst.
- **Einstellungen → Listen:** Die Erklärung der Verkaufsliste nennt jetzt, wo es sie als CSV oder PDF gibt („Export“).
- Tests: Reihenfolge und Überschriften mit einer Platte „Ohne Regalplatz“; die Verkaufsliste wird als PDF und CSV wirklich erzeugt und der Inhalt der CSV geprüft; Dateiname des automatischen Exports für die Verkaufsliste.
- Sonst ohne Befund durchgesehen: CSV (BOM, Zeilenenden, Anführungszeichen, Formel-Schutz), PDF (Seitenumbruch, „Fortsetzung“, leere Liste), Dateinamen, automatischer Export (leere Liste ersetzt nichts, kein Lauf während der Synchronisierung, Fehler nur einmal im Protokoll).
- Geprüft: Build ohne Warnungen, 207 Tests. Nicht angeklickt; die erzeugte PDF wurde nicht angesehen, nur ihr Entstehen geprüft.

# Export: Verkaufsliste als CSV oder PDF · 12.10.2026

- Einstellungen → Export → „Daten“ hat eine dritte Wahl: **Verkaufsliste**. Die Datei enthält nur die zum Verkauf vorgemerkten Platten – dieselben wie unter Einstellungen → Listen, also auch eine, die inzwischen nicht mehr in der Discogs-Collection ist. Format, Spalten, Reihenfolge (wie im Regal / alphabetisch) und der automatische Export arbeiten wie bei der Collection; die PDF heißt „Plattenregal – Verkaufsliste“, die Datei des automatischen Exports „Plattenregal Verkaufsliste“.
- Ist die Verkaufsliste unter „Listen“ abgeschaltet, fehlt die Wahl; war sie gewählt, gilt wieder die Collection (auch für den automatischen Export). Eine leere Liste ersetzt wie bisher keine vorhandene Datei.
- Nachgebessert bei der Durchsicht: Die Anzahl der Verkaufsliste wird in der Datenbank gezählt (der Export-Reiter fragt bei jedem Neuzeichnen; vorher wurden dafür alle Platten geladen). Eine leere Verkaufsliste schreibt beim automatischen Export keine Warnung mehr ins Protokoll – sie ist nach „Alle verkauft“ der Normalfall und wäre sonst alle 30 Minuten gemeldet worden.
- Technik: `ExportSource.sale`, `CollectionExportService.collectionTable(only:)`; Test `ExportTests.saleListExportsOnlyMarkedRecords`.
- Geprüft: Build ohne Warnungen, 207 Tests. Nicht angeklickt, keine Datei in der laufenden App erzeugt.

# Durchsicht der Änderungen vom 12.10.: vier Korrekturen · 12.10.2026

- **„Im Regal zeigen“ wieder englisch.** Beim Entfernen aus dem „i“-Popover ging die Übersetzung im Katalog verloren; der Knopf der Zufallsplatte in der Statistik benutzt den Text aber weiter und stand in der englischen Oberfläche auf Deutsch.
- **Kein Pause-Knopf mehr in den Texten.** Die Erklärung der Suchliste (Einstellungen → Listen) und das README nannten noch den Pause-Knopf in „Platte hinzufügen“; den gibt es seit dem Umbau nicht mehr, nur den Rechtsklick. Dazu überholte Code-Kommentare (Pause, Pfeil) im Einsortieren-Fenster.
- **„Einsortieren“ bei leerem Regal:** Solange in keinem Fach eine Platte steht, tut ein Klick auf eine Zeile nichts (es gibt keine alphabetische Stelle), und der Pfeil, der früher weiterhalf, ist weg. Die Zeile sagt jetzt, wie es weitergeht: Fach wählen und dort über „+“ hinzufügen (derselbe Text wie in der Platzsuche).
- **Collection, Rechtsklick:** „Auf die Suchliste setzen“ wird für Platten „Ohne Regalplatz“ nicht mehr angeboten. Die Markierung wäre unsichtbar geblieben – die Liste in den Einstellungen zeigt solche Platten nicht, und „Ohne Regalplatz“ hebt „Gesucht“ ohnehin auf. „Wieder gefunden“ bleibt für bereits markierte.
- Aufgeräumt: `errorTitle` in `CollectionView` war seit dem Wegfall von „Discogs-Daten aktualisieren“ immer derselbe Text.
- Geprüft: Build ohne Warnungen, 206 Tests. Nicht angeklickt.

# Sync-Kapsel: weniger Arbeit auf dem Hauptthread · 12.10.2026

Die Kapsel selbst war in Ordnung; geruckelt hat, was im selben Moment auf dem Hauptthread lief.

- **Start und Ende der Synchronisierung bauen die Seiten nicht mehr neu.** Collection, Wantlist und Statistik lasen `sync.busy` in ihrem `body` (für „Ziehen zum Aktualisieren“ und ⌘R) und liefen deshalb komplett neu durch – genau beim Hereinkommen der Kapsel. `pullToRefresh` / `refreshShortcut` fragen den Zustand jetzt selbst ab (`disabled:` als Closure, eigener Modifier `RefreshShortcut`); die Statistik beobachtet das Sync-Ende über `onObservedChange`.
- **Statistik rechnet nach einer Synchronisierung nur noch neu, wenn sie gezeigt wird.** Verborgen merkt sie es sich und holt es beim nächsten Anzeigen nach (wie schon bei anderen Speichervorgängen). Bisher wurden alle Diagramme im Hintergrund neu gezeichnet, während die Kapsel auf „Synchronisiert“ wechselte.
- **Tracklisten-Prüfung im Hintergrund** (`DiscogsSyncService.dueTracklists`): Welche Releases fällig sind, wurde nach jeder Synchronisierung und bei jedem Start auf dem Hauptthread ermittelt – jede Platte, jedes Release einzeln gelesen. Jetzt abseits des Hauptthreads, Releases in einer Abfrage.
- **Sammlungswert:** Die Signatur der Sammlung (zweimal pro Synchronisierung) wird ebenfalls im Hintergrund und mit einer Abfrage gebildet (`CollectionValueHistoryService.activeCollection`).
- Geprüft: Build, 206 Tests. **Nicht gemessen:** kein Profil mit Instruments und keine Synchronisierung gegen die echte Sammlung – die Wirkung auf das Ruckeln ist aus dem Code abgeleitet, nicht belegt.

# Einsortieren-Fenster: eine Zeile je Platte, Standort groß · 12.10.2026

- Statt vier Kacheln nebeneinander steht jede Platte in einer Zeile über die Fensterbreite: Cover (132 pt, wie im Fachinhalt), daneben Beschriftung und darunter groß der Standort – Regal · Fach in der Akzentfarbe, dann „Position n · zwischen … und …“. In „Platte hinzufügen“ heißt es bei Platten für ein anderes Fach „Gehört in „…““ in Grau. „Als Nächstes“ steht als Etikett unter der Beschriftung, das Positions-Etikett auf dem Cover entfällt. Klick und Rechtsklick-Menü wie zuvor.
- Geprüft: Build, Tests, Fensterfotos beider Fenster (Demo, Modern hell). Nicht angeklickt.

# Einsortieren-Fenster: Kacheln wie im Fach, Klick statt Symbole · 12.10.2026

- Die Symbole beim Überfahren (Pause, „i“, „+“) samt „i“-Popover sind entfallen. Jede Kachel ist aufgebaut wie im Fachinhalt: Cover mit Positions-Etikett (die Position, die die Platte bekäme), Beschriftung, darunter das Fach, in das sie gehört („Einsortieren“) bzw. „gehört in …“ („Platte hinzufügen“, dort ohne Position, weil der Klick ins offene Fach geht).
- **Ein Klick auf die Kachel fügt hinzu** (bisher „+“ oder Doppelklick). Rechtsklick öffnet ein Menü mit „Einsortieren“ / „Zum Fach hinzufügen“ und „Auf die Suchliste setzen“ (nur bei eingeschalteter Suchliste).
- Der Platz je Platte wird pro Fenster gemerkt und nach jedem Hinzufügen neu bestimmt (`ShelfAssignmentSession.place`).
- Geprüft: Build, Tests, Fensterfotos beider Fenster (Demo, Modern hell). **Nicht angeklickt:** Klick auf eine Kachel und das Rechtsklick-Menü.

# „Ohne Regalplatz“ und „Noch nicht einsortiert“ · 12.10.2026

- **„Nicht im Regal“ heißt jetzt „Ohne Regalplatz“** (Rechtsklick-Menüs, Schalter in der Plattenansicht, Standortangabe, Export, Sicherungsübersicht, Texte bei „Alle verkauft“ und beim Zurücksetzen, Protokoll). Das Gegenstück bleibt „Wieder einsortieren“.
- **„Ohne Fach“ heißt jetzt „Noch nicht einsortiert“**: Überschrift über den Suchtreffern, Karte im Einsortieren-Fenster (bisher „Platten ohne Fach“), Standortangabe (bisher „Noch keinem Fach zugeordnet“), Spalte im Export; Hinweistexte entsprechend. Im Protokoll steht weiter „ohne Fach“.
- Nur Texte (deutsch/englisch: „Kept off shelf“, „Not placed yet“), keine Änderung an Daten oder Sicherungsformat. Ältere Abschnitte dieser Datei und von VALIDIERUNG.md nennen noch die alten Begriffe.

# „Discogs-Daten aktualisieren“ entfernt · 12.10.2026

- Der Eintrag ist aus dem Rechtsklick-Menü der Collection entfallen. Er war die einzige Stelle, die einzelne Releases sofort neu lud; `MetadataRefreshService` und seine Texte sind deshalb mit entfernt. Release-Daten kommen weiter mit der normalen Synchronisierung.
- Einstellungen → Listen: Die Listen blenden beim Schalten animiert ein und aus.

# „Vermisst“ heißt jetzt Suchliste / „Gesucht“ · 12.10.2026

- Überall in der App umbenannt: Etikett „Gesucht“, Menüeintrag „Auf die Suchliste setzen“ (statt „Als vermisst markieren“), Liste „Suchliste“ in den Einstellungen, Hinweise auf der Einsortier-Karte, in „Einsortieren“, beim Zurücksetzen und im Protokoll. „Wieder gefunden“ / „Gefunden“ bleiben. Intern heißen Modell und Schlüssel weiter `MissingCopyMark` / `missingListEnabled` – keine Migration, bestehende Markierungen bleiben. Ältere Abschnitte dieser Datei und von VALIDIERUNG.md nennen noch „Vermisst“.
- **Einstellungen → Listen:** Die Karten haben keine eigene Überschrift mit Kurztext mehr; es bleibt je die Zeile mit Schalter („Suchliste“, „Verkaufsliste“) und Erklärung.
- Englisch: „Search list“ / „Looking for“.

# Vermisst und Verkauf einzeln abschaltbar · 12.10.2026

- **Einstellungen → Listen:** je eine Karte „Vermisst“ und „Verkauf“ mit eigenem Schalter, darunter die Liste (nur wenn eingeschaltet). Neu ist der Schalter „Verkaufsliste“ (`saleListEnabled`, Vorgabe an).
- **Rechtsklick in der Collection** hat jetzt auch „Als vermisst markieren“ / „Wieder gefunden“, neben „Zum Verkauf vormerken“ / „Nicht mehr verkaufen“. Beide Einträge erscheinen nur, wenn die jeweilige Liste eingeschaltet ist – ebenso im Fachinhalt, wo ohne Verkaufsliste auch das Etikett „Verkauf“ entfällt. Abschalten löscht keine Markierung.
- Geprüft: Build, 206 Tests, Fensterfoto des Reiters (Demo, Modern hell). **Nicht angeklickt:** die Schalter und die Rechtsklick-Menüs.

# Reiter „Listen“ und Verkaufsliste, Schema V16 · 12.10.2026

- **Einstellungen: „Vermisst“ heißt jetzt „Listen“** (`ListsSettingsView`) und hat eine zweite Liste **„Verkauf“** für Platten, die irgendwann verkauft werden sollen.
- **Vormerken** per Rechtsklick: „Zum Verkauf vormerken“ / „Nicht mehr verkaufen“ im Fachinhalt (Raster und Liste) und in der Collection. Im Fach tragen vorgemerkte Platten das Etikett „Verkauf“. Fach und Position bleiben unverändert.
- **„Alle verkauft …“** (mit Rückfrage) schließt die ganze Liste in einer Transaktion ab: Platten aus den Fächern, „Nicht im Regal“ gesetzt, übrige rücken auf, „Vermisst“ aufgehoben, Liste geleert (`PositionService.sellAllForSale`). Einzeln geht nur „Entfernen“ von der Liste.
- **Schema V16** (leichte Migration von V15): neue Tabelle `SaleCopyMark`, alle übrigen Modelle unverändert aus V15. **Eine einmal mit diesem Stand geöffnete Datenbank lässt sich mit älteren Versionen (bis 1.0.7) nicht mehr öffnen.** Die Liste ist nicht Teil der Sicherung; „Alles zurücksetzen“ leert sie, „Standorte zurücksetzen“ lässt sie stehen.
- Demo: zwei Platten sind zum Verkauf vorgemerkt.
- Tests: `saleMarkKeepsPlaceUntilAllAreSold` neu; der Migrationstest läuft jetzt V13 → V16 und prüft die leere Verkaufsliste. 206 Tests grün. Fensterfoto des Reiters „Listen“ in der Demo (Modern hell). **Nicht angeklickt:** die Rechtsklick-Einträge, „Entfernen“, „Alle verkauft …“ und das Etikett im Fach; die echte Datenbank wurde nicht migriert, nur der Test-Store.

# Einstellungen → Vermisst: „Gefunden“ statt „Freigeben“ · 12.10.2026

- Der Knopf je Platte heißt wie auf der Regalseite „Gefunden“, der für die ganze Liste „Alle gefunden“; Hinweistexte entsprechend. Bei Platten ohne Fach steht kein „Ohne Fach“ mehr, der Standort erscheint nur bei einsortierten Platten.

# „i“-Popover ohne „Im Regal zeigen“ · 12.10.2026

- Das Popover „Hier würde sie stehen“ zeigt nur noch Fach, Position und Nachbarn; der Link „Im Regal zeigen“ ist entfallen. Aus dem Fenster heraus gibt es damit keinen Sprung zur Einsortier-Karte mehr (die bleibt über Suche, Collection und Rechtsklick erreichbar). Karte oben im Fenster bündig mit den äußeren Covern.

# „Einsortieren“ als Cover-Raster · 12.10.2026

- **„Platte hinzufügen“ / „Einsortieren“** zeigt die Platten jetzt als Cover-Raster wie der Fachinhalt darunter: vier Cover nebeneinander (Fenster 660 statt 460 pt breit), darunter dieselbe Beschriftung wie im Fach (Interpret, Titel, Jahr · Label) und „gehört in …“. Pause, „i“ und „+“ liegen beim Überfahren in einer Glaskapsel unten auf dem Cover, „Als Nächstes“ als Etikett oben links; ein Doppelklick fügt weiterhin hinzu. Eine hinzugefügte Platte blendet aus, die übrigen rücken nach.
- Die Überschrift („Einsortieren“ bzw. „Platte hinzufügen“) und der Knopf „x vermisst“ sind entfallen; die Karte oben nennt weiter Fach und Platz. Zum Reiter „Vermisst“ führt nur noch der Knopf im leeren Zustand „Nur noch vermisste Platten“.
- Technisch: Die AppKit-Tabelle (`ShelfAssignmentTableController`) ist durch ein SwiftUI-Raster ersetzt (`ShelfAssignmentGrid`, `ShelfAssignmentTile`).
- Geprüft: Build ohne Warnungen, Tests grün, Fensterfotos der Demo von beiden Fenstern (Modern hell), eines mit der Kapsel unter dem Zeiger. **Nicht angeklickt:** „+“, Pause und das „i“-Popover; Klassisch nicht fotografiert; nicht mit einer langen Liste (hunderte Platten ohne Fach) ausprobiert.

# Vermisst in den Einstellungen, „i“ beim Einsortieren · 12.10.2026

- **Neuer Reiter „Vermisst“ in den Einstellungen** (`MissingSettingsView`): Schalter „Vermisst-Liste“ (bisher unter „Regal“) und die Liste aller vermissten Platten mit Cover, Standort und „Freigeben“, dazu „Alle freigeben“. Freigegebene Platten ohne Fach stehen sofort wieder unter „Einsortieren“ und „Platte hinzufügen“, auch im offenen Fenster.
- **„Platte hinzufügen“ / „Einsortieren“** zeigt nur noch verfügbare Platten. Die Vermisst-Spalte rechts samt Einklappen ist weg (`MissingCopiesColumn`, `missingColumnCollapsed`); oben rechts steht „x vermisst“ und öffnet den neuen Reiter. Der Pause-Knopf bleibt: Er stellt eine Platte zurück, sie verlässt die Liste.
- **„i“ statt Pfeil** in jeder Zeile: ein Popover „Hier würde sie stehen“ mit Fach, Position und Nachbarn (bei zwei passenden Fächern beide) und „Im Regal zeigen“ für die Einsortier-Karte. Das „i“ gibt es jetzt auch für Platten, die ins offene Fach passen.
- Welche vermissten Platten gelistet werden, steht an einer Stelle (`MissingCopies.listed`). Texte deutsch/englisch ergänzt, verwaiste entfernt.
- Geprüft: Build ohne Warnungen, 205 Tests grün, Fensterfotos der Demo von „Einsortieren“ und dem Reiter „Vermisst“ (Modern hell). **Nicht angeklickt:** das „i“-Popover, „Freigeben“ und der Pause-Knopf in der laufenden App; Klassisch nicht fotografiert.

# Abschlussprüfung 1.0.7 · 10.10.2026

- README: Der Abgleich schreibt nur Geändertes; Tests brauchen rund 25 Sekunden und was sie abdecken; Prüfdatum. STATISTIK.md: Prüfdatum, Testzahl (31, der Test mit 2.000 Exemplaren entfiel). VALIDIERUNG.md: Befunde zu Tests, Doku, Absturzberichten, Protokoll, Fehlermeldungen und Lokalisierung – kein Fehler im Code, keine neuen Texte.
- DMG aus dem Stand dieses Commits neu erstellt (`dist/Plattenregal-1.0.7.dmg`); gegenüber dem vom Vormittag ohne Unterschied im Verhalten.

# Tests durchgesehen · 10.10.2026

- Alle Tests laufen schon über Swift Testing (kein XCTest mehr), eine Umstellung entfiel. 208 Tests gelesen und gegen den Code abgeglichen; danach **205 Tests**, Laufzeit **24 s statt 78 s**.
- **Entfernt, weil doppelt:** `largeCollectionMergeAndRepeat` (dasselbe prüfen `repeatedSyncIsIdempotent` und `tenThousandRecords`), `folderMove` (die Prüfung steht jetzt in `collectionDetailsCountAsChanges`), `oldStoreMigrationPreservesLocalData` (V2 → V15 prüft `v2StoreMigrates…` gründlicher, „Sync behält den Platz“ `shelfPlaceSurvivesUpdateAndRemoval`), `pdfIsProduced` (in `pdfSpansPagesAndHandlesEmptyLists` aufgegangen), `analyticsDoesNotRequestNetworkAndHandlesThousands` (die Berechnung bekommt nur Werte, der Netzteil konnte nie fehlschlagen; die Menge deckt `tenThousandRecords`).
- **Entfernt mit totem Code:** `normalization` prüfte `PositionService.normalize`, das die App nirgends aufruft. Funktion und Test sind weg; was beim Start tatsächlich repariert wird, prüft jetzt `launchHealsPositionsCompartmentsAndActiveCabinet`.
- **Neu:** Regale umsortieren und umbenennen (`CabinetService.move`/`rename`, bisher ungetestet); Reparatur beim Start (Positionen mit Lücken oder Doppelten, fehlendes Fach, kein aktives Regal); leere Collection/Wantlist gilt als vollständig geladen und leert die Sammlung; Tracklisten werden nur geladen, wenn sie fällig sind (nie gefragt oder älter als 180 Tage; alte ohne Datum werden nur datiert); abgebrochener Sync speichert nichts und hinterlässt keine Statuszeile; eine inzwischen verkaufte Platte wird aus „Platte hinzufügen“ nicht mehr einsortiert; Discogs-Datumsformen (`DiscogsDate.parse`); Ordner und Hinzufügedatum im Export; ein geändertes Release schreibt genau dieses Release.
- **Umgebaut:** Die fünf Fehlerfälle des Discogs-Clients sind ein Test mit Argumenten (`@Test(arguments:)`) statt fünf fast gleicher. Falsch einsortierte Tests liegen jetzt bei ihrem Thema (Export-Intervalle und Fälligkeit in ExportTests, Aufbewahrung in BackupTests). `demoStoresNeverWriteRealBackups` heißt `testStoresNeverWriteRealBackups` – es ging nie um die Demo.
- **Schneller:** `DiscogsAPIClient` nimmt den Abstand zwischen Anfragen (1,1 s) und die Pause vor einer Wiederholung (1 s, dann 2 s) als Parameter; die App nutzt weiter die Vorgaben, die Tests kürzen sie über `DiscogsAPIClient.stubbed`. Ein `Retry-After` von Discogs wird in den Tests weiter abgewartet. Am Verhalten der App ändert sich nichts.

# Version 1.0.7 · 10.10.2026

- Version 1.0.7, Build bleibt 102026. DMG neu erstellt (`dist/Plattenregal-1.0.7.dmg`), mit der korrigierten Sortierung nach Jahr/Label und dem sparsameren Sync. README, STATISTIK.md und VALIDIERUNG.md: Version.

# Logik geprüft: Sortierung nach Jahr und Label, Sync schreibt nur Geändertes · 10.10.2026

- **Fehler behoben – Reihenfolge bei gleichem Interpreten nach „Jahr“ oder „Label“:** Platten ohne Jahr standen vor statt hinter den übrigen des Interpreten, ebenso Platten ohne Label vor Labels, die mit einer Ziffer beginnen („4AD“, „2 Tone“); solche Labels standen außerdem hinter allen Labels mit Buchstaben. Ursache: Das Kennzeichen „bekannt/fehlt“ (0/1) klebte direkt am Wert, und der Vergleich (`localizedStandardCompare`) las „01999“ als Zahl 1999 und „04AD“ als 4 – beides größer als die 1 für „fehlt“. Jetzt steht das Kennzeichen allein vor einem Tabulator (`ShelfSecondaryOrder.key`). Betrifft Platzsuche, „Platte hinzufügen“, „Sortierung prüfen“ und die alphabetische Collection, jeweils nur bei „Jahr“ oder „Label“. Wer danach sortiert hat: „Sortierung prüfen“ zeigt die betroffenen Platten jetzt als Umstellung.
- **Sync schreibt nur, was sich geändert hat:** Bisher setzte jeder Abgleich alle Felder aller Releases, Exemplare, Ordner und Wantlist-Einträge neu (gleiche Werte, dazu `fetchedAt`). Die Datenbank speicherte deshalb bei jedem Sync alles, und das Hauptfenster las anschließend jeden dieser Einträge erneut (`LibraryRecords.refetch`). Jetzt vergleicht `DiscogsBasicInformation.apply` Feld für Feld und meldet, ob etwas anders ist; `merge` fasst Exemplare, Ordner und Wantlist-Einträge nur noch bei Abweichung an. Ein Sync ohne Änderungen speichert nur noch die Zeitpunkte am Konto. `fetchedAt` ist damit der Zeitpunkt der letzten Änderung (wird nirgends gelesen). Die Zählung „aktualisiert“ und `hasChanges` ergeben sich aus denselben Vergleichen wie bisher; das Release-JSON wird nur noch einmal statt zweimal kodiert.
- **Export „Wie im Regal“:** Alphabetisch sortiert werden nur noch die Platten ohne Fach, nicht erst die ganze Sammlung.
- Durchgesehen ohne Befund: Positionen und Regale (`PositionService`, `CabinetService`), Platzsuche und Fachnamen, Sicherung und Wiederherstellung, Zurücksetzen, Export, Statistik und Sammlungswert, Tracklisten, Discogs-Client (Seiten, Limit, Wiederholungen), Cover-Cache. Der Tabulator zwischen Interpret und Titel im Sortierschlüssel sortiert vor Leerzeichen und Satzzeichen – „Beck“ bleibt vor „Beck Hansen“ – per Skript nachgemessen.
- Zwei neue Tests (`recordsWithoutYearOrLabelSortBehindTheOthers`, `unchangedSyncRewritesNoRecords`), der zweite schlug vorher fehl (schrieb 8 statt 1 Eintrag). 208 Tests grün.

# Version 1.0.6 · 09.10.2026

- Version 1.0.6, Build bleibt 102026. DMG neu erstellt (`dist/Plattenregal-1.0.6.dmg`), mit „Einsortieren per Knopf“. README und STATISTIK.md: Version.

# Einsortieren per Knopf · 09.10.2026

- Auf der Regalseite sitzt unten rechts jetzt auch der runde Knopf, als „+“ ohne Fächer. Ein Klick öffnet **Einsortieren**: alle Platten ohne Fach nach Interpret, jede mit „gehört in …“, ohne vorher ein Fach wählen zu müssen. Grund: Für eine neue Platte gab es bisher nur die Suche (Name muss bekannt sein) oder das „+“ eines beliebigen Fachs.
- „+“ in der Zeile setzt die Platte an ihre alphabetische Stelle in ihrem Fach (zwischen zwei Fächern ans Ende des ersten), der Pfeil öffnet die Einsortier-Karte mit beiden Möglichkeiten. Die Karte oben nennt Fach und Nachbarn. Beim Schließen springt das Regal zur zuletzt einsortierten Platte.
- Technisch dasselbe Fenster wie „Platte hinzufügen“ (`ShelfAssignmentSession` mit `shelf == nil`), Raster/Liste bleibt über dem Fachinhalt. Raster und Liste des Fachs lassen unten Platz für den Knopf. Neu `--preview-sortin`.
- Englische Texte im Katalog ergänzt, ein Test für das Einsortieren ohne Fach. Demo in Klassisch angesehen. 206 Tests grün.

# Version 1.0.5, Prüfung · 09.10.2026

- Version 1.0.5, Build bleibt 102026. DMG neu erstellt.
- README: Ziehen zum Aktualisieren nur mit zwei Fingern auf dem Trackpad, Covergröße Klein/Mittel/Groß, Version und Prüfdatum. STATISTIK.md: Version. Befunde zu Protokoll, Absturzberichten und Lokalisierung in VALIDIERUNG.md, ohne Fehler im Code.

# Willkommensseite statt Tour · 09.10.2026

- Die Tour mit sechs Seiten und je zwei Bildschirmfotos ist durch eine Willkommensseite ersetzt: ein Satz zur App, drei nummerierte Schritte (Discogs verbinden, abgleichen, Regal einrichten), Knöpfe „Später“, „Demo starten …“ und „Token eintragen …“. In der Demo nur „Los geht’s“.
- Gründe: Beim ersten Start ist die Sammlung leer, Seiten über Regal, Statistik und Export erklärten Dinge, die noch nicht zu sehen waren. Der eigentliche erste Schritt (Token) stand auf Seite 2. Die 24 Fotos (3,2 MB) waren nach jeder Änderung an der Oberfläche veraltet. Die Leerzustände und die Demo erklären die App ohnehin.
- Die Seite sitzt in der Mitte des Fensters: `appPanel` hat dafür eine Ausrichtung, Standard bleibt oben (wachsende Panels gehen nach unten auf).
- Hilfe-Menü: „Erste Schritte …“ und „Demo starten …“ statt „Tour durch Plattenregal …“.
- Gesehen-Schlüssel bleibt `tourSeen`: Wer die Tour schon geschlossen hat, bekommt die neue Seite nicht noch einmal von selbst.
- Entfernt: `Assets.xcassets/Tour`, `Scripts/tour-screenshots.sh`, `Scripts/winid.swift`. `--preview-tour` heißt jetzt `--preview-welcome`.
- Texte englisch übersetzt, die der Tour im Katalog als veraltet markiert. Demo auf Deutsch hell und Englisch dunkel in Klassisch angesehen. 205 Tests grün.

# DMG mit eigenem Fenster · 09.10.2026

- `Scripts/make-dmg.sh` baut Release und packt die App in `dist/Plattenregal-<Version>.dmg`. Das Fenster ist 660 × 400 pt groß und zeigt die App und den Programme-Ordner mit Pfeil dazwischen, Symbole in 112 pt.
- Hintergrund aus `Scripts/dmg-background.swift`: Papier, eine schwarze Platte mit goldenem Etikett unten, Equalizer und Noten in den Diagrammfarben, Hinweis auf Deutsch und Englisch. Erst ein Regal mit Plattenrücken, auf Wunsch entfernt.
- Der Pfeil sitzt 7 pt unter der Mittellinie der Symbolrahmen. Genau auf der Linie wirkte er zu hoch, weil Ordnerkörper und Hülle im App-Symbol das Gewicht tiefer tragen.
- Die Fenstergrenzen im AppleScript enthalten die Titelleiste (32 pt), sonst fehlt unten ein Streifen des Bildes.
- Einmal speicherte der Finder Fenstergröße und Position, aber weder Hintergrund noch Symbolgröße. Deshalb liest das Skript die `.DS_Store` nach und legt das Layout bis zu dreimal an.

# Einstellungen durchgesehen · 09.10.2026

Alle acht Reiter auf Sinn, Doppelungen und Lücken geprüft.

- **Collection und Wantlist an einem Ort** (Darstellung): Die Reihenfolge stand unter Allgemein › Start, Raster/Liste und Covergröße unter Darstellung in zwei Karten („Übersicht“, „Cover“). Jetzt eine Karte „Collection und Wantlist“: Ansicht und Reihenfolge je Seite, darunter „Covergröße im Raster“. Unter Allgemein › Start bleibt nur „Beim Öffnen zeigen“.
- **Regal › Bei gleichem Interpreten nach**: Der Hinweis nennt jetzt auch die alphabetische Collection, die diese Reihenfolge ebenfalls nutzt.
- **Discogs › Hinweise**: Untertitel „Speicherplatz und Cover-Cache stehen unter ‚Daten‘“ entfernt – ein Überbleibsel, auf der Seite gibt es dazu nichts mehr.
- **Export**: Karte heißt „Automatischer Export“ statt genauso wie ihr Schalter.
- **Daten › Einstellungen zurücksetzen**: Die Rückfrage nennt die Sprache, die dabei auf „System“ zurückgeht (nicht in der Demo).
- **Tastenkürzel**: neue Gruppe „Einstellungen“ mit esc / ⌘W zum Schließen.
- Bewusst gelassen: Akzent- und Ambient-Farbe in Klassisch ausgegraut (dokumentierte Entscheidung), Protokoll unter Speicherplatz (Größe, Leeren) und Diagnose (Finder, Sichern), Demo unter Allgemein und im App-Menü. Kein Abgleich beim Start ergänzt – „Abgeglichen wird auf Wunsch“ ist so gewollt.
- Texte englisch übersetzt, alte im Katalog als veraltet markiert. Fensterfotos der Demo: Allgemein; die neue Karte unter Darstellung liegt unterhalb des sichtbaren Bereichs und ist nicht im Bild. 205 Tests grün.

# Umschalter in den Einstellungen: Animation geprüft, VoiceOver · 09.10.2026

- **Animation geprüft, ohne Änderung**: Alle Umschalter der Einstellungen sind derselbe Baustein (`GlassSegmentedPicker`), dessen Auswahl in 0,3 s zur neuen Option gleitet. In der Demo (Klassisch) jeden per Bedienungshilfen gedrückt und sofort fotografiert – die Auswahl stand jedes Mal zwischen alter und neuer Option: Reiterleiste; Allgemein (Startseite, Reihenfolge Collection und Wantlist); Darstellung (Modus, Raster/Liste, Covergröße); Regal (Bei gleichem Interpreten nach, Beschriftung); Export (Collection/Wantlist, CSV/PDF, Wie im Regal/Alphabetisch); Sicherung (Letzte Stände). Nicht gedrückt: Sprache (fragt nach einem Neustart), Trennzeichen im Export.
- **VoiceOver**: Ein Etikett am Umschalter (`.accessibilityLabel("Modus")`) ersetzte den Namen jeder Option – VoiceOver las „Modus, Modus, Modus“ statt System, Hell, Dunkel; ebenso bei Covergröße, Einstellungsreitern und dem Seitenumschalter. Der Umschalter ist jetzt eine Gruppe mit diesem Namen, die Optionen behalten ihre (per Bedienungshilfen-Abfrage geprüft).
- 205 Tests grün.

# Covergröße: Klein, Mittel, Groß · 09.10.2026

- **Drei Stufen statt Regler** (Einstellungen › Darstellung › Cover): Das Raster füllt die Fensterbreite immer ganz aus, eine Größe zeigt sich also erst, wenn sich die Spaltenzahl ändert – beim alten Regler (120–220 pt in 5-pt-Schritten) tat sich bei jedem zweiten Strich nichts. Jetzt ein Umschalter wie bei „Modus“: Klein 125 pt, Mittel 155 pt (der bisherige Standard), Groß 195 pt; die Abstände ändern bei üblichen Fensterbreiten bei jedem Schritt die Spaltenzahl. Ein gespeicherter Wert des alten Reglers wird zur nächsten Stufe. ⌘+ / ⌘− gehen eine Stufe weiter, ⌘0 auf Mittel. Der Zurücksetzen-Pfeil entfällt (Text im Katalog als veraltet markiert); „Klein“, „Mittel“, „Groß“ englisch übersetzt.
- Geprüft mit Fensterfotos der Demo (Klassisch hell): Umschalter in der Cover-Karte, Auswahl „Groß“ (noch mit dem Regler-Zwischenstand). Test `coverSizeStaysInRange` auf die Stufen umgestellt. 205 Tests grün.

# Wantlist scrollt wie die Collection · 09.10.2026

Gemessen in einer auf ~2.200 Platten und ~2.200 Wantlist-Einträge vergrößerten Demo (Klassisch, Release-Build), Scrollen per Scrollrad-Ereignissen (40/s à 40 pt, 10 s), CPU-Zeit des Hauptthreads, je drei Läufe: **Wantlist 3,85–3,91 s → 3,51–3,59 s; Collection unverändert 3,35–3,47 s.** Ursachen per Time Profiler und Diagnose-Ausgaben gefunden.

- **Scrollposition baute das Raster neu** (`scrollPosition(_:)`): Die Bindung an `ScrollAnchor.id` entstand im Closure des Rasters, und schon das Erzeugen liest `id`. Damit lief bei jeder neuen obersten Reihe der ganze Rasterinhalt samt aller sichtbaren Zellen neu (33-mal in 5 s Scrollen, die Collection 0-mal). Jetzt entsteht die Bindung im Modifier (`AnchoredScrollPosition`), das Raster bleibt unberührt. Gilt für jede Seite mit `ScrollAnchor`.
- **Wantlist-Zelle ohne `frame(maxWidth: .infinity)`**, wie `RecordCard` in der Collection: Der flexible Rahmen ließ SwiftUI die Zelle bei jedem Vermessen auf dem langsamen Weg auslegen. Optik per Fensterfoto unverändert.
- **Der verbleibende Abstand (~4 %)** ist das Mitführen der Scrollposition selbst: Bei jeder neuen obersten Reihe vermisst SwiftUI die sichtbaren Zellen einmal (~7 ms). Mit abgeschalteter Scrollposition lagen Wantlist und Collection gleichauf.
- **Gefunden, nicht geändert:** Das Collection-Raster führt seine Scrollposition nicht mit – beim Scrollen kommt nur `nil` an, weil die Kacheln über die Release-Gruppe (`CollectionCoverGroup.Identity`) identifiziert sind, die Scrollposition aber die UUID der Platte erwartet (`.id(copy.id)` greift dafür nicht). Darum zahlt die Collection die Kosten oben nicht; nach einer Suche springt das Raster laut Code an den Anfang statt an die alte Stelle (nicht in der App ausprobiert).
- 205 Tests grün.

# Ziehen zum Aktualisieren, Suchfeld in der Toolbar, Wantlist-Raster · 09.10.2026

- **Nur echtes Ziehen aktualisiert** (`PullToRefresh`): Ein schneller Wisch nach oben federte mit seinem Schwung über den oberen Rand und füllte den Ring wie ein Ziehen – Collection und Wantlist synchronisierten. Jetzt zählt die Überdehnung nur, solange die Finger auf dem Trackpad liegen (`onScrollPhaseChange`, `.interacting`); ein Rückfedern aus dem Schwung zeigt keinen Ring und bleibt wirkungslos, auch wenn die Finger währenddessen aufsetzen. Ziehen mit der Maus und ⌘R unverändert. Gilt auch für die Statistik.
- **Suchfeld in der Toolbar bleibt petrol** (Klassisch): Das Feld nahm `AtelierPalette.surface`, das sich nach dem Farbschema der Toolbar (dunkel) richtet. Kam dieses Schema in einem Randfall hell an, wurde das Feld cremeweiß, bis zum Neustart. Jetzt feste Farben der dunklen Fläche (`toolbarField`, `toolbarFieldBorder`) und ein festes dunkles Schema für Text und Platzhalter. Nicht reproduziert, daher nur über den Weg abgesichert, nicht am Fehler selbst geprüft.
- **Wantlist-Raster wie die Collection**: Die Zelle ist eine eigene View (`WantlistCard`, wie `RecordCard`), und Raster, Liste, Scrollposition, Klicks und Menüs verwenden die Discogs-Release-ID als gespeicherte Zahl (`WantlistItem`) statt des `PersistentIdentifier` des Modells, der bei jeder Zelle über SwiftData gelesen und aufwendig gehasht wurde. Nicht mit Instruments gemessen.
- 205 Tests grün.

# Start, verborgene Seiten, Speicher · 09.10.2026

Gemessen in einer auf ~2.000 Platten vergrößerten Demo (Release-Build): Zeitstempel in der App über je drei Starts, Instruments (Time Profiler) und `footprint`. **Nach dem ersten Erscheinen des Fensters war der Hauptthread ~1,36 s beschäftigt, jetzt ~0,75–0,87 s.**

- **Seiten beim Start nacheinander** (`PageStack`): Alle vier Seiten wurden sofort gebaut, angelegt und gezeichnet, auch die drei unsichtbaren (~0,6 s). Jetzt sofort nur die gezeigte; die übrigen folgen eine nach der anderen, sobald der Hauptthread nichts zu tun hat (ab ~0,8 s nach dem Start), oder sofort, wenn man vorher auf sie wechselt. Geprüft mit Fensterfotos: Wechsel 0,3 s nach dem Start zur noch nicht gebauten Statistik und spätere Wechsel auf Regal, Wantlist, Statistik zeigen jeweils die fertige Seite.
- **Keine Animationen auf verborgenen Seiten**: Der Aktivitätsring (`ActivityRing`) drehte sich in jedem Bild auch auf verborgenen Seiten – beim Sync auf Collection *und* Wantlist, beim Start auf der rechnenden Statistik. Er steht dort jetzt still. Die großen Zahlen der Statistik rollen nur noch, wo man sie sieht; auf der verborgenen Seite stehen sie gleich auf ihrem Wert.
- **Gemessen, ohne Änderung**:
  - *Seitenwechsel*: ~40 ms am Stück beim Klick, insgesamt ~200 ms Hauptthread über die 0,3 s der Animation. Fast alles davon ist das Gleiten der Auswahl im Umschalter: Jede animierte Änderung in einem Toolbar-Element lässt AppKit die Toolbar in jedem Bild neu anordnen (ohne Animation ~28 ms). Eine verschobene statt gemorphte Linse änderte daran nichts; die gleitende Linse bleibt (Design).
  - *Verborgene Seiten wirklich ausblenden* (`isHidden`) statt nur durchsichtig: beim Hovern keine messbare Ersparnis, daher nicht übernommen.
  - *Speicher*: ~220 MB nach dem Start, ~300 MB nach dem Besuch aller Seiten und mehrerer Fächer, bis ~500 MB nach langem Scrollen durch die Collection, danach stabil. Davon Cover-Bitmaps bis ~150 MB (die Grenze von 320 Covern greift vor den 256 MB) und etwa ebenso viel Ebenen-Speicher von Core Animation, der mit den angezeigten Covern mitwächst. Echte Discogs-Cover vorab ins native Pixelformat von Core Animation (BGRX) umzurechnen änderte weder Speicher noch Scroll-Zeit (Gegenprobe mit echten Covern, je zwei Läufe).
  - *Kurzansicht eines Covers öffnen*: ~70 ms. *Erstes Anzeigen der Statistik*: ~40 ms.
  - *Nach einem Sync*: die verborgene Regal-Seite baut ihre Fachbeschriftungen neu (~140 ms), die Collection ihre Listen (~50 ms) – einmal pro Sync, daher belassen.
- 205 Tests grün.

# Statistik: Neuberechnung im Hintergrund, Hover ohne unsichtbare Seiten · 09.10.2026

Gemessen mit Instruments (Time Profiler, Release-Build) in einer auf ~2.000 Platten vergrößerten Demo mit Discogs-Rohdaten je Release, Hauptthread-Zeit alt → neu: **Neuberechnung nach einem Sync-Speichern ~390 ms → ~5 ms; danach gleiten die Diagramme nicht mehr ~0,45 s bei voller Last zu den neuen Werten; insgesamt pro Sync-Speichern ~1,7 s → ~0,95 s. Mausbewegung über die Statistik (Fenster aktiv): über der Wertkurve 61 % → 30 % Hauptthread-Last, über einer Stelle ohne Hover-Effekt 30 % → 25 %.**

- **Neuberechnung ganz im Hintergrund**: Die Statistik las alle Platten auf dem Hauptthread in einem frischen Kontext, und jedes Release kam als eigene Datenbankabfrage (`discogsID` als erster Zugriff). Jetzt in einem eigenen Kontext neben dem Hauptthread, die Releases in derselben Abfrage. Die Platten, die die Seite zeigt, kommen aus dem gemeinsamen Bestand des Hauptfensters – es sind dieselben Objekte wie überall, die Detailansicht speichert sie direkt. Neuer Test `statisticsShowTheAppsOwnRecords`.
- **Feder-Animation nur für die Kapsel** „Wird berechnet“: Sie lag auf der ganzen Seite und erfasste auch die neuen Zahlen, die im selben Moment ankamen – jedes Diagramm glitt zu seinen neuen Werten und wurde dabei in jedem Bild neu gezeichnet. Jetzt springen die Diagramme, die Kapsel gleitet wie bisher (Entscheidung des Nutzers). Das Hochrollen der großen Zahlen bleibt bewusst (~40 % Last für gut eine Sekunde).
- **Unsichtbare Seiten bekommen kein Hover mehr** (`PageStack`): Ausgeblendete Seiten liegen durchsichtig im Fenster und nahmen keine Klicks, aber weiter Mausbewegungen an. Fuhr der Zeiger über die Statistik, leuchteten darunter unsichtbare Fächer des Regals auf und wurden neu gezeichnet, und das Fenster berechnete jedes Mal seine Ziehbereiche über alle Seiten neu. Gilt für alle Seiten.
- **Wertkurve zeichnet nur bei neuem Punkt neu**: Sie merkte sich das Datum unter dem Zeiger, das sich mit jedem Pixel ändert; jetzt den Punkt. Balken und Kreisdiagramm setzen ihren Zustand ebenfalls nur bei einem Wechsel.
- **Ohne Änderung, gemessen**: Erstes Anzeigen der Statistik ~40 ms am Stück, danach der Seitenwechsel. Was beim Bewegen des Zeigers bleibt, sind die Hover- und Tooltip-Prüfungen von SwiftUI über die sichtbare Seite (~2 ms pro Mausereignis). Nach einem Sync-Speichern baut die verborgene Regal-Seite ihre Fachbeschriftungen neu (~140 ms, bei einem echten Sync einmal am Ende).
- Geprüft mit Fensterfotos der Demo: Statistik unverändert, Hover-Wert unter der Kurve („1.213,00 € · 9. Juni 2025“) im alten und neuen Stand gleich. 205 Tests grün.

# Regal: Fach wählen, „Platte hinzufügen“, Platz finden · 09.10.2026

Gemessen mit Instruments (Time Profiler, Release-Build) in einer auf ~2.000 Platten vergrößerten Demo (12 Fächer à 150, 180 Platten ohne Fach), Klicks per synthetischen Mausereignissen, Hauptthread-Zeit alt → neu: **„Platte hinzufügen“ öffnen: Einlesen 72 ms → 28 ms; Platz finden (Suchtreffer „Platz finden“) 33 ms → 10 ms; eine Platte im offenen Fenster hinzufügen: Fachinhalt dahinter ~25 ms → ~3 ms; Klick auf ein Cover (Positionsregler) ~6 ms → <1 ms pro Neuzeichnen.**

- **Sortierschlüssel beim Einsortieren aus dem Zwischenspeicher**: Platzsuche, „gehört in …“ in „Platte hinzufügen“ und die Platzkarte lasen die Schlüssel aller eingeräumten Platten frisch aus den Releases – nach jedem Speichern holt SwiftData die einzeln nach. Jetzt dieselben Schlüssel wie die Fachbeschriftungen (`ShelfSortKeys`, gültig bis zur nächsten Metadaten-Änderung); Beschriftung und Einsortieren können so auch nie verschiedene Stände sehen.
- **Nur die nötigen Fächer sortieren**: Für die Reihenfolge der Fächer genügen erster und letzter Schlüssel; nach Position sortiert werden nur noch die ein, zwei Fächer, neben die die Platte kommt (vorher jedes Fach bei jeder Platzsuche).
- **Platten ohne Fach in einer Abfrage**: „Platte hinzufügen“ lädt deren Releases gleich mit, statt sie für Schlüssel und Liste einzeln nachzuladen.
- **Fachinhalt nach dem Speichern**: Interpret, Titel, Jahr, Label und Style der Kacheln und Tabellenzeilen werden pro Platte bis zur nächsten Metadaten-Änderung gemerkt (`ShelfCopyReleaseFields`). Vorher las jedes Einsortieren und jede Bewegung mit dem Positionsregler alle Releases des Fachs einzeln neu.
- **Positionsregler im Cover-Popover** zählte das Fach bei jedem Neuzeichnen – auch bei jedem Schritt beim Ziehen – rund achtmal durch; jetzt einmal.
- **Platten ohne Collection** (Hinweis über dem Regal): Prüft nach jedem Speichern zuerst die Collection, erst dann das Fach.
- **Ohne Änderung, gemessen**: Ein Fachwechsel kostet ~130 ms am Stück plus ~170 ms Einblend-Animation, davon nur ~20 ms eigener Code – der Rest ist SwiftUI beim Aufbau des Cover-Rasters (150 Kacheln). Ein Cover-Klick ~90 ms, überwiegend das Öffnen des Popovers durch AppKit.
- **Fenster über der Seite blenden nur noch ein** („Platte hinzufügen“, „Sortierung prüfen“ und die übrigen Fenster dieser Art, Klassisch und Modern): Das leichte Hineinzoomen (0,96 → 1) ließ AppKit in jedem Bild alle Tabellenzeilen und die Ziehbereiche des Fensters neu berechnen; der Hauptthread war beim Öffnen von „Platte hinzufügen“ ~0,45 s voll ausgelastet. Jetzt ~160 ms am Stück, danach läuft die Einblendung bei ~20 % Last. Entscheidung des Nutzers nach der Messung.
- Geprüft mit Fensterfotos der Demo: Platzkarte (gleiche Position und Nachbarn wie vorher), „gehört in …“ in „Platte hinzufügen“, vier Platten nacheinander hinzugefügt, Positionsregler im Cover-Popover. Neuer Test `placementAndShelfContentsFollowChangedMetadata` (schlägt mit abgeschalteter Invalidierung fehl, geprüft). 204 Tests grün.

# Doku, Fehlerprotokoll und ein Testabsturz im gemeinsamen Bestand · 08.10.2026

- **Absturz in `LibraryRecords`** (macOS-Bericht `Plattenregal-2026-10-08-093425.ips`, aus einem Testlauf während des Umbaus am Morgen; `EXC_BREAKPOINT` in SwiftData, aus `reloadSmallLists`): Der gemeinsame Bestand merkte sich Container nur an ihrer Adresse. Ein Kontext hält seinen Container nicht fest; wurde einer freigegeben und ein neuer bekam dieselbe Adresse, hielt der alte Bestand dessen Speichern für sein eigenes und las über seinen toten Kontext. In Tests (Hunderte Container) reproduzierbar, in der App mit einem einzigen Container unwahrscheinlich, aber nicht ausgeschlossen. Jetzt hält der Bestand seinen Container schwach und reagiert nur auf Speichervorgänge genau dieses Containers; Bestände freigegebener Container werden aufgeräumt. Neuer Test `sharedRecordsOfReleasedContainersStayOut` – mit dem alten Code stürzt er genauso ab (geprüft), mit dem neuen grün.
- **Lesefehler im gemeinsamen Bestand** wurden still verschluckt und ersetzten die Liste durch eine leere – die Sammlung wäre auf allen Seiten verschwunden, ohne Spur im Protokoll. Jetzt bleibt der letzte Stand stehen und das Protokoll bekommt eine Zeile (Kategorie „Datenbank“).
- **README**: Modern mit weißem Passepartout, Ambient-Fläche und Farbpunkten; Regalsuche („Regal durchsuchen“, „Ohne Fach“); `LibraryRecords` unter „Wichtige Dateien“; neuer Fall unter „Fehlermeldungen und Protokoll“. **STATISTIK.md**: Zufallsfund rechnet seinen Platz erst beim Anzeigen nach, Sammlungswert während eines Syncs, feste Ranglisten bei Gleichstand, 31 Statistik-Tests.
- **Lokalisierung** per Skript geprüft: 871 Einträge, 34 veraltet (keiner davon noch im Code), jeder aktive mit englischer Übersetzung und gleichen Platzhaltern; kein Text aus `Text`, `Button`, `String(localized:)` usw. fehlt im Katalog. Keine Änderung nötig.
- 203 Tests grün, keine Compilerwarnungen.

# Datenänderungen und Suche: weniger Arbeit nach jedem Speichern · 08.10.2026

Gemessen mit Instruments (Release-Build) in einer Demo in der Größe der echten Sammlung (≈900 Platten, 870 Wantlist-Einträge, je ~10 Tracks), Hauptthread-Zeit pro Ereignis alt → neu: **10 Tracklisten gespeichert (Download nach dem Sync) ~210 ms → ~5 ms; eine Platte verschoben (Regal-Seite) ~350 ms → ~45 ms; Sync gespeichert (50 geändert, 5 neu) 500–700 ms → ~255 ms; automatische Sicherung ~75 ms → ganz im Hintergrund.**

- **Gemeinsamer Bestand statt `@Query` pro Seite** (`LibraryRecords`): Collection, Wantlist und Regal hatten je eigene Abfragen auf alle Platten, Wünsche, Fächer, Regale, Konten. SwiftData lud sie nach *jedem* Speichern komplett neu und baute dabei jede Seite samt Kacheln neu auf – auch die unsichtbaren. Jetzt werden Platten und Wünsche einmal geladen und nur neu, wenn ein Speichern (aus irgendeinem Kontext) welche einfügt oder löscht; die kleinen Listen werden nach jedem Speichern gelesen, aber nur bei echter Änderung übernommen. Werte, die ein anderer Kontext gespeichert hat (Sync, Tracklisten), holt der Hauptkontext gezielt für die geänderten Objekte – das hatte vorher die ständige Neuabfrage nebenbei erledigt (beim Umbau zuerst übersehen, in der Demo gefunden: neue Tracks waren nicht suchbar). Neuer Test `sharedRecordsFollowSavesFromOtherContexts`.
- **Seiten beobachten Datenstand und Suchtext in eigenen Bausteinen** (`onObservedChange`, `observedTask`): Gelesen im Body der Seite, baute jede Meldung (`tracksVersion`, `libraryVersion`, …) und bei Collection/Wantlist jeder Tastendruck die ganze Seite mit allen Kacheln neu auf – auch wenn nichts zu tun war.
- **Fachbeschriftungen**: Sortierschlüssel der Platten werden zwischengespeichert, bis sich Metadaten oder die Reihenfolge ändern (`ShelfSortKeys`); vorher fragte SwiftData nach dem Speichern für jeden Interpreten einzeln die Datenbank ab. Müssen mehrere Fächer neu gelesen werden (nach einem Sync), kommen die Releases in einer Abfrage, einmal pro Datenstand.
- **Zufallsplatte der Statistik** rechnet ihren Platz nicht mehr bei jeder Verschiebung neu, während die Statistik nicht gezeigt wird – erst beim Zeigen.
- **Automatische Sicherung** liest die Belegung in einem eigenen Kontext neben dem Hauptthread (vorher ~75 ms Hänger 3 s nach der letzten Änderung). Neuer Test `backupTakenOffTheMainActorMatches`.
- **Sichtbare Kacheln nach einem Sync**: zeigten geänderte Titel erst nach dem Wegscrollen (war auch vorher so, per Foto verglichen). Beschriftung und Cover lesen jetzt den Datenstand mit und zeichnen sich bei Sync/Neuladen neu.
- **Suche** (Messung): Tippen in der Collection kostet ~1,2 s Hauptthread für 10 Zeichen; die Suche selbst ~10 %, die Gleit-Animation der Treffer etwa die Hälfte – als Design-Entscheidung unverändert. Regalsuche ~80 ms pro Taste, fast nur Zeichnen der Trefferliste.
- Geprüft in der laufenden Demo: neue Platten nach Sync erscheinen und sind suchbar; neue Tracks werden gefunden (Suche vorher wie nachher gestartet); geänderte Titel werden angezeigt und gefunden; Verschieben im sichtbaren Fach aktualisiert Kacheln und Nummern. 202 Tests grün.

# Scrollen: weniger Arbeit pro Frame · 08.10.2026

Gemessen mit Instruments (Time Profiler, Release-Build) in einer auf ~2.200 Platten vergrößerten Demo, Scrollen per Scrollrad-Ereignissen (40/s à 40 pt, 10 s), Hauptthread-Zeit alt → neu: **Collection Klassisch 5,6 s → 2,8 s, Modern 5,7 s → 2,7 s; Regal (Fachinhalt) Klassisch 5,4 s → 2,5 s, Modern 5,3 s → 3,3 s**.

- **Scroll-Position baute die Seite neu auf**: Jedes Mal, wenn eine neue Reihe oben ankam, lief die ganze Collection-Seite samt aller vorgehaltenen Cover-Zellen neu (~150 Zellen, mehrmals pro Sekunde; dabei auch `items.map(\.id)` über alle Platten). Die Position liegt jetzt in einem beobachteten Objekt (`ScrollAnchor`) und wird in einem eigenen Modifier gelesen (`scrollPosition(_:)` / `scrollPosition(tracking:)`), sodass nur dieser nachläuft. Gilt für Collection, Wantlist (Raster und Liste) und den Fachinhalt im Regal; dort sind die gemerkten Positionen von der Beobachtung ausgenommen (`ShelfContentsSession`), weil das Wiederherstellen ohnehin ausdrücklich scrollt.
- **Rechtsklick ohne AppKit-View pro Cover**: Jede Zelle hatte eine eigene unsichtbare AppKit-View für den Rechtsklick. Allein deren Existenz ließ macOS bei jedem Scroll-Frame die Ziehbereiche des Fensters über alle Zellen neu berechnen (bis ein Viertel der Zeit). Jetzt liegt ein einziger Fänger über dem Raster und findet die Zelle über deren Rahmen (`GridSecondaryClicks`). Menü und Ankerpunkt unverändert – nach dem Scrollen per Foto mit dem alten Stand verglichen (pixelgleich).
- **Marken auf den Covern in Klassisch ohne Glas**: `appChipSurface` setzte auch in Klassisch `.glassEffect(.identity)`, was trotzdem die Glas-Maschinerie an jede Positions- und Anzahlmarke hängt; im Regal ein Drittel der restlichen Zeit. Aussehen unverändert (Papier mit Rand).
- **Cover beim Zurückscrollen sofort da**: Bereits geladene Cover kommen synchron aus dem Speicher (`CoverCache.cachedImage`) statt über den Actor – kein Platzhalter-Frame mehr. Der Speicher führt seine Größe mit, statt sie bei jedem neuen Cover über alle Einträge zu summieren.
- **Ziehen zum Aktualisieren** meldet die Scroll-Position nur noch nahe dem oberen Rand, nicht bei jedem Frame.
- **Glasmarken im Regal gemeinsam gerendert** (Modern): Jede Kachel im Fachinhalt trägt eine Positionsmarke aus Glas; ein `GlassEffectContainer` um das Raster spart ~10 % pro Scroll-Schritt. Marken per Foto mit dem alten Stand verglichen: pixelgleich.
- Geprüft mit Fensterfotos der Demo: Marken in Klassisch unverändert; Rechtsklick im Regal nach dem Scrollen trifft das richtige Cover (Klassisch und Modern); Scrollstelle kommt nach Fachwechsel hin und zurück wieder. 200 Tests grün.

# Aktualisieren: Ring mit Abstand, Sync-Kapsel gleitet · 07.10.2026

- **Linie unter der Toolbar** nach dem Wechsel von Klassisch zu Modern: Das Hauptfenster behielt den sichtbaren Toolbar-Hintergrund von Klassisch samt Trennlinie. Modern blendet ihn jetzt ausdrücklich aus wie schon die Einstellungen. Dadurch bekommt die Toolbar in Modern auch beim Scrollen keine weiße Leiste mit Linie mehr, der Hintergrund läuft durch. Geprüft mit Fotos der Demo: Wechsel Klassisch → Modern bei aktivem Fenster, frischer Start in Modern, gescrollt alt und neu.
- **Rand um die Cover auch in Modern**: derselbe Passepartout wie in Klassisch (6 pt Rand, abgerundete Ecken, feine Kante, weicher Schatten), in Modern weiß (dunkel: leichter heller Schleier über dem Fenster) mit der Kante des Systems statt Creme. Geprüft mit Fotos der Demo: Collection hell und dunkel, Regal hell. Gilt überall, wo Klassisch den Rahmen zeigt (Collection, Wantlist, Regal, Statistik); Auswahlrand und Abstand der Marken auf dem Cover passen sich an (`AtelierCoverFrame.usesMat`). Die Cover werden dadurch etwas kleiner, wie in Klassisch.
- **Toolbar nach Designwechsel**: Wurden die Einstellungen in Klassisch geöffnet und dann auf Modern umgestellt, behielt ihre Toolbar das dunkle Schema von Klassisch – graue Glaslinse, kaum lesbare helle Bereichsnamen auf der hellen Leiste. `SignatureToolbarAppearance` setzt das Farbschema jetzt immer (Klassisch dunkel, Modern das des Fensters), statt es in Modern wegzulassen. Nachgestellt in der Demo (Start in Klassisch → Einstellungen → Modern) und nach der Korrektur geprüft, auch zurück zu Klassisch.
- **Farbpunkte für Modern** (Einstellungen › Darstellung › Design): wie bei Klassisch drei Punkte unter der Beschreibung – die gewählte Akzentfarbe, die Fensterfläche und die gewählte Ambient-Farbe (bei „Aus“ die Fläche). Sie wechseln mit, wenn man die Farben ändert.
- **Hintergrund in Modern** als Gegenstück zum Papier von Klassisch: Statt nur eines schwachen Scheins oben liegt das ganze Fenster leicht in der Ambient-Farbe (oben stärker, nach unten auslaufend), mit hellerem Schein oben und einem zweiten sanften Schein aus der unteren rechten Ecke. Bei Ambient „Aus“ unverändert neutral. Geprüft mit Fensterfotos der Demo: Collection hell und dunkel, Regal hell, Einstellungen hell.
- **Platzkarte im Regal**: „Abbrechen“ und „Gefunden“/„Hier einsortieren“ stehen jetzt vertikal mittig neben Cover und Text statt oben an der Überschrift; Cover und Text bleiben oben ausgerichtet.
- **Suchtreffer im Regal anklicken**: Das Cover-Raster des neuen Fachs blendete oben ein und scrollte dann sichtbar zur Platte, während die Platzkarte aufklappte – wirkte hektisch. Jetzt bleibt das neue Raster kurz unsichtbar, springt ohne Animation auf die Platte und blendet dann weich ein (`gridRevealPending` in `ShelfContentsView`). Gilt auch für „im Regal zeigen“; bei reduzierter Bewegung wie bisher.
- **Herunterziehen** geprüft: Collection, Wantlist und Statistik nutzen denselben Baustein (`pullToRefresh`) mit denselben Schwellen (Maus 70 pt gedämpfter Zug) – kein Angleichen nötig. Trackpad-Schwelle von 38 auf 40 pt angehoben.
- **Ring beim Ziehen** 8 pt unter dem oberen Seitenrand statt direkt daran; von dort folgt er dem Zug wie bisher.
- **Sync-Kapsel** (`DiscogsSyncPill`): Jeder Schritt bleibt mindestens 0,9 s stehen, schnelle Zwischenschritte werden übersprungen, und Text, Symbol und Größe wechseln in einer gemeinsamen Animation (vorher drei getrennte mit unterschiedlicher Dauer) – beim Nachladen der Tracklisten nach dem Start springt sie nicht mehr. Inhalt und Kapsel bewegen sich beim Größerwerden als ein Stück (`geometryGroup`), ebenso in der Kapsel der Statistik.
- **Zweite Zeile der Sync-Kapsel** („Nichts hinzugefügt“, „x von y“) in der Akzentfarbe wie Ring und Haken (Klassisch Petrol, Modern der gewählte Akzent) statt grau; die Titelzeile beider Kapseln in Klassisch in der Tinte des Designs.
- **Suchfeld auf der Regalseite**: Platzhalter „Regal durchsuchen“ statt „Platte im Regal suchen …“ (englisch „Search shelf“, alter Text als veraltet markiert).
- **Trefferliste der Regalsuche** überarbeitet: Zeilen und Cover wie bei „Platte hinzufügen“ (52 pt, Cover 38 statt 28 pt), Interpret halbfett, Titel gedämpft; der Platz rechts zweizeilig (Fach, darunter Regal · Position) statt einer abgeschnittenen Zeile. Platten ohne Fach unter dem Zwischentitel „Ohne Fach“ mit „Platz finden“ in der Akzentfarbe statt Trennlinie. Fläche in Klassisch Papier mit Rand und Tinte, in Modern zur Fensterfarbe getöntes Glas wie Popover und Sync-Kapsel; scrollt nur, wenn das Fenster zu niedrig ist. Geprüft mit Fensterfotos der Demo in beiden Designs, hell und dunkel.
- **„x weitere Treffer“** unter der Regalsuche in der Akzentfarbe (Klassisch Petrol, Modern der gewählte Akzent) statt grau, wie die zweite Zeile der Sync-Kapsel.
- **Rechtsklick auf ein Fach** (Regalseite und Einstellungen): „Inhalt anzeigen“ entfällt; „Fach sperren“ ohne zweite Zeile „Nur leere Fächer lassen sich sperren“ (bei belegten Fächern weiterhin ausgegraut). Beide Texte im Katalog als veraltet markiert.
- **Sortierung prüfen** ruhiger: Unten steht nur noch „Reihenfolge übernehmen“ – als schlichter Button, golden (Modern: Akzentschrift) erst, wenn alle Schritte abgehakt sind. Der Hinweis „Übernimmt ‚…‘ auch für Platzsuche …“ steht in der Akzentfarbe unter der Auswahl Titel/Jahr/Label und nur, wenn dort etwas anderes als bisher gewählt ist. Die Karte „x Platten umstellen“ ohne Erklärsatz, mit „1 von 3“ in der Akzentfarbe und dünnem Fortschrittsbalken; am Ende „Alles umgestellt“ mit Haken in Grün. Der nächste offene Schritt trägt den Auswahlrand (Klassisch Gold), das Ziel („hinter **Interpret** – Titel“) steht in der Textfarbe statt grau, nur „Platz x“ bleibt gedämpft. Neue Startargumente `--preview-sortcheck` und `--preview-sortcheck-done=N` für Fensterfotos. Geprüft mit Fotos der Demo: Klassisch hell und dunkel, Modern dunkel; der Hinweis bei geänderter Reihenfolge nicht im Bild.
- **Fenster über der Seite** (`appPanel`: Sortierung prüfen, Platte hinzufügen, Plattenliste der Statistik): Ein Klick direkt nach dem Schließen ging verloren, weil Klickfläche und Fenster während des Ausblendens (0,25 s) noch Klicks abfingen. Beim Schließen lassen beide Klicks jetzt sofort durch. Nachgestellt in der Demo mit echten Mausklicks (Rechtsklick → Sortierung prüfen → daneben → gleich ein anderes Fach): vorher erst der zweite Klick, jetzt der erste – für Fächer neben und unter dem Fenster.
- **Ordner `outputs/` gelöscht** (Arbeitsdateien: zwei gebaute Apps, Vergleichsbilder, Vorlage und Prompt des App-Symbols). Verweise in README, AENDERUNGEN.md und VALIDIERUNG.md zeigen auf die Git-Historie (Commit `2b2152e`).
- **Durchsicht des Codes** (Stand nach den heutigen Änderungen): alle 197 Tests grün, kompletter Neubau ohne Warnungen, jeder aktive Katalogeintrag mit englischer Übersetzung und passenden Platzhaltern (per Skript geprüft). Korrigiert:
  - **Sortierung prüfen bei gleichen Platten**: Zwei Exemplare desselben Albums (gleicher Sortierschlüssel) wurden nach ihrer internen ID geordnet; je nach ID verlangte die Prüfung, eine Platte „hinter“ ihr gleiches Gegenstück zu stellen, und „Reihenfolge übernehmen“ tauschte sie. Bei gleichem Schlüssel gilt jetzt die bisherige Reihenfolge im Fach (`ShelfSortCheck.sortedCopies`); neuer Test `sortCheckKeepsEqualRecordsInPlace`.
  - **Zielzeile der Umstellschritte** ohne das in macOS 26 veraltete Verketten von `Text` mit `+` (drei Compiler-Warnungen), jetzt als `AttributedString` mit halbfettem Interpreten.
- **Randfälle appweit geprüft** (Rechnungen mit Teilern, Listenzugriffe, leere Sammlung und leere Fächer, Positionen, Regale verkleinern/löschen, Sicherung wiederherstellen inkl. handbearbeiteter Dateien, Export ohne Platten, Formeln in CSV, Preise von Discogs, Rückgängig nach gelöschtem Fach). Korrigiert: **Suche findet Buchstaben ohne zerlegbaren Akzent** – „mo“ findet „MØ“, „lona“ findet „Łona“, „oystein“ findet „Øystein“, wie es die Buchstabenleiste schon einordnete. `SearchIndex.fold` wendet dafür Latin-ASCII an, aber nur auf Texte, in denen nach dem Akzent-Entfernen noch ein solcher Buchstabe steht (die Umwandlung ist langsam, Tracklisten sind meist reines ASCII). Gilt für Collection, Wantlist, Regal und Discogs-Suche; neuer Test `searchFoldsLatinLettersWithoutAccentMarks`. 198 Tests grün.
- **Weitere Randfälle** (Discogs-Anbindung, Fachbeschriftungen, Platzsuche, Listen):
  - **Ein Interpret über mehrere Fächer**: Fächer, die mit denselben Buchstaben beginnen (etwa zwei Fächer „The Beatles“), standen in der alphabetischen Folge in zufälliger Reihenfolge – „Th · 1“ und „Th · 2“ konnten bei jeder Neuberechnung tauschen, und die Grenzbuchstaben zum Nachbarn hingen vom Zufall ab. Jetzt entscheiden die vollen Sortierschlüssel (Interpret, dann Titel bzw. die gewählte Reihenfolge) wie beim Einsortieren, danach die Lage im Regal (`Shelf.readingOrder`). Dasselbe für die Platzsuche, wenn zwei Fächer mit derselben Platte beginnen. Der Zwischenspeicher der Fachgrenzen rechnet nach einem Wechsel von Titel/Jahr/Label neu. Neuer Test `labelsOfShelvesStartingAlikeAreStable`.
  - **Gleiche Platten in Listen**: Trefferliste der Regalsuche und „Platte hinzufügen“ ordnen zwei Exemplare desselben Albums jetzt fest (wie die Collection), statt sie beim Tippen oder Aktualisieren tauschen zu lassen.
  - Ohne Befund: Discogs-Seitenzählung, Wartezeiten bei Drosselung, Wiederholungen, Tokenprüfung; Zusammenführen beim Sync (doppelte Ordner/Wünsche, entfernte Platten behalten ihren Platz), Tracklisten-Nachladen (gelöschte Releases, Abbruch, Fehler je Release); geplanter Export (läuft nicht während eines Syncs, ersetzt nie eine Datei durch eine leere Liste, falsche Uhrzeit); Collection-Gruppen; Positionsregler bei einem Fach mit einer Platte. 199 Tests grün.
- **Randfälle in Statistik und Sammlungswert:**
  - **Sammlungswert während eines Syncs**: Speicherte ein Sync, während die Statistik den Wert lud, meldete die App fälschlich „Der Discogs-Token passt nicht mehr zum geladenen Konto“, und der Sync übersprang seine eigene Wertabfrage (lief ja schon eine) – der Wert blieb alt. Jetzt fragt sie einmal für die neue Sammlung nach; die Token-Meldung kommt nur, wenn sich der Token wirklich geändert hat. Neuer Test `collectionChangingDuringValueRequestIsAskedAgain`.
  - **Ranglisten bei Gleichstand**: Gruppen mit gleicher Anzahl und gleichem Namen (zwei Discogs-Künstler „Moby“, „Rock“/„rock“) standen in zufälliger Reihenfolge und konnten bei jedem Aktualisieren springen; die ID entscheidet jetzt zuletzt (`CollectionAnalyticsService.ranked`).
- Debug-Build erfolgreich.

# Platte hinzufügen, Vermisst und Rechtsklick-Menüs ruhiger · 07.10.2026

- **Vermisst-Spalte** aufgebaut wie die linke Spalte: Titel, Karte „Beim Einsortieren nicht gefunden – Vermutlich noch in einem anderen Fach“ mit dem Raster-Symbol (gemeinsamer Baustein `AssignmentCard`), darunter die Platten flach in Regalreihenfolge. Entfallen: Anzahl, Beschreibungstext, Fach-Zwischentitel, Text „Platz finden“/„Zeigen“. Zeilen so hoch wie links (52 pt, Cover 38 pt, gleiche Schrift), erstes Cover pixelgenau auf Höhe des ersten Covers links. Der Haken erscheint nur beim Überfahren; ein Klick auf die Zeile zeigt das Fach bzw. sucht den Platz.
- **Platte hinzufügen**: kein Suchfeld mehr, keine Zeile „x Platten ohne Fach“. Die Fachkarte ohne Goldrand (neutrale Kartenfläche); die Fläche ragt seitlich heraus, damit das Raster-Symbol mittig über den Covern und „Fach …“ bündig mit den Interpreten steht. Pause, Pfeil und Plus als schlichte Kreissymbole wie der Haken bei Vermisst, nur beim Überfahren sichtbar (ein rotes Pause-Symbol einer vermissten Platte bleibt stehen).
- **Rechtsklick-Menüs** (Fachinhalt, Fächer, Collection/Wantlist): ohne Symbole und ohne Trennlinien; „Exemplar bearbeiten“ ohne Auslassungspunkte.
- **Übersetzungen**: neue Texte der Vermisst-Karte und „Exemplar bearbeiten“ ins Englische übersetzt, der entfallene Beschreibungstext als veraltet markiert; die zuvor offenen Katalogänderungen von Xcode (veraltete Einträge, „%lld von %lld“, „Die technischen Details stehen im Protokoll.“) mit übernommen. Jeder aktive Eintrag hat eine englische Übersetzung mit passenden Platzhaltern (per Skript geprüft).
- **README**: „Platte hinzufügen“, Vermisst-Spalte und Rechtsklick-Menüs auf den neuen Stand gebracht.
- Geprüft mit Fensterfotos der Demo (Klassisch hell und dunkel, Modern dunkel; Modern hell nur vor dem Umbau der Vermisst-Spalte): Symbol mittig über den Covern, Titel, Karten und erstes Cover links und rechts auf gleicher Höhe (nachgemessen), Hover-Symbole sichtbar. Nicht im Bild geprüft: Rechtsklick-Menüs.

# Nachprüfung mit echten Fensterfotos: Statistik, Popover, Tour · 07.10.2026

Bisher Ungeprüftes in beiden Designs angesehen (echte Fensterfotos der Demo, Scrollen und Klicken per Ereignis): untere Statistik-Bereiche, Listenansichten, Popover und Rechtsklick-Menüs, Einstellungen, Klassisch dunkel, Regalsuche, Positionsregler und die gleitende Auswahlkapsel in Bewegung.

- **Klangbild**: Die Anteilsbalken wurden am größten Eintrag gemessen – das war fast immer „Weitere (24)“ mit über 60 %, alle echten Styles schrumpften auf wenige Pixel. Jetzt Maßstab ist der größte benannte Eintrag; „Weitere“ ist auf volle Länge begrenzt.
- **Top-Künstler**: Das Cover war „das Exemplar mit der kleinsten ID“ – nach einem neuen Abgleich oder in der Demo bei jedem Start ein anderes Album. Jetzt das älteste Release des Künstlers, dann nach Titel.
- **Popover und Rechtsklick-Menüs in Modern**: klares Glas, auf bunten Covern kaum lesbar. Jetzt zur Fensterfarbe getönt wie die Glasfenster über der Seite und die Sync-Kapsel (`appPopoverSurface`).
- **Style-Plaketten** (Zufallsfund, Detailansicht): eigene graue Füllung statt des gemeinsamen Plaketten-Bausteins; jetzt `appChipSurface` (Glas bzw. Papier mit Rand).
- **Positionsregler**: Eine feste Anzeige „Position x von y“ unter dem Titel wurde kurz ergänzt und auf Wunsch wieder entfernt – die Zahl erscheint bewusst nur beim Ziehen über dem Knopf.
- **Einstellungen › Darstellung**: Die Beschreibung von Klassisch nannte „Angaben unter jedem Cover“ als Besonderheit – das hat Modern jetzt auch. Jetzt „Matte Papierflächen statt Glas“. Die kleine Modern-Vorschau zeigt wie die Klassisch-Vorschau eine Beschriftungszeile.
- **Tour-Bilder** neu aufgenommen: „Regal“ zeigte noch die entfernte Titelzeile mit Plattenrücken und die alte Tabelle, die Collection das alte enge Raster ohne Beschriftung. Ausschnitt des Fachbilds auf das Cover-Raster, Collection und Wantlist 30 px höher, damit die Coverkanten nicht angeschnitten sind. Das Skript fotografiert nur noch das Fenster der gestarteten Demo (`Scripts/winid.swift <PID>`), nie eine gleichzeitig offene eigene Sammlung.
- Ohne Befund: Listen in beiden Designs, Klassisch dunkel, Regalsuche mit Trefferliste, Einstellungen, Zufallsfund, Labels, Zeitreise; die Auswahlkapsel gleitet sichtbar und der Text blendet weich um. Bewusst gelassen: Tabellenkarten reichen bei wenigen Zeilen bis zum Fensterende (Verhalten der System-Tabelle); das gewählte Blau in Modern dunkel ist etwas kontrastärmer, aber lesbar.
- Debug-Build und 196 Tests erfolgreich, keine Compilerwarnungen; jeder aktive Katalogtext übersetzt.

# Modern im Aufbau wie Klassisch: Abstände, Beschriftung, Auswahl, Animationen · 07.10.2026

Modern und Klassisch unterscheiden sich jetzt nur noch in Flächen und Farben (Glas statt Papier, Akzent statt Petrol/Gold), nicht mehr in Aufbau, Abständen oder Bewegung. Alle Weichen auf das Design (`AppStyle.isAtelier`) durchgesehen; reine Flächen- und Farbweichen bleiben.

- **Cover-Raster** (Collection, Wantlist, Fach): Abstand in Modern 18 pt wie in Klassisch (vorher 8 bzw. 16 in der Wantlist), Abstand Cover–Text 9 pt (`CoverGrid.spacing`, `CoverGrid.captionSpacing`). Unter jedem Cover in beiden Designs dieselbe Beschriftung: Interpret, Titel (oder der gefundene Track), Jahr · Label (`RecordCaption`, vorher `AtelierRecordCaption` nur in Klassisch; Modern zeigte in der Collection gar keinen Text, in der Wantlist nur zwei Zeilen). Plaketten 8 pt vom Coverrand wie bei der Hülle.
- **Umschalter** (`GlassSegmentedPicker`: Rubriken, Regal-Reiter, Raster/Liste, Einstellungen, Statistik-Optionen): In Modern gleitet jetzt wie in Klassisch eine Auswahlkapsel animiert zur neuen Wahl – als Glaslinse, nicht grau oder blau gefüllt. Trennstriche zwischen Regal-Reitern verschwinden in beiden Designs neben der Kapsel, statt an sie zu stoßen.
- **Auswahl**: Das aktive Regalfach trägt in Modern einen feinen Akzentrand (Gegenstück zum Goldrand), wie die gewählte Design-Karte.
- **Suchplaketten**: In Modern Primärtext für die aktuelle Rubrik und Akzent für den Link, wie Tinte/Petrol in Klassisch; vorher grau und auf bunten Covern schlecht lesbar.
- **Statistik**: Modern ohne Glaskarten, wie Klassisch flach auf der Seite mit feinen Trennlinien und bündig mit dem Seitenrand; Farbverlauf der Sammlungskarte und verschwommenes Cover hinter dem Zufallsfund entfallen (`SectionSurface`, `StatisticsBackdropKey` entfernt). Alle Kacheln einheitlich hell; beim Überfahren wie in Klassisch Rand in der Auswahlfarbe und wachsender Schatten statt einer Farbtönung. Die Spaltenzahl rechnete noch mit dem Innenabstand der Karten (auch in Klassisch, das keine hat); jetzt mit der tatsächlichen Breite.
- Geprüft mit echten Fensterfotos der Demo (Modern hell/dunkel, Klassisch hell): Collection, Suche, Wantlist, Regal, Statistik. Debug-Build und 196 Tests erfolgreich, keine Compilerwarnungen.

# Collection, Wantlist und Regal geprüft: Schatten, Überblendungen, Suchplaketten · 07.10.2026

- **Schatten am Rasterrand**: `coverGridMotion` schnitt das Raster an seinen eigenen Grenzen ab. In Klassisch endete der Schatten der Hüllen in der linken (und rechten) Spalte deshalb in einer harten senkrechten Kante – in Collection, Wantlist und im Fachraster. Der Clip liegt jetzt um `CoverGrid.shadowRoom` (16 pt) außerhalb; das Fachraster bekommt denselben Platz innerhalb seiner ScrollView, die Cover bleiben bündig mit dem Regal.
- **Raster ↔ Liste im Fach**: Beide Ansichten standen beim Überblenden kurz untereinander und teilten sich die Höhe (das Fach stauchte sich). Jetzt ein gemeinsamer Platz (ZStack) wie in Collection und Wantlist. Ebenso beim animierten Wechsel zwischen leerem/gesperrtem und belegtem Fach.
- **Fachwechsel in der Liste** blendet wieder sanft über (wie vor dem Umbau mit `FadeInOnChange`); das Raster behält seine Überblendung, Sortieren und Datenänderungen bleiben sofort.
- **Suchplaketten**: Die Plakette der aktuellen Rubrik („Collection“ in der Collection, „Wantlist“ in der Wantlist) war ein Knopf ohne Wirkung. Sie ist jetzt eine ruhige Angabe in Tinte; nur die Plakette der anderen Rubrik ist ein Link (Petrol) und wechselt dorthin.
- **Track-Treffer in der Collection (Klassisch)**: Wie in der Wantlist steht unter dem Cover „♪ A2 · Titel“, wenn die Suche eine Platte über einen Track gefunden hat.
- `scrollTargetLayout` sitzt direkt am Raster statt hinter den Bewegungs-Modifiern.
- In der Demo angesehen (Klassisch hell, Hülle): Collection-Suche und Fachraster. Debug-Build und 196 Tests erfolgreich, keine Compilerwarnungen. Die Überblendungen selbst lassen sich per Schnappschuss nicht zeigen; sie wurden am Aufbau der Ansichten geprüft.

# Klassisch: aktives Regalfach wieder mit Goldrand · 07.10.2026

- Das aktive Regalfach hatte heute eine feine Petrolkante bekommen, entgegen der Regel „Auswahl überall mit Goldrand“. Wie gewünscht wieder Goldrand (1,5 pt) mit dem bisherigen Schatten (`RaisedPlate`); README angepasst.
- Zweite Durchsicht: unbenutzte Option `AppMenu.fillsWidth` (Überbleibsel eines verworfenen Ansatzes) entfernt, doppelte Leerzeilen nach dem Ausbau des Trefferzählers bereinigt.
- In der Demo angesehen (Klassisch hell mit Passepartout, dunkel mit Hülle): goldenes aktives Fach, Positionsplaketten auf den Covern, Raster/Liste-Umschalter rechts über dem Inhalt. Debug-Build und 196 Tests erfolgreich, keine Compilerwarnungen.

# Prüfung der Änderungen vom 07.10.2026: Fachinhalt, Suchplaketten, Fehlermeldungen · 07.10.2026

- **Fachinhalt als Raster/Liste** (`ShelfContentsView`, vorher `ShelfCopyTable`): standardmäßig Cover-Raster in Fachreihenfolge mit Positionsplakette, umschaltbar auf die Tabelle (neu mit Spalte Label); Scrollstellen je Fach und Ansicht für die Sitzung (`ShelfContentsSession`). „Exemplar bearbeiten …“ ist jetzt ein kleiner Regler für die Position im aktuellen Fach, „Nicht im Regal“ und „Platz im Regal zeigen“ (darüber auch in ein anderes Fach) stehen im Rechtsklick-Menü. Die Spalte mit Lupe und Papierkorb in der Tabelle entfällt.
- **Suchplaketten** an den Rastertreffern von Collection und Wantlist sind anklickbar und wechseln zur Rubrik; der Trefferzähler im Suchfeld entfällt (`LibrarySearch.wantlistMatches`/`collectionMatches` entfernt).
- **Korrigiert bei der Prüfung:**
  - Klassisch: Das gewählte Cover im Fachraster trug einen Petrol- statt des Goldrands; jetzt `AppStyle.selectedBorder` wie überall sonst.
  - Fünf neue Texte (Ansichts-Umschalter, Tooltip und Bedienhilfe der Fachkacheln, Plaketten-Tooltip, Reglerwert) hatten keine englische Übersetzung oder fehlten im Katalog; ergänzt. Der Tooltip „Doppelklick: …“ hieß im Code inzwischen „Klick: …“; alter Eintrag und das unbenutzte „Platz im Regal“ als veraltet markiert.
  - Tooltip „Nicht in der Collection“ verwies auf das Popover, das kein Entfernen mehr bietet; jetzt „per Rechtsklick aus dem Fach entfernen“.
  - Positionsregler: zählt dieselben Exemplare wie Raster und Tabelle (ohne gelöschte und ohne solche, deren Fach sich gerade geändert hat) und speichert nicht mehr in ein Exemplar, das ein Sync währenddessen gelöscht hat.
  - „Nicht im Regal“ aus dem Menü lässt die Auswahl der Platte los, die das Fach verlassen hat (vorher blieb sie unsichtbar ausgewählt).
  - Tabelle: Eine gemerkte Scrollstelle, deren Platte das Fach verlassen hat, führte zu endlosen Wiederherstellungsversuchen bei jedem Layout; jetzt beginnt die Tabelle dann oben.
  - Unbenutzte Parameter `shelves` und `rangeLabels` entfernt.
- Debug-Build und 196 Tests erfolgreich, keine Compilerwarnungen.

# Dokumentation, Fehlermeldungen und Diagnose geprüft · 07.10.2026

- **README** an den vorhandenen Stand 1.0.3 (102026) angepasst: Fachinhalt standardmäßig als Cover-Raster, unabhängig umschaltbare Liste, Position je Exemplar, Scrollstellen je Fach/Ansicht und anklickbare Collection-/Wantlist-Plaketten in Raster-Suchergebnissen. Der Trefferzähler im Suchfeld ist entfernt. Die heute bereits vorhandenen UI-Änderungen werden hier nachgetragen.
- **Fehlermeldungen**: Die Fehlerseite beim Start zeigt eine verständliche Erklärung und verweist für technische Details auf das Protokoll. Sie verspricht nicht mehr, dass beschädigte oder fehlende Daten sicher noch vorhanden seien. Die Schlüsselbundmeldung enthält keinen Statuscode mehr; der Fehler selbst behält ihn für das Protokoll. Deutsche und englische Texte angepasst.
- **Abbrechen**: `CancellationError`, `URLError.cancelled` und der Abbruch eines Dateidialogs erhalten dieselbe Abbruchmeldung. `reportedMessage` protokolliert sie nicht als Fehler; `ReadError.wrapping` erhält den Abbruch. Neuer Regressionstest prüft diese Fälle und den Schlüsselbundcode.
- **Protokoll/Crashlog**: Vorhandenes App-Protokoll und macOS-Berichte gelesen. Am 7. Oktober bislang zwei abgewiesene Zweitinstanzen, kein Absturzblock. Drei macOS-Berichte vom 4. Oktober betreffen denselben Test `sharedSearchIndexFollowsChanges` in Version 1.0 (092026); sie belegen keinen Absturz der aktuellen Version. Am 6. Oktober hauptsächlich fehlgeschlagene Debug-Schnappschüsse ohne Fenster. Vorhandene Protokolle wurden nicht verändert.
- **Grenzen korrekt dokumentiert**: Das eigene Crashprotokoll ist bestmöglich, nicht garantiert. macOS-Berichte liegen separat und werden nicht mit dem App-Protokoll exportiert. Rotation ab 2 MB, Export beider Logdateien, Leeren und persönliche Angaben erläutert. Der Code-Kommentar benennt die eingeschränkte Sicherheit der Stack-Aufzeichnung im Signal-Handler; sein Verhalten wurde nicht geändert.
- **STATISTIK**: Lokales Vorladen beim Start und fehlender Netzabruf beim Rubrikwechsel präzisiert; Wertabrufe bleiben explizit bzw. an einen erfolgreichen Collection-Sync gebunden. Fehlerhinweise und erhaltene Daten erläutert.
- **Prüfung**: Debug-Build mit 196 Tests (0 Fehler) und Release-Build erfolgreich. Ergebnisse und Grenzen stehen am Anfang von VALIDIERUNG.md. Frühere Prüfstände bleiben als Historie erhalten und gelten jeweils nur für den dort genannten Stand.

# Modern: Cover so nah unter der Toolbar wie in Klassisch · 06.10.2026

- Im Raster von Collection und Wantlist beginnt die erste Cover-Reihe jetzt in beiden Designs 18 pt unter der Toolbar (gemessen: 36 px auf Retina, Modern und Klassisch gleich). Modern hatte zusätzlich den Seitenrand (24 pt) darüber, insgesamt rund 32 pt. Weil Modern enger rastert (8 statt 18 pt), gleicht `CoverGrid.topSpace` den Unterschied aus; Klassisch bleibt unverändert. Die Listenansicht behält ihren Rand.

# Prüfung: Robustheit, Klassisch durchgehend, Doku nachgetragen · 06.10.2026

- **Robustheit geprüft**: Discogs-Client und Abgleich (Taktung, Retry-After, Seitenprüfung, Kontowechsel, ein Speichervorgang), Tracklisten, Positionen und Regale, Sicherung und Wiederherstellen samt Aufbewahrung, Zurücksetzen, automatischer Export, Ordner-Lesezeichen, Schlüsselbund, Cover-Cache, Protokoll und Absturz-Handler, dazu die neuen Bausteine von Toolbar-Suche, Aktionsfächer und Tour. Keine Datenverlust- oder Absturzgefahr gefunden; Force-Unwraps sind alle abgesichert.
- **Behoben – Tabellenkopf beim Designwechsel**: Der Kopf der Tabellen ist eine AppKit-Ansicht und zeichnete nach einem Wechsel zwischen Modern und Klassisch erst beim nächsten Scrollen oder Ändern der Fenstergröße neu (Petrol-Band bzw. Milchglas blieben stehen). Jetzt sofort (`QuietIconColumnHeaders`).
- **Klassisch durchgehend** (alle Seiten, Einstellungs-Tabs, Tour und Panels per Schnappschuss in Hell und Dunkel durchgesehen):
  - Auswahl überall gleich: Goldrand auf dem tieferen Creme der Palette (`AtelierPalette.soft`). Die Design-Karte in den Einstellungen hatte als einzige einen Petrol-Rand, gewählte Regal-Karten einen grünlich-grauen Grund (Petrol-Tönung auf Creme).
  - Signalfarben gedeckt statt System-Grün/-Orange/-Rot: Moos, Ocker, Ziegel (`AtelierPalette.success/warning/error`, in Hell und Dunkel). Betrifft u. a. die Wertveränderung in der Statistik, den Aktiv-Punkt der Regale, „Vermisst“, „Nicht in der Collection“, Fehlertexte und Häkchen in „Sortierung prüfen“. Modern unverändert.
  - Creme im Tabellenkopf kommt aus der Palette statt als eigener Farbwert.
- **Nachgetragen** (Commits ohne Eintrag): Klassisch ohne Glas (Treffer-Plaketten, Stepper, Toast, Rundknöpfe, Popover und Hinweisbanner auf Papier, Treffer-Hinweis im Suchfeld als Petrol-Schild, Regalfächer matt, Titelzeile über der Fach-Tabelle entfernt); Tabellenkopf als Petrol-Band mit cremefarbenen Titeln, Regalkorpus hell wie die Regal-Reiter; Cover als Plattenhülle statt Passepartout (alter Rahmen per `atelierCoverFrame=passepartout`); Auswahlkapsel der Regal-Reiter gleitet zum neuen Regal; veraltete Texte im String-Katalog markiert.
- **Doku**: README (Fach-Tabelle ohne Titelzeile, Klassisch-Merkmale, Debug-Argumente `--preview-search`, `--preview-actions`, `--snapshot`, Design per Startargument), STATISTIK.md (kein Aktualisieren-Knopf mehr in der Toolbar, Signalfarben). Fehlermeldungen und Protokoll ohne Befund: keine neuen Meldungen seit der letzten Prüfung, alle deutsch mit Ursache und nächstem Schritt.
- **Offen**: Die Bilder der Tour zeigen immer das Design Modern, auch wenn Klassisch gewählt ist.

# Aktionsknopf nur in Collection/Wantlist, Suche wieder oben, Statistik bündig · 06.10.2026

- **Runder Knopf** (`FloatingControls`) nur noch in Collection und Wantlist; Aktionen dort: Raster/Liste, Synchronisieren, Einstellungen. In Regal und Statistik verschwindet er (die Statistik aktualisiert weiter mit ⌘R oder Herunterziehen, Einstellungen über ⌘,). Platz unten (`floatingClearance`) nur noch auf diesen beiden Seiten.
- **Suche wieder in der Toolbar** (`ToolbarSearchField`, rechts, 300 pt breit) für Collection, Wantlist und Regal, immer sichtbar, ⌘F setzt den Cursor hinein. Ihr rechtes Ende sitzt bündig mit der rechten Kante der Cover bzw. des Regals: Der Toolbar-Rand (8 pt) wird um `AppStyle.toolbarSearchInset` auf den Seitenrand (`pagePadding + 4`) aufgefüllt – im Bildschirmfoto in Klassisch pixelgenau gleich. Die Trefferliste der Regalsuche schwebt rechtsbündig direkt unter dem Feld.
- **Statistik bündig**: Bereichstitel („Deine Sammlung“, „Auf einen Blick“ …) ohne vorangestelltes Symbol, sie beginnen jetzt an derselben Kante wie die Werte und Wörter darunter. Die große Zahl (Sammlungswert bzw. Plattenzahl) gleicht den Vorlauf der Ziffern aus.
- Tests grün.

# Aktionsfächer klappt bei Klick daneben zu · 06.10.2026

- **Klick außerhalb**: Der Fächer am runden Knopf fährt jetzt bei jedem Klick neben Knopf und Aktionen wieder ein – auf der Seite, in Listen und Tabellen und in der Toolbar. Statt einer unsichtbaren Fläche, die AppKit-Listen nicht zuverlässig abfing, beobachtet `OutsideClickWatcher` die Klicks im Fenster; der Klick selbst geht weiter an das, was darunter liegt.

# Oben nur die Rubriken, Aktionen unten rechts, keine ABC-Leiste mehr · 06.10.2026

- **Toolbar**: Nur noch der Rubriken-Umschalter, mittig und auf jeder Seite gleich breit. Leiste mit Raster/Liste, Lupe, Sync und Zahnrad entfällt (`MainToolbar` und Hilfsbausteine entfernt).
- **Runder Knopf unten rechts** (`FloatingControls`): Ein Klick fächert die Aktionen der Seite im Viertelkreis aus (Federanimation, nacheinander), der Knopf dreht dabei seine Punkte. Aktionen je Seite: Suche (Collection, Wantlist, Regal), Raster/Liste (Collection, Wantlist), Synchronisieren bzw. Aktualisieren (nicht im Regal; in der Demo wie bisher gesperrt außer in der Statistik), Einstellungen. Esc, Klick daneben oder eine gewählte Aktion schließen den Fächer, ein Seitenwechsel ebenso. Modern: Glas-Kreise; Klassisch: petrolfarbener Knopf, cremefarbene Aktionen mit feinem Rand. Sync und Einstellungen gibt es damit in beiden Designs an derselben Stelle.
- **Raster/Liste als ein Umschalter**: Statt zweier Symbole ein Knopf, der das Ziel zeigt („Als Liste anzeigen“ bzw. „Als Raster anzeigen“).
- **Suche unten rechts**: öffnet als Feld links neben dem Knopf (Klick auf die Lupe im Fächer oder ⌘F), bleibt offen, solange gesucht wird; Treffer-Hinweis der anderen Seite dezent im Feld (`AppSearchField` hat dafür ein `accessory`). Die Trefferliste der Regalsuche schwebt direkt über dem Feld.
- **Platz unten auf jeder Seite** (`AppStyle.floatingClearance`), damit nichts dauerhaft unter dem Knopf liegt.
- **ABC-Leiste entfernt**: Die Buchstaben-Navigation am rechten Rand von Collection und Wantlist ist samt Sprungmarken weg; das Raster nutzt die frei gewordene Breite. Die alphabetische Reihenfolge („#“ zuerst, dann A–Z) bleibt unverändert.
- Einstellungen → Darstellung: Hinweis „über den runden Knopf unten rechts“ statt „in der Kopfleiste“. Neue Texte englisch übersetzt.
- Debug: `--preview-actions` startet mit aufgefächerten Aktionen.
- Tests: 193, 0 Fehler.

# Durchsicht: Regal-Trefferliste unter der Leiste, Kleinigkeiten · 06.10.2026

- **Regalsuche**: Die schwebende Trefferliste steht jetzt mittig unter der Toolbar-Leiste, also unter dem Suchfeld, statt oben rechts.
- **Statistik in Klassisch**: Abstand des ersten Bereichs ohne Gegenrechnung, Diagrammpalette einmal gelesen.
- **Debug**: `--snapshot` wartet bis zu 30 s auf das Fenster und protokolliert Erfolg oder Fehler; `--preview-search` gilt auch für die Regalsuche.
- Doku zur Suche präzisiert (zuklappen per Esc, Lupe oder Fokuswechsel bei leerem Feld).
- Gefunden, nicht behoben: In Klassisch mit vorbelegter Suche (nur per Debug-Argument) entsteht beim Start kein Fenster – schon vor diesen Änderungen so, siehe VALIDIERUNG.md.

# Statistik im Design „Klassisch“ · 06.10.2026

- **Auf dem Papier statt in Karten**: In Klassisch liegen die Bereiche der Statistik wie die Cover in Collection und Wantlist direkt auf dem cremefarbenen Grund, getrennt durch feine Linien und bündig mit dem Seitenrand; der erste Titel steht so weit unter der Toolbar wie die Cover auf den anderen Seiten. Modern bleibt unverändert (Glas-Karten).
- **Kacheln als Hüllen**: Kennzahlen, „Auf einen Blick“ und Labels sind cremefarbene Kacheln mit feinem Rand und weichem Schatten wie die Cover-Hüllen; beim Überfahren wird der Rand golden. Top-Künstler und Zufallsfund zeigen ihre Cover in derselben Hülle (`atelierRecordSleeve`).
- **Farben des Designs**: Die bunten Symbole (blau, türkis, lila, rosa, orange) sind in Klassisch einheitlich Petrol auf hellem Grund. Das Klangbild nutzt eine eigene Palette (`AtelierPalette.chart`: Petrol, Gold, Salbei, Terrakotta, Schieferblau, Pflaume, Oliv). Der Farbverlauf in „Deine Sammlung“ und das weichgezeichnete Cover hinter dem Zufallsfund entfallen.
- **Schrift**: Zahlen und Bereichstitel in Klassisch in normaler statt runder Schrift (`AppStyle.figureDesign`), wie die Angaben unter den Covern.
- **Text-Links** („Alle 40 Labels“, „Rangliste ab Platz 6“, Links auf der Regalseite und im Sync-Hinweis) sind in Klassisch Petrol statt Systemblau (`appLinkButton()`).
- Debug: `--snapshot=name.png` zeichnet das Fenster nach ein paar Sekunden selbst in eine PNG-Datei im temporären Ordner des Containers und beendet die App – funktioniert auch bei gesperrtem Bildschirm (Glas wird dabei nicht gezeichnet).

# Toolbar aus einem Guss, ausklappbare Suche, Designs „Modern“ und „Klassisch“ · 06.10.2026

- **Eine zentrierte Leiste**: App-Symbol und Name oben links sind weg. Rubriken, Raster/Liste, Suche und (in Klassisch) Synchronisieren und Zahnrad stehen gemeinsam in einer Leiste mitten in der Toolbar – in Modern eine Glas-Kapsel, in Klassisch ein etwas dunkleres Band auf dem Petrol, getrennt durch feine Striche. Die Leiste ist so breit wie auf der vollsten Seite und beginnt immer an derselben Stelle: Der Rubriken-Umschalter wandert beim Seitenwechsel nicht unter dem Mauszeiger weg. Das Einstellungsfenster nutzt dieselbe Leiste.
- **Suche als Lupe**: Statt eines immer offenen Felds steht in der Leiste eine Lupe. Klick oder ⌘F klappt das Feld animiert auf und setzt den Cursor hinein; Esc leert es, ein zweites Esc klappt es zu, ebenso ein Klick auf die Lupe oder ein Fokuswechsel, solange das Feld leer ist. Solange eine Suche aktiv ist, bleibt das Feld offen (ein Klick auf die Lupe holt dann nur den Cursor zurück), damit kein Filter unsichtbar wirkt. Das Feld hat keine eigene Fläche mehr, es sieht aus wie der Rest der Leiste.
- **Treffer-Hinweis dezent**: „3 in der Wantlist“ bzw. „… in der Collection“ steht jetzt klein und grau im Feld statt farbig daneben; ein Klick wechselt weiter dorthin.
- **Designs umbenannt**: „Liquid Glass“ heißt jetzt **Modern**, „Atelier“ heißt **Klassisch**; die Gruppenüberschriften in den Einstellungen entfallen. Die gespeicherten Werte bleiben („none“, „atelier“), eine vorhandene Wahl gilt also weiter. Protokoll: „Design Klassisch“ in der Startzeile, „Design: Klassisch statt Modern“ beim Wechsel.
- Debug: `--preview-search=…` startet mit einer Suche (für Screenshots).
- Tests: `everyDesignBelongsToExactlyOneCategory` wird zu `designsKeepTheirStoredValuesUnderTheNewNames`. 193 Tests, 0 Fehler.

# Suche in der Toolbar, Designs in zwei Gruppen, keine Plattenrücken mehr · 06.10.2026

- **Suchfeld fest in der Toolbar**: Statt einer Suchleiste, die ⌘F unter den Rubriken einblendete, steht das Suchfeld jetzt immer rechts in der Toolbar (Collection, Wantlist, Regal; nicht in der Statistik). Die Cover beginnen dadurch direkt unter der Toolbar, nichts rückt beim Suchen nach unten. ⌘F setzt den Cursor ins Feld, Esc leert es, ein zweites Esc verlässt es. Collection und Wantlist teilen sich die Suche wie bisher; der Knopf „3 in der Wantlist“ bzw. „… in der Collection“ steht links neben dem Feld. Auf der Regalseite schweben die Treffer wie bisher als Liste über dem Regal, jetzt oben rechts unter dem Feld. Solange das Feld den Cursor hat, gehört ⌘Z dort weiter dem Text und nicht „Aus Fach entfernt“.
- **Designs in zwei Gruppen**: Einstellungen → Darstellung → Design zeigt **Modern** mit **Liquid Glass** (die bisherige Gestaltung, vorher „Aktuelle Gestaltung“) und **Klassisch** mit **Atelier**, beide mit kleiner Vorschau. Akzent- und Ambient-Farbe sind in Atelier ausgegraut („Gilt nur für Liquid Glass.“), bleiben aber gespeichert. Der gespeicherte Wert von Liquid Glass bleibt „none“, eine vorhandene Wahl gilt also weiter.
- **Atelier ohne Seitentitel**: Der Titel über jeder Seite samt Lupe ist weg; die Cover beginnen direkt unter der petrolfarbenen Toolbar, mit demselben Abstand wie zum Fensterrand. „Synchronisieren“ bzw. „Aktualisieren“ und das Einstellungs-Zahnrad stehen als Symbole rechts in der Toolbar.
- **Keine Plattenrücken mehr**: Der Streifen mit den Rücken unter dem Fachtitel (samt Cover beim Überfahren, Positionszeile und Genre-Legende) ist aus der App entfernt, ebenso die Genre-Farben (`StylePalette`), die nur dafür da waren. Unter dem Fachtitel folgt direkt die Fach-Tabelle; wo eine Platte steht, sagen Tabelle, Suchtreffer und Einsortier-Karte. Die Fach-Statistik liest dadurch keine Release-Daten mehr, nur noch die Exemplare.
- **Aufgeräumt**: Der Mechanismus zum Einblenden der Suchleisten (`SearchReveal`, `SearchBarSlot`, `OverviewSearchControl`, `ShelfSearchField`) ist entfernt; die Rücken-Bausteine (`SpineRack`, `ShelfPositionStrip`, `ShelfStyleLegend`) ebenso. Verwaiste Texte aus dem Übersetzungskatalog entfernt, neue Texte übersetzt.
- **Tour-Bilder** zeigen noch die alte Suche und die Rückenleiste: `Scripts/tour-screenshots.sh` neu laufen lassen (braucht einen entsperrten Bildschirm).
- Tests: `styleSharesCountFamilies` entfällt mit den Genre-Farben, neu ist `everyDesignBelongsToExactlyOneCategory`. 193 Tests, 0 Fehler.

# Signature Design „Atelier“ · 06.10.2026

Unter **Einstellungen → Darstellung → Designs** lässt sich neben der bisherigen Gestaltung das Design **„Atelier“** wählen – Petrol, Creme und Gold aus dem App-Symbol.

- **Aussehen**: cremefarbener Seitengrund, matte Karten, Knöpfe, Suchleisten und Menüs mit feinem Rand statt Liquid Glass; Toolbar petrolfarben mit App-Symbol, Rubriken und Zahnrad für die Einstellungen (auch im Einstellungsfenster). Über jeder Seite ein Titel, rechts die Lupe (wie ⌘F) und „Synchronisieren“ (Collection, Wantlist; in der Demo gesperrt) bzw. „Aktualisieren“ (Statistik). Cover stehen in einer matten Hülle mit mehr Abstand, darunter Interpret, Titel sowie Jahr und Label; bei Suchtreffern in der Wantlist der gefundene Track. Das Regal ist ein petrolfarbener Korpus mit cremefarbenen Mulden, das gewählte Fach hat einen goldenen Rand. Hell und Dunkel folgen dem gewählten Modus.
- **Bisherige Einstellungen bleiben**: Modus, Akzent- und Ambient-Farbe werden nicht verändert und gelten wieder, sobald „Aktuelle Gestaltung“ gewählt ist. Gespeichert als `signatureDesign`; ein unbekannter Wert (etwa aus einer späteren Version) fällt auf die aktuelle Gestaltung zurück, ohne ihn zu überschreiben. „Einstellungen zurücksetzen“ stellt auf die aktuelle Gestaltung zurück.
- **Technik**: Die gemeinsamen Bausteine in `AppAppearance.swift` fragen `AppStyle.isAtelier` ab; die Seiten selbst bleiben dieselben Instanzen, ein Wechsel baut nichts neu auf. `AppPreferences` lässt sich für Tests mit eigenen `UserDefaults` anlegen.
- **Bei der Prüfung korrigiert**: Die nur für Atelier gedachten Toolbar-Einträge (Symbol, Zahnrad) standen auch in der bisherigen Gestaltung als leere Einträge in der Toolbar; jetzt gibt es sie nur in Atelier. In der Wantlist zeigte Atelier für fehlende Release-Daten „Unbekannt“ und „—“ statt wie bisher „Unbekannter Interpret“ und „Release #…“.
- **Protokoll**: Die Startzeile trägt „Design Atelier“, wenn es gewählt ist; ein Wechsel steht als „Design: Atelier statt aktuelle Gestaltung“ im Protokoll – hilfreich, wenn ein Fehlerbericht nur in einem Design auftritt.
- Englische Übersetzungen für alle neuen Texte. Drei neue Tests (Standard und unbekannte Werte, Speichern und Neuladen, bisherige Einstellungen bleiben unverändert). 193 Tests, 0 Fehler.

# Keine Einfüge-Linie mehr in der Rückenleiste · 06.10.2026

- Beim Einsortieren stand in der Rückenleiste eine pulsierende blaue Linie an der Zielposition. Sie ist entfernt, samt Puls-Zeitgeber; `SpineRack` kennt keine `insertionPosition` mehr. Die Position nennt weiterhin die Zeile unter der Leiste („Neue Platte an Position 3 · …“) und die Einsortier-Karte.
- Falls die Tour-Bilder der Seite „Einsortieren“ die Linie noch zeigen: `Scripts/tour-screenshots.sh` neu laufen lassen.

# Tour beim ersten Start · 06.10.2026

Beim ersten Start öffnet sich über dem Hauptfenster eine kurze Tour mit sechs Seiten: Willkommen, Discogs, Regal, Einsortieren, Statistik sowie Export und Sicherung. Jede Seite zeigt zwei versetzte Ausschnitte der echten App aus der Demo, einen Titel und zwei bis drei Sätze.

- **Bedienung**: „Weiter“ (auch ↩ und →), „Zurück“ (←), Punkte zum Springen, „Überspringen“; auf der letzten Seite „Los geht’s“. Wie die anderen Glasfenster über der Seite schließt sie auch ein Klick daneben oder Esc. Auf der Discogs-Seite führt „Token eintragen …“ direkt ins Token-Feld der Einstellungen (nicht in der Demo). Die Seiten schieben sich in Blätterrichtung herein; mit „Bewegung reduzieren“ blenden sie nur über. Glasfenster 620 pt breit.
- **Wann**: einmal, beim ersten Start, egal wie sie geschlossen wird (`tourSeen` in den Einstellungen). Nicht in der Demo und nicht bei den Tests. Jederzeit wieder über **Hilfe → Tour durch Plattenregal …** (öffnet bei Bedarf auch das Hauptfenster). „Einstellungen zurücksetzen“ und „Alles zurücksetzen“ bringen sie beim nächsten Start zurück. Wer die App schon nutzt, sieht sie nach dem Update ebenfalls einmal.
- **Bilder**: echte Bildschirmfotos der Demo in Deutsch und Englisch, hell und dunkel (`Assets.xcassets/Tour`, 12 Ausschnitte × 2 Sprachen, je mit Dunkel-Variante, zusammen 2,8 MB JPEG). Die Tour wählt die Sprache der App, macOS das Erscheinungsbild. Wo ein Ausschnitt mitten in einer Karte oder Liste endet, blendet er rechts bzw. unten weich aus, samt Rahmen und Schatten.
- **Bilder neu machen**: `Scripts/tour-screenshots.sh` baut die Debug-App, startet die Demo neunmal je Sprache und Erscheinungsbild, fotografiert das Fenster (`screencapture`, braucht die Bildschirmaufnahme-Freigabe fürs Terminal), schneidet die Ausschnitte zu und schreibt den Asset-Ordner neu. Die Ausschnitte stehen als Pixelangaben im Skript; `--raw <Ordner>` liefert nur die Fensterfotos zum Ausmessen.
- **Neue Debug-Schalter** dafür: `--preview-add` öffnet auf der Regalseite „Platte hinzufügen“ für das gewählte Fach, `--preview-place=Interpret` die Einsortier-Karte dieser Platte, `--preview-tour` zeigt die Tour auch in der Demo. `--screenshots` blendet jetzt zusätzlich die Demo-Hinweise in den Einstellungen aus und zeigt Token-Feld, automatischen Export und automatische Sicherung wie in der echten App; Abgleich, Export und Sicherung bleiben in der Demo trotzdem gesperrt (die Dienste prüfen weiter `DemoMode.isActive`).
- Englische Übersetzungen für alle neuen Texte. 190 Tests, 0 Fehler.

# Neues App-Symbol · 05.10.2026

Das App-Symbol wurde ersetzt. Es zeigt jetzt eine schwarze Schallplatte mit sandfarbenem Etikett, die aus einer elfenbeinfarbenen Papierhülle ragt, auf einer gedämpft petrolblauen, abgerundeten Kachel – in den ruhigen Petrol- und Sandtönen der App, ohne Schrift. Bisher war es eine flache Schallplatte über einem hellen Balken. Damit gehört es zur gleichen Icon-Familie wie Media und Sync.

- Alle zehn Größen in `Plattenregal/Assets.xcassets/AppIcon.appiconset` (16 bis 1.024 Pixel) wurden ersetzt, außen transparent. `Contents.json` ist unverändert. Das Symbol erscheint im Dock, im Finder und auf der Karte „Über Plattenregal“.
- Vorlage, Prompt und das bisherige Symbol lagen in `outputs/AppIcon-Vinyl-2026-10-05/` (Ordner inzwischen gelöscht, in der Git-Historie bis Commit `2b2152e`).
- **Version 1.0.2, Build 102026** (vorher 1.0, Build 092026); „Über Plattenregal“ und das Protokoll zeigen sie automatisch. Die Beispielangabe im README ist entsprechend angepasst.
- Am Swift-Code und an den Tests hat sich nichts geändert.

# Prüfung der App · 04.10.2026

Abgleich mit Discogs (Seitenprüfung, Wiederholungen, Kontowechsel), Positionen und Einsortieren, Sicherung und Wiederherstellen, Zurücksetzen, Export (CSV-Formelschutz, PDF-Umbruch), Start und Datenbank-Sperre, Demo sowie die heutigen Änderungen an Suche und Einstellungsfenster auf Randfälle durchgesehen. Kein Fehler gefunden; alle Listenzugriffe sind abgesichert. Nur ein veralteter Kommentar beim Wantlist-Export ist berichtigt. 190 Tests, 0 Fehler.

# Suche verlassen · 04.10.2026

- **Einstellungsfenster**: ohne Fensterknöpfe, nur die Bereichsleiste mittig in der Titelzeile; Esc und ⌘W schließen es; solange „Neues Regal“ offen ist, bricht Esc nur dieses Formular ab. 760 × 510 pt, keine Trennlinie mehr unter der Leiste. „Demo starten“ im Fenster ohne Auslassungspunkte (im Menü bleiben sie, dort folgt eine Rückfrage).
- **Suche in Collection und Wantlist verlassen**: Wird die Suche geleert (Esc, ⌘F, Löschknopf), wartet die Liste nicht mehr 0,12 s wie beim Tippen, und die Cover gleiten nicht mehr zurück. Die Treffer blenden in 0,1 s aus, die ganze Liste steht wieder an der Stelle, an der sie vor der Suche war, und blendet in 0,22 s ein – getaktet wie der Rubrikwechsel. Wird die Suche auf der anderen Seite geleert (beide teilen sie), steht auch diese Seite beim nächsten Öffnen wieder an der alten Stelle. Beim Tippen gleiten die Treffer weiter an ihren Platz.

# Rubrikwechsel mit Richtung · 04.10.2026

- **Wechsel zwischen den Rubriken**: Statt der Überblendung (0,2 s) blendet die Seite jetzt durch: Die alte verschwindet in 0,1 s an Ort und Stelle, danach blendet die neue ein und schiebt sich dabei ein Stück (18 pt) in Richtung des Umschalters herein – nach rechts von rechts, nach links von links. Die beiden Seiten liegen nie gleichzeitig sichtbar übereinander (beim Überblenden mit Schub lagen sonst die Cover der einen Seite in den Lücken der anderen); dazwischen sieht man kurz nur Fensterhintergrund und Ambient-Schein. Der Schub ist eine kritisch gedämpfte Feder (~0,3 s) wie überall in der App, rein Core Animation, ohne Neuzeichnen der Seiten. Mit „Bewegung reduzieren“ bleibt nur das Ein- und Ausblenden.
- **Ausprobiert und verworfen**: weiche Ränder am Cover-Raster – Cover unter Kopfleiste und Toolbar laufen lassen (der Systemrand verwischte dort nicht, die Suchleiste über den Covern war kaum lesbar) und kurze Verläufe oben und unten (wirkten wie ein heller Streifen bzw. eine unscharfe Kante). Die Cover enden weiter an einer klaren Kante.

# Abschlussprüfung des Tages · 04.10.2026

Alle Änderungen von heute noch einmal auf Richtigkeit und Nebenwirkungen durchgesehen (Sprache, Tastenkürzel, Speicherwege, Änderungserkennung des Abgleichs, Statistik, Beschriftungen, Suchdaten, Cover). Die App baut ohne Warnungen, die Demo startet und beendet sich sauber.

- **Regal-Einstellungen**: Die Fach-Beschriftungen dort merkten nur, wenn sich die Zahl der Platten in einem Fach änderte. Tauschte man zwei Platten zwischen zwei Fächern, blieb die alte Beschriftung stehen, bis sich sonst etwas änderte. Jetzt folgen sie jeder Platzänderung – wie Collection und Zufallsfund; dank des Zwischenspeichers werden nur die betroffenen Fächer neu gelesen.
- **Ohne Befund**: Ein Abgleich ohne Änderungen lässt die Seiten in Ruhe, die Zeit in den Discogs-Kacheln („synchronisiert vor 1 Minute“) folgt trotzdem. Keine Zahl der Statistik hängt an Fach oder Position; der Zufallsfund und die von dort geöffnete Detailansicht zeigen den aktuellen Platz. Beschriftungen hängen nur am Interpreten, der Zwischenspeicher bleibt also auch beim Umstellen der Reihenfolge bei gleichem Interpreten richtig. Alle 831 Texte sind übersetzt, keiner ist verwaist.
- **README**: Einstellungsreiter „Tastenkürzel“ und die Sprachwahl unter „Allgemein“ ergänzt, die Kürzel kurz in „Was die App kann“.
- Neuer Test: `collectionDetailsCountAsChanges` (Ordnerwechsel und Entfernen aus der Collection gelten als Änderung, ein Wiederholen nicht). 190 Tests, 0 Fehler.

# Weniger unnötige Rechenarbeit · 04.10.2026

Die App auf Arbeit durchgesehen, die sie umsonst macht – vor allem bei großen Sammlungen spürbar. Am Verhalten und an den Daten ändert sich nichts.

- **Synchronisierung ohne Änderungen** lässt die Seiten in Ruhe: Der Abgleich meldet jetzt, ob sich wirklich etwas geändert hat – auch Wantlist-Notizen und -Daten, Release-Daten aus der Wantlist, geleerte Ordner, entfernte Releases und ein Wechsel des aktuellen Kontos. Nur dann sortieren Collection und Wantlist neu und rechnen Regal-Seite, Fach-Tabelle und Beschriftungen neu. Im Protokoll steht sonst „Keine Änderungen, Seiten bleiben unverändert“.
- **Statistik** lädt nicht mehr nach jedem Speichern komplett neu, sondern nur, wenn Platten dazukommen oder wegfallen, Releases, Sammlungswert oder Konten sich ändern. Einsortieren, Verschieben und „Vermisst“ ändern keine Zahl dort. Der Zufallsfund liest seinen Platz dafür selbst aus der Hauptdatenbank und folgt Platzänderungen sofort.
- **Fach-Beschriftungen** („A – Be“) in Collection, Zufallsfund und Regal-Einstellungen lesen nur noch die Fächer neu, deren Platten sich geändert haben (`ShelfLabelsCache`). Vorher las jede Neuberechnung alle Platten im Regal – über eine Sekunde bei 10 000, spürbar beim Wechsel vom Regal zur Collection nach dem Einsortieren.
- **„Vermisst“ markieren** stößt keine automatische Sicherung und keine neuen Beschriftungen mehr an; beides hängt nicht davon ab (Markierungen stehen nicht in der Sicherung).
- **Suche**: Collection und Wantlist teilen sich die Suchtexte (`LibrarySearchIndexes`), statt sie je einmal für sich aufzubauen. Gebaut werden sie erst bei der nächsten Suche nach einer Änderung – während die Tracklisten nachladen (alle paar Sekunden eine Meldung) also nicht mehr jedes Mal für die ganze Sammlung. Sie enthalten alle Platten und Einträge, unabhängig von Konto und Collection-Status; die Seiten schlagen nur nach, was sie zeigen.
- **Neuaufbau nach einer Synchronisierung**: Collection und Wantlist bauten nach einem Abgleich zwei- bis dreimal hintereinander neu auf (Meldung des Abgleichs und geänderte Abfragen kamen kurz nacheinander). Jetzt einmal.
- **Regal-Seite** zählt die verkauften Platten im Regal nur noch bei Datenänderungen statt bei jedem Klick auf einen Rücken.
- **Alphabet-Register**: Der Buchstabe eines Interpreten (eine Unicode-Umwandlung) wird einmal pro Name gemerkt; das Register der Wantlist entsteht nur noch bei alphabetischer Reihenfolge.
- **Cover**: Lesen und Aufbereiten laufen parallel statt nacheinander, der Zwischenspeicher wird nicht mehr bei jedem Abruf neu aufgebaut, und das Änderungsdatum einer Cover-Datei (für das Aufräumen alter Cover) wird höchstens einmal am Tag geschrieben statt bei jedem Lesen.
- **Fehlermeldung beim Lesen**: Konnte die Statistik oder die Liste von „Platte hinzufügen“ die gespeicherten Daten nicht lesen, hieß es „Die Änderung konnte nicht gespeichert werden“ – obwohl nichts gespeichert wurde. Jetzt: „Die gespeicherten Daten konnten gerade nicht gelesen werden …“ (`ReadError`).
- **Protokoll nach einem Absturz**: Wurde das Protokoll beim nächsten Start gerade zu `Plattenregal.old.log`, verweist der Hinweis jetzt dorthin statt auf „direkt vor diesem Start“.
- Neue Tests: `unchangedSyncReportsNoChanges`, `wantlistDetailsCountAsChanges`, `anotherAccountCountsAsChange`, `onlyRelevantSavesReloadStatistics`, `sharedSearchIndexFollowsChanges`, `cachedShelfLabelsMatchFullComputation`; `errorsReachTheUserInPlainGerman` prüft die neue Lesemeldung. 189 Tests, 0 Fehler.

# Aufgeräumt nach der technischen Prüfung · 04.10.2026

- **Tracklist im Popover**: Wird beim Klick auf ein Cover eine fehlende Tracklist nachgeladen, speichert die App sie jetzt direkt. Vorher lief das über den Speicherweg für Regal-Änderungen, der jedes Mal eine automatische Sicherung der Belegung anstieß und die Fach-Beschriftungen neu berechnete, obwohl sich am Regal nichts geändert hatte.
- **„Discogs-Daten aktualisieren“** speichert ebenso direkt: keine automatische Sicherung der Belegung mehr, wenn sich nur Release-Daten ändern. Die Fach-Beschriftungen folgen weiterhin, weil sich Interpret oder Titel ändern können.
- **Ungenutzter Code entfernt**: `DiscogsAPIClient.testToken()` (der Verbindungstest nutzt `quickTest`) und `Release.isFresh` (nur noch in einem Test geprüft; der Test prüft jetzt, dass `fetchedAt` gesetzt wird). Am Datenbankschema ändert sich nichts.

183 Tests, 0 Fehler.

# Technische Prüfung · 04.10.2026

Das ganze Projekt auf mögliche Fehler durchgesehen (Sync, Speichern, Sicherungen, Export, Regal, Statistik, Nebenläufigkeit). Die Daten- und Fehlerwege sind gut abgesichert; behoben wurden zwei Stellen:

- **Wantlist-Sortierung**: Der Vergleich las bei jedem Schritt Interpret und Titel neu und rechnete den Buchstaben fürs Alphabet-Register (eine Unicode-Umwandlung) zweimal aus – bei einer großen Wantlist bis zu Sekunden auf dem Hauptthread nach jeder Synchronisierung, jedem Wechsel der Sortierung und bei jedem Export der Wantlist. Die Schlüssel werden jetzt einmal pro Eintrag gebildet; die Reihenfolge bleibt exakt dieselbe.
- **Compiler-Warnungen**: Das Überblenden zwischen den Rubriken (`PageStack`) griff im Abschluss-Block der Animation ohne Hauptthread-Zusicherung auf die Ansicht zu – drei Swift-6-Warnungen. Der Block läuft jetzt ausdrücklich auf dem Main Actor. Der Build ist warnungsfrei.

183 Tests, 0 Fehler.

# Englisch und Deutsch, zweite Prüfung · 04.10.2026

Alle Texte noch einmal gelesen, dazu die App auf Englisch und Deutsch in der Demo durchgesehen (alle Einstellungsseiten, Regal, Statistik). Korrigiert:

- **macOS-Schreibweise im Englischen**: Menüpunkte, Knöpfe und die Tastenkürzel-Liste in Title Case („Show in Finder“, „End Demo“, „Sync Everything“), Hinweise, die diese Knöpfe zitieren, passend dazu. Auslassungspunkte direkt am Wort („Save As…“ statt „Save As …“), typografische Apostrophe („can’t“), „100%“ ohne Leerzeichen.
- **Zahlen und Einheiten**: Der Anteil der Stile unter dem Regal war fest als „12 %“ geschrieben, jetzt im Format der Sprache („12%“ im Englischen). Speicherplatz zeigt „0 bytes“ statt „Zero kB“.
- **Begriffe**: „Speicherort“ der Sicherungen heißt „Storage location“ und in Sätzen „folder“ – vorher stand „location“ für Ordner und Plattenstandorte im selben Satz. „Neue Platte ziehen“ ist „Draw Another Record“, „Zufallsfund“ „Random pick“, „Klangbild“ „Sound profile“, Regalgrößen „vertical/horizontal“ statt „portrait/landscape“ u. a.
- **Discogs-Kacheln**: „56 Platten · synchronisiert vor 5 Minuten“ statt „Stand vor 5 Minuten“ (englisch „synced 5 minutes ago“ statt „As of 5 minutes ago“).
- **CSV-Trennzeichen** voreingestellt nach Systemeinstellung: Semikolon, wo das Komma Dezimalzeichen ist (deutsches Excel), sonst Komma. Gespeicherte Wahl bleibt.
- **Automatischer Export**: Der Dateiname hängt nicht mehr an der Sprache der Oberfläche – die Datei soll bei jedem Lauf ersetzt werden, nicht nach einem Sprachwechsel neu entstehen.
- **Sprachwahl**: „Neustart nötig“ erscheint nur noch, wenn sich die angezeigte Sprache wirklich ändert (auf einem deutschen Mac ist „System“ → „Deutsch“ keine Änderung).
- **Code**: „Synchronisierung abgeschlossen“ wird über eine Konstante erkannt statt über zwei Vergleiche mit dem übersetzten Text. Deutsch: „Trage deinen Token ein“ wie überall sonst statt einmal „Trag“.
- **Demo**: Die Discogs-Ordner zeigten „0 Platten“, jetzt die echte Zahl. 183 Tests, 0 Fehler.

# Englische Übersetzung geprüft · 04.10.2026

Alle rund 800 Texte im String-Katalog gegengelesen und mit dem Code abgeglichen (jeder Text im Code hat einen Eintrag, kein Eintrag ist verwaist). Korrigiert:

- **Falsche Wörter**: „Platz 3“ in der Umstell-Liste hieß „Rank 3“ statt „Position 3“, „Rekord“ in der Neuzugangs-Statistik „Record“ (in einer Platten-App missverständlich, jetzt „Peak“), „Fach“ einmal „shelf“ statt „compartment“, „Beschriftung“ der Fächer „Labels“ (wie Plattenlabels, jetzt „Labeling“), „Seit mindestens 30 Tagen“ war kein Englisch („Over 30+ days“).
- **Sicherungen**: „Stände“ heißen jetzt „versions“ statt „states“ („Keep recent versions“, „Daily versions“).
- **Feinschliff**: „Last exported …“ statt „Last …“ beim automatischen Export, „Value trend“, „Top decade“, „Space“-Taste ausgeschrieben, „Plattenregal is already running“ u. a.
- **Einzahl/Mehrzahl** (auch im Deutschen): „1 Spalte“/„1 Reihe“ statt „1 Spalten“/„1 Reihen“ beim Regal-Anlegen, „1 Platte wird wieder einsortiert“ im Wiederherstellen-Dialog, „1 weiterer Treffer“, „1 fehlt“ bei den Tracklisten, „Show 1 result“.
- **Protokoll wieder deutsch**: Die Sync-Bereiche („Collection“, „Alles“, „Ordner 123“) wurden im Protokoll übersetzt, obwohl es deutsch bleiben soll.
- **Code**: Das Balkendiagramm verglich seinen Einheitentext mit dem übersetzten Wort „Platten“, um die Mehrzahl zu wählen – die nie genutzte Einheit ist entfernt. 183 Tests, 0 Fehler.

# Tastenkürzel · 04.10.2026

- **Neue Kürzel**: ⌥⌘R synchronisiert alles mit Discogs, ⌘. bricht eine laufende Synchronisierung ab. Auf Collection und Wantlist: ⌥⌘1 / ⌥⌘2 für Raster und Liste, ⌘+ / ⌘− für größere oder kleinere Cover (auch ⌘= für US-Tastaturen), ⌘0 für die Standardgröße.
- **Übersicht** im neuen Einstellungsreiter „Tastenkürzel“: alle Kürzel der App nach Ort sortiert (Überall, Collection und Wantlist, Regal, Statistik, Einstellungen → Regal), auch die schon vorhandenen wie ⌘1–⌘4, ⌘F, ⌘R, ⌘← / ⌘→, ⌘Z und ⇧⌘R. Die neuen Kürzel kommen aus derselben Liste (`AppShortcuts`), Anzeige und Verhalten können also nicht auseinanderlaufen.
- Bei der Sprachwahl und der Akzentfarbe heißt die erste Option jetzt „System“ statt „Wie macOS“.

# Englisch als zweite Sprache · 04.10.2026

Plattenregal gibt es jetzt auf Deutsch und Englisch.

- **Sprachwahl** unter Einstellungen → Allgemein → „Sprache“: „System“, „Deutsch“ oder „English“. Die Wahl gilt nur für Plattenregal und ab dem nächsten Start; ein Knopf „Jetzt neu starten“ erscheint, sobald sie sich von der laufenden unterscheidet. Gespeichert ist sie dort, wo auch macOS sie ablegt (Systemeinstellungen → Sprache & Region → Apps zeigt dieselbe Wahl). „Einstellungen zurücksetzen“ setzt sie auf „System“ – außer in der Demo, die die Sprache der echten App nicht ändert.
- **Übersetzt** ist die ganze Oberfläche: Seiten, Einstellungen, Hinweise, Fehlermeldungen, Dialoge, Menüs, die Demo-Sammlung (Regal- und Ordnernamen) sowie Spaltenköpfe und Texte in CSV und PDF. Rund 800 Texte in einem String-Katalog (`Localizable.xcstrings`), Deutsch ist die Ausgangssprache.
- **Unverändert deutsch** bleiben das Protokoll (für die Fehlersuche), Dateinamen der automatischen Sicherungen (sonst würden ältere nicht mehr erkannt) und bereits gespeicherte Werte wie Regalnamen.
- Jahreszahlen und Discogs-IDs erscheinen in übersetzbaren Texten ohne Tausenderpunkt („1990er“, „Release #1234567“).
- Die Tests laufen immer auf Deutsch (im Schema festgelegt), egal welche Sprache eingestellt ist. 183 Tests, 0 Fehler.

# Sicherung gründlich geprüft · 28.09.2026

Geprüft mit Tests und an den echten Sicherungsdateien (7 Stände, alle wirklich verschieden, Aufbewahrung 5 + Tagesstände korrekt). Korrigiert:

- **Aufbewahrung verkleinern fragt nach**: Weniger „Letzte Stände“ oder „Tagesstände“ löschten überzählige Sicherungen sofort und endgültig – auch wenn man sich nur verklickt hatte. Jetzt erst die Rückfrage „3 ältere Sicherungen löschen?“; gespeichert wird die Einstellung erst nach „Löschen“, damit eine gerade laufende Sicherung nicht schon mit ihr aufräumt.
- **Dateinamen mit Zeitzone** („Belegung 2026-09-27 23-50-00 +0200.json“): Die neueste Sicherung und die Aufbewahrung richten sich nach der Zeit im Namen. Ohne Zeitzone kam bei der Zeitumstellung im Herbst (2–3 Uhr doppelt) oder nach einer Reise eine neuere Sicherung hinter ältere – dann konnte eine Änderung als „schon gesichert“ gelten. Alte Namen werden weiter erkannt.
- **Wiederherstellen sagt, wenn sich die Regale ändern**: Die Sicherung bringt auch Anzahl, Größe und Namen der Regale zurück; der Dialog weist jetzt darauf hin, wenn sie sich seitdem geändert haben.
- **Gleiche Belegung**: Entspricht eine Sicherung schon dem aktuellen Stand, gibt es statt der Rückfrage nur den Hinweis, dass sich nichts ändern würde.
- **Vorschau = Ergebnis** bei handbearbeiteten Dateien: Ein Regal mit mehr Fächern als sein Raster fasst, oder eine leere Regalliste, führten dazu, dass die Vorschau andere Platten zählte, als dann einsortiert wurden.
- **Liste flüssiger**: Die Sicherungsliste las bei jeder Änderung und jedem Sync alle Dateien neu (bei großen Sammlungen und iCloud spürbar). Jetzt nur noch neue oder geänderte; eine unlesbare Datei wird einmal protokolliert statt bei jedem Neuladen.
- **Speicherort** (Sicherung und automatischer Export): Das Ordner-Lesezeichen wird beim Öffnen der Seite aufgelöst statt bei jedem Neuzeichnen – ein getrenntes Netzlaufwerk bremst die Seite nicht mehr aus.
- **Ohne Befund**: Sicherheitskopie vor jedem Wiederherstellen und Zurücksetzen (ohne sie wird nichts ersetzt), erneute Prüfung direkt vor dem Anwenden, Sperre während des Syncs, Sichern beim Beenden, leere Belegung nie automatisch gesichert, fremde Dateien im Ordner werden weder gelistet noch gelöscht, zu große/neuere/fremde Dateien werden abgelehnt, Ordnerwechsel kopiert erst alle Sicherungen und bleibt sonst beim alten, Demo schreibt nie in echte Ordner, jede Regal- und Belegungsänderung löst eine Sicherung aus.
- Neue Tests: `previewAndRestoreAgreeOnTheCompartments`, `restoringTheCurrentLayoutNeedsNoConfirmation`, Zeitzonen-Fälle in `fileNamesCarryTheirTimeInOrder`. 183 Tests, 0 Fehler.

# Export gründlich geprüft · 27.09.2026

Geprüft mit Tests und einem Probe-Export einer Kopie der echten Sammlung (842 Platten, 868 Wünsche; CSV und PDF, beide Reihenfolgen). Korrigiert:

- **Reihenfolge wie in der App**: „Alphabetisch“ folgt jetzt genau der Collection-Seite (Abschnitte des Alphabet-Index, z. B. „Þeyr“ hinter Z), die Wantlist der Wantlist-Seite. Vorher sortierte der Export leicht anders.
- **Master-ID „0“** (139 Platten): Discogs meldet so „kein Master“ – die Zelle bleibt jetzt leer.
- **Doppelte Katalognummern und Labels in anderer Schreibweise** („DOS 202, dos 202“, „Dos 237, DOS 237“) stehen nur einmal da.
- **Mehrfachformate** lesen sich als Anzahl: „2 × Vinyl · LP“ statt „2 · Vinyl · LP“; „1 · Box Set“ wird zu „Box Set“.
- **PDF**: Die Format-Spalte war so schmal, dass fast jede Angabe abgeschnitten wurde; sie ist breiter, der Titel etwas schmaler. Der Hinweis zum PDF nennt bei der Collection auch das Fach.
- **Ordner im Papierkorb**: Ein Lesezeichen folgt seinem Ordner in den Papierkorb – der automatische Export schrieb dann unbemerkt dorthin. Ein Ordner im Papierkorb gilt jetzt als nicht erreichbar (Hinweis in den Einstellungen); Sicherungen fallen dann wie bei einem gelöschten Ordner auf den Ordner der App zurück.
- **Knopf während des Erstellens**: „Wird erstellt …“ statt eines stumm ausgegrauten „Als PDF exportieren …“.
- **Ohne Befund**: Jede Zeile hat so viele Werte wie Spalten (auch Wantlist mit allen Spalten, Platten ohne Release-Daten), PDF über viele Seiten mit „(Fortsetzung)“ und leerer Liste, Formel-Schutz („@dam“ bleibt Text), Kopfzeile, Umlaute, Datumsformat.
- Bekannte Grenze der CSV: Reine Ziffern-Katalognummern verlieren in Numbers/Excel führende Nullen; Mehrere Exemplare desselben Release erscheinen als mehrere Zeilen, die oft völlig gleich aussehen (z. B. „Connected Vol. 3“ dreimal).
- Neue Tests: `wantlistHasNoPlacesAndMatchingRows`, `pdfSpansPagesAndHandlesEmptyLists`, `trashedFolderCountsAsGone`. 182 Tests, 0 Fehler.

# CSV-Export aufgeräumt · 27.09.2026

- **Standort im Regal** ist beim Export standardmäßig aus und hat nur noch drei Spalten: **Regal, Fach, Position**. Reihe, Spalte und Beschriftung fallen weg (Reihe/Spalte stecken schon im Fach, die Beschriftung ist App-intern). Platten ohne Fach tragen in „Fach“ „Noch keinem Fach zugeordnet“ bzw. „Nicht im Regal“. Wer den Standort schon eingeschaltet hatte, behält ihn; das PDF zeigt ihn weiterhin immer.
- **Genres** entfallen (bei elektronischen Sammlungen fast überall „Electronic“), **Stile** bleiben.
- **Format** ohne „1 ·“ bei Einzelplatten („Vinyl · 12" · 45 RPM“); ab zwei Stück bleibt die Anzahl stehen.
- **Katalognummer** ohne Doppelungen: Haben zwei Labels eines Release dieselbe Nummer, steht sie nur einmal da („ASOT018“ statt „ASOT018, ASOT018“).
- Rein numerische Katalognummern („012“, „2003“) behandeln Numbers und Excel weiterhin als Zahl (rechtsbündig, führende Null weg) – das lässt sich in einer CSV nicht sauber verhindern.
- **Export geprüft**, dabei korrigiert:
  - Discogs' Platzhalter **„none“** fällt aus der Katalognummer („none, 1725773, none“ → „1725773“, „none“ → leer).
  - **Doppelte Labels** stehen nur einmal da („Positiva, Positiva“ → „Positiva“).
  - **PDF alphabetisch**: Die Fach-Spalte nennt bei mehreren Regalen auch das Regal („KALLAX · 3“), Platten ohne Fach zeigen „–“ statt eines abgeschnittenen Texts.
  - Wird Format oder Daten umgestellt, während ein großes PDF noch entsteht, speichert der Dialog die Datei trotzdem mit dem richtigen Typ und Namen.
  - Wantlist: Der Hinweis bei „Exemplar“ lautet „Hinzufügedatum“ – einen Discogs-Ordner hat die Wantlist nicht.
  - Ohne Befund: CSV-Maskierung (Anführungszeichen, Zeilenumbrüche, führende Leerzeichen), Formel-Schutz, BOM und CRLF, Zählung = exportierte Zeilen, automatischer Export (kein Überschreiben mit leerer Liste, nicht während des Syncs, nicht in der Demo, nicht erreichbarer Ordner, atomisches Schreiben, Uhr in der Zukunft).
- Tests: `releaseValuesAreTidied`, `locationIsOffByDefaultAndCompact`. 178 Tests, 0 Fehler.

# Regalgrößen ohne Maße, 1 × 1 dazu · 27.09.2026

- **Einstellungen › Regal › Größe**: Die Auswahl zeigt nur noch die Aufteilung („2 × 4 (hochkant)“), ohne Zentimeter. Neu ist **1 × 1**. „Eigene Größe …“ bleibt. Ein Regal mit 1 Spalte und 1 Reihe (z. B. EKET) steht jetzt automatisch auf „1 × 1“. Der Hinweis unter „Größe“ lautet nur noch „Spalten × Reihen“.
- **Regal löschen**: Der rote Knopf heißt nur noch „Löschen“, ohne „…“.

# Über Plattenregal als kleine Karte, Doku geprüft · 27.09.2026

- **„Über Plattenregal“** (App-Menü) öffnet statt des System-Fensters eine kleine, kompakte Karte (260 pt breit): App-Symbol, Name, „Version 1.0 (092026)“ – zum Kopieren auswählbar, für Fehlermeldungen – und „© 2026 Patrice Werner“. Eigenes Fenster ohne Titelleiste, feste Größe, nicht minimierbar, erscheint mittig und wird nach einem Neustart nicht wiederhergestellt (`Views/AboutView.swift`).
- **README**: ein Hauptfenster, App läuft nach dem Schließen weiter, Über-Karte; beim Melden eines Fehlers Protokoll und Version mitgeben. **STATISTIK.md**: Anzahl im Titel des Auswahlfensters, kein Hinweis beim Sammlungswert nach reiner Wantlist-Synchronisierung, 29 Statistik-Tests. **VALIDIERUNG.md** auf den aktuellen Stand gebracht.
- **Fehlermeldungen und Protokoll geprüft ohne Befund**: Alle Texte der App-Fehler (Discogs, Regal, Positionen, Sicherung, Dateien, Zurücksetzen, Schlüsselbund, zweite Instanz) sind deutsch, sagen was passiert ist und was zu tun ist; Codes nur dort, wo sie beim Nachschlagen helfen (HTTP, Schlüsselbund). Protokoll: Startzeile mit Version und Ladeadresse, Absturz-Block mit Signal, Uhrzeit, Version und Aufrufliste, Hinweis auf unerwartetes Ende, Rotation ab 2 MB samt Umstellen des Absturz-Deskriptors. Nur ein veraltetes Beispiel („Version 1.0 (7)“) im Code-Kommentar korrigiert.

# Nur noch ein Hauptfenster · 27.09.2026

- **⌘N öffnet kein zweites Hauptfenster mehr**: Statt `WindowGroup` eine einzelne `Window`-Szene. Ein zweites Fenster lud und berechnete jede Seite ein weiteres Mal (Statistik, Suchindex, Regal). Das Menü „Ablage“ fällt damit weg – es enthielt nur „Neues Fenster“.
- **Die App läuft weiter, wenn das Fenster geschlossen wird** (`applicationShouldTerminateAfterLastWindowClosed` → nein), wie bisher: Automatischer Export, Tracklisten und Sicherungen laufen weiter. Ein Klick aufs Dock-Symbol holt das Fenster zurück.
- In der Demo geprüft: ⌘N ohne Wirkung, nach ⌘W läuft die App weiter, das Fenster kommt per Dock zurück.

# Randfälle und Logik: zweite Runde · 27.09.2026

- **Rückfragen in der Demo versprachen eine Sicherung**, die es dort absichtlich nie gibt („Die aktuelle Belegung wird vorher gesichert“) – vor „Wiederherstellen“ und „Standorte zurücksetzen“. In der Demo entfällt der Satz jetzt, wie schon in der Erfolgsmeldung danach.
- **„Standorte zurücksetzen“ verschwieg „Vermisst“**: Die Markierungen werden dabei aufgehoben und kommen mit einer Sicherung nicht zurück (sie sind nicht Teil davon). Die Rückfrage sagt das jetzt.
- **Geprüft ohne Befund**: Übernahme der Discogs-Daten (Interpreten mit Namensvarianten, Jahr 0, leere Cover, Datumsformate), Statistik-Berechnung (unplausible Jahre, Platten ohne Datum, „Various“, Zusammenführen alter Einträge), Einlesen der Geldbeträge (Tausender- und Dezimaltrenner, Währungssymbole), CSV (Formeln entschärft, BOM, Anführungszeichen) und PDF (Seitenumbruch, Fach-Überschriften), Reihenfolgen „Zufällig“ und „Neueste zuerst“, Protokoll (Rotation, Absturz-Block, Instanzwechsel), App-Start (Demo, zweite Instanz, Datenbankfehler), Export-, Daten- und Sicherungs-Einstellungen, Neuladen einzelner Releases. 176 Tests, 0 Fehler.

# Randfälle, Logik und toter Code: ganze App geprüft · 27.09.2026

- **Sync stürzte bei doppelten Einträgen in der Datenbank ab**: Ordner und Wantlist wurden über `Dictionary(uniqueKeysWithValues:)` nachgeschlagen, das bei einem doppelten Schlüssel die App beendet. Discogs-Antworten mit Doppelten lehnt der Client schon ab; ein Doppel, das bereits in der Datenbank steht, führt jetzt nicht mehr zum Absturz – der erste Eintrag wird aktualisiert. Test: `duplicatesAlreadyInTheStoreDoNotStopTheSync`.
- **Sammlungswert nach reiner Wantlist-Synchronisierung**: Die Aktualisierung meldete fälschlich „Der Discogs-Token passt nicht mehr zum geladenen Konto“, wenn das Konto noch keine Collection hatte. Jetzt gibt es dann einfach noch nichts zu bewerten, ohne Meldung. Test: `valueRefreshAfterWantlistOnlySyncIsNoError`.
- Doku-Kommentar der Fach-Beschriftungen stand über dem falschen Typ.
- **Toter Code**: Per Skript jede Deklaration gegen ihre Verwendungen geprüft (ohne Kommentare, getrennt nach App und Tests), dazu private Member, Zustände und Stil-Konstanten. Kein ungenutzter Code gefunden; was nur Vorschauen und Tests dient (`insert(release:)`, `PreviewData`), steht bereits in `#if DEBUG`.
- **Geprüft ohne Befund**: Positionen und Transaktionen, Sortierschlüssel (Tabulator trennt Interpret und Titel korrekt), Jahr 0 von Discogs, Fach-Beschriftungen, Regale anlegen/verkleinern/löschen, Sicherung und Wiederherstellung samt Aufbewahrung, Zurücksetzen, Instanz-Sperre, automatischer Export, Discogs-Client (Seitenprüfung, Ratenlimit, Wiederholungen), Cover-Cache, Schlüsselbund und Token-Test, Demo-Abschottung, Ordner-Lesezeichen. 176 Tests, 0 Fehler.

# Collection, Wantlist, Einstellungen, Statistik: zweite Runde · 27.09.2026

- **Statistik-Fenster mit den Platten einer Auswahl** (Klick auf Kachel, Diagramm oder Rangliste): neben dem Titel steht jetzt die Anzahl („Downtempo · 7 Platten“), wie beim Fach im Regal und in der Vermisst-Liste.
- **Wantlist-Raster**: Interpret unter dem Cover halbfett wie in „Zuletzt hinzugefügt“ und „Top-Künstler“ der Statistik.
- **Detailansicht einer Platte**: Standort in der gemeinsamen Titelschrift, Abstände aus den Stil-Konstanten.
- Geprüft ohne Befund: Detailansicht und Cover-Popover, Suche mit Markierungen und Treffern der anderen Seite, Rechtsklick-Menü, unterer Teil der Statistik (Klangbild, Top-Künstler, Labels, Zufallsfund, Zeitreise, Neuzugänge, Zuletzt hinzugefügt), Einstellungen im Dunkelmodus, abgesicherte Divisionen und Indexzugriffe.

# Collection, Wantlist, Einstellungen, Statistik: Feinschliff · 27.09.2026

- **Listenansicht von Collection und Wantlist** auf derselben abgerundeten Glaskarte wie die Fach-Tabelle im Regal (neuer Baustein `appTableCard`). Vorher stand die Tabelle direkt auf der Seite, mit eckigem weißem Kopfbalken.
- **Gesperrte Hauptknöpfe sahen klickbar aus**: `PrimaryButton` setzte seine Akzentfarbe fest, so blieb z. B. „Speichern & testen“ und „Alles synchronisieren“ in der Demo blau, obwohl gesperrt. Gesperrt wird er jetzt grau wie alle anderen Knöpfe. Ebenso „Löschen …“ bei einem Regal mit Platten (Einstellungen › Regal): grau statt rot.
- **Statistik › Sammlungswert im Verlauf**: In den halbbreiten Diagrammen überlappten sich die Datumsbeschriftungen („Apr. 20Juli 2026“). Der Monatsabstand der Beschriftungen richtet sich jetzt nach Breite und Zeitraum, immer mit Monat und Jahr; kurze Zeiträume bleiben automatisch.
- **Tausenderpunkte** auch bei großen Zahlen in Statistik (Anzahlen in Klangbild, Labels, Diagrammen), Sync-Fortschritt, „N hinzugefügt“, Treffer der anderen Seite und Discogs-Aktualisierung.
- „Keine Treffer“ in Collection und Wantlist mit demselben Hinweis („… oder ein anderes Label“).
- In der Demo geprüft: Raster und Liste von Collection und Wantlist, alle Einstellungs-Tabs, Statistik hell und dunkel.

# Regal: Feinschliff bei Optik und Konsistenz · 27.09.2026

- **Tabelle im Fach**: Die mattierte Kopfzeile hatte eckige Ecken und stand oben aus der abgerundeten Glasfläche heraus (im inaktiven Fenster als grauer Balken gut sichtbar). Die Tabelle ist jetzt auf die Rundung der Fläche zugeschnitten, der 4-pt-Streifen über der Kopfzeile entfällt.
- **Leere Fächer**: „Leer“ steht mittig im Fach wie Schloss und Name eines gesperrten Fachs, statt klein oben links etwas höher als die Buchstaben der Nachbarfächer. Im Detailbereich entfällt „0 Platten“ – die Zeile darunter sagt es schon.
- **Einheitliche Etiketten**: „Vermisst“, „Nicht in der Collection“ und „Als Nächstes“ nutzen einen gemeinsamen Baustein `StatusTag` statt dreier Nachbauten.
- **Vermisst-Spalte**: Hover-Hintergrund wie in Suche und „Sortierung prüfen“ (`appHoverable`, gleiche Rundung); die Anzahl mit Tausenderpunkt über `AppStyle.records`.
- **„Sortierung prüfen“**: Symbol der Umstell-Karte in derselben Größe wie das Häkchen von „Alles in Ordnung“ und das Fach-Symbol in „Platte hinzufügen“ (22 pt).
- **Hinweis beim Namen eines gesperrten Fachs** stimmt jetzt: Der Name erscheint unter dem Schloss und als Titel des Fachs (vorher: „anstelle von ‚Gesperrt‘“, das nirgends steht).
- Feste Werte durch Stil-Konstanten ersetzt: Abstand zwischen den großen Blöcken der Seite (`blockSpacing`, auch für Suchleiste und Regal-Reiter), Rundung der Suchtreffer und der vorgeschlagenen Zeile, Abstand im Rückgängig-Hinweis.
- In der Demo geprüft, hell und dunkel, mit 4 × 3 und 2 × 2 samt leerem und gesperrtem Fach.

# „Reihenfolge übernehmen“ schließt das Fenster · 27.09.2026

- **Erster Klick danach ging ins Leere**: Nach „Reihenfolge übernehmen“ blieb „Sortierung prüfen“ offen (mit „Alles in Ordnung“). Ein offenes Glasfenster fängt Klicks daneben ab, um sich zu schließen – der erste Klick auf ein anderes Fach schloss also nur das Fenster. Jetzt schließt es sich nach dem erfolgreichen Speichern selbst, der nächste Klick erreicht sofort das Fach. Scheitert das Speichern, bleibt es mit der Fehlermeldung offen.

# Schmale Regale bündig mit dem Fachbereich · 27.09.2026

- **Regale mit weniger als vier Spalten** (1 × 1, 2 × 2 …) waren auf höchstens 300 pt pro Spalte begrenzt, Fach-Titel („Y–Z“), Rückenleiste und Tabelle darunter liefen aber über die volle Breite. Das Regal nimmt jetzt immer die ganze Breite ein und schließt links und rechts bündig mit dem Bereich darunter ab – wie beim 4 × 3.
- **Rückenleiste bündig mit dem Fach-Titel**: Jeder Rücken stand mittig in seinem Platz, der erste also rund 5 pt hinter der linken Kante – das „Y“ von „Y–Z“ ragte darüber hinaus. `SpineLayout` setzt den ersten Rücken jetzt genau an die Kante (bei vollem Fach den letzten genau an die rechte). Zeichnen, Klick, Hover-Cover und Einfügemarke rechnen mit demselben Layout; ein herausgezogener Rücken am Rand wächst nicht über die Leiste hinaus.

# Kein Aufblitzen mehr beim ersten ⌘F · 27.09.2026

- **Ursache gefunden**: Der Kasten war das AutoFill-Fenster von macOS für zugestellte Einmal-Codes (Nachrichten, Mail). Textfelder ohne Inhaltstyp gelten als „nicht gekennzeichnet“; beim ersten Fokus nach dem Start ruft AppKit dafür `displayOTPAutoFill…` auf und blendet das leere Vorschlagsfenster (312 × 237 pt) für einen Frame ein. Belegt mit 120-fps-Aufnahme, Fensterliste (Plattenregal, Ebene 101) und Aufrufkette (`NSAutoFillHeuristicController _showPasswordAutoFillIfNecessaryForView:` → `SPSafariPlatformSupport`).
- **Behoben** mit öffentlicher API: `noTextAutoFill()` gibt Suchfeldern, Glas-Textfeldern und dem Positionsfeld einen eigenen Inhaltstyp, den AutoFill nicht kennt. Gemessen: ohne Korrektur in 4 von 5 Starts ausgelöst, mit Korrektur in 0 von 8 (Collection, Wantlist, Regal). Das Token-Feld (SecureField) bleibt unverändert.

# ⌘F schaltet die Suche um · 27.09.2026

- **⌘F ein und aus**: Ein zweites ⌘F (oder die Suche aus dem Menü), während der Cursor in der Suchleiste steht, leert sie und blendet sie aus – in Collection, Wantlist und Regal. Ist die Leiste noch da (mit Text), aber nicht im Fokus, holt ⌘F zuerst den Cursor zurück. `SearchReveal` bekommt den Suchtext dafür als Binding.

# Drei Prüfrunden, Fehlermeldungen und Protokoll · 27.09.2026

- **Esc schloss die Glasfenster nie**: Die Seiten sind eigene SwiftUI-Wurzeln (`PageStack`), dort erreicht ein `.cancelAction`-Kürzel die Taste nicht. Jetzt fängt eine eigene Abfrage (`PanelEscapeMonitor`) Esc ab – nur für das Fenster, in dem das Panel liegt (nicht aus dem Einstellungsfenster heraus), nur bei sichtbarer Seite und nicht, solange ein Popover oder eine Rückfrage davorliegt. In der App geprüft.
- **Fenster oben verankert** statt mittig: Wuchs ein Fenster (andere Sortierung, Spalte klappt auf), rutschte der Inhalt unter dem Zeiger weg – so wurde ein Schritt in „Sortierung prüfen“ versehentlich abgehakt.
- **Collection** sortiert sofort neu, wenn die Reihenfolge bei gleichem Interpreten geändert wird. „Sortierung prüfen“ liest keine gerade gelöschten Platten. Wertezeilen der Diagramme brechen nicht um. Einstellungsschlüssel der Vermisst-Spalte zentral in `DisplaySettings`.
- **Fehlermeldung** `LibraryError.orderNotSaved`: Scheitert „Reihenfolge übernehmen“, heißt es „Die neue Reihenfolge konnte nicht gespeichert werden – das Fach ist unverändert …“ statt der allgemeinen Speicher-Meldung.
- **Protokoll**: jede Prüfung mit Fach, Sortierung und Ergebnis; „Reihenfolge übernehmen“ mit der Zahl geänderter Positionen; Wechsel der Reihenfolge bei gleichem Interpreten (in den Einstellungen oder aus der Prüfung); Vermisst-Liste ein/aus.
- Protokoll der Testläufe durchgesehen: keine Absturzblöcke, keine Fehlermeldungen. Eine Warnung „nicht normal beendet“ (9:56) stammt von einer Testinstanz, die während eines Neubaus beendet wurde.
- Test: `errorsReachTheUserInPlainGerman` um die neue Meldung erweitert (174 Tests, 0 Fehler).

# Sortierung prüfen, Reihenfolge bei gleichem Interpreten · 27.09.2026

- **„Sortierung prüfen“** im Rechtsklick-Menü eines Fachs (ersetzt „Alphabetisch sortieren …“): prüft die gespeicherte Reihenfolge und zeigt die kleinstmögliche Zahl an Umstellungen als nummerierte Schritte zum Abhaken – Platte mit Cover, jetziger Platz, „hinter …“ bzw. „ganz vorn, vor …“ mit Cover des Nachbarn. Die Schritte stehen in der Reihenfolge ihrer Zielplätze, sodass jeder nur auf Platten verweist, die dann schon richtig stehen (`ShelfSortCheck.steps`: alle außer einer längsten schon richtig stehenden Folge). „Reihenfolge übernehmen“ speichert die neue Reihenfolge.
- **Reihenfolge bei gleichem Interpreten** (`ShelfSecondaryOrder`: Titel, Jahr, Label/Katalognummer), wählbar in der Prüfung und unter Einstellungen → Regal → Einsortieren. Der Interpret bleibt erster Schlüssel (`SortingService.sortKey`), Fachnamen und Platzsuche bleiben gültig; die Wahl gilt auch für Platzsuche, „Platte hinzufügen“ und die alphabetische Collection.
- Menüpunkte „Platte hinzufügen“ und „Sortierung prüfen“ ohne Auslassungspunkte.
- Tests: `sortCheckMovesFewestRecordsInTargetOrder`, `sortCheckByYearWithinArtist`.

# Platte hinzufügen mit Vermisst-Spalte · 27.09.2026

- **Vermisst-Spalte** rechts in „Platte hinzufügen“ statt eigenem Knopf „Vermisst“ auf der Regalseite: nach Fach gruppiert, mit „Zeigen“ und „Wieder gefunden“. Nur vorhanden, solange etwas vermisst wird (das Fenster bleibt sonst schmal), einklappbar (dann „x vermisst ‹“ oben; gemerkt). Links stehen nur noch einsortierbare Platten; Zurückstellen und Wiederfinden wandern animiert zwischen Liste und Spalte, Gefundene kehren an ihre Stelle zurück statt ans Ende. Ist links nichts mehr, heißt es „Nur noch vermisste Platten“.
- **„Als Nächstes“**: die nächste passende Platte (nach Interpret) ist leicht hervorgehoben.
- **Vermisst-Liste abschaltbar** (Einstellungen → Regal → Einsortieren): ohne Zurückstellen, Spalte, Etiketten und Umrisse; die Markierungen bleiben gespeichert.
- **„+“ im Fach** statt Knopf unter dem Regal: kleines Glas-Plus oben rechts beim Überfahren und im gewählten Fach, an der Stelle der Plattenanzahl; blendet beim Fachwechsel ein und aus. Nicht bei gesperrten Fächern.
- Test `addingListsFittingRecordsFirstPausedInPlace` (vorher `…AndPausedLast`): Zurückgestellte behalten ihren Platz.

# Fenster ohne Ampel, Oberfläche feiner · 27.09.2026

- **Glasfenster über der Seite** (`appPanel`) statt Sheets mit Ampel: Plattenliste und Plattendetails der Statistik, „Platte hinzufügen“. Schließen per Klick daneben oder Esc; keine Abdunklung mehr (sie endete hart an der Toolbar), ein weicher Schatten setzt das Fenster ab. `SheetCloseLight` und `AppSheetHeader` entfernt.
- **Statistik**: Plattenliste ohne Suchleiste, Titel neben Raster/Liste. Werte beim Überfahren in einer festen Zeile unter dem Diagramm statt im mitwandernden Glas-Kästchen (`chartTooltipChrome` entfernt). Letztes Datum der Zeitachse ragt nicht mehr in die Werteachse. Karten zur Fensterfarbe getönt, eingebauter Glas-Schatten abgeschnitten (`appCardSurface`, auch in den Einstellungen).
- **Regal**: Hover hellt nur noch das Fach unter dem Zeiger auf (statt eines wandernden Lichtscheins über mehrere Fächer); die Auswahl-Platte blendet im Fach ein statt übers Regal zu gleiten. Regal-Reiter mit feinen Trennlinien, ohne Fachanzahl und Plattenzahl daneben. Umbenennen-Popover des Regal-Reiters in normaler Schrift statt Tab-Blau.
- **Toolbar**: Lupe entfernt (Suche über ⌘F), kein Rechtsklick-Menü „Symbol und Text“ mehr (`windowToolbarLabelStyle(fixed: .iconOnly)`).
- Inaktive Fenster bleiben beim nativen Verhalten (macOS flacht das Glas ab).

# Eingabequellen-Blase wirklich aus · 26.09.2026

- Die Blase über dem Cursor erschien bei ⌘F wieder: Der nur registrierte Standard lebt allein im Prozess der App, macOS hat ihn nicht gesehen. `InputSourceIndicator.disableForApp()` schreibt `TSMLanguageIndicatorEnabled = false` jetzt dauerhaft in die Einstellungen der App. Wer die Blase in macOS ausdrücklich ein- oder ausgeschaltet hat (globale Domäne), behält das.
- Test: `inputSourceBubbleIsStoredOffForTheApp`.

# Ambient-Farbe · 26.09.2026

- **Ambient-Farbe** (Einstellungen › Darstellung): ein Farbschein von oben über das ganze Fenster, bis unter die Rubriken (`AmbientGlow` in `RootView`, hinter allen Seiten). Aus oder eine der acht Akzentfarben, Standard Blau; die Reihe steht bündig unter der Akzentfarbe (`AmbientChoice`). Ersetzt den Hauch der Genrefarbe im Regal, der an der Toolbar hart abbrach – die Seiten liegen in eigenen Hosting-Views und reichen nicht darunter.
- Akzent- und Ambient-Farbe ohne grauen Erklärtext.

# Letzte Prüfung: Cover ohne Bild, verschobene Ordner · 26.09.2026

- **Leere Cover-URL** (`DiscogsBasicInformation.apply`): Discogs schickt für Platten ohne Bild `""`. Das wurde als Cover gespeichert und belegte z. B. einen der drei Plätze im Ambient-Hintergrund. Jetzt bleibt es leer, und wenn nur das Vorschaubild existiert, wird es verwendet. Greift nach dem nächsten Sync.
- **Verschobener Sicherungs- oder Export-Ordner** (`FolderAccess.url`): Das veraltete Lesezeichen wurde ohne geöffneten Zugriff erneuert – das scheitert in der Sandbox still, es blieb dauerhaft veraltet. Jetzt mit Zugriff.
- Test: `emptyCoverFallsBackToThumbnailOrNothing` (171 Tests, 0 Fehler).

# Zweite Prüfung: Kontowahl, Discogs-Wartezeit · 26.09.2026

- **Aktuelles Discogs-Konto** (`DiscogsAccount.lastSync`): Zählte den ersten vorhandenen Sync-Zeitpunkt (Voll-Sync vor Collection vor Wantlist) statt des neuesten. Nach einem alten Voll-Sync von Konto A, einem Sync von Konto B und einem neuen Collection-Sync von A blieb B „aktuell“ – Collection, Regal, Statistik, Export und Sicherung zeigten das falsche Konto. Jetzt entscheidet der neueste Sync gleich welcher Art.
- **Wartezeit bei „zu viele Anfragen“** (`DiscogsAPIClient.retryDelay`): Ein unsinnig großes `Retry-After` hätte jede Discogs-Anfrage stundenlang ohne Rückmeldung blockiert. Jetzt höchstens 10 Minuten; Leerzeichen und vergangene Zeitpunkte werden sauber behandelt.
- **Belegung zurücksetzen in der Demo**: Die Meldung verwies auf eine Sicherung, die die Demo nie schreibt.
- „Ohne Collection aus dem Regal nehmen“ mit inzwischen leerer Liste schreibt nichts und protokolliert nichts.
- Veraltete Kommentare (Wantlist als „kompakte Tabelle“, „Auswahl aufheben“) und der Vorschau-Name „Übersicht“ angepasst.
- Tests: `mostRecentSyncOfAnyKindPicksTheCurrentAccount`, `retryAfterSecondsAndHTTPDate` um Grenzfälle erweitert (170 Tests, 0 Fehler).

# Prüfung der letzten Änderungen · 26.09.2026

- **Zufällige Reihenfolge je Seite** (`OverviewOrder`): Collection und Wantlist teilten sich einen Zufallswert. Stellte man die Wantlist auf „Zufällig“, war die Collection-Reihenfolge danach eine andere – sichtbar erst beim nächsten Sync, als plötzliches Umsortieren. Jetzt mischt jede Seite für sich.
- **Statistik und Token** (`StatisticsViewModel`): wertete einen nicht lesbaren Schlüsselbund als „Token fehlt“, der Rest der App als „vorhanden“. Jetzt überall dieselbe Regel (`KeychainStore.hasToken`).
- **„Platte hinzufügen“**: Das Ziel-Detail („zwischen … und …“) liest keine inzwischen gelöschte Platte mehr. In den Einstellungen prüft „Fach sperren“, ob das Fach noch existiert.
- Protokoll: „x von y fehlgeschlagen“ beim Neuladen als Warnung. Veraltete Kommentare (Auswahlrahmen, Detailansicht) und ein ungenutzter Parameter entfernt.
- Tests: neuer Migrationstest V13 → V15 (`v13StoreKeepsPlacesAndMarksWhileDroppingUnusedData`) – der Weg jeder bestehenden Datenbank; `fittingShelves` gegen `spots` geprüft; Export ohne entfernte Spalten; getrennte Zufallsreihenfolgen. Die älteren Migrationstests heißen nach dem, was sie prüfen, statt „V6“/„V8“ als Ziel zu nennen.

# Fehlermeldungen und Protokoll nachgezogen · 26.09.2026

- **„Discogs-Daten aktualisieren“** (Collection-Menü): Das Fehlerfenster hieß wie bei einer Regal-Änderung „Änderung nicht gespeichert“, auch wenn nur Discogs nicht erreichbar war. Jetzt „Discogs-Daten nicht aktualisiert“ mit dem Grund. Das Protokoll hält neben dem Beginn auch das Ergebnis fest („neu geladen“ bzw. „x von y fehlgeschlagen“).
- **Name eines gesperrten Fachs** (`ShelfNamePopover`): Return speicherte und schloss das Fenster in einem Zug – eine Fehlermeldung erschien in einem Fenster, das schon zu war. Jetzt bleibt es bei einem Fehler offen und zeigt ihn. Beim Schließen per Klick daneben bleibt der alte Name, der Fehler steht im Protokoll.
- **Schlüsselbund nicht lesbar** (`KeychainStore.hasToken`): wurde stillschweigend als „Token vorhanden“ gewertet; jetzt mit Warnung im Protokoll.
- README, STATISTIK.md und VALIDIERUNG.md auf den Stand der neuen Oberfläche gebracht.

# Suche ohne Aufblitzen, keine Eingabequellen-Blase · 26.09.2026

- Die Suchleisten von Collection, Wantlist und Regal sind von Anfang an da und werden nur ein- und ausgeblendet (`searchBarSlot`): verborgen ohne Höhe, unsichtbar und nicht erreichbar. Vorher wurden Glas und Textfeld erst beim ersten ⌘F aufgebaut, und die Leiste stand sofort da, statt einzublenden.
- Die Eingabequellen-Blase von macOS, die beim ersten ⌘F über dem Cursor erschien, ist in der App abgeschaltet – nur als registrierter Standard (`TSMLanguageIndicatorEnabled`); wer sie in macOS ausdrücklich einschaltet, behält sie.

# Reihenfolge von Collection und Wantlist · 26.09.2026

- **Einstellungen → Allgemein → Start**, getrennt für Collection und Wantlist: alphabetisch (mit Alphabet am Rand), zufällig oder neueste zuerst (nach Discogs-Hinzufügedatum, Undatierte am Ende).
- Zufällig mischt bei jedem Start und beim Umschalten auf „Zufällig“ neu, dazwischen bleibt die Reihenfolge stabil. Exemplare einer Veröffentlichung bleiben eine Kachel (`OverviewOrder`).
- Der Rand fürs Alphabet bleibt bei jeder Reihenfolge gleich breit, damit sich die Covergröße beim Umschalten nicht ändert.
- Test: `SettingsTests.overviewOrderShufflesStablyAndSortsNewestFirst`.

# Collection und Wantlist: eigenes Menü statt Detailansicht · 26.09.2026

- **Keine große Detailansicht mehr** in Collection und Wantlist, kein „Öffnen“, kein Vergrößern-Pfeil im Popover. Die Statistik öffnet einzelne Platten weiter in der Detailkarte (Ampel oben links, ohne Überschrift, „Auf Discogs öffnen“, „Nicht im Regal“ direkt in der Standort-Karte).
- **Rechtsklick** öffnet an der Mausposition ein App-eigenes Menü (`AppMenu`) mit Hover-Zeilen: „Im Regal anzeigen“ bzw. „Platz im Regal finden“, „Auf Discogs öffnen“, „Discogs-Daten aktualisieren“, „Nicht im Regal“ bzw. „Wieder einsortieren“ – im Raster und in der Liste. Die Wantlist hat dasselbe Menü mit „Auf Discogs öffnen“.
- **Keine Mehrfachauswahl** mehr (⌘/⇧-Klick, Auswahlrahmen, „x ausgewählt“, Rahmen und Haken am Cover). Ein Klick zeigt das kleine Popover, das Menü gilt immer der angeklickten Platte.
- **Wantlist** mit demselben Popover samt Tracklist (`RecordPopover` nimmt dafür ein Release), Doppelklick in der Liste.
- Das Detailfenster zeigt keine Tracklist mehr (die steht im Popover) und passt seine Höhe dem Inhalt an. „Discogs-Daten aktualisieren“ und der Discogs-Ordner sind aus ihm entfernt; der Dialog „Exemplar bearbeiten“ ist entfallen.
- **Erster Start:** Ohne Token öffnet „Token eintragen“ auf der leeren Collection bzw. Wantlist die Einstellungen bei Discogs mit aktivem Token-Feld (`SettingsRequest`); mit Token bleibt es bei „Jetzt synchronisieren“. `KeychainStore.hasToken` (in der Demo immer ja).

# Regal in Glas · 26.09.2026

- **Regalbild** als ein Glaskörper, Fächer als eingelassene Mulden; das gewählte Fach hebt sich als Platte heraus und gleitet von Fach zu Fach. Lichtreflex folgt dem Zeiger. Fach: Bereich oben links, Plattenanzahl oben rechts, Genre-Punkt. Gesperrte Fächer als Milchglas statt Schraffur. Regalwechsel gleitet seitlich, „Rückgängig“ als Glas-Toast.
- **Rückenleiste**: Rücken mit Glanz und Schatten, leuchtender Einfügespalt. Das Cover erscheint beim Überfahren (beim ersten Mal nach 450 ms, danach folgt es dem Zeiger sofort) als Glaskarte neben dem Rücken.
- **Hintergrund**: ein Hauch der Genrefarbe des Fachs (`AmbientBackdrop`, auch in Collection, Wantlist und Statistik mit weichgezeichneten Covern).
- **Fachsperre nur noch per Menü**: Das Optionssymbol neben „+“ ist entfernt. Rechtsklick auf ein Fach (im Regal) bzw. Klick darauf (in den Einstellungen) öffnet ein `AppMenu` mit „Fach sperren“/„Fach entsperren“ und „Namen ändern …“ für gesperrte Fächer (`ShelfNamePopover`).
- **Fach-Tabelle** als Glaskarte mit eigenem Rechtsklickmenü, neu mit „Nicht im Regal“; Doppelklick öffnet weiter den Schnelleditor. „Vermisst“ oben rechts nur noch als Text in der Glaskapsel.
- **„Platte hinzufügen“** im Glas-Design (Ampel, Zielkarte „Kommt in …“ mit Zähler, runde Glasknöpfe). Passende Platten zuerst, dann die übrigen mit „gehört in …“, pausierte zuletzt; die Reihenfolge wird beim Öffnen einmal festgelegt (`AlphabeticalPlacement.fittingShelves`). „+“ setzt an die alphabetische Stelle statt ans Ende; die Zielkarte zeigt „zwischen „X“ und „Y““. Der Pfeil bei Platten für ein anderes Fach schließt das Fenster und zeigt dort ihren Platz. Test: `ScenarioTests.addingListsFittingRecordsFirstAndPausedLast`.
- **Leeres Regal**: Sind Platten da, aber keine einsortiert, bietet ein Hinweis „Belegung wiederherstellen …“ an (öffnet „Sicherung“).

# Statistik in Glas · 26.09.2026

- Karten auf Liquid Glass statt grauer Fläche; ein Rahmen erscheint nur als Ablageziel beim Umsortieren. Rang-Plaketten der Top-Künstler (außer Platz 1) aus Glas, „Details“ im Zufallsfund als Glasknopf, das Blau in „Deine Sammlung“ dezenter.
- Hintergrund: die Cover der zuletzt hinzugefügten Platten, weichgezeichnet.
- Die gefilterte Plattenliste als Glas-Sheet mit Ampel statt „Schließen“.

# Rubriken in der Toolbar, einheitliches Liquid Glass · 25.09.2026

- **Seitenleiste entfernt.** Oben in der Toolbar Collection · Wantlist · Regal · Statistik (⌘1–⌘4), rechts eine Glas-Gruppe mit Raster/Liste (nur Collection/Wantlist) und Lupe (nicht in der Statistik). Die Kopfzeile auf der Seite entfällt, Cover beginnen direkt unter der Toolbar. Das Zahnrad ist entfernt – Einstellungen über das App-Menü und ⌘,.
- **Suche per ⌘F** oder Lupe, mittig unter den Rubriken, höchstens 480 pt breit. Sie bleibt, solange sie Text hat; leer und ohne Fokus verschwindet sie. Collection und Wantlist teilen Suchtext und Sichtbarkeit (`LibrarySearch`); „N in der Wantlist“ hängt rechts an der Leiste und springt zur anderen Rubrik. Ein- und Ausblenden gleitet aus der Toolbar, mit „Bewegung reduzieren“ nur Überblenden.
- **Ruckelfreier Rubrikwechsel** (Time Profiler, Release, 12 Wechsel: Main-Thread-Last ~4,1 s → ~0,2 s; pro Wechsel 100–200 ms Hänger → 5–20 ms; keine Animation Hitches). `PageStack` hält jede Seite in einer eigenen, dauerhaft eingehängten Hosting-View und blendet nur per Core Animation über; verborgene Seiten bekommen keine Klicks, Kürzel, Fokus oder VoiceOver. Auswahl, Sichtbarkeit und ⌘F kommen als gleichbleibende Objekte (`PageSelection`, `PageVisibility`, `SearchRequests`, `PageActivity`), sodass sich beim Wechsel kein Umgebungswert ändert.
- **`GlassSegmentedPicker`** ersetzt alle Umschalter (Toolbar, Einstellungen, Statistik, Regalauswahl): keine graue Spur, die gewählte Option trägt die Akzentfarbe. Knöpfe als Glas-Kapseln ohne Füllung, die Hauptaktion mit Akzentfarbe im Titel; Aufklappmenüs als `GlassMenuPicker`. Einstellungen mit Glas-Umschalter in der Toolbar statt Tabs.

# „Nicht auffindbar“ heißt jetzt „Vermisst“ · 25.09.2026

- Die Markierung heißt überall „Vermisst“: Etikett, Knöpfe, Menüs, Hinweise, Fehlermeldungen, Protokoll und Dokumentation.
- Die Übersicht neben der Suche auf der Regalseite zeigt nur noch „Vermisst“ statt der Anzahl („7 nicht auffindbar“); die Liste darin nennt weiter jede Platte.
- Die Liste hinter „Vermisst“ ist jetzt ein Popover statt eines Menüs: Kopfzeile mit Anzahl, Platten nach Fach gruppiert („Noch ohne Fach“ zuletzt), je Zeile Cover, Titel und Künstler. Ein Klick auf die Zeile zeigt die Platte im Fach bzw. sucht ihren Platz, das Häkchen markiert sie als wieder gefunden. Ab etwa acht Platten scrollt die Liste. Im Knopf steht ein roter Punkt vor „Vermisst“.

# Schema V15: nur noch, was die App nutzt · 25.09.2026

- **Neues, in sich vollständiges Schema V15** (leichte Migration von V14). Entfernt, weil nirgends gelesen:
  - Exemplar: Discogs-Bewertung, Discogs-Notizfelder, Zeitpunkt des letzten Abgleichs.
  - Wantlist-Eintrag: Bewertung, Zeitpunkt des letzten Abgleichs (die Notiz bleibt – sie steht in der Wantlist-Ansicht).
  - Discogs-Ordner und -Konto: Zeitpunkt des letzten Ordner-Abgleichs.
  - Wert-Verlauf: Anzahl verschiedener Releases.
  - „Nicht im Regal“ und „Vermisst“: Anlegedatum.
  - Das Modell `ReleaseMarketValue` (seit der früheren Einzelpreis-Funktion nie mehr befüllt).
- Discogs-Abgleich liest Bewertung und Notizfelder der Collection nicht mehr (`DiscogsNote` entfällt); eine geänderte Bewertung zählt nicht mehr als „aktualisiert“.
- Die älteren Schemata verweisen jetzt ausdrücklich auf ihre eigenen Modellversionen statt auf die globalen Namen, damit sie eingefroren bleiben.
- Alle Typnamen (`Release`, `RecordCopy`, …, `DiscogsFolder`, `DiscogsAccount`) zeigen gesammelt auf V15.

# Export ohne Zustand, Notizen und Bewertung · 25.09.2026

- Die Spaltengruppe „Exemplar“ enthält nur noch Discogs-Ordner und Hinzufügedatum (Wantlist: Hinzufügedatum). „Zustand Platte“, „Zustand Hülle“, „Notizen“ und „Bewertung“ sind entfallen, ebenso `DiscogsNote.fieldTitle`.
- Der Szenario-Test prüft den Schutz vor Excel-Formeln jetzt an einem Label, das mit „=“ beginnt.
- Löschhinweis auf der Regalseite erwähnt keine Notizen mehr.

# Eigene Angaben pro Exemplar entfernt · 25.09.2026

- **Zustand, Kaufpreis, Kaufdatum, Notizen und das lokale Hinzufügedatum** sind aus der App verschwunden: aus dem Bearbeiten-Fenster, den Demo-Daten und dem Datenmodell. Neues Schema **V14** (leichte Migration von V13); vorhandene Werte werden dabei verworfen. Export und Sicherung enthielten sie nicht – die Export-Spalten „Zustand“, „Notizen“ und „Bewertung“ kommen aus Discogs und bleiben.
- **Bearbeiten-Fenster**: nur noch „Nicht im Regal“.
- Entfallen: `PriceInput` samt Test, die `edit:`-Parameter von `PositionService.move`, `unplace` und `setExcluded` (nur noch vom Bearbeiten-Fenster genutzt).
- README und VALIDIERUNG angepasst.

# Detailfenster aufgeräumt, Standort prominent, Vergrößern im Popover · 25.09.2026

- **Popover der Übersicht**: Ein runder Glas-Knopf oben rechts (↖↘) öffnet das Detailfenster. Damit ist es auch in der Coveransicht ohne Rechtsklick erreichbar.
- **Detailfenster**: Zustand, Kaufpreis, Kaufdatum, Hinzugefügt, Notizen, Discogs-Notizfelder, Bewertung und der Hinweis „Gespeicherter Stand …“ sind entfernt. Das Fenster liegt auf Glas.
- **Standort**: eigene Glas-Karte direkt unter Cover und Metadaten, Fach groß, daneben „Im Regal anzeigen“ bzw. „Platz im Regal finden“ als hervorgehobener Knopf. Der Discogs-Ordner steht jetzt klein bei den Metadaten.

# Platten-Popover der Übersicht verschlankt · 25.09.2026

- Ein Klick auf ein Cover zeigt nur noch Cover, Interpret, Titel, Label, Jahr, Style, Trennlinie und Tracklist. Standort und der Schalter „Nicht im Regal“ sind entfallen; „Nicht im Regal“ bleibt über Rechtsklick, Mehrfachauswahl, Bearbeiten und die Fach-Tabelle erreichbar.
- Die Exemplar-Auswahl bei mehreren Exemplaren unter einem Cover (`GroupedRecordPopover`) ist entfernt: Sie unterschied die Exemplare nur nach Standort, alles andere gehört zum gemeinsamen Release.

# Interpretennamen, einheitliches Discogs-Mapping, Laufmarkierung · 25.09.2026

- **Interpretennamen**: Aus Discogs' Trennzeichen „,“ wurde „Moby , Kid“; ein leeres oder fehlendes Trennzeichen ergab doppelte Leerzeichen. Jetzt „Moby, Kid“ – ein Komma steht direkt am Namen, jedes andere Trennzeichen („&“, „Feat.“, „Vs.“) zwischen Leerzeichen, ein fehlendes gilt als Komma (`DiscogsBasicInformation.artistLine`). Die eigene Sammlung übernimmt das beim nächsten Sync.
- **Ein Weg für Sync und Einzel-Nachladen**: „Discogs-Daten aktualisieren“ setzte Interpret, Label, Format und Cover mit einer eigenen Kopie der Sync-Logik und wählte das Cover anders. Jetzt nutzt es `DiscogsBasicInformation.apply` und ergänzt nur Tracklist und Land; das Cover ist in beiden Fällen das Hauptbild.
- **Laufmarkierung**: Eine zweite Instanz, die die Sammlung nicht öffnen darf, überschrieb die Markierung „App läuft“ der ersten und löschte sie beim Beenden – ein späterer Stromausfall der ersten wäre beim nächsten Start nicht gemeldet worden. Die Markierung geht jetzt an die laufende Instanz zurück.
- `StorageError` („Plattenregal ist bereits geöffnet“) ist als nutzerlesbarer Fehler eingeordnet und im Fehlermeldungs-Test enthalten.

# Absturz der Statistik nach „Alles zurücksetzen“, toter Code entfernt · 25.09.2026

- **Absturz behoben**: Die Statistik hält ihre Platten in einem eigenen Datenbank-Kontext, der vom Löschen anderswo nichts erfährt. Nach „Alles zurücksetzen“ brachte das Nachladen von Fach oder Release einer dieser Platten SwiftData zum Absturz – mit einem Probe-Test nachgewiesen. Das Statistik-Modell lässt jetzt beim Zurücksetzen sofort alle Platten los, die Seite schließt offene Detail- und Filterfenster und lädt neu.
- **Toter Code entfernt** (281 Zeilen weniger, 185 neu):
  - Fehlerbanner im Hauptfenster, das nur durch seinen eigenen „Erneut versuchen“-Knopf ausgelöst werden konnte – samt einer Abfrage über alle Releases bei jedem Neuzeichnen.
  - Die Sync-Variante für ein einzelnes Release (wurde nie gestartet) mit ihren Zweigen beim Laden, Speichern und in der Statusmeldung.
  - Die Sortierung nach Jahr: Sortiert wird nur alphabetisch (`SortingService.sorted(_:)`, `PositionService.sortAlphabetically(_:)`).
  - Nur von Tests genutzte Funktionen – zwei eigene Suchfunktionen, eine Filterhülle für „Platte hinzufügen“, ein zweiter Einstieg für den Token-Test. Die Tests prüfen jetzt die Wege der App (`SearchIndex`, `candidates`, `startTest`).
  - Zwei ungenutzte Stil-Modifier, ein nie gesetzter Umgebungswert, ein ungenutzter Vorschau-Container, überflüssige Variablen.
- `DiscogsSearchModel.swift` enthielt kein Suchmodell mehr und heißt jetzt `MetadataRefreshService.swift` und `DiscogsSettingsModel.swift`. Die Titel der Discogs-Notizfelder gehören zum Datentyp (`DiscogsNote.fieldTitle`) statt zur Detailansicht, aus der der Export sie bisher holte.

# Große Views aufgeteilt · 25.09.2026

- `AppSettingsView.swift` (1.725 Zeilen) → `Views/Settings/`, eine Datei pro Tab.
- `KallaxView.swift` (2.611 Zeilen) → `Views/Shelf/`: Seite, Suche und Einsortieren, Regalbild, Fach-Tabelle, Fachoptionen, „Platte hinzufügen“.
- `StatisticsView.swift` (1.356 Zeilen) → Seite, Karten, Diagramme.
- Inhalt unverändert (Zeile für Zeile geprüft); nur Typen, die jetzt aus anderen Dateien gebraucht werden, sind nicht mehr `private`.

# Einzelinstanz-Sperre, Zurücksetzen in einem Schritt, Änderungszähler · 25.09.2026

- **Nur eine Instanz öffnet die Sammlung**: Eine Sperrdatei neben der Datenbank (`.Plattenregal.lock`) verhindert, dass zwei Instanzen – etwa aus Xcode und aus dem Finder – gleichzeitig in die Sammlung schreiben. Die zweite zeigt „Plattenregal ist bereits geöffnet“. Eine Instanz, die gerade beendet wird, bekommt fünf Sekunden; die Demo braucht die Sperre nicht, der Wechsel in die Demo und zurück bleibt unberührt.
- **„Alles zurücksetzen“ in einem Speichervorgang**: Bisher waren nach dem ersten von zwei Speichervorgängen die Platten gelöscht; scheiterte der zweite, blieben Releases und Konto stehen. Jetzt geht alles oder nichts; das erste Regal wird danach neu angelegt (oder beim nächsten Start).
- **Änderungszähler in `LibraryChanges`** statt im Discogs-Sync-Service: Jeder Schreibweg meldet dort, ob Platten, Tracklisten, Regale oder Positionen betroffen sind; Seiten bauen ihre Zwischenspeicher darauf neu auf.
- **Regalseite**: Die Signatur, an der die Seite ihre Fach-Statistik neu berechnet, liest nicht mehr bei jedem Neuzeichnen jede Platte samt Fach, sondern nur die Zähler und ein paar Anzahlen.
- **Protokoll** rotiert ab 2 MB auch während einer Sitzung; der Absturz-Handler folgt der neuen Datei.
- Eine Compiler-Warnung behoben; Kommentar zu den Schema-Aliasen (V13 übernimmt die Modelle von V12).

# Schneller einsortieren, sortieren und exportieren · 25.09.2026

Gemessen mit einer Sammlung in der Größe der echten (841 Platten, 868 Wantlist-Einträge, 12 Fächer; `-O`) und dem Test mit 10.000 Platten. Ursache war fast immer SwiftData: Jeder Lesezugriff auf eine Eigenschaft kostet Mikrosekunden, und nach jedem Speichern liefert die Abfrage der Seite Exemplare, deren Releases einzeln neu geladen werden (rund 0,1 ms je Platte).

- **Regalseite nach dem Einsortieren**: Statistik und Buchstabenbereich werden nur noch für Fächer neu berechnet, deren Platten sich geändert haben; die übrigen kommen aus einem Zwischenspeicher (`ShelfContentCache`). Pro „+“ 104 ms → 9 ms. Release-Daten folgen wie bisher `libraryVersion`.
- **Einsortieren speichert nur, was sich ändert**: Beim Umnummerieren eines Fachs werden nur Positionen geschrieben, die tatsächlich anders sind – hinten angefügt ist das eine einzige Platte statt des ganzen Fachs. Verschieben + Speichern 13,9 ms → 2,7 ms.
- **Sortieren ohne Datenbank-Zugriffe im Vergleich**: Alphabetische Reihenfolge, Reihenfolge im Fach (Regalseite, Platzsuche, Fachstatistik) und die Regal-Reihenfolge im Export lesen ihre Schlüssel einmal pro Platte statt bei jedem der ~n·log n Vergleiche. Collection aufbauen 60 ms → 38 ms, Export-Tabelle 183 ms → 112 ms (10.000 Platten: 3,2 s → 1,5 s).
- **Buchstabenbereiche und Platzsuche** bestimmen erste und letzte Platte eines Fachs in einem Durchgang, statt alle Schlüssel zu sortieren. Platz finden 19 ms → 4,6 ms (10.000 Platten: 531 ms → 115 ms).
- Neuer Test `LibraryTests.shelfContentCacheMatchesAFullRecompute`: Der Zwischenspeicher liefert nach Einsortieren und nach geänderten Release-Daten dieselben Beschriftungen und Statistiken wie eine vollständige Neuberechnung.

# Export, Sicherung und Cover-Cache ohne Hänger · 25.09.2026

- **Export**: Die Platten werden weiter auf dem Haupt-Thread gelesen, damit die Liste in sich stimmig ist. Das Erstellen von PDF bzw. CSV und das Schreiben in den Zielordner (z. B. iCloud Drive oder ein Netzlaufwerk) laufen jetzt im Hintergrund. Das gilt für den automatischen Export, „Jetzt exportieren“ und „Als … exportieren“. Die Knöpfe sind gesperrt, solange ein Export läuft; ein zweiter automatischer Lauf wartet auf die nächste Prüfung.
- **Automatische Sicherung**: Die Belegung wird weiter auf dem Haupt-Thread erfasst. Der Vergleich mit der neuesten Sicherung, das Schreiben und das Löschen alter Dateien laufen im Hintergrund. Beim Beenden der App wird weiterhin sofort und synchron gesichert; das gilt auch, wenn gerade eine Sicherung im Hintergrund läuft (schlimmstenfalls entsteht dann eine doppelte Datei).
- **Cover-Cache**: Heruntergeladene Daten werden nur gespeichert, wenn sie ein vollständiges Bild sind. Beim Start löscht die App im Hintergrund Cover, die 90 Tage lang nicht angezeigt wurden, und über 1 GB die am längsten ungenutzten. Gelöschte Cover werden bei Bedarf einfach neu geladen.
- **Schnelleres Lesen für Sicherung und Export**: Exemplare werden zusammen mit Release und Fach in einem Rutsch geladen, statt jedes Release einzeln nachzuladen. Gemessen mit 10.000 Platten (Debug): Sicherung erstellen 1,55 s → 0,69 s, Export-Tabelle mit allen Spalten 4,1 s → 3,3 s.
- Neuer Test für das Aufräumen des Cover-Caches; insgesamt 162 Tests grün.

# Platten als „Vermisst“ markieren · 24.09.2026

Für das Einsortieren: Platten, die laut App in ein Fach gehören, aber gerade vermisst werden (vermutlich noch in einem Fach, das noch nicht sortiert ist), lassen sich markieren und später wieder als gefunden kennzeichnen. Die Markierung gibt es nur auf der Regalseite; Collection, Statistik und Export bleiben unverändert.

- **„Platte hinzufügen“**: Jede Zeile hat links neben „+“ einen **Pause-Knopf**. Er stellt die Platte zurück – die Zeile wird blasser und trägt das rote Etikett „Vermisst“, bleibt aber in der Liste. Ein zweiter Klick („Wieder gefunden“) hebt das auf; wird sie mit „+“ oder Doppelklick einsortiert, gilt sie ebenfalls als gefunden. Die Unterzeile zählt die zurückgestellten Platten in Rot und wird dafür nie abgeschnitten.
- **Plattentabelle eines Fachs**: Rechtsklick → „Als vermisst markieren“ bzw. „Wieder gefunden“. Die Platte behält Fach und Position.
- **Übersicht neben der Suche**: „N vermisst“ (rot) öffnet eine Liste aller markierten Platten mit Fach bzw. „noch ohne Fach“; je Platte „Im Fach zeigen“ bzw. „Platz im Regal finden“ und „Wieder gefunden“.
- **Streifen mit den Plattenrücken**: Eine fehlende Platte erscheint als roter Umriss statt als Rücken – genau die Lücke, die im echten Fach zu sehen ist; darunter „· 1 vermisst“ bzw. das Etikett bei der gewählten Platte.
- **Suche und Platzsuche**: Treffer tragen das Etikett. Die Karte „Platz im Regal finden“ weist auf die Markierung hin („hier sollte sie stehen“ bzw. „beim Einsortieren gilt sie als gefunden“), „Gefunden“ bzw. „Hier einsortieren“ hebt sie auf. Ist ein Nachbar („zwischen … und …“) selbst vermisst, steht das dabei – er taugt im Regal nicht zur Orientierung.
- **Was die Markierung aufhebt**: Einsortieren von Hand (Platte hinzufügen, Platzsuche), „Wieder gefunden“, „Nicht im Regal“, Löschen aus der Sammlung, „Standorte zurücksetzen“ und „Alles zurücksetzen“. Herausnehmen, „Rückgängig“ und Verschieben im Doppelklick-Editor behalten sie – nur wer die Platte einsortiert, hat sie in der Hand. Platten in deaktivierten Regalen oder außerhalb der aktuellen Collection erscheinen nicht in der Liste; ihre Markierung bleibt und ist wieder da, sobald sie es wieder sind.
- **Sicherung**: Markierungen sind nicht Teil der Sicherungsdatei und bleiben beim Wiederherstellen stehen – außer bei Platten, die die Sicherung auf „Nicht im Regal“ setzt.
- **Demo**: Eine Platte im Wohnzimmer ist als vermisst markiert.
- Datenbank-Schema **V13** mit neuem Modell `MissingCopyMark` (nur Exemplar-ID und Zeitpunkt); leichte Migration von V12, bestehende Daten bleiben unverändert.
- **Fehlermeldungen**: Scheitert das Speichern, heißt es „„Vermisst“ (bzw. „Wieder gefunden“) konnte nicht gespeichert werden – die Platte ist unverändert …“ statt der allgemeinen Speicher-Meldung; die Datenbank-Ursache steht im Protokoll.
- **Protokoll**: „Vermisst“ und „Wieder gefunden“ mit Plattenname; beim Einsortieren „· nicht mehr „Vermisst““; aufgehobene Markierungen durch „Nicht im Regal“ oder eine wiederhergestellte Sicherung; das Schließen von „Platte hinzufügen“, weil in den Einstellungen Regale geändert wurden.

## Regalseite, Grenzfall-Prüfung

- **Absturzgefahr beseitigt**: Nach „Alles zurücksetzen“ hielt die Regalseite noch gelöschte Platten fest (Auswahl, Platzsuche, Rückgängig-Hinweis, Editor, offenes „Platte hinzufügen“) – ein späterer Zugriff konnte abstürzen. Jetzt werden diese Verweise beim Zurücksetzen geleert.
- Wiederherstellen einer Sicherung, Regale umbauen oder Standorte zurücksetzen im Einstellungsfenster schließt ein offenes „Platte hinzufügen“, die Fachoptionen und die Rückfrage „Alphabetisch sortieren“ – deren Fach konnte gelöscht sein. Fachoptionen speichern nie in ein gelöschtes Fach; „+“ und Pause bei einer inzwischen gelöschten oder schon einsortierten Platte entfernen nur die Zeile.
- „Im Regal anzeigen“ für eine Platte in einem **deaktivierten Regal** nennt jetzt dieses Regal und wie es sich aktivieren lässt, statt „Hier steht …“ ohne sichtbares Fach.
- „N nicht in der Collection“ zählt und entfernt nur Platten aus Regalen, die auf der Seite zu sehen sind – nicht mehr unsichtbar aus deaktivierten Regalen.
- Neue Tests für Markierung, Aufheben durch Regal-Aktionen, Wiederherstellen, deaktivierte Regale und die Fehlermeldung; insgesamt 161 Tests grün.

# Mehrere Regale und neue Einstellungen · 24.09.2026

- **Mehrere Regale** (Einstellungen › Regal): beliebig viele Regale mit eigenem Namen und eigener Größe anlegen, umbenennen, umsortieren, aktivieren/deaktivieren und – wenn leer – löschen. Größen als **IKEA-KALLAX-Vorlagen** mit Maßen (1 × 2 bis 5 × 5, hochkant oder quer, z. B. „2 × 4 · 77 × 147 cm“) oder eigene Größe (1–6 Spalten/Reihen). Beim Verkleinern bleiben die Fächer in Lesereihenfolge; wegfallende Fächer müssen leer sein. Mindestens ein Regal bleibt aktiv.
- Bedienung per Tastatur: in den Einstellungen ← / → zwischen den Regalen, Leertaste aktiviert/deaktiviert; auf der Regalseite ⌘← / ⌘→ bzw. der Regal-Umschalter über dem Möbel.
- Inaktive Regale behalten ihre Platten, sind aber auf der Regalseite ausgeblendet und werden beim Einsortieren übersprungen; Ortsangaben nennen sie mit „(inaktiv)“. Bei mehreren Regalen steht der Regalname vor jeder Ortsangabe.
- **Fach-Beschriftung** wählbar: Buchstabenbereich („A – Be“) oder Fachnummer („Fach 3“) – gilt für Regalseite, Listen, Details und Export.
- Neuer Tab **Allgemein**: Startseite (Collection, Wantlist, Statistik, Regal), Erscheinungsbild (System/Hell/Dunkel) und Akzentfarbe.
- **Sicherung**: Anzahl der letzten Stände (5/10/20/50) und Tagesstände (keine bis 90 Tage) einstellbar; eigener Speicherort, z. B. in iCloud Drive (vorhandene Sicherungen werden mitkopiert). Sicherungen enthalten jetzt auch die Regale; ältere Sicherungsdateien ohne Regale lassen sich weiter wiederherstellen.
- **Export**: automatischer Export täglich, wöchentlich oder monatlich in einen gewählten Ordner, mit den Export-Einstellungen des Tabs; „Jetzt exportieren“. Die CSV hat eine neue Spalte „Regal“, „Fach“ ist die Nummer im Regal.
- Neuer Tab **Daten**: Speicherplatz (Sammlung, Cover-Cache, Sicherungen, Protokoll) mit Leeren für Cover-Cache und Protokoll; Diagnose mit Protokoll-Export und Discogs-Rate-Limit dieser Sitzung; Zurücksetzen von Standorten, Einstellungen oder allem (mit Sicherung der Belegung vorher).
- **Daten** robuster: „Einstellungen/Alles zurücksetzen“ behält Speicherort und Aufbewahrung der Sicherungen – vorher verschwanden Sicherungen in einem eigenen Ordner (inkl. der Sicherheitssicherung des Resets) aus der Liste, und die kleinere Standard-Aufbewahrung hätte ältere Stände gelöscht. Bricht „Alles zurücksetzen“ in der Datenbank ab, werden offene Löschungen verworfen statt später mitgespeichert; nach gelöschter Sammlung werden Cover und Einstellungen in jedem Fall zurückgesetzt, ein nicht löschbarer Token wird gemeldet. Die Speicherplatz-Anzeige rechnet nicht mehr alle 5 Sekunden auf dem Main-Thread (Sicherungsordner in iCloud Drive konnte die Einstellungen blockieren) und zählt die Datenbank wie die übrigen Ordner nach belegtem Platz.
- **Daten**, zweite Prüfung: „Alles zurücksetzen“ stoppt vorher den Tracklisten-Download, der nach einem Sync weiterläuft und sonst auf gerade gelöschte Releases zugegriffen hätte; danach verschwinden alte Sync-Meldungen, und die Fach-Beschriftungen werden neu berechnet (auch nach „Standorte zurücksetzen“). Die Gesamtgröße zählt Sicherungen in einem eigenen Ordner (z. B. iCloud Drive) nicht mehr zum Platz der App, wie es der Hinweis schon sagte. „Im Finder zeigen“ beim Protokoll öffnet den Ordner, wenn die Datei noch nicht existiert.
- **Daten**, dritte Prüfung: „Alles zurücksetzen“ schaltet den automatischen Export jetzt ab, bevor es auf das Leeren des Cover-Caches wartet – vorher konnte ein fälliger Export in diesem Moment die letzte gute Exportdatei mit einer leeren Liste überschreiben. „Wird berechnet …“ bleibt nicht mehr dauerhaft stehen, wenn die Datenbank nicht gefunden wird; der Hinweis bei „Sammlung“ verspricht nicht mehr, dass die Datenbankdatei nach dem Zurücksetzen leer ist.
- **Export und Sicherung** geprüft: Der automatische Export überspringt eine leere Liste (vor dem ersten Sync, nach Datenverlust oder „Alles zurücksetzen“), statt die letzte gute Datei zu ersetzen, und schreibt nach Einschalten oder Ordnerwahl innerhalb von Sekunden statt erst bei der nächsten halbstündlichen Prüfung. „Jetzt exportieren“ ist während eines Syncs gesperrt. Ein nicht mehr erreichbarer Export- oder Sicherungsordner wird als solcher angezeigt statt als „kein Ordner gewählt“ bzw. „Im Ordner der App“; „Standard“ ist dann wählbar. Lassen sich die Sicherungen beim Ordnerwechsel nicht kopieren, bleibt der alte Ordner eingestellt. Nach dem Wiederherstellen einer Belegung mit Regalen werden die Fach-Beschriftungen neu berechnet.
- **Sicherung** schneller: Nach jeder Regal-Änderung liest die automatische Sicherung nur noch die neueste Datei (Vergleich) und räumt alte Stände anhand der Uhrzeit im Dateinamen auf – vorher wurden alle Sicherungsdateien zweimal eingelesen, bei vielen Ständen und großer Sammlung spürbar auf dem Main-Thread. Die Einstellungen lesen die aktuelle Belegung nicht mehr bei jedem Neuzeichnen, sondern beim Öffnen, nach Änderungen und beim Zurückkehren ins Fenster.
- **Fehlermeldungen**: Regal-Fehler (z. B. „Mindestens ein Regal muss aktiv bleiben“) und Zurücksetzen-Fehler erschienen bisher nur als „Da ist etwas schiefgelaufen“ – alle eigenen Fehlertypen tragen jetzt die Kennzeichnung `UserFacingError`, sodass ein neuer Fehlertyp nicht mehr unbemerkt auf den allgemeinen Text zurückfällt. Neue, genauere Meldungen für einen nicht erreichbaren Ordner, einen fehlgeschlagenen Wechsel des Sicherungsordners und eine Zeitüberschreitung bei Discogs; ein fehlgeschlagener automatischer Export unterscheidet „Export nicht erstellt“ von „Datei nicht gespeichert“ und steht nur noch einmal im Protokoll. Die Fehlerseite beim Start hat einen Knopf „Protokoll im Finder zeigen“.
- **Absturz-Protokoll**: Der Absturzblock enthält die App-Version; beim nächsten Start steht in Klartext, welcher Absturz es war und wann (statt nur „nicht normal beendet“). Die Startzeile nennt die Ladeadresse, damit sich die Aufrufliste mit `atos` auflösen lässt. Ein eigener Signal-Stack sorgt dafür, dass auch ein Stack-Überlauf protokolliert wird.
- **Demo-Modus für alle**: „Plattenregal → Demo starten …“ und Einstellungen → Allgemein starten die App neu mit einer Beispielsammlung (rund 50 Alben mit auf dem Gerät gezeichneten Covern, zwei Regale mit gesperrtem Deko-Fach, Platten ohne Fach, Wantlist, 18 Monate Wertverlauf). Alles ist bedienbar, nichts wird gespeichert; ein Banner auf jeder Seite – bündig mit Covern bzw. Karten – bietet „Demo beenden“. Getrennt von den echten Daten: Sammlung im Arbeitsspeicher, eigene Einstellungs-Domäne (`AppDefaults`), Sicherungen und Cover im temporären Ordner, Discogs aus, Schlüsselbund unberührt. Vorher gab es die Demo nur im Debug-Build per Startargument, und dort änderten Einstellungen in der Demo die echten.
- **Demo, Grenzfälle**: Der Neustart in die Demo übergab sein Startargument nicht (die Sandbox verwirft es) und öffnete stattdessen die echte Sammlung – jetzt über eine eine Minute gültige Anfrage in den Einstellungen, die der nächste Start übernimmt. Beim Wechsel laufen alte und neue Instanz kurz gleichzeitig: Die Markierung „läuft“ trägt jetzt die Prozess-ID, sodass weder eine falsche Meldung „nicht normal beendet“ entsteht noch die alte Instanz die Markierung der neuen löscht. In der Demo keine Discogs-Links (die Beispiel-IDs gehören bei Discogs zu fremden Releases, auch im CSV), keine Aktualisierungs-Aktionen und kein automatischer Tracklisten-Abruf mit Fehlermeldung. Automatische Sicherung, Speicherort und Aufbewahrung sind gesperrt, damit die Demo nie echte Sicherungen aufräumt; vorgeschlagene und automatisch geschriebene Dateien tragen „(Demo)“ im Namen. Leere Seiten nach „Alles zurücksetzen“ bieten „Demo neu starten“ statt „Synchronisieren“; „Demo neu starten“ auch im Menü und unter Allgemein. Der Start-Dialog weist auf eine laufende Synchronisierung hin.
- **Demo, zweite Prüfung**: Der Wechsel wird abgelehnt, wenn Plattenregal noch ein zweites Mal läuft (z. B. aus Xcode) – so sind nie zwei Instanzen auf derselben Sammlung offen; ein Doppelklick startet keine zweite neue Instanz. Das Protokoll schreibt mit `O_APPEND`, damit beim kurzen Nebeneinander zweier Instanzen keine Zeilen verloren gehen; ein fehlgeschlagenes Öffnen konnte vorher die ganze Protokolldatei durch eine Zeile ersetzen. Automatischer Export in der Demo gesperrt (Oberfläche und Service). Lässt sich die Beispielsammlung nicht aufbauen, erklärt eine eigene Fehlerseite das und bietet „Demo beenden“, statt von der eigenen Sammlung zu sprechen. Neuer Test für die nur eine Minute gültige Startanfrage.
- **Demo, dritte Prüfung**: Jede Protokollzeile aus der Demo ist mit „Demo ·“ markiert, damit ein „Alles zurückgesetzt“ aus der Demo bei der Fehlersuche nie wie eines der eigenen Sammlung aussieht. Die Demo-Einstellungen fallen im Fehlerfall nicht mehr stillschweigend auf die echten zurück. Ein gescheiterter Wechsel in die Demo meldet, dass die eigene Sammlung geöffnet bleibt, statt zum Beenden zu raten.
- **README**: Die Collection wird nicht beim Start abgeglichen, sondern auf Wunsch – korrigiert.
- **STATISTIK.md** neu gefasst: beschreibt die heutige Statistik-Seite (Abschnitte, Drill-down, Sammlungswert als einzige Discogs-Anfrage) statt der entfernten Einzelpreis-Abfragen und der gelöschten `MarketValueService.swift`. **VALIDIERUNG.md** beginnt mit dem aktuellen Prüfstand (146 Tests) und benennt, was nicht geprüft wurde; ältere Prüfstände sind als Verlauf gekennzeichnet.
- **README** auf den aktuellen Stand gebracht (Discogs als einzige Quelle, mehrere Regale, Einstellungs-Tabs, Speicherorte, Sicherung, Export, Fehlermeldungen und Protokoll).
- Datenbank-Schema V12 (neues Modell `Cabinet`); bestehende Fächer 1–12 landen automatisch im ersten Regal „Regal“ (4 × 3), Nummern, Sperren und Platten bleiben unverändert.
- Neue Tests: `CabinetTests` (13), insgesamt 141 Tests grün.
- **Grenzfälle, Gesamtprüfung**: Releases, die Discogs nicht mehr kennt (404 oder anderer releasebezogener 4xx-Fehler), wurden bei jedem Start erneut nach ihrer Tracklist gefragt und blendeten dabei jedes Mal „Synchronisierung abgeschlossen“ ein – jetzt gelten sie als abgefragt und kommen erst mit der regulären Auffrischung wieder dran (403 und unlesbare Antworten weiterhin nicht, die können am Token oder an Discogs liegen). Der automatische Export bleibt nicht mehr bis zu einem Datum in der Zukunft stehen, wenn die Uhr des Macs beim letzten Lauf falsch ging. „Rückgängig“ nach dem Herausnehmen einer Platte greift nicht mehr auf ein inzwischen gelöschtes Fach zu (Regal verkleinert, Sicherung wiederhergestellt, zurückgesetzt) – das konnte abstürzen; ebenso speichert „Exemplar bearbeiten“ nicht mehr in ein zwischenzeitlich gelöschtes Exemplar. Ein Token mit Leerzeichen, Zeilenumbruch oder Sonderzeichen in der Mitte wird mit klarer Meldung abgelehnt und nie in den HTTP-Header geschrieben. Beim Wiederherstellen einer unvollständigen Sicherung können neu angelegte Fächer keine Nummer eines gleichzeitig gelöschten Fachs mehr bekommen; Regale ohne Namen heißen „Regal n“. Der Cover-Cache im Arbeitsspeicher ist zusätzlich auf 256 MB begrenzt (vorher nur auf 320 Bilder, bei großen Covern über 1 GB). Neue Tests, insgesamt 151 Tests grün.
- **Grenzfälle, zweite Prüfung**: Das Platten-Popover fragt eine Tracklist, die Discogs nicht hat, nicht mehr bei jedem Öffnen neu an (vorher je eine Anfrage und ein kurzer Ladekreisel), und lädt während einer laufenden Synchronisierung nichts nach, weil der Abgleich dieselben Releases gerade neu schreibt. Ein dauerhaft nicht erreichbarer Export-Ordner steht nur noch einmal im Protokoll statt alle 30 Minuten.
- **Grenzfälle, dritte Prüfung (Szenarien und laufende App)**: Neue `ScenarioTests` spielen Abgleich ohne Netz, Netzverlust bei den Tracklisten, Discogs-Bremse, gelöschte Fächer unter offenen Ansichten und eine Sammlung mit 10.000 Platten durch. Dabei gefunden und behoben: Das Entfernen der Discogs-Nummer („Moby (2)“ → „Moby“) lief über einen regulären Ausdruck mit ~60 µs pro Aufruf und steckte in jeder Anzeige, Sortierung, Beschriftung und Platzsuche – jetzt eine gleichwertige einfache Zeichenprüfung (Test vergleicht sie mit dem alten Ausdruck); Statistik bei 10.000 Platten 3,2 s → 0,4 s, Platz finden 1,2 s → 0,5 s, Export-Tabelle 7 s → 4 s. Detailfenster und Platten-Popover berechneten die Beschriftungen aller Fächer bei jedem Neuzeichnen neu (bei großer Sammlung über eine Sekunde pro Klick, z. B. auf „Nicht im Regal“) – jetzt einmal pro Öffnen bzw. von der Collection-Seite übernommen. Die Collection-Seite zeigte nach dem Einsortieren auf der Regalseite bis zum nächsten Sync „–“ bzw. veraltete Fachbereiche; neues Signal `placementsVersion`, neu berechnet wird, sobald die Seite sichtbar ist. Insgesamt 158 Tests grün.
- Schneller: Regal anlegen, ändern oder löschen baut nicht mehr Collection- und Wantlist-Listen samt Suchindizes neu auf (eigenes Signal `shelvesVersion` nur für die Fach-Beschriftungen); die Regal-Einstellungen berechnen die Beschriftungen nur noch bei echten Änderungen statt bei jedem Neuzeichnen.

# Export und Sicherung · 24.09.2026

- Neuer Einstellungs-Tab **Export**: Collection oder Wantlist als CSV (Spaltengruppen Standort, Exemplar, Discogs-Verweise und Tracklist wählbar; Semikolon oder Komma; UTF-8 mit BOM für Excel) oder als druckfertige PDF-Liste im A4-Querformat, in Regal-Reihenfolge mit einer Überschrift je Fach.
- Neuer Einstellungs-Tab **Sicherung**: Fach-Belegung, gesperrte Fächer und „Nicht im Regal“ als JSON sichern und wiederherstellen, mit Vorschau und automatischer Sicherung des aktuellen Stands davor. Automatische Sicherung nach jeder Regal-Änderung und beim Beenden; erhalten bleiben die letzten 10 Stände plus der letzte Stand jedes Tages der vergangenen 14 Tage. Ein leeres Regal wird nicht automatisch gesichert, damit es nach einem Datenverlust keine guten Stände verdrängt.
- Verständliche Fehlermeldungen für Export, Speichern, Öffnen und Wiederherstellen statt der allgemeinen Speicher-Meldung; Abbrechen im Sichern-/Öffnen-Fenster gilt nicht als Fehler. Fehlgeschlagene automatische Sicherungen werden im Tab angezeigt.
- Protokoll: Exporte, Sicherungen, Wiederherstellungen, nicht lesbare Sicherungsdateien und Fehler der automatischen Sicherung werden festgehalten.
- Grenzfälle: Wiederherstellen wird abgelehnt, wenn keine Platte der Sicherung in der Sammlung ist (z. B. vor dem ersten Sync nach Datenverlust oder bei fremdem Konto), und die Vorschau warnt, wenn mehr als die Hälfte fehlt; Wiederherstellen ist während eines Syncs gesperrt (nicht während des Tracklist-Downloads); zu große Dateien werden nicht geladen; Demo-Daten landen nie im Sicherungsordner; der Sicherungsordner listet und löscht nur eigene Dateien; beim Bestätigen wird die Vorschau erneut geprüft; Dateinamen und die CSV-Spalte „Hinzugefügt“ verwenden das lokale Datum statt UTC; PDFs tragen einen Dokumenttitel; doppelte oder ungültige Einträge in Sicherungsdateien werden bereinigt; CSV-Werte, die mit = + - @ beginnen, werden als Text geschützt, damit Excel sie nicht als Formel ausführt.
- Neue Tests: `ExportTests`, `BackupTests`.

# Wantlist · 21.09.2026

- Beim Appstart wird nur noch die Discogs-Collection synchronisiert. Die Wantlist bleibt vollständig lokal, bis „Wantlist synchronisieren“ in der Wantlist-Ansicht gewählt wird.
- Auch Sammlungs- und Metadatenabgleiche verwenden nur noch den Collection-Scope. Die Wantlist-Aktion wurde aus den Einstellungen entfernt und befindet sich direkt oberhalb der Wantlist.
- Neue adaptive Kartenansicht: zwei Spalten bei normaler Fenstergröße und drei Spalten bei breiten Fenstern.
- Sortierung nach dem tatsächlichen Discogs-Zeitpunkt „zuletzt hinzugefügt“, einschließlich korrekter Zeitzonenbehandlung.
- Eigene Suche über Interpret, Titel, Label, Katalognummer, Land, Format, Genre, Style, Notizen und Release-ID.
- „Veröffentlichung aktualisieren“ wurde aus jeder Wantlist-Karte entfernt.
- Visuell mit lokalen Beispieldaten bei zwei und drei Spalten sowie mit gefilterten Suchergebnissen geprüft.
- Debug-Build und vollständige XCTest-Suite: 74 Tests, 0 Fehler. Finaler Universal-Release-Build erfolgreich.

# Einheitliches Seitenraster · abschließende Überarbeitung

Alle Hauptansichten verwenden gemeinsame Typografie, Abstände und Leerzustände. `AppAppearance.swift` enthält `AppPageLayout`, `AppPageHeading`, `AppEmptyState` und die gemeinsame native Glas-/Materialfläche. Suche und Regaloptimierung sind ausdrücklich an die verfügbare Fenstergeometrie gebunden: Kopfbereich oben, Controls auf einer gemeinsamen Achse, restliche Fläche für Ergebnisse oder einen mittigen Leerzustand. KALLAX, Statistik, Sammlung, Wantlist, manuelles Hinzufügen und Dialoge verwenden dieselben Schriftrollen und Außenabstände.

Die Detailspalte des Hauptfensters ist jetzt ebenfalls an die verfügbare Fensterhöhe gebunden. Dadurch schieben leere Ansichten wie Favoriten und Manuell hinzufügen weder die Seitenleiste noch ihre Bedienelemente unter die Titelleiste. Der Wechsel zwischen beiden Bereichen wurde im laufenden Debug-Build bei normaler und vergrößerter Fensterbreite visuell geprüft; der Release-Build und die Codesign-Prüfung waren erfolgreich.

# Layout und Typografie · 20.09.2026

- Kompakte adaptive Glasleiste für Ordner, Anzahl, Sortierung, Raster/Liste und Sync direkt unter der Toolbar; bei wenig Platz zwei geordnete Zeilen.
- Kein freier Platz oberhalb der Controls bei leerer Sammlung; Leerzustände mittig in der verbleibenden Inhaltsfläche.
- Native Liquid-Glass-Fläche ab macOS 26, Material-Fallback auf macOS 14/15.
- Gemeinsame abgerundete Systemtypografie, konsistente Überschriften und Abstände für App-Fenster, Einstellungen und Dialoge (`Utilities/AppAppearance.swift`).
- Gleichmäßige Textzeilen und Jahrespositionen in Cover-Karten; Beschriftungen der kompakten Controls bleiben über Accessibility und Tooltips erhalten.
- Einheitliche Dialogränder, korrigierter Wantlist-Leerzustand, besser angeordnete Optimierungs-Controls.

Die Glasfläche verwendet Apples [glassEffect](https://developer.apple.com/documentation/swiftui/view/glasseffect%28_%3Ain%3A%29).

# Statistik-Erweiterung · 20.09.2026

Neuer Hauptbereich Statistik mit Swift Charts, lokalen Auswertungen, persistenter Wert-Historie und getrennten Preis-Caches. Vollständige Dateiliste und technische Beschreibung: [STATISTIK.md](STATISTIK.md).

# Discogs-Synchronisierung

| Status | Datei |
|---|---|
| Geändert | Plattenregal/Discogs/DiscogsAPIClient.swift |
| Geändert | Plattenregal/Discogs/DiscogsDTO.swift |
| Geändert | Plattenregal/Discogs/DiscogsSearchModel.swift |
| Neu | Plattenregal/Discogs/DiscogsSyncDTO.swift |
| Neu | Plattenregal/Discogs/DiscogsSyncService.swift |
| Geändert | Plattenregal/Models/LibraryModels.swift |
| Geändert | Plattenregal/Services/PositionService.swift |
| Geändert | Plattenregal/Storage/LibraryStorage.swift |
| Geändert | Plattenregal/Views/AppSettingsView.swift |
| Geändert | Plattenregal/Views/CollectionView.swift |
| Neu | Plattenregal/Views/DiscogsSyncView.swift |
| Geändert | Plattenregal/Views/RecordDetailView.swift |
| Geändert | Plattenregal/Views/RecordEditor.swift |
| Geändert | Plattenregal/Views/RootView.swift |
| Geändert | Plattenregal.xcodeproj/project.pbxproj |
| Neu | PlattenregalTests/DiscogsSyncTests.swift |
| Geändert | PlattenregalTests/LibraryTests.swift |
| Geändert | README.md |
| Geändert | VALIDIERUNG.md |

Der Original-Projektordner wurde mit diesen Änderungen aktualisiert. Diese Ausgabe enthält zusätzlich eine vollständige Projektkopie. Der Release-Build liegt neben diesem Ordner als `Plattenregal.app`.

Bedienung im aktuellen Stand: Die Collection wird beim Appstart und über die Sammlungs-/Einstellungsaktionen abgeglichen. Die Wantlist wird ausschließlich manuell in der Wantlist-Ansicht synchronisiert. Ordneraktionen stehen am Sammlungsfilter bereit; einzelne Release-Updates bleiben im Kontextmenü der Sammlung. Die neuen Daten werden erst nach vollständig erfolgreichem Laden mit vorhandenen Datensätzen zusammengeführt. Lokale Exemplardaten und KALLAX-Zuordnungen bleiben erhalten. Details und Testergebnisse stehen in `README.md` und `VALIDIERUNG.md`.


## Rubriken vorladen und Zustand erhalten (20.09.2026)

- Alle Rubriken werden beim Fensterstart aus der lokalen Datenbank aufgebaut und behalten ihre SwiftUI-Identität. Scrollpositionen, Auswahl, Filter, Suchergebnisse und Optimierungsvorschläge bleiben beim Rubrikwechsel erhalten.
- Nur die aktive Rubrik nimmt Eingaben entgegen und stellt ihre Toolbar bereit. Der Fenstertitel folgt zentral der aktiven Rubrik.
- Diese ältere Zwischenfassung startete ohne automatischen Discogs-Abgleich. Im aktuellen Stand wird beim Appstart ausschließlich die Collection synchronisiert; die Wantlist bleibt eine explizite Aktion in ihrem eigenen Bereich.
- Lokale Änderungen und abgeschlossene manuelle Synchronisierungen aktualisieren die Statistik weiterhin.
- Die Sammlung filtert und sortiert nur einmal pro View-Auswertung; Sortierschlüssel werden einmal pro Exemplar aufgebaut.
- Der auf 150 Bilder begrenzte Cover-Cache entfernt nur das am längsten unbenutzte Bild statt den gesamten Cache.
- Das Badge „Data provided by Discogs.“ wurde aus allen Ansichten entfernt.
- Seitenleisten-Schalter ohne gewölbten Glashintergrund; Ein-/Ausblenden visuell geprüft. Die normalen macOS-Fensterknöpfe bleiben erhalten. Der violette Aufnahmeindikator wird vom Betriebssystem eingeblendet.
- Prüfung: 66 Tests ohne Fehler; finaler Release-Build erfolgreich. Alle neun Rubriken mit der bestehenden Sammlung geöffnet, Scrollposition bei Rückkehr kontrolliert und Badge-Entfernung visuell bestätigt.
