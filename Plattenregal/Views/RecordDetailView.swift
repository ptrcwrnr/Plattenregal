import SwiftUI
import SwiftData

struct RecordDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var exclusions: [OptimizationExclusion]
    @Query private var shelves: [Shelf]
    @AppStorage(ShelfLabelStyle.key) private var labelStyle = ShelfLabelStyle.range
    let copy: RecordCopy
    /// The calling page's current labels; computed here (once) without them.
    var labels: ShelfLabels? = nil
    var showShelf: (() -> Void)?
    @State private var labelCache = ShelfLabelCache()
    @State private var error: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Meine Schallplatte").font(AppStyle.dialogTitle); Spacer()
                GhostButton(title: "Schließen") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(.horizontal, AppStyle.pagePadding).padding(.vertical, AppStyle.cardPadding)
            Divider()
            // Without the tracklist everything fits; the sheet is as tall as its content.
            VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                if let r = copy.release {
                    ReleaseHeaderView(release: r, removedFromDiscogs: !copy.discogsActive)
                }
                locationCard
                if let error { AppBanner(message: error, kind: .error).transition(AppStyle.funnelTransition()) }
            }.padding(AppStyle.pagePadding)
            .animation(AppStyle.standardAnimation, value: error)
        }.frame(width: 800)
        .fixedSize(horizontal: false, vertical: true)
        .appGlassSurface(cornerRadius: 0)
        .presentationBackground(.clear)
    }

    private var excluded: Bool { exclusions.contains { $0.copyID == copy.id } }

    /// Where the copy stands, large and with the way to the shelf right next to
    /// it, and whether it belongs in the shelf at all ("Nicht im Regal").
    private var locationCard: some View {
        let location = ShelfRangeLabels.location(
            of: copy,
            labels: labels ?? labelCache.labels(for: shelves, style: labelStyle, showing: copy.shelf),
            excluded: excluded
        )
        return VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
          HStack(spacing: AppStyle.rowSpacing) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 30))
                .foregroundStyle(copy.shelf == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            VStack(alignment: .leading, spacing: 2) {
                Text("Standort").font(.callout).foregroundStyle(.secondary)
                Text(location).font(.title.weight(.semibold)).lineLimit(2)
            }
            Spacer(minLength: AppStyle.rowSpacing)
            if let showShelf {
                Button(copy.shelf == nil ? "Platz im Regal finden" : "Im Regal anzeigen", action: showShelf)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            }
          }
          Divider()
          Toggle(isOn: Binding(get: { excluded }, set: setExcluded)) {
              VStack(alignment: .leading, spacing: 2) {
                  Text("Nicht im Regal")
                  Text(excluded
                       ? "Die Platte bekommt kein Fach und zählt nicht zu den Platten, die noch einsortiert werden müssen."
                       : "Fach und Position vergibst du in der Rubrik Regal.")
                      .font(.caption).foregroundStyle(.secondary)
              }
          }
          .toggleStyle(.switch)
        }
        .padding(AppStyle.cardPadding + 4)
        .glassEffect(.regular.tint(AppStyle.accent.opacity(0.12)), in: .rect(cornerRadius: 16))
    }

    /// Excluding takes the copy out of its shelf; including puts it back among
    /// the records waiting to be sorted in.
    private func setExcluded(_ value: Bool) {
        // Removed while the sheet was open ("Alles zurücksetzen" in the settings window).
        guard !copy.isDeleted, copy.modelContext != nil else {
            error = LibraryError.missingRelease.errorDescription; return
        }
        do { try PositionService(context: context).setExcluded([copy], value); error = nil }
        catch { self.error = error.reportedMessage() }
    }
}
struct ReleaseHeaderView: View {
    let release: Release
    let removedFromDiscogs: Bool
    var body: some View {
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
                if removedFromDiscogs { Text("Nicht mehr in der Discogs-Collection").foregroundStyle(.secondary) }
                if let url = release.sourceURL { Link("Pressung auf Discogs öffnen ↗", destination: url) }
            }
        }
    }
}
/// Compact popover for a single click on a cover in the overview: cover,
/// label, year and the tracklist (the detail window has none). Copies behind one cover share the release,
/// so the first one stands for all of them. `expand` opens the detail window.
struct RecordPopover: View {
    @Environment(\.modelContext) private var context
    let copy: RecordCopy
    var expand: (() -> Void)? = nil
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
                Spacer(minLength: 0)
                if let expand {
                    Button(action: expand) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .help("Details öffnen")
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
