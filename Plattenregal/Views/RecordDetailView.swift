import SwiftUI
import SwiftData

struct RecordDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var exclusions: [OptimizationExclusion]
    @Query private var shelves: [Shelf]
    @AppStorage(ShelfLabelStyle.key) private var labelStyle = ShelfLabelStyle.range
    @Query private var folders: [DiscogsFolder]
    let copy: RecordCopy
    /// The calling page's current labels; computed here (once) without them.
    var labels: ShelfLabels? = nil
    var showShelf: (() -> Void)?
    @State private var labelCache = ShelfLabelCache()
    @State private var editing = false
    @State private var refresh = MetadataRefreshService()
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Meine Schallplatte").font(AppStyle.dialogTitle); Spacer()
                GhostButton(title: "Bearbeiten") { editing = true }
                GhostButton(title: "Schließen") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(.horizontal, AppStyle.pagePadding).padding(.vertical, AppStyle.cardPadding)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                    if let r = copy.release {
                        ReleaseMetadataView(release: r)
                        if !r.isFresh && !DemoMode.isActive {
                            // Just this release — `refresh` would start a sync of the whole collection.
                            GhostButton(title: "Discogs-Daten aktualisieren") { Task { await refresh.reload([r], context: context) } }
                                .disabled(refresh.busy || DiscogsSyncService.shared.busy)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Discogs").font(.headline)
                        Text(copy.discogsActive ? "In der Collection · Ordner „\(folderName)“" : "Nicht mehr in der Discogs-Collection")
                        Text("Bewertung: \(rating) · Hinzugefügt: \(DiscogsDate.parse(copy.discogsDateAdded)?.formatted(date: .abbreviated, time: .omitted) ?? "—")")
                        if let data = copy.discogsNotes, let notes = try? JSONDecoder().decode([DiscogsNote].self, from: data) {
                            ForEach(notes.filter { !$0.value.isEmpty }, id: \.field_id) { Text("\($0.fieldTitle): \($0.value)") }
                        }
                    }
                    Divider()
                    HStack {
                        Label(ShelfRangeLabels.location(of: copy, labels: labels ?? labelCache.labels(for: shelves, style: labelStyle, showing: copy.shelf), excluded: exclusions.contains { $0.copyID == copy.id }), systemImage: "square.grid.3x3").font(AppStyle.dialogTitle).foregroundStyle(.tint)
                        Spacer()
                        if let showShelf { GhostButton(title: copy.shelf == nil ? "Platz im Regal finden" : "Im Regal anzeigen", action: showShelf) }
                    }
                    Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 12) {
                        GridRow { Text("Zustand").foregroundStyle(.secondary); Text(copy.condition.isEmpty ? "—" : copy.condition) }
                        GridRow { Text("Kaufpreis").foregroundStyle(.secondary); Text(copy.purchasePrice.map { $0.formatted(.currency(code: "EUR")) } ?? "—") }
                        GridRow { Text("Kaufdatum").foregroundStyle(.secondary); Text(copy.purchaseDate?.formatted(date: .abbreviated, time: .omitted) ?? "—") }
                        GridRow { Text("Hinzugefügt").foregroundStyle(.secondary); Text(copy.dateAdded.formatted(date: .abbreviated, time: .omitted)) }
                    }
                    Text("Notizen").font(.headline)
                    Text(copy.notes.isEmpty ? "Noch keine Notizen." : copy.notes).textSelection(.enabled)
                    if let error = refresh.error { AppBanner(message: error, kind: .error).transition(AppStyle.funnelTransition()) }
                }.padding(AppStyle.pagePadding)
                .animation(AppStyle.standardAnimation, value: refresh.error)
            }
        }.frame(width: 800, height: 760)
        .sheet(isPresented: $editing) { RecordEditor(copy: copy) }
    }

    private var folderName: String {
        guard let id = copy.discogsFolderID else { return "Unbekannt" }
        return folders.first { $0.folderID == id && $0.owner == copy.discogsOwner }?.name
            ?? (id == 1 ? "Uncategorized" : "Ordner \(id)")
    }
    private var rating: String {
        guard let stars = copy.discogsRating, stars > 0 else { return "keine" }
        return String(repeating: "★", count: stars) + String(repeating: "☆", count: max(0, 5 - stars))
    }
}
struct ReleaseMetadataView: View {
    let release: Release
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
            HStack(alignment: .top, spacing: AppStyle.sectionSpacing) {
                CoverView(url: release.coverURL, size: 220)
                VStack(alignment: .leading, spacing: 10) {
                    Text(release.displayArtist).font(.title2).foregroundStyle(.secondary)
                    Text(release.displayTitle).font(AppStyle.pageTitle).textSelection(.enabled)
                    Text([release.year.map(String.init), release.country.isEmpty ? nil : release.country, release.format].compactMap { $0 }.joined(separator: " · "))
                    Text(release.displayLabel).font(.headline)
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

/// Compact popover for a single click on a cover in the overview: cover,
/// label, year and the tracklist. Copies behind one cover share the release,
/// so the first one stands for all of them.
struct RecordPopover: View {
    @Environment(\.modelContext) private var context
    let copy: RecordCopy
    /// Tracklists are loaded after each collection sync; this only covers a
    /// record whose tracklist isn't there yet (e.g. while that is still running).
    @State private var loadingTracks = false
    /// Why the tracklist couldn't be loaded, in plain words; nil = no failure.
    @State private var trackLoadError: String?
    @State private var triedLoadingTracks = false

    var body: some View {
        let release = copy.release
        VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
            HStack(alignment: .top, spacing: AppStyle.rowSpacing + 2) {
                CoverView(url: release?.coverURL, size: 128)
                VStack(alignment: .leading, spacing: AppStyle.tightSpacing) {
                    Text(release?.displayArtist ?? "Unbekannt")
                        .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    Text(release?.displayTitle ?? "—")
                        .font(AppStyle.sectionTitle).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Grid(alignment: .leading, horizontalSpacing: AppStyle.itemSpacing, verticalSpacing: 3) {
                        GridRow { label("Label:"); Text(release.map { $0.label.isEmpty ? "–" : $0.displayLabel } ?? "–").lineLimit(2) }
                        GridRow { label("Jahr:"); Text(release?.year.map(String.init) ?? "–").monospacedDigit() }
                        GridRow { label("Style:"); Text(release.map { $0.primaryStyle.isEmpty ? "–" : $0.primaryStyle } ?? "–").lineLimit(1) }
                    }
                    .font(.callout)
                    .padding(.top, AppStyle.tightSpacing)
                }
            }

            if let tracks = release?.tracks, !tracks.isEmpty {
                Divider()
                Text("Tracklist").font(.headline)
                trackList(tracks)
            } else if loadingTracks || triedLoadingTracks {
                Divider()
                Text("Tracklist").font(.headline)
                if loadingTracks {
                    HStack(spacing: AppStyle.itemSpacing) {
                        ProgressView().controlSize(.small)
                        Text("Wird von Discogs geladen …")
                    }
                    .font(.callout).foregroundStyle(.secondary)
                } else {
                    Text(trackLoadError.map { "Die Tracklist konnte nicht geladen werden. \($0)" } ?? "Bei Discogs ist für diese Platte keine Tracklist hinterlegt.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .padding(AppStyle.cardPadding)
        .frame(width: 400)
        .task(id: copy.id) {
            // The demo is offline and has no tracklists; no attempt, no error.
            guard !DemoMode.isActive, let release = copy.release, release.tracks.isEmpty else { return }
            // Already asked: Discogs has no tracklist for it. Not again on every
            // opening – that cost a request and a spinner each time.
            if release.detailsFetchedAt != nil { triedLoadingTracks = true; return }
            // A running sync rewrites the same releases; the download after it
            // brings the tracklist.
            guard !DiscogsSyncService.shared.busy else { return }
            loadingTracks = true
            do { try await DiscogsSyncService.shared.loadTracklist(for: release, context: context) }
            catch is CancellationError { loadingTracks = false; return }
            catch { trackLoadError = error.reportedMessage() }
            loadingTracks = false; triedLoadingTracks = true
        }
    }

    private func trackList(_ tracks: [Track]) -> some View {
        ScrollView {
            Grid(alignment: .leading, horizontalSpacing: AppStyle.rowSpacing, verticalSpacing: 5) {
                ForEach(Array(tracks.enumerated()), id: \.offset) { _, track in
                    GridRow {
                        Text(track.position).monospaced().foregroundStyle(.secondary)
                        Text(track.title).lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(track.duration).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            .font(.callout)
        }
        .frame(maxHeight: 220)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary)
    }
}
