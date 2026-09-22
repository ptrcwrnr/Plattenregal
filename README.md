# Neu: Statistik-Dashboard

Diese Projektversion enthält den neuen Statistik-Bereich. Bedienung, Dateiliste, SwiftData-Migration, Preisquellen und Tests stehen in [STATISTIK.md](STATISTIK.md).

# Plattenregal

Native macOS-App für eine private Vinylsammlung. Swift 6, SwiftUI und SwiftData, ohne externe Abhängigkeiten. Erstellt und geprüft mit Xcode 27.0 / Swift 6.4; Deployment Target macOS 14.0.

## In Xcode starten

1. `Plattenregal.xcodeproj` öffnen.
2. Scheme **Plattenregal**, Ziel **My Mac** wählen.
3. Mit **⌘R** starten; mit **⌘U** die Unit-Tests ausführen.

Das Projekt ist für lokales Ad-hoc-Signing eingerichtet und benötigt dafür kein bezahltes Entwicklerkonto. Für Weitergabe oder Notarisierung ein eigenes Signing-Team unter „Signing & Capabilities“ konfigurieren. Die Bundle-ID nach dem ersten produktiven Einsatz beibehalten, damit Sandbox und Schlüsselbund stabil bleiben.

## Dein KALLAX

**3 Reihen von oben nach unten, jeweils 4 Fächer von links nach rechts.** Diese Anordnung berücksichtigt die nachgereichte Korrektur zur ursprünglichen Spezifikation.

```text
┌────┬────┬────┬────┐
│  1 │  2 │  3 │  4 │
├────┼────┼────┼────┤
│  5 │  6 │  7 │  8 │
├────┼────┼────┼────┤
│  9 │ 10 │ 11 │ 12 │
└────┴────┴────┴────┘
```

Position 1 ist die linke Platte innerhalb eines Fachs. Die Kapazität ist je Fach einstellbar; 90 ist nur der änderbare Anfangswert. Namen und Kapazitäten lassen sich in den Einstellungen oder über das Kontextmenü eines Fachs bearbeiten.

## Implementierte Funktionen

- Manuelles Hinzufügen, Bearbeiten, Favorisieren und Löschen von Exemplaren.
- Veröffentlichungen/Pressungen und physische Exemplare als getrennte Datenmodelle; mehrere Exemplare einer Veröffentlichung werden unterstützt.
- Cover-Raster und native Tabelle; Suche über Interpret, Titel, Label, Katalognummer, Genre und Style. Suchbegriffe werden auch über mehrere Felder kombiniert.
- Sofort sichtbarer Standort „Fach X · Position Y“ und „Im Regal anzeigen“ aus dem Detail bzw. Kontextmenü.
- KALLAX-Raster mit Belegung, Kapazitäten, Auswahlmarkierung und Fachinhalt in physischer Reihenfolge.
- Einfügen zwischen Exemplaren, Verschieben innerhalb eines Fachs oder in ein anderes Fach, lückenlose Neunummerierung nach Löschen und Kapazitätsprüfung.
- Sortierungen nach Interpret auf-/absteigend, Jahr, Genre, Style, Label/Katalognummer sowie physischer Reihenfolge. „Zuletzt hinzugefügt“ zeigt die letzten 30 Tage, neueste zuerst.
- Discogs-Vinylsuche mit Seiten, konkreten Release-IDs, Pressungsvorschau, Tracklist und ausdrücklich bestätigter lokaler Übernahme. Master-Releases werden nicht importiert.
- Token im macOS-Schlüsselbund, Verbindungstest in den Einstellungen und verständliche Fehler für Authentifizierung, Rate Limits, HTTP, Netzwerk und ungültige Antworten.
- Asynchrone Cover mit Platzhalter, zusammengefassten parallelen Downloads und begrenztem Arbeitsspeicher-Cache; kein dauerhafter Bildcache.
- Native Settings, konfigurierbare Covergröße, SwiftUI Previews und ein ausschließlich temporärer Demo-Modus.

## Discogs einrichten

Unter **Plattenregal → Einstellungen → Discogs** einen persönlichen Token eingeben und „Speichern & Verbindung testen“ wählen. Den Token bei https://www.discogs.com/settings/developers erzeugen. Tokens gehören weder in Quelldateien noch in Build-Einstellungen. Ein leeres Feld beim Speichern löscht den gespeicherten Token.

Die Integration liest nur aus Discogs. Sie ändert weder deine Discogs-Sammlung noch Marketplace-Daten. Die Discogs-Suche übernimmt einzelne Pressungen weiterhin über „Zur Sammlung hinzufügen“. Zusätzlich importieren die Sync-Aktionen Collection und Wantlist vollständig. Gleiche Discogs-Release-IDs verwenden dieselbe lokale Veröffentlichung, aber jeweils ein eigenes Exemplar.

API-Metadaten bleiben nur so lange gespeichert, wie sie für die verwalteten Exemplare benötigt werden. Eine Zeitprüfung blendet veraltete API-Daten vor Ablauf von sechs Stunden aus; eigene Notizen, Zustand, Kaufdaten und Standorte bleiben verfügbar. Abgelaufene Metadaten werden beim Öffnen/Aktivieren oder über die Aktualisieren-Aktion geladen. Ohne Netz bzw. Token kann ein älterer Discogs-Eintrag vorübergehend nur anhand seiner Release-ID und seines Standorts angezeigt werden. Manuell erfasste Veröffentlichungen funktionieren vollständig offline. Die Metadaten importierter Pressungen sind schreibgeschützt, damit ein API-Refresh eigene Exemplardaten nicht überschreibt.

API-Daten tragen direkt einen Link „Data provided by Discogs.“ zur zugehörigen Veröffentlichung. Grundlage der Implementierung sind die am 19.09.2026 eingesehenen [offiziellen API-Nutzungsbedingungen](https://support.discogs.com/hc/en-us/articles/360009334593-API-Terms-of-Use), insbesondere Aktualität, eingeschränkte Bildnutzung und Attribution. Bitte diese Bedingungen bei einer späteren Veröffentlichung der App erneut prüfen.

This application uses Discogs’ API but is not affiliated with, sponsored or endorsed by Discogs. ‘Discogs’ is a trademark of Zink Media, LLC.

## Daten und Sicherung

Die produktive Datenbank wird beim Start geöffnet, nicht neu erstellt. Es gibt keinen automatischen Lösch- oder Rücksetzpfad, auch nicht nach einem Speicherfehler. Beim erstmaligen Start werden ausschließlich die zwölf Fächer angelegt.

Die Datenbank liegt in `Library/Application Support/Plattenregal/Collection.store` innerhalb der App-Sandbox, normalerweise unter:

```text
~/Library/Containers/de.private.Plattenregal/Data/Library/Application Support/Plattenregal/
```

Für ein manuelles Backup die App beenden und **den gesamten Ordner** inklusive möglicher SQLite-Begleitdateien sichern. Cover und Token sind nicht Teil dieser Datenbanksicherung. Ein integrierter Export/Import ist noch nicht enthalten.

`LibrarySchemaV1` bleibt unverändert. `LibrarySchemaV2` ergänzt optionale Discogs-Felder, Wantlist, Ordner und Account-Metadaten. `LibraryMigrationPlan` migriert V1 → V2 per Lightweight-Migration; ein Test erzeugt eine echte V1-Dateidatenbank, migriert sie und prüft UUID, Fach, Position und lokale Felder. Geometrieanpassungen ändern keine Fach-UUIDs oder Exemplarpositionen.

## Wichtige Dateien

| Bereich | Datei | Aufgabe |
|---|---|---|
| Start | `Plattenregal/PlattenregalApp.swift` | App-/Settings-Szenen, Speicherstart und sichtbarer Fehlerzustand |
| Daten | `Models/LibraryModels.swift` | Versioniertes Schema, Releases, Exemplare, Fächer, Geometrie |
| Speicherung | `Storage/LibraryStorage.swift` | Dauerhafter SwiftData-Container und Fachinitialisierung |
| Positionen | `Services/PositionService.swift` | Atomare Änderungen, Kapazitäten, Rollback und Neunummerierung |
| Sortierung | `Sorting/SortingService.swift` | Suche, Sortierungen und erweiterbares Platzierungskonzept |
| Netzwerk | `Discogs/DiscogsAPIClient.swift` | URLSession, async/await, Authentifizierung, Fehler und Anfragetaktung |
| API-Mapping | `Discogs/DiscogsDTO.swift` | Codable-DTOs und Übertragung in eigene Models |
| Zugang | `Storage/KeychainStore.swift` | Speichern, Lesen und Entfernen des Tokens |
| Oberfläche | `Views/` | Navigation, Sammlung, KALLAX, Editor, Details, Discogs und Einstellungen |
| Tests | `PlattenregalTests/LibraryTests.swift` | Positions-, Speicher-, Sortierungs-, Mapping- und API-Fehlertests |

## Entwicklung und Prüfung

Die Previews verwenden eine eigene In-Memory-Datenbank. Für einen interaktiven Demo-Lauf im Debug-Scheme unter **Edit Scheme → Run → Arguments** `--demo` ergänzen. Die vier Beispielplatten und alle Änderungen dieses Laufs verschwinden beim Beenden. Das Argument vor der echten Nutzung wieder entfernen; Release-Builds ignorieren es.

```sh
xcodebuild -project Plattenregal.xcodeproj -scheme Plattenregal \
  -configuration Debug -destination 'platform=macOS' build

xcodebuild -project Plattenregal.xcodeproj -scheme Plattenregal \
  -configuration Debug -destination 'platform=macOS' test
```

Die Discogs-Transporttests verwenden lokale URLProtocol-Antworten und einen ausschließlich im Test erzeugten Platzhalter. Sie benötigen weder Internet noch einen echten Token und verändern den Schlüsselbund nicht. Ein authentifizierter vollständiger Live-Sync wurde am 20.09.2026 im flüchtigen Demo-Datenbestand erfolgreich geprüft (839 Collection-Instanzen, 868 Wants, 7 Ordner).

## Sinnvolle nächste Ausbauschritte

- Geführte, bestätigbare Umräumschritte und eine Strategie mit möglichst wenigen Bewegungen.
- Alphabetisch passende Einfügevorschläge; aktuell besteht die Erweiterungsschnittstelle mit einer einfachen „erstes freies Fach“-Strategie.
- Integrierter Backup-/Wiederherstellungsdialog.
- Separater Medien-/Hüllenzustand, zusätzliche Filter und lokale Coverdateien.

Den abschließenden Build- und Teststand dokumentiert `VALIDIERUNG.md`.

## Collection und Wantlist synchronisieren

Beim Appstart wird ausschließlich die **Collection** abgeglichen. Die **Wantlist** wird nicht automatisch geladen und lässt sich nur in der Rubrik **Discogs-Wantlist** über **Wantlist synchronisieren** aktualisieren. Dort stehen außerdem eine eigene Suche und eine adaptive Kartenansicht mit zwei beziehungsweise drei Spalten bereit. Die Account-Erkennung verwendet den vorhandenen Keychain-Token. Username, User-ID und ein SHA-256-Fingerabdruck zur Cache-Zuordnung werden lokal gespeichert; der Token selbst bleibt ausschließlich im Schlüsselbund.

- **Collection** lädt die Ordner und alle Seiten von Ordner 0. **Wantlist synchronisieren** lädt alle Wantlist-Seiten erst nach der manuellen Aktion in der Wantlist-Rubrik.
- **Ordner synchronisieren** lädt den ausgewählten Ordner vollständig. Fehlende Exemplare verlieren hier nur ihre Ordnerzuordnung: Ein Ordner-Sync kann nicht erkennen, ob sie in andere Ordner verschoben wurden. Ein vollständiger Collection-Sync klärt die Mitgliedschaft.
- **Veröffentlichung aktualisieren** im Kontextmenü der Sammlung lädt einen gezielten Release-Detailrequest. In der Wantlist gibt es diese Einzelaktion nicht mehr; der vollständige Wantlist-Abgleich verwendet die Basic Information und erzeugt keine Detailanfrage pro Album.
- **Discogs-Ordner** in der Sammlung filtert nach der externen Ordner-ID. **Alle lokalen Exemplare** umfasst weiterhin lokale Exemplare, die aus Discogs entfernt wurden. **Discogs Collection · Alle** zeigt ausschließlich aktive Discogs-Zuordnungen.
- Neue Exemplare sind **noch keinem Fach zugeordnet**. Über „Bearbeiten“ kann ein KALLAX-Platz gewählt werden. Lokale Notizen können auch ohne Standort gespeichert werden.
- Mehrere Instanzen derselben Release-ID bleiben getrennte `RecordCopy`-Datensätze und teilen Release-Metadaten. Bereits vorhandene, noch nicht verknüpfte lokale Exemplare derselben Release-ID werden einmalig zugeordnet; vorhandene Positionen und Notizen bleiben erhalten.
- Entfernte Instanzen bleiben als lokale Exemplare mit `discogsActive = false` erhalten. Ein erneutes Hinzufügen derselben Instanz reaktiviert sie. Entfernte Wants löschen ausschließlich die Wantlist-Zuordnung.

Der Netzwerkclient taktet Anfragen, beachtet `Retry-After` (Sekunden und HTTP-Datum) sowie `X-Discogs-Ratelimit-Remaining` und versucht temporäre Fehler höchstens dreimal insgesamt. Seitenzahl, Anzahl pro Seite, Gesamtzahl und eindeutige Instanz-/Release-IDs werden geprüft. Abbruch, ungültige Daten oder ein Tokenwechsel verhindern das Speichern. Discogs bietet keine serverseitige Snapshot-Isolation; gleichzeitige Änderungen mit identischer Gesamtzahl lassen sich über eine paginierte API nicht vollständig ausschließen.

Der Merge läuft in einem Hintergrundtask mit eigenem SwiftData-Kontext und einem abschließenden atomaren Save. Rollbacks berühren keine offenen Bearbeitungen in anderen Fenstern. KALLAX-Fach, Position, Favorit, Zustand, Kaufdaten, lokales Hinzufügedatum und lokale Notizen werden vom Sync nie beschrieben.

Neue Dateien: `DiscogsSyncDTO.swift`, `DiscogsSyncService.swift`, `DiscogsSyncView.swift`, `DiscogsSyncTests.swift`. Die bestehende Ordnerstruktur, Cover-Lösung und Keychain-Implementierung bleiben Grundlage.
