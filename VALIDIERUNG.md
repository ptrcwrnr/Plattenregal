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
13. KALLAX, Position, Notizen, Favorit, Zustand, Kaufpreis, Kaufdatum und lokales Hinzufügedatum bleiben bei Update, Verschiebung und Entfernung erhalten.
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
