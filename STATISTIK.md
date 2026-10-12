# Statistik

Dokumentation geprüft am **12.10.2026**, Projektversion **1.1.0 (102026)**.

Die Seite **Statistik** wertet die aktuelle Collection aus und zeigt den Verlauf ihres Discogs-Sammlungswerts. Alles außer dem Sammlungswert wird lokal berechnet, ohne Anfrage an Discogs.

## Bedienung

- Oben in der Toolbar die Rubrik **Statistik** wählen oder **⌘4**.
- Grundlage sind dieselben Platten wie auf der Collection-Seite: die aktive Discogs-Collection des zuletzt synchronisierten Kontos. In Discogs entfernte, lokal noch vorhandene Exemplare zählen nicht mit – so stimmt jede Zahl mit der Liste überein, die sich beim Antippen öffnet.
- **Aktualisieren** – die Seite nach unten ziehen oder **⌘R** – rechnet die Auswertungen neu und ruft den Sammlungswert ab. Nach jedem erfolgreichen Collection-Sync wird der Wert ebenfalls geladen; scheitert nur dieser Abruf, bleibt der Sync gespeichert und eine eigene Meldung erscheint. Wurde nur die Wantlist synchronisiert und das Konto hat noch keine Collection, gibt es nichts zu bewerten – dann ohne Meldung.
- Genres, Styles, Künstler, Labels, Jahre, Formate und Länder öffnen die passenden Platten als gefilterte Collection-Liste – in einem Glasfenster über der Seite, mit dem Namen der Auswahl und ihrer Anzahl links („Downtempo · 7 Platten“) und Raster/Liste rechts, ohne Suchleiste (die Liste ist zum Anschauen). Einzelne Platten öffnen ihre Detailansicht im selben Fensterstil oder zeigen ihren Platz im Regal. Beide Fenster schließen mit einem Klick daneben oder **Esc**, eine Ampel gibt es nicht.
- **Werte beim Überfahren:** In den Kurven (Sammlungswert, Durchschnitt pro Platte, Anzahl) zeigen eine senkrechte Linie und ein Punkt die Stelle, in den Balken (Zeitreise, Neuzugänge) wird der Balken hervorgehoben. Wert und Datum bzw. Bezeichnung und Anzahl stehen in einer festen Zeile unter dem Diagramm, dort wo sonst der Hinweis steht – kein mitwanderndes Kästchen im Diagramm. Das letzte Datum der Zeitachse endet an der Diagrammkante statt in die Werteachse zu ragen. Neu gezeichnet wird nur, wenn ein anderer Punkt, Balken oder Abschnitt unter den Zeiger kommt, nicht bei jedem Pixel.
- Reihenfolge der Abschnitte: **Einstellungen → Darstellung**; auf der Seite selbst lassen sich die Bereiche am Titel per Ziehen umsortieren (nur dann erscheint ein Rahmen als Ablageziel).
- Aussehen, in beiden Designs gleich aufgebaut: Es gibt keine großen Karten. Die Bereiche liegen wie die Cover in Collection und Wantlist direkt auf der Seite, getrennt durch feine Linien, bündig mit dem Seitenrand. Die kleinen Kacheln (Kennzahlen, „Auf einen Blick“, Labels) haben alle dieselbe Fläche und einen feinen Rand, der beim Überfahren die Auswahlfarbe annimmt, dazu wächst ihr Schatten. **Modern**: helle Kacheln, Rand beim Überfahren in der Akzentfarbe, bunte Symbole, Zahlen und Überschriften in runder Schrift, dahinter der dezente Hauch der zuletzt hinzugefügten Cover. **Klassisch**: cremefarbene Hüllen, beim Überfahren golden; statt bunter Symbole ein einheitliches Petrol, das Klangbild in einer eigenen Palette aus Petrol, Gold und gedeckten Erdtönen, Zahlen und Überschriften in normaler statt runder Schrift, kein Cover-Hauch; Zu- und Abnahme des Werts in Moos bzw. Ziegel statt Systemgrün und -rot. Aktualisiert wird in beiden Designs durch Ziehen oder ⌘R, einen eigenen Knopf (auch den runden unten rechts) und ein Suchfeld hat die Statistik nicht.
- Regal-Markierungen ändern die Statistik nicht: Platten mit „Ohne Regalplatz“ oder „Gesucht“ gehören weiter zur Collection und zählen voll mit.

## Abschnitte

| Abschnitt | Inhalt |
|---|---|
| Deine Sammlung | Sammlungswert (Median) mit kleiner Kurve; Anzahl Schallplatten, Releases, Künstler, Styles und Labels |
| Auf einen Blick | Häufigster Künstler, Style, Jahrzehnt und Jahr, Neuzugänge im laufenden Jahr |
| Sammlungswert im Verlauf | Median, Niedrig und Hoch über 1 Monat bis „Alles“ |
| Klangbild | Genres, Styles und Formate |
| Top-Künstler, Labels | Die häufigsten, ausklappbar |
| Zufallsfund | Eine zufällige Platte mit Weg ins Regal |
| Zeitreise | Veröffentlichungen nach Jahrzehnten oder Jahren |
| Neuzugänge | Zugänge pro Monat oder Jahr, lückenlos vom ersten bis zum letzten Zeitraum (leere eingeschlossen) |
| Zuletzt hinzugefügt | Die neuesten Platten |

## Sammlungswert

Einzige Discogs-Anfrage der Statistik: `GET /users/{username}/collection/value` über den gemeinsamen API-Client (Taktung, `Retry-After`, Token aus dem Schlüsselbund). Vor und nach dem Abruf wird geprüft, dass Token und Bestand noch zum Konto passen; sonst wird nichts gespeichert. Ändert ein Sync die Sammlung, während der Wert noch geladen wird, fragt die Statistik einmal für die neue Sammlung nach; die Meldung „Der Discogs-Token passt nicht mehr zum geladenen Konto“ kommt nur bei wirklich geändertem Token (Test `collectionChangingDuringValueRequestIsAskedAgain`).

Jeder Abruf wird als `CollectionValueSnapshot` gespeichert (Konto, Zeitpunkt, Niedrig/Median/Hoch als `Decimal`, Währung, Anzahl Exemplare und eindeutiger Releases, Signatur des Bestands) – höchstens einer pro Kalendertag, außer

- der Bestand hat sich geändert (Signatur aus Instanz- und Release-IDs, auch bei gleicher Anzahl),
- die Währung hat sich geändert oder
- einer der drei Werte hat sich um mindestens 1 % und mindestens eine Währungseinheit bewegt.

Kleinere Änderungen aktualisieren den heutigen Eintrag, statt neue Verlaufspunkte zu erzeugen. Beim Start lädt die Seite die gespeicherten Daten lokal vor; Öffnen und Rubrikwechsel lösen keinen Wertabruf aus. Bei einem nicht erzwungenen Wertabruf wird ein heutiger Wert desselben Bestands wiederverwendet. Konten und Währungen werden nie zu einer Kurve vermischt; es gibt keine erfundene Umrechnung. Der Durchschnitt pro Platte ist Median-Gesamtwert geteilt durch die Anzahl Exemplare. Veränderungen beziehen sich auf den letzten Wert spätestens 30 Tage bzw. ein Jahr zuvor („seit mindestens …“). Vergangene Werte vor der ersten Nutzung werden nicht rekonstruiert.

## Lokale Auswertungen

Innerhalb eines Exemplars werden identische Genre-, Style-, Künstler- und Labelangaben nur einmal gezählt; mehrere Exemplare derselben Veröffentlichung zählen mehrfach. Künstler- und Label-IDs von Discogs haben Vorrang vor Namen. Bei gleicher Anzahl und gleichem Namen entscheidet zuletzt die ID, damit Ranglisten beim Aktualisieren nicht springen. Formate werden in Medium und Merkmal getrennt, ohne aus unklarem Text zu raten. Fehlende Jahre, Genres und Styles werden ausgewiesen; Einträge ohne gültiges Hinzufügedatum erhalten kein erfundenes.

Die Berechnung läuft ganz im Hintergrund, in einem eigenen Datenbank-Kontext: Platten samt Releases werden in einer Abfrage gelesen, in einfache Werte überführt und ausgewertet, ohne den Hauptthread (vorher ~0,4 s Hänger nach jedem Sync bei 2.000 Platten). Die wenigen Platten, die die Seite selbst zeigt (Top-Künstler, Zuletzt hinzugefügt, Zufallsfund, Cover-Hauch), kommen aus dem gemeinsamen Bestand des Hauptfensters.

## Aktualisierung und Zurücksetzen

Die Seite rechnet neu, wenn sich die Sammlung ändert: nach einem Sync einmal (und noch einmal nach den Tracklisten), sonst kurz nach jedem Speichern, das ihre Zahlen betrifft – neue oder entfernte Platten, geänderte Releases, Sammlungswert, Konten (`StatisticsView.affectsStatistics`). Einsortieren, Verschieben und „Gesucht“ lösen kein Neuladen aus. Solange die Seite verborgen ist, wird erst beim nächsten Anzeigen neu gerechnet. Der Zufallsfund folgt Platzänderungen sofort, solange die Statistik zu sehen ist; Verschiebungen auf der Regalseite rechnet er erst beim nächsten Anzeigen nach. Lassen sich die gespeicherten Daten nicht lesen, steht oben „Die gespeicherten Daten konnten gerade nicht gelesen werden …“ (Ursache im Protokoll). Fehler beim Abruf des Sammlungswerts erscheinen als wegklickbarer Hinweis; bereits gespeicherte Auswertungen und Verlaufspunkte bleiben erhalten. Ein Abbruch wird nicht als Verbindungsfehler ausgegeben. Eine von hier geöffnete Platte ist dieselbe wie auf den anderen Seiten; Bearbeitungen in der Detailansicht werden also über das Hauptfenster gespeichert (Test `statisticsShowTheAppsOwnRecords`).

Nach **Alles zurücksetzen** sind die gezeigten Platten gelöscht; die Statistik lässt sie deshalb sofort los (`StatisticsViewModel.forget`), schließt offene Detail- und Filterfenster und lädt neu, samt Konto. Vorher konnte das Nachladen von Fach oder Release einer gelöschten Platte die App zum Absturz bringen. Die Mitteilung kommt unmittelbar nach dem Löschen, vor dem Leeren des Cover-Caches – in dieser Wartezeit wird schon wieder gezeichnet. Test: `StatisticsTests.statisticsForgetTheirRecordsOnReset`.

## Dateien

| Datei | Aufgabe |
|---|---|
| `Statistics/StatisticsModels.swift` | Geldbeträge (`DiscogsMoney`), Auswertungsmodelle, API-Antwort des Sammlungswerts |
| `Statistics/CollectionAnalyticsService.swift` | Rein lokale Berechnungen |
| `Statistics/CollectionValueHistoryService.swift` | Wertabruf, Regeln für Verlaufspunkte, Veränderungen |
| `Statistics/StatisticsViewModel.swift` | Laden, Hintergrundberechnung, Zustand der Seite |
| `Statistics/StatisticsView.swift` | Seite, Abschnitte, Drill-down |
| `Statistics/StatisticsCards.swift` | Karten der Seite: Überblick, Kennzahlen, Klangbild, Interpreten, Zufallsplatte, Labels |
| `Statistics/StatisticsCharts.swift` | Balken, Zeitreise, Zugänge, zuletzt hinzugefügt, gemeinsame Bausteine |
| `Statistics/ValueHistoryDashboard.swift` | Wertverlauf mit Swift Charts |
| `PlattenregalTests/StatisticsTests.swift` | Parsing, Aggregation, Verlaufsregeln, Migrationen bis zum aktuellen Schema V16, Verhalten beim Zurücksetzen, welche Speichervorgänge neu rechnen lassen, Sammlungswert während eines Syncs, gezeigte Platten aus dem Hauptfenster (31 Tests; die Menge prüft `tenThousandRecords` in ScenarioTests) |

Das Modell `ReleaseMarketValue` aus der früheren Einzelpreis-Funktion ist seit Schema V15 entfernt; die Migration verwirft seine Zeilen.

## Demo

In der Demo (**Plattenregal → Demo starten …**) zeigt die Statistik die Beispielsammlung samt 18 Monaten Wertverlauf; Aktualisieren rechnet nur neu, ohne Abruf bei Discogs. Aus Xcode öffnet `--statistics-demo` die Demo direkt auf dieser Seite.
