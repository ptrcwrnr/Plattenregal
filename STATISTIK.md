# Statistik-Erweiterung

Die vollständige Erweiterung ist in dieser Projektkopie integriert. Das ursprüngliche Projekt und die persönliche Collection-Datenbank wurden bei der Entwicklung nicht verändert. Die Anwendung verwendet weiterhin den bisherigen Speicherort `Application Support/Plattenregal/Collection.store` innerhalb ihrer bestehenden App-Umgebung.

## Bedienung

- In der Sidebar **Statistik** wählen.
- Die Datenbasis ist entweder die aktive Discogs Collection eines Accounts oder alle aktuellen lokalen Exemplare. In Discogs entfernte, lokal aufbewahrte Exemplare werden nicht als aktuelle Sammlung gezählt.
- **Statistik aktualisieren** berechnet lokale Auswertungen und ruft den offiziellen Sammlungswert ab. Es findet kein vollständiger Collection-Import statt.
- Nach einem erfolgreichen vollständigen Collection-Sync wird der Sammlungswert ebenfalls geladen. Scheitert nur dieser Abruf, bleibt der bereits erfolgreiche Sync gespeichert und eine gesonderte Meldung erscheint.
- Genre, Style, Künstler, Label, Jahr, Jahrzehnt, Format und Land öffnen eine gefilterte Variante der vorhandenen `CollectionView`. Release-Einträge öffnen die vorhandene `RecordDetailView`.
- **Fehlende / veraltete Preise laden** lädt nur nicht vorhandene oder mindestens sieben Tage alte Ergebnisse. **Alle Preise aktualisieren** erzwingt eine erneute Prüfung. **Abbrechen** behält bereits gespeicherte Ergebnisse.

## Dateien

Neu unter `Plattenregal/Statistics/`:

| Datei | Aufgabe |
| --- | --- |
| `StatisticsModels.swift` | Schema V3, persistente Modelle, Decimal-Geldbeträge und API-Antwortmodelle |
| `CollectionAnalyticsService.swift` | Rein lokale Berechnungen auf übertragbaren Datenstrukturen |
| `CollectionValueHistoryService.swift` | Accountbezogene Wertabrufe, Snapshot-Regeln und Veränderungen |
| `MarketValueService.swift` | Sequenzielle Preisabfragen, Cache, Fortschritt, Abbruch und getrennte Ranglisten |
| `StatisticsViewModel.swift` | UI-Zustand, Hintergrundberechnung und Laden lokaler Daten |
| `StatisticsView.swift` | Dashboard, Kennzahlen, Verteilungen und Navigation |
| `ValueHistoryDashboard.swift` | Swift-Charts-Verläufe, Zeiträume, Durchschnitt und Veränderungen |

Neu: `PlattenregalTests/StatisticsTests.swift` mit 23 Tests.

Geändert:

- `DiscogsAPIClient.swift`: drei zusätzliche GET-Funktionen und Berücksichtigung von Server-Cooldowns auch für wartende Anfragen.
- `DiscogsDTO.swift`: einzelne Künstler-/Label-IDs auch nach Detailabrufen lokal erhalten.
- `DiscogsSyncService.swift`: Wertabruf nach erfolgreichem Collection-Commit.
- `LibraryModels.swift`: Migrationsplan V3; strukturierte Metadaten beim Aktualisieren eines vorhandenen Releases weitergeben. Keine bestehenden persistenten Felder entfernt oder umbenannt.
- `LibraryStorage.swift`: Schema V3 öffnen.
- `RootView.swift`: neuer Navigationspunkt.
- `CollectionView.swift`: optionaler Filter anhand der Exemplar-IDs.
- `PlattenregalApp.swift`, `PreviewData.swift`: isolierter Statistik-Demomodus für Debug-Builds.
- `project.pbxproj`: neue App- und Testdateien eingebunden.

## Datenbank und Migration

Neue SwiftData-Modelle:

- **CollectionValueSnapshot**: UUID, Account, Zeitpunkt, Minimum/Median/Maximum als Decimal, Währung, Instanzzahl, eindeutige Release-Anzahl und Signatur des Bestands.
- **ReleaseMarketValue**: Account, Release-ID, optionaler Decimal-Preis, Währung, Zustand, Quelle und Abrufzeit. Fehlende Preisdaten werden als fehlend gespeichert, niemals als erfundener Nullpreis.

Schema V3 übernimmt die bestehenden V2-Modelle unverändert in ihrer Struktur und ergänzt diese beiden Entitäten. Der Migrationsplan enthält V1 → V2 → V3 als Lightweight-Migrationen. Es gibt keinen Lösch- oder Neuinitialisierungs-Fallback für die persönliche Datenbank.

Der Migrationstest schreibt eine echte temporäre V2-Datenbank und öffnet sie mit V3. Geprüft werden unter anderem Exemplar-ID, KALLAX-Fach, Position, Notizen, Favorit, Kaufpreis, Discogs-Instanz, Account, Ordner und Wantlist. Die persönliche Datenbank wurde für diesen Test nicht geöffnet.

## Wert-Historie

Ein erfolgreicher Abruf erzeugt normalerweise höchstens einen Snapshot pro lokalem Kalendertag. Weitere Snapshots am selben Tag sind erlaubt bei:

- anderem Bestand, auch bei gleicher Exemplarzahl (Signatur aus Instanz- und Release-IDs),
- geänderter Währung,
- Änderung eines der drei Werte um mindestens 1 % und mindestens eine Währungseinheit.

Beim bloßen Öffnen der Ansicht wird ein vorhandener Snapshot desselben Tages und Bestands wiederverwendet. Ein expliziter Refresh ruft den Wert neu ab, speichert aber keine identische Momentaufnahme. Kleinere Änderungen aktualisieren den heutigen letzten Snapshot, damit die Wertkarten aktuell bleiben, ohne zusätzliche Verlaufspunkte zu erzeugen. Parallele Abrufe desselben Accounts werden zusammengefasst.

Accounts und Währungen werden nie zu einer Verlaufskurve vermischt. Ein tatsächlicher EUR-Betrag wird lokalisiert als Euro angezeigt. Liefert Discogs eine andere Währung, bleibt sie erhalten; es gibt keine erfundene Umrechnung in EUR.

Der Durchschnitt ist **Median-Gesamtwert / gespeicherte Instanzzahl**. Bei null Instanzen bleibt er unbekannt. Er ist kein durchschnittlicher Verkaufspreis einzelner Platten. Veränderungen beziehen sich auf den vorherigen Snapshot beziehungsweise den letzten vorhandenen Snapshot spätestens 30 Tage bzw. ein Jahr vor dem aktuellen. Deshalb heißen diese Vergleiche „seit mindestens …“. Ein Prozentwert bei Ausgangswert null wird nicht erfunden.

Historische Werte entstehen ab der Nutzung dieser Erweiterung. Vergangene Gesamtwerte werden nicht rekonstruiert. Neuzugänge lassen sich unabhängig davon aus bereits gespeicherten Discogs-Hinzufügedaten auswerten.

## Discogs-Endpunkte und Einzelpreise

Der vorhandene API-Client, Keychain-Token und synchronisierte Username werden weiterverwendet:

1. `GET /users/{username}/collection/value`
2. `GET /marketplace/price_suggestions/{release_id}`
3. `GET /marketplace/stats/{release_id}?curr_abbr=EUR`

Preisvorschläge bevorzugen **Very Good Plus (VG+)**. Fehlt VG+, gilt eine feste Fallback-Reihenfolge: VG, NM, G+, G, M, F, P. Der tatsächliche Zustand wird gespeichert und angezeigt. Unterschiedliche Zustände erscheinen in getrennten, auswählbaren Ranglisten. Es wird nicht einfach der höchste verfügbare Vorschlag gewählt.

Günstigste Marketplace-Angebote sind eine separat auswählbare Preisquelle. Sie werden ausdrücklich als Angebote bezeichnet und nie als Schätzung des Marktwerts. Bei verweigerten Preisvorschlägen erscheint eine Fehlermeldung mit Hinweis auf diese Alternative. Es gibt keinen stillen Quellenwechsel.

Jede Rangliste ist nach Account, Quelle, Währung und Zustand getrennt und enthält höchstens zehn eindeutige Releases aus der aktuellen Sammlung. Sie basiert auf den verfügbaren Cache-Daten; eine unvollständige Preisabdeckung kann die Rangfolge beeinflussen. Alter und Preisbasis stehen an jedem Eintrag.

Abrufe laufen nacheinander über den gemeinsamen Client (regulär mindestens 1,1 Sekunden Abstand). `Retry-After`, erschöpftes Request-Budget und Abbruch werden berücksichtigt. Bei 401/403 wird der Lauf beendet; bei bestätigtem 404 wird das fehlende Ergebnis gecacht. Pro Öffnen des Dashboards werden keine Einzelpreis-Requests gestartet.

Die offizielle [Discogs-API-Dokumentation](https://www.discogs.com/developers/) wurde während der Entwicklung angefragt, war hier jedoch mit HTTP 403 gesperrt. Authentifizierte Live-Antworten mit dem persönlichen Token wurden nicht abgefragt. Die Integration ist mit simulierten HTTP-Antworten getestet; ob Price Suggestions für den konkreten Account verfügbar sind, wird beim tatsächlichen Abruf festgestellt.

## Vollständig lokale Statistiken

Exemplare, eindeutige Releases, Genres, Styles, Künstler, Labels, konkrete Release-Jahre, Jahrzehnte, vorhandene Länder und strukturierte Formatmerkmale, ältestes/neuestes Release, häufigste Kategorien, letzte zehn Neuzugänge sowie Zugänge pro Monat/Jahr.

Innerhalb eines Exemplars werden identische Genre-, Style-, Künstler- und Labelangaben dedupliziert. Mehrere Exemplare derselben Veröffentlichung zählen mehrfach. Artist- und Label-IDs aus `basicInformation` haben Vorrang; bei alten manuellen Datensätzen ohne strukturierte Identitäten wird der gespeicherte Name verwendet. Zusammengefügte Altdaten werden nicht durch geratenes Aufteilen verändert.

Formate werden getrennt als Medium und Merkmal normalisiert. Ohne strukturierte Formatdaten wird nichts aus einem unklaren zusammengesetzten Text geraten. Fehlende Jahre, Genres und Styles werden ausgewiesen. Discogs-Einträge ohne gültiges `date_added` erhalten kein erfundenes Hinzufügedatum.

Die zentrale Aggregation läuft außerhalb des SwiftUI-`body` auf einer Hintergrund-Task. SwiftData-Objekte werden vorher auf dem Main Actor in einfache Werte überführt. Ereignisse während Preisserien lösen keine vollständige Neuberechnung für jedes einzelne Preisresultat aus.

## Validierung

Die vorhandenen Sync-, API-, Sortier- und KALLAX-Tests sowie die neuen Statistiktests werden gemeinsam ausgeführt. Die neue Suite deckt Parsing, deutsches Zahlenformat, persistente Snapshots, Deduplizierung, Durchschnitt, Aggregationen, Mehrfachinstanzen, Neuzugänge, vergleichbare Top-10-Listen, fehlende Daten, prozentuale Änderungen, 2.000 Exemplare, API-Aufrufe, Cache-Wiederverwendung, Abbruch, Zugriff verweigert, Sync-Nachlauf und Migration ab.

```sh
xcodebuild -project Plattenregal.xcodeproj -scheme Plattenregal \
  -configuration Debug -destination 'platform=macOS' \
  -parallel-testing-enabled NO test

xcodebuild -project Plattenregal.xcodeproj -scheme Plattenregal \
  -configuration Release build
```

Debug-Demo: App mit `--statistics-demo` starten. Alle Beispieldaten liegen ausschließlich in einer In-Memory-Datenbank. Der Account ist sichtbar als „Demo · Beispieldaten“ markiert. Der Modus ist nicht in Release-Builds verfügbar.

### Ergebnis vom 20.09.2026

- Debug-Build und gesamte XCTest-Suite: **66 Tests, 0 Fehler**, davon 23 neue Statistiktests.
- Release-Build: **erfolgreich**, Universal Binary für Apple Silicon und Intel (`arm64`, `x86_64`).
- Kopierte Release-App mit `codesign --verify --deep --strict` erfolgreich geprüft (lokale Ad-hoc-Signatur; keine notarisierten Distributionsdateien).
- Visuell geprüft: Dashboard mit isolierten Beispieldaten, lokalisierte Eurokarten, Verlaufskurve und Genre-Drilldown in die vorhandene Collection-Ansicht.
- Nicht live geprüft: Discogs-Wertabruf und individuelle Preisfreigaben des persönlichen Accounts. HTTP-Verhalten und Fehlerfälle wurden mit URLProtocol-Testantworten überprüft.
