import SwiftUI
import SwiftData

/// Edits the user's own data of a copy (condition, price, notes, "Nicht im
/// Regal"). Records come only from the Discogs sync, and their metadata is
/// Discogs' – there is no adding or metadata editing here.
struct RecordEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var exclusions: [OptimizationExclusion]
    let copy: RecordCopy
    /// "Nicht im Regal": the copy is kept out of the shelf allocation entirely.
    @State private var notInShelf = false
    @State private var condition = "Nicht bewertet"
    @State private var price = ""
    @State private var hasDate = false
    @State private var date = Date()
    @State private var notes = ""
    @State private var error: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Exemplar bearbeiten").font(AppStyle.dialogTitle)
                Spacer()
            }.padding(.horizontal, AppStyle.pagePadding).padding(.vertical, AppStyle.cardPadding)
            Divider()
            Form {
                Section("Veröffentlichung") {
                    if let release = copy.release {
                        Text(release.displayArtist).font(.headline)
                        Text(release.displayTitle)
                        Text("Die Metadaten dieser Pressung werden von Discogs aktualisiert.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                // Shelf and position are managed only on the shelf page; here a
                // copy can just be kept out of the shelf allocation altogether.
                Section("Regal") {
                    Toggle("Nicht im Regal", isOn: $notInShelf)
                    Text(notInShelf
                         ? "Die Platte bekommt kein Fach und zählt nicht zu den Platten, die noch einsortiert werden müssen."
                         : "Fach und Position vergibst du in der Rubrik Regal.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Mein Exemplar") {
                    Picker("Zustand", selection: $condition) {
                        ForEach(conditions, id: \.self) { Text($0) }
                    }
                    TextField("Kaufpreis (€)", text: $price)
                    Toggle("Kaufdatum erfassen", isOn: $hasDate)
                    if hasDate { DatePicker("Kaufdatum", selection: $date, in: ...Date.now, displayedComponents: .date) }
                    TextField("Notizen", text: $notes, axis: .vertical).lineLimit(3...6)
                }
            }.formStyle(.grouped)
            Divider()
            HStack {
                SecondaryButton(title: "Abbrechen") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                PrimaryButton(title: "Speichern", action: save)
                    .keyboardShortcut(.defaultAction)
            }.padding(.horizontal, AppStyle.pagePadding).padding(.vertical, AppStyle.cardPadding)
        }.frame(width: 640, height: 600)
        .alert("Speichern nicht möglich", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .onAppear(perform: load)
    }
    private func load() {
        notInShelf = copy.shelf == nil && exclusions.contains { $0.copyID == copy.id }
        condition = copy.condition.isEmpty ? "Nicht bewertet" : copy.condition
        price = copy.purchasePrice.map(PriceInput.format) ?? ""
        hasDate = copy.purchaseDate != nil; date = copy.purchaseDate ?? .now
        notes = copy.notes
    }
    private func save() {
        // Removed while the sheet was open ("Alles zurücksetzen" in the
        // settings window): writing to the deleted model would crash.
        guard !copy.isDeleted, copy.modelContext != nil else {
            error = LibraryError.missingRelease.errorDescription; return
        }
        do {
            guard let parsedPrice = PriceInput.parse(price) else {
                error = "Den Kaufpreis kann Plattenregal nicht lesen. Gib ihn als Betrag ein, z. B. 24,99."; return
            }
            let service = PositionService(context: context)
            let edit = {
                copy.condition = condition; copy.purchasePrice = parsedPrice.amount
                copy.purchaseDate = hasDate ? date : nil; copy.notes = notes
            }
            if notInShelf != exclusions.contains(where: { $0.copyID == copy.id }) {
                // Excluding takes the copy out of its shelf; including puts it back
                // among the records waiting to be sorted in.
                try service.setExcluded([copy], notInShelf, edit: edit)
            } else {
                try service.save(edit)
            }
            dismiss()
        } catch { self.error = error.reportedMessage() }
    }
    private static let gradings = ["Nicht bewertet", "Mint (M)", "Near Mint (NM)", "Very Good Plus (VG+)", "Very Good (VG)", "Good (G)", "Fair (F)", "Poor (P)"]
    /// A stored value outside the list (older data) stays selectable instead
    /// of leaving the picker blank.
    private var conditions: [String] {
        Self.gradings.contains(condition) || condition.isEmpty ? Self.gradings : Self.gradings + [condition]
    }
}

/// Purchase price as typed: "24,99", "24.99", "1.234,50", "1,234.50",
/// "24,99 €", "€ 5" — at most two decimals, never negative.
enum PriceInput {
    /// `nil` = not a valid amount; `.init(amount: nil)` = field left empty.
    struct Parsed: Equatable { let amount: Decimal? }

    static func parse(_ raw: String) -> Parsed? {
        let text = raw.filter { !$0.isWhitespace && $0 != "€" }
        guard !text.isEmpty else { return Parsed(amount: nil) }
        guard text.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "," || $0 == ".") }) else { return nil }
        // The last separator followed by one or two digits is the decimal mark;
        // every other separator groups thousands (in blocks of three).
        var integer = text, fraction = ""
        if let last = text.lastIndex(where: { $0 == "," || $0 == "." }) {
            let tail = text[text.index(after: last)...]
            if (1...2).contains(tail.count) {
                integer = String(text[..<last]); fraction = String(tail)
                // One character can't be both: "12,345,6" is ambiguous.
                if integer.contains(text[last]) { return nil }
            }
        }
        // Grouping uses one kind of separator only ("1.234.567", not "1.234,567").
        if integer.contains(",") && integer.contains(".") { return nil }
        let groups = integer.split(separator: ",", omittingEmptySubsequences: false)
            .flatMap { $0.split(separator: ".", omittingEmptySubsequences: false) }
        guard let first = groups.first, !first.isEmpty,
              groups.count == 1 || (first.count <= 3 && groups.dropFirst().allSatisfy { $0.count == 3 })
        else { return nil }
        let number = groups.joined() + (fraction.isEmpty ? "" : "." + fraction)
        guard let amount = Decimal(string: number, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return Parsed(amount: amount)
    }

    /// For the text field: "24,99", "12,50", "30" in the user's locale.
    static func format(_ amount: Decimal) -> String {
        let whole = amount == amount.rounded(0)
        return amount.formatted(.number.grouping(.never).precision(.fractionLength(whole ? 0 : 2)))
    }
}

private extension Decimal {
    func rounded(_ scale: Int) -> Decimal {
        var value = self, result = Decimal()
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }
}
