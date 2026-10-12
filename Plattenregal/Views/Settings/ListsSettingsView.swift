import SwiftUI
import SwiftData

// MARK: - Listen

/// The app's two lists of marked records.
/// - "Gesucht": marked on the shelf page, and the way back – found, a
///   record without a shelf is offered in "Einsortieren" and "Platte
///   hinzufügen" again; one standing in a shelf simply loses its mark.
/// - "Verkauf": records to be sold some day. They stay where they stand
///   until "Verkauft" takes the whole list out of the shelves.
struct ListsSettingsView: View {
    @Environment(\.modelContext) private var context
    /// Shared with the pages, fetched only when they change (see `LibraryRecords`).
    private var records: LibraryRecords { .of(context) }
    @AppStorage(DisplaySettings.missingListKey) private var missingEnabled = true
    @AppStorage(DisplaySettings.saleListKey) private var saleEnabled = true
    @AppStorage(ShelfLabelStyle.key) private var labelStyle = ShelfLabelStyle.range
    @State private var labels = ShelfLabels()
    @State private var labelsCache = ShelfLabelsCache()
    @State private var changes = LibraryChanges.shared
    @State private var error: String?
    @State private var saleError: String?
    @State private var confirmSold = false

    /// On the "Verkauf" list, by artist.
    private var forSale: [RecordCopy] {
        let ids = Set(records.saleMarks.map(\.copyID))
        guard !ids.isEmpty else { return [] }
        return ShelfAssignmentPresentation.sortedByArtist(records.copies.filter { ids.contains($0.id) })
    }

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
        let forSale = forSale
        SettingsPage {
            ListCard {
                SettingsRow(title: String(localized: "Suchliste"),
                            hint: missingEnabled
                            ? String(localized: "Für Platten, die gerade nicht zu finden sind: per Rechtsklick auf die Suchliste setzen. Bis du sie hier als gefunden markierst, werden sie nicht zum Einsortieren angeboten.")
                            : String(localized: "Aus: keine Suchliste. Bereits gesuchte Platten bleiben gemerkt, falls du sie wieder einschaltest.")) {
                    Toggle("Suchliste", isOn: $missingEnabled.animation(AppStyle.standardAnimation))
                        .labelsHidden().toggleStyle(.switch)
                }
                // Off: the marks are kept, but nothing shows them.
                if missingEnabled {
                    // The list pours out below its switch and back in.
                    VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                        Divider()
                        if copies.isEmpty {
                            SettingsNote(String(localized: "Keine Platte steht auf der Suchliste."))
                        } else {
                            SettingsNote(String(localized: "\(AppStyle.records(copies.count)) · Gefundene, noch nicht einsortierte Platten stehen wieder unter „Einsortieren“."))
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(copies) { copy in
                                    ListSettingsRow(copy: copy, location: location(copy), actionTitle: String(localized: "Gefunden"),
                                                    actionHelp: copy.shelf == nil ? String(localized: "Wieder zum Einsortieren anbieten") : String(localized: "Markierung aufheben")) { release([copy]) }
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
                    }
                    .transition(AppStyle.funnelTransition())
                }
                if let error { AppBanner(message: error, kind: .error).transition(AppStyle.funnelTransition()) }
            }

            ListCard {
                SettingsRow(title: String(localized: "Verkaufsliste"),
                            hint: saleEnabled
                            ? String(localized: "Für Platten, die du irgendwann verkaufen willst: per Rechtsklick vormerken. Sie bleiben im Regal, bis du alle verkauft hast. Als CSV oder PDF gibt es die Liste unter „Export“.")
                            : String(localized: "Aus: keine Verkaufsliste. Bereits vorgemerkte Platten bleiben gemerkt, falls du sie wieder einschaltest.")) {
                    Toggle("Verkaufsliste", isOn: $saleEnabled.animation(AppStyle.standardAnimation))
                        .labelsHidden().toggleStyle(.switch)
                }
                if saleEnabled {
                    // The list pours out below its switch and back in.
                    VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
                        Divider()
                        if forSale.isEmpty {
                            SettingsNote(String(localized: "Keine Platte ist zum Verkauf vorgemerkt."))
                        } else {
                            SettingsNote(AppStyle.records(forSale.count))
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(forSale) { copy in
                                    ListSettingsRow(copy: copy, location: location(copy), actionTitle: String(localized: "Entfernen"),
                                                    actionHelp: String(localized: "Von der Verkaufsliste nehmen")) { keep(copy) }
                                    if copy.id != forSale.last?.id { Divider() }
                                }
                            }
                            HStack {
                                Spacer(minLength: 0)
                                SecondaryButton(title: String(localized: "Verkauft")) { confirmSold = true }
                            }
                        }
                    }
                    .transition(AppStyle.funnelTransition())
                }
                if let saleError { AppBanner(message: saleError, kind: .error).transition(AppStyle.funnelTransition()) }
            }
        }
        .confirmationDialog(forSale.count == 1 ? "Die Platte auf der Verkaufsliste ist verkauft?" : "Alle \(forSale.count) Platten auf der Verkaufsliste sind verkauft?",
                            isPresented: $confirmSold) {
            Button("Verkauft") { sellAll() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Sie werden aus ihren Fächern genommen und auf „Ohne Regalplatz“ gesetzt, die übrigen Platten rücken auf, die Liste wird geleert. Aus der Collection verschwinden sie erst, wenn du sie auf Discogs entfernst und synchronisierst.")
        }
        .animation(AppStyle.standardAnimation, value: copies.map(\.id))
        .animation(AppStyle.standardAnimation, value: forSale.map(\.id))
        .animation(AppStyle.standardAnimation, value: saleError)
        .animation(AppStyle.standardAnimation, value: error)
        .animation(AppStyle.standardAnimation, value: missingEnabled)
        .animation(AppStyle.standardAnimation, value: saleEnabled)
        .onChange(of: saleEnabled) { _, on in
            AppLog.info("Einstellungen", "Verkaufsliste \(on ? "eingeschaltet" : "ausgeschaltet – Vormerkungen bleiben gespeichert")")
        }
        .onChange(of: missingEnabled) { _, on in
            AppLog.info("Einstellungen", "Suchliste \(on ? "eingeschaltet" : "ausgeschaltet – Markierungen bleiben gespeichert")")
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

    /// Off the "Verkauf" list after all.
    private func keep(_ copy: RecordCopy) {
        guard !copy.isDeleted, copy.modelContext != nil else { return }
        do { try PositionService(context: context).setForSale([copy], false); saleError = nil }
        catch { saleError = error.reportedMessage() }
    }

    private func sellAll() {
        do { try PositionService(context: context).sellAllForSale(); saleError = nil }
        catch { saleError = error.reportedMessage() }
    }
}

/// A card without a heading: the switch row names the list already.
private struct ListCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.rowSpacing) { content }
            .padding(AppStyle.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCardSurface()
    }
}

/// A row of either list: cover, artist and title, where the record stands
/// (if it has a shelf), and the list's action ("Gefunden", "Entfernen").
private struct ListSettingsRow: View {
    let copy: RecordCopy
    let location: String
    let actionTitle: String
    let actionHelp: String
    let action: () -> Void

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
            SecondaryButton(title: actionTitle, action: action)
                .help(actionHelp)
                .accessibilityLabel("\(artist) – \(title): \(actionTitle)")
        }
        .frame(height: AssignmentRowMetrics.height)
    }
}
