import SwiftUI
import SwiftData

struct RecordDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let copy: RecordCopy
    var showShelf: (() -> Void)?
    @State private var editing = false
    @State private var refresh = MetadataRefreshService()
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Meine Schallplatte").font(AppStyle.dialogTitle); Spacer()
                Button("Bearbeiten") { editing = true }
                Button("Schließen") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(.horizontal, AppStyle.pagePadding).padding(.vertical, AppStyle.cardPadding)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let r = copy.release {
                        ReleaseMetadataView(release: r)
                        if !r.isFresh {
                            Button("Discogs-Daten aktualisieren") { Task { await refresh.refresh([r], context: context) } }.disabled(refresh.busy)
                        }
                    }
                    if let instance = copy.discogsInstanceID {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Discogs · Instanz \(instance)").font(.headline)
                            Text(copy.discogsActive == true ? "In der Collection · Ordner-ID: \(copy.discogsFolderID.map(String.init) ?? "unbekannt")" : "Nicht mehr in der Discogs-Collection")
                            Text("Bewertung: \(copy.discogsRating ?? 0)/5 · Hinzugefügt: \(copy.discogsDateAdded ?? "—")")
                            if let data = copy.discogsNotes, let notes = try? JSONDecoder().decode([DiscogsNote].self, from: data) {
                                ForEach(notes, id: \.field_id) { Text("Discogs-Feld \($0.field_id): \($0.value)") }
                            }
                        }
                    }
                    Divider()
                    HStack {
                        Label(copy.location, systemImage: "square.grid.3x3").font(AppStyle.dialogTitle).foregroundStyle(.tint)
                        Spacer()
                        if let showShelf { Button("Im Regal anzeigen", action: showShelf) }
                        Button("Platz ändern") { editing = true }
                    }
                    Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 12) {
                        GridRow { Text("Zustand").foregroundStyle(.secondary); Text(copy.condition) }
                        GridRow { Text("Kaufpreis").foregroundStyle(.secondary); Text(copy.purchasePrice.map { $0.formatted(.currency(code: "EUR")) } ?? "—") }
                        GridRow { Text("Kaufdatum").foregroundStyle(.secondary); Text(copy.purchaseDate?.formatted(date: .abbreviated, time: .omitted) ?? "—") }
                        GridRow { Text("Hinzugefügt").foregroundStyle(.secondary); Text(copy.dateAdded.formatted(date: .abbreviated, time: .omitted)) }
                    }
                    Text("Notizen").font(.headline)
                    Text(copy.notes.isEmpty ? "Noch keine Notizen." : copy.notes).textSelection(.enabled)
                    if let error = refresh.error { Text(error).foregroundStyle(.red) }
                }.padding(AppStyle.pagePadding)
            }
        }.frame(width: 800, height: 760)
        .sheet(isPresented: $editing) { RecordEditor(copy: copy) }
    }
}
struct ReleaseMetadataView: View {
    @Environment(\.metadataClock) private var metadataClock
    let release: Release
    var body: some View {
        let _ = metadataClock
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 24) {
                CoverView(url: release.coverURL, size: 220)
                VStack(alignment: .leading, spacing: 10) {
                    Text(release.displayArtist).font(.title2).foregroundStyle(.secondary)
                    Text(release.displayTitle).font(AppStyle.pageTitle).textSelection(.enabled)
                    Text([release.year.map(String.init), release.country.isEmpty ? nil : release.country, release.format].compactMap { $0 }.joined(separator: " · "))
                    Text(release.label).font(.headline)
                    Text(release.catalogNumber).foregroundStyle(.secondary)
                    Text(release.genres.joined(separator: " · "))
                    Text(release.styles.joined(separator: " · ")).foregroundStyle(.secondary)
                    if let url = release.sourceURL { Link("Pressung auf Discogs öffnen ↗", destination: url) }
                }
            }
            if !release.tracks.isEmpty {
                Text("Tracklist").font(.headline)
                ForEach(Array(release.tracks.enumerated()), id: \.offset) { _, track in
                    HStack {
                        Text(track.position).monospaced().foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
                        Text(track.title); Spacer(); Text(track.duration).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            if !release.isFresh {
                Text("Gespeicherter Stand · wird beim nächsten Discogs-Abgleich aktualisiert.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
