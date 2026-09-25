import SwiftUI
import SwiftData

/// Edits what belongs to the copy itself: whether it is kept out of the
/// shelves ("Nicht im Regal"). Records come only from the Discogs sync, and
/// their metadata is Discogs' – there is no adding or metadata editing here.
struct RecordEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var exclusions: [OptimizationExclusion]
    let copy: RecordCopy
    /// "Nicht im Regal": the copy is kept out of the shelf allocation entirely.
    @State private var notInShelf = false
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
            }.formStyle(.grouped)
            Divider()
            HStack {
                SecondaryButton(title: "Abbrechen") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                PrimaryButton(title: "Speichern", action: save)
                    .keyboardShortcut(.defaultAction)
            }.padding(.horizontal, AppStyle.pagePadding).padding(.vertical, AppStyle.cardPadding)
        }.frame(width: 640, height: 400)
        .alert("Speichern nicht möglich", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .onAppear(perform: load)
    }
    private func load() {
        notInShelf = copy.shelf == nil && exclusions.contains { $0.copyID == copy.id }
    }
    private func save() {
        // Removed while the sheet was open ("Alles zurücksetzen" in the
        // settings window): writing to the deleted model would crash.
        guard !copy.isDeleted, copy.modelContext != nil else {
            error = LibraryError.missingRelease.errorDescription; return
        }
        do {
            if notInShelf != exclusions.contains(where: { $0.copyID == copy.id }) {
                // Excluding takes the copy out of its shelf; including puts it back
                // among the records waiting to be sorted in.
                try PositionService(context: context).setExcluded([copy], notInShelf)
            }
            dismiss()
        } catch { self.error = error.reportedMessage() }
    }
}
