# Statistik

Die Seite **Statistik** wertet die aktuelle Collection aus und zeigt den Verlauf ihres Discogs-Sammlungswerts. Alles außer dem Sammlungswert wird lokal berechnet, ohne Anfrage an Discogs.

## Bedienung

- In der Seitenleiste **Statistik** wählen.
- Grundlage sind dieselben Platten wie auf der Collection-Seite: die aktive Discogs-Collection des zuletzt synchronisierten Kontos. In Discogs entfernte, lokal noch vorhandene Exemplare zählen nicht mit – so stimmt jede Zahl mit der Liste überein, die sich beim Antippen öffnet.
- **Aktualisieren** – die Seite nach unten ziehen oder **⌘R** – rechnet die Auswertungen neu und ruft den Sammlungswert ab. Nach jedem erfolgreichen Collection-Sync wird der Wert ebenfalls geladen; scheitert nur dieser Abruf, bleibt der Sync gespeichert und eine eigene Meldung erscheint.
- Genres, Styles, Künstler, Labels, Jahre, Formate und Länder öffnen die passenden Platten als gefilterte Collection-Liste. Einzelne Platten öffnen ihre Detailansicht oder zeigen ihren Platz im Regal.
- Reihenfolge der Abschnitte: **Einstellungen → Darstellung**.
- Regal-Markierungen ändern die Statistik nicht: Platten mit „Nicht im Regal“ oder „Nicht auffindbar“ gehören weiter zur Collection und zählen voll mit.

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
| Neuzugänge | Zugänge pro Monat oder Jahr |
| Zuletzt hinzugefügt | Die neuesten Platten |

## Sammlungswert

Einzige Discogs-Anfrage der Statistik: `GET /users/{username}/collection/value` über den gemeinsamen API-Client (Taktung, `Retry-After`, Token aus dem Schlüsselbund). Vor und nach dem Abruf wird geprüft, dass Token und Bestand noch zum Konto passen; sonst wird nichts gespeichert.

Jeder Abruf wird als `CollectionValueSnapshot` gespeichert (Konto, Zeitpunkt, Niedrig/Median/Hoch als `Decimal`, Währung, Anzahl Exemplare und eindeutiger Releases, Signatur des Bestands) – höchstens einer pro Kalendertag, außer

- der Bestand hat sich geändert (Signatur aus Instanz- und Release-IDs, auch bei gleicher Anzahl),
- die Währung hat sich geändert oder
- einer der drei Werte hat sich um mindestens 1 % und mindestens eine Währungseinheit bewegt.

Kleinere Änderungen aktualisieren den heutigen Eintrag, statt neue Verlaufspunkte zu erzeugen. Beim bloßen Öffnen der Seite wird ein heutiger Wert desselben Bestands wiederverwendet. Konten und Währungen werden nie zu einer Kurve vermischt; es gibt keine erfundene Umrechnung. Der Durchschnitt pro Platte ist Median-Gesamtwert geteilt durch die Anzahl Exemplare. Veränderungen beziehen sich auf den letzten Wert spätestens 30 Tage bzw. ein Jahr zuvor („seit mindestens …“). Vergangene Werte vor der ersten Nutzung werden nicht rekonstruiert.

## Lokale Auswertungen

Innerhalb eines Exemplars werden identische Genre-, Style-, Künstler- und Labelangaben nur einmal gezählt; mehrere Exemplare derselben Veröffentlichung zählen mehrfach. Künstler- und Label-IDs von Discogs haben Vorrang vor Namen. Formate werden in Medium und Merkmal getrennt, ohne aus unklarem Text zu raten. Fehlende Jahre, Genres und Styles werden ausgewiesen; Einträge ohne gültiges Hinzufügedatum erhalten kein erfundenes.

Die Berechnung läuft im Hintergrund: SwiftData-Objekte werden auf dem Main Actor in einfache Werte überführt, die Auswertung selbst läuft außerhalb davon, damit große Sammlungen die Oberfläche nicht blockieren.

## Dateien

| Datei | Aufgabe |
|---|---|
| `Statistics/StatisticsModels.swift` | Geldbeträge (`DiscogsMoney`), Auswertungsmodelle, API-Antwort des Sammlungswerts |
| `Statistics/CollectionAnalyticsService.swift` | Rein lokale Berechnungen |
| `Statistics/CollectionValueHistoryService.swift` | Wertabruf, Regeln für Verlaufspunkte, Veränderungen |
| `Statistics/StatisticsViewModel.swift` | Laden, Hintergrundberechnung, Zustand der Seite |
| `Statistics/StatisticsView.swift` | Seite, Abschnitte, Drill-down |
| `Statistics/ValueHistoryDashboard.swift` | Wertverlauf mit Swift Charts |
| `PlattenregalTests/StatisticsTests.swift` | Parsing, Aggregation, Verlaufsregeln, 2.000 Exemplare, Migrationen bis zum aktuellen Schema V13 |

Das Modell `ReleaseMarketValue` stammt aus der früheren Einzelpreis-Funktion. Es bleibt im Datenbankschema, damit bestehende Datenbanken ohne Migration weiter öffnen, wird aber nicht mehr befüllt; „Alles zurücksetzen“ leert es.

## Demo

In der Demo (**Plattenregal → Demo starten …**) zeigt die Statistik die Beispielsammlung samt 18 Monaten Wertverlauf; Aktualisieren rechnet nur neu, ohne Abruf bei Discogs. Aus Xcode öffnet `--statistics-demo` die Demo direkt auf dieser Seite.
