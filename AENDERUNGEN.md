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
