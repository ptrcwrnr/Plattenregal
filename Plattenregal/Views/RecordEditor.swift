import SwiftUI
import SwiftData

struct RecordEditor: View {
    @Environment(\.metadataClock) private var metadataClock
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Shelf.number) private var shelves: [Shelf]
    @Query private var releases: [Release]
    var copy: RecordCopy?
    var importedRelease: Release?
    @State private var artist = ""
    @State private var title = ""
    @State private var year = ""
    @State private var label = ""
    @State private var catalog = ""
    @State private var country = ""
    @State private var format = "Vinyl"
    @State private var genres = ""
    @State private var styles = ""
    @State private var cover = ""
    @State private var shelfID: UUID?
    @State private var position = 1
    @State private var condition = "Nicht bewertet"
    @State private var price = ""
    @State private var hasDate = false
    @State private var date = Date()
    @State private var notes = ""
    @State private var error: String?
    private var source: Release? { copy?.release ?? importedRelease }
    private var isDiscogs: Bool { source?.discogsID != nil }
    private var selectedShelf: Shelf? { shelves.first { $0.id == shelfID } }
    private var maximumPosition: Int { max(1, (selectedShelf?.copies.filter { $0.id != copy?.id }.count ?? 0) + 1) }
    var body: some View {
        let _ = metadataClock
        VStack(spacing: 0) {
            HStack {
                Text(copy == nil ? "Schallplatte hinzufügen" : "Exemplar bearbeiten").font(AppStyle.dialogTitle)
                Spacer()
            }.padding(.horizontal, AppStyle.pagePadding).padding(.vertical, AppStyle.cardPadding)
            Divider()
            Form {
                Section("Veröffentlichung") {
                    if isDiscogs, let source {
                        Text(source.displayArtist).font(.headline)
                        Text(source.displayTitle)
                        Text("Die Metadaten dieser Pressung werden von Discogs aktualisiert.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        TextField("Interpret *", text: $artist)
                        TextField("Titel *", text: $title)
                        TextField("Jahr", text: $year)
                        TextField("Label", text: $label)
                        TextField("Katalognummer", text: $catalog)
                        TextField("Land", text: $country)
                        TextField("Format", text: $format)
                        TextField("Genres (mit Komma trennen)", text: $genres)
                        TextField("Styles (mit Komma trennen)", text: $styles)
                        TextField("Cover-URL (HTTPS, optional)", text: $cover)
                        if let source, source.copies.count > 1 {
                            Text("Metadatenänderungen gelten für alle \(source.copies.count) Exemplare dieser Veröffentlichung.").font(.caption)
                        }
                    }
                }
                Section("Physischer Platz") {
                    Picker("Fach", selection: $shelfID) {
                        if copy != nil { Text("Noch keinem Fach zugeordnet").tag(nil as UUID?) }
                        ForEach(shelves) { shelf in Text("\(shelf.title) (\(shelf.copies.count)/\(shelf.capacity))").tag(Optional(shelf.id)) }
                    }
                    if selectedShelf != nil { Stepper("Position: \(position)", value: $position, in: 1...maximumPosition) }
                    Text("Position 1 ist links im Fach. Beim Einfügen rücken nachfolgende Platten nach rechts.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Mein Exemplar") {
                    Picker("Zustand", selection: $condition) {
                        ForEach(["Nicht bewertet", "Mint (M)", "Near Mint (NM)", "Very Good Plus (VG+)", "Very Good (VG)", "Good (G)", "Fair (F)", "Poor (P)"], id: \.self) { Text($0) }
                    }
                    TextField("Kaufpreis (€)", text: $price)
                    Toggle("Kaufdatum erfassen", isOn: $hasDate)
                    if hasDate { DatePicker("Kaufdatum", selection: $date, displayedComponents: .date) }
                    TextField("Notizen", text: $notes, axis: .vertical).lineLimit(3...6)
                }
            }.formStyle(.grouped)
            Divider()
            HStack {
                Button("Abbrechen") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(copy == nil ? "Zur Sammlung hinzufügen" : "Speichern", action: save)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.padding(.horizontal, AppStyle.pagePadding).padding(.vertical, AppStyle.cardPadding)
        }.frame(width: 640, height: 780)
        .alert("Speichern nicht möglich", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .onAppear(perform: load)
        .onChange(of: shelfID) { _, _ in position = min(position, maximumPosition) }
    }
    private func load() {
        if let r = source {
            artist = r.artist; title = r.title; year = r.year.map(String.init) ?? ""
            label = r.label; catalog = r.catalogNumber; country = r.country; format = r.format
            genres = r.genres.joined(separator: ", "); styles = r.styles.joined(separator: ", "); cover = r.coverURL ?? ""
        }
        if let copy {
            shelfID = copy.shelf?.id; position = max(1, copy.positionInShelf); condition = copy.condition
            price = copy.purchasePrice.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
            hasDate = copy.purchaseDate != nil; date = copy.purchaseDate ?? .now
            notes = copy.notes
        } else {
            let target = shelves.first { $0.copies.count < $0.capacity } ?? shelves.first
            shelfID = target?.id; position = (target?.copies.count ?? 0) + 1
        }
    }
    private func save() {
        do {
            let shelf = selectedShelf
            let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let year = year.trimmingCharacters(in: .whitespaces)
            let priceText = price.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
            let parsedPrice = Decimal(string: priceText, locale: Locale(identifier: "en_US_POSIX"))
            guard !artist.isEmpty, !title.isEmpty,
                  year.isEmpty || (Int(year).map { (1...9999).contains($0) } ?? false),
                  priceText.isEmpty || (priceText.range(of: #"^\d+(\.\d{1,2})?$"#, options: .regularExpression) != nil && parsedPrice != nil)
            else { throw LibraryError.invalidMetadata }
            if !isDiscogs && !cover.isEmpty {
                guard let url = URL(string: cover), url.scheme == "https", url.host != nil else {
                    error = "Bitte gib eine gültige HTTPS-Adresse für das Cover ein."; return
                }
            }
            if isDiscogs && copy == nil && source?.isFresh != true { throw LibraryError.staleData }
            let service = PositionService(context: context)
            let editCopy: (RecordCopy) -> Void = { item in
                item.condition = condition; item.purchasePrice = priceText.isEmpty ? nil : parsedPrice
                item.purchaseDate = hasDate ? date : nil; item.notes = notes
            }
            let editRelease: (Release) -> Void = { r in
                guard !isDiscogs else { return }
                r.artist = artist; r.title = title; r.year = Int(year); r.label = label; r.catalogNumber = catalog
                r.country = country; r.format = format; r.genres = split(genres); r.styles = split(styles)
                r.coverURL = cover.isEmpty ? nil : cover
            }
            if let copy, let release = copy.release {
                if let shelf {
                    try service.move(copy, to: shelf, position: position) { editCopy(copy); editRelease(release) }
                } else {
                    try service.unplace(copy) { editCopy(copy); editRelease(release) }
                }
            } else {
                guard let shelf else { throw LibraryError.missingRelease }
                let existing = importedRelease.flatMap { incoming in releases.first { $0.discogsID == incoming.discogsID && incoming.discogsID != nil } }
                let release = existing ?? importedRelease ?? Release(artist: artist, title: title)
                try service.validate(shelf: shelf, position: position)
                // Insert and metadata edits are committed together by PositionService.
                try service.insert(release: release, shelf: shelf, position: position) { item in
                    if let existing, let importedRelease { existing.updateMetadata(from: importedRelease) }
                    editRelease(release); editCopy(item)
                }
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
    private func split(_ text: String) -> [String] { text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
}
