import SwiftUI
import SwiftData

// MARK: - Vermisst

/// The records marked "Vermisst" on the shelf page, and the way back:
/// found, a record without a shelf is offered in "Einsortieren" and
/// "Platte hinzufügen" again; one standing in a shelf simply loses its mark.
struct MissingSettingsView: View {
    @Environment(\.modelContext) private var context
    /// Shared with the pages, fetched only when they change (see `LibraryRecords`).
    private var records: LibraryRecords { .of(context) }
    @AppStorage(DisplaySettings.missingListKey) private var missingEnabled = true
    @AppStorage(ShelfLabelStyle.key) private var labelStyle = ShelfLabelStyle.range
    @State private var labels = ShelfLabels()
    @State private var labelsCache = ShelfLabelsCache()
    @State private var changes = LibraryChanges.shared
    @State private var error: String?

    /// As on the shelf page: in shelf order, then those without a shelf by artist.
    private var copies: [RecordCopy] {
        MissingCopies.listed(Set(records.missingMarks.map(\.copyID)), in: records.copies,
                             owner: DiscogsAccount.current(in: records.accounts)?.username,
                             excluding: Set(records.exclusions.map(\.copyID)))
    }

    /// The labels sort every record's artist: only recomputed when something
    /// they depend on changed (see `ShelfSettingsView`).
    private var labelSignature: Int {
        var hasher = Hasher()
        hasher.combine(labelStyle)
        hasher.combine(changes.libraryVersion)
        hasher.combine(changes.shelvesVersion)
        hasher.combine(changes.placementsVersion)
        hasher.combine(records.shelves.count)
        return hasher.finalize()
    }

    var body: some View {
        let copies = copies
        SettingsPage {
            SettingsCard(title: String(localized: "Vermisst"),
                         subtitle: String(localized: "Für Platten, die beim Einsortieren gerade nicht zu finden sind.")) {
                SettingsRow(title: String(localized: "Vermisst-Liste"),
                            hint: missingEnabled
                            ? String(localized: "Platten lassen sich zurückstellen: mit dem Pause-Knopf in „Platte hinzufügen“ oder per Rechtsklick im Fach. Bis du sie hier als gefunden markierst, werden sie nicht mehr zum Einsortieren angeboten.")
                            : String(localized: "Aus: kein Zurückstellen und keine Liste. Bereits vermisste Platten bleiben gemerkt, falls du es wieder einschaltest.")) {
                    Toggle("Vermisst-Liste", isOn: $missingEnabled)
                        .labelsHidden().toggleStyle(.switch)
                }
            }

            SettingsCard(title: String(localized: "Vermisste Platten"),
                         subtitle: copies.isEmpty ? nil : String(localized: "\(AppStyle.records(copies.count)) · Gefundene Platten ohne Fach stehen wieder unter „Einsortieren“.")) {
                if copies.isEmpty {
                    SettingsNote(String(localized: "Keine Platte ist als vermisst markiert."))
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(copies) { copy in
                            MissingSettingsRow(copy: copy, location: location(copy)) { release([copy]) }
                            if copy.id != copies.last?.id { Divider() }
                        }
                    }
                    if copies.count > 1 {
                        HStack {
                            Spacer(minLength: 0)
                            SecondaryButton(title: String(localized: "Alle gefunden")) { release(copies) }
                        }
                    }
                }
                if let error { AppBanner(message: error, kind: .error).transition(AppStyle.funnelTransition()) }
            }
            // Off: the marks are kept, but nothing on the shelf page shows them.
            .opacity(missingEnabled ? 1 : 0.5)
        }
        .animation(AppStyle.standardAnimation, value: copies.map(\.id))
        .animation(AppStyle.standardAnimation, value: error)
        .animation(AppStyle.standardAnimation, value: missingEnabled)
        .onChange(of: missingEnabled) { _, on in
            AppLog.info("Einstellungen", "Vermisst-Liste \(on ? "eingeschaltet" : "ausgeschaltet – Markierungen bleiben gespeichert")")
        }
        .task(id: labelSignature) { labels = labelsCache.labels(for: records.shelves, style: labelStyle) }
    }

    /// "Wohnzimmer · A – Be · Position 12"; nothing for a record without a shelf.
    private func location(_ copy: RecordCopy) -> String {
        guard let shelf = copy.shelf else { return "" }
        return labels.prefix(for: shelf) + (labels[shelf.id] ?? shelf.numberText) + " · " + String(localized: "Position \(copy.positionInShelf)")
    }

    private func release(_ copies: [RecordCopy]) {
        // Removed meanwhile (sync, reset): nothing to release.
        let present = copies.filter { !$0.isDeleted && $0.modelContext != nil }
        guard !present.isEmpty else { return }
        do { try PositionService(context: context).setMissing(present, false); error = nil }
        catch { self.error = error.reportedMessage() }
    }
}

/// Cover, artist and title as in "Platte hinzufügen", where the record
/// stands (if it has a shelf), and "Gefunden" as on the shelf page.
private struct MissingSettingsRow: View {
    let copy: RecordCopy
    let location: String
    let release: () -> Void

    var body: some View {
        let artist = copy.release?.displayArtist ?? "—"
        let title = copy.release?.displayTitle ?? "—"
        HStack(spacing: AppStyle.rowSpacing) {
            CoverView(url: copy.release?.coverURL, size: AssignmentCard<EmptyView>.coverSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(artist).font(.callout.weight(.medium))
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .help("\(artist) – \(title)")
            Spacer(minLength: AppStyle.itemSpacing)
            Text(location).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                .lineLimit(1)
            SecondaryButton(title: String(localized: "Gefunden"), action: release)
                .help(copy.shelf == nil ? String(localized: "Wieder zum Einsortieren anbieten") : String(localized: "Markierung aufheben"))
                .accessibilityLabel("\(artist) – \(title) gefunden")
        }
        .frame(height: AssignmentRowMetrics.height)
    }
}
