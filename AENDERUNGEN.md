# „Nicht auffindbar“ heißt jetzt „Vermisst“ · 25.09.2026

- Die Markierung heißt überall „Vermisst“: Etikett, Knöpfe, Menüs, Hinweise, Fehlermeldungen, Protokoll und Dokumentation.
- Die Übersicht neben der Suche auf der Regalseite zeigt nur noch „Vermisst“ statt der Anzahl („7 nicht auffindbar“); die Liste darin nennt weiter jede Platte.

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
