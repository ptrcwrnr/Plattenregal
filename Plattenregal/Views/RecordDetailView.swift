import SwiftUI
import SwiftData

struct RecordDetailView: View {
    @Environment(\.modelContext) private var context
    @Query private var exclusions: [OptimizationExclusion]
    @Query private var shelves: [Shelf]
    @AppStorage(ShelfLabelStyle.key) private var labelStyle = ShelfLabelStyle.range
    let copy: RecordCopy
    var showShelf: (() -> Void)?
    @State private var labelCache = ShelfLabelCache()
    @State private var error: String?
    var body: some View {
        VStack(spacing: 0) {
            // Without the tracklist everything fits; the panel is as tall as its content.
            VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                if let r = copy.release {
                    ReleaseHeaderView(release: r, removedFromDiscogs: !copy.discogsActive)
                }
                locationCard
                if let error { AppBanner(message: error, kind: .error).transition(AppStyle.funnelTransition()) }
            }.padding(.horizontal, AppStyle.pagePadding).padding(.vertical, AppStyle.pagePadding)
            .animation(AppStyle.standardAnimation, value: error)
        }.frame(width: 800)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var excluded: Bool { exclusions.contains { $0.copyID == copy.id } }

    /// Where the copy stands, large and with the way to the shelf right next to
    /// it, and whether it belongs in the shelf at all ("Ohne Regalplatz").
    private var locationCard: some View {
        let location = ShelfRangeLabels.location(
            of: copy,
            labels: labelCache.labels(for: shelves, style: labelStyle, showing: copy.shelf),
            excluded: excluded
        )
        return VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
          HStack(spacing: AppStyle.rowSpacing) {
            Image(systemName: "square.grid.3x3.fill")
                .font(AppStyle.cardSymbol)
                .foregroundStyle(copy.shelf == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
                Text("Standort").font(.callout).foregroundStyle(.secondary)
                Text(location).font(AppStyle.pageTitle).lineLimit(2)
            }
            Spacer(minLength: AppStyle.rowSpacing)
            if let showShelf {
                Button(action: showShelf) {
                    Text(copy.shelf == nil ? "Platz im Regal finden" : "Im Regal anzeigen").foregroundStyle(AppStyle.accent)
                }
                .appGlassButton()
                .controlSize(.large)
            }
          }
          Divider()
          SettingsRow(title: String(localized: "Ohne Regalplatz"), hint: excluded
                      ? String(localized: "Die Platte bekommt kein Fach und zählt nicht zu den Platten, die noch einsortiert werden müssen.")
                      : String(localized: "Fach und Position vergibst du in der Rubrik Regal.")) {
              Toggle("Ohne Regalplatz", isOn: Binding(get: { excluded }, set: setExcluded))
                  .labelsHidden().toggleStyle(.switch)
          }
        }
        .padding(AppStyle.sectionSpacing)
        .accentGlassCard()
    }

    /// Excluding takes the copy out of its shelf; including puts it back among
    /// the records waiting to be sorted in.
    private func setExcluded(_ value: Bool) {
        // Removed while the panel was open ("Alles zurücksetzen" in the settings window).
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
        // Same language as the "Zufallsfund" on the statistics page: small
        // captions over their values, styles as badges.
        HStack(alignment: .top, spacing: AppStyle.sectionSpacing) {
            CoverView(url: release.coverURL, size: 220)
                .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
            VStack(alignment: .leading, spacing: AppStyle.cardPadding) {
                VStack(alignment: .leading, spacing: AppStyle.tightSpacing) {
                    Text(release.displayArtist).font(.title2).foregroundStyle(.secondary).lineLimit(2)
                    Text(release.displayTitle).font(AppStyle.pageTitle).lineLimit(3)
                }
                .textSelection(.enabled)
                Grid(alignment: .leading, horizontalSpacing: AppStyle.sectionSpacing, verticalSpacing: AppStyle.rowSpacing) {
                    GridRow {
                        detail(String(localized: "Jahr"), release.year.map(String.init))
                        detail(String(localized: "Land"), release.country)
                        detail(String(localized: "Format"), release.format)
                    }
                    GridRow {
                        detail(String(localized: "Label"), release.displayLabel)
                        detail(String(localized: "Katalognummer"), release.catalogNumber)
                        detail(String(localized: "Genre"), release.genres.joined(separator: " · "))
                    }
                }
                if !release.styles.isEmpty || removedFromDiscogs {
                    HStack(spacing: AppStyle.itemSpacing) {
                        ForEach(release.styles.prefix(5), id: \.self) { AppBadge(title: $0) }
                        if removedFromDiscogs { AppBadge(title: String(localized: "Nicht mehr in der Discogs-Collection"), systemImage: "exclamationmark.circle") }
                    }
                }
                if let url = release.sourceURL {
                    Link(destination: url) {
                        Label("Auf Discogs öffnen", systemImage: "arrow.up.forward")
                    }
                    .appGlassButton()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func detail(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value.flatMap { $0.isEmpty ? nil : $0 } ?? "—").font(.callout.weight(.medium)).lineLimit(2)
                .textSelection(.enabled)
        }
    }
}
/// Compact popover for a click on a cover in the collection or wantlist:
/// cover, label, year and the tracklist. Copies behind one cover share the
/// release, so the first one stands for all of them.
struct RecordPopover: View {
    @Environment(\.modelContext) private var context
    let release: Release?
    /// Shown as a small arrow in the corner (the wantlist, whose covers have
    /// no other way to Discogs than the menu).
    var discogsURL: URL?
    @Environment(\.openURL) private var openURL

    /// The release's videos from Discogs (at most one row); live, so links
    /// appear as soon as the background download has stored them.
    @Query private var videoLists: [ReleaseVideoList]

    init(copy: RecordCopy) { self.init(release: copy.release) }
    init(release: Release?, discogsURL: URL? = nil) {
        self.release = release
        self.discogsURL = discogsURL
        let id = release?.discogsID ?? -1
        _videoLists = Query(filter: #Predicate<ReleaseVideoList> { $0.discogsID == id })
    }
    /// Tracklists are loaded after each collection sync; this only covers a
    /// record whose tracklist isn't there yet (e.g. while that is still running).
    @State private var loadingTracks = false
    /// Why the tracklist couldn't be loaded, in plain words; nil = no failure.
    @State private var trackLoadError: String?
    @State private var triedLoadingTracks = false
    /// Width of the position column (A1, B2 …), measured from the tracklist.
    @State private var positionWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
            HStack(alignment: .top, spacing: AppStyle.rowSpacing) {
                CoverView(url: release?.coverURL, size: 128)
                VStack(alignment: .leading, spacing: AppStyle.tightSpacing) {
                    Text(release?.displayArtist ?? String(localized: "Unbekannt"))
                        .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    Text(release?.displayTitle ?? "—")
                        .font(AppStyle.sectionTitle).lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Grid(alignment: .leading, horizontalSpacing: AppStyle.itemSpacing, verticalSpacing: 3) {
                        GridRow { label(String(localized: "Label")); Text(release.map { $0.label.isEmpty ? "–" : $0.displayLabel } ?? "–").lineLimit(2) }
                        GridRow { label(String(localized: "Jahr")); Text(release?.year.map(String.init) ?? "–").monospacedDigit() }
                        GridRow { label(String(localized: "Style")); Text(release.map { $0.primaryStyle.isEmpty ? "–" : $0.primaryStyle } ?? "–").lineLimit(1) }
                    }
                    .font(.callout)
                    .padding(.top, AppStyle.tightSpacing)
                }
                Spacer(minLength: 0)
                if let discogsURL {
                    Button { openURL(discogsURL) } label: {
                        Image(systemName: "arrow.up.forward")
                            .font(AppStyle.buttonSymbol)
                            .frame(width: 26, height: 26)
                            .contentShape(Circle())
                            .background {
                                if AppStyle.isAtelier {
                                    Circle().fill(AtelierPalette.soft)
                                        .overlay(Circle().strokeBorder(AtelierPalette.border, lineWidth: 1))
                                }
                            }
                            .glassEffect(AppStyle.isAtelier ? .identity : .regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .help("Auf Discogs öffnen")
                    .accessibilityLabel("Auf Discogs öffnen")
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
                        ActivityRing(size: 13)
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
        .background {
            if AppStyle.isAtelier { AtelierPalette.surface }
        }
        .task(id: release?.persistentModelID) {
            // The demo is offline and has no tracklists; no attempt, no error.
            guard !DemoMode.isActive, let release else { return }
            guard release.tracks.isEmpty else {
                // Tracklist from before videos were stored: fetch the videos
                // quietly now instead of waiting for the background download.
                // Until then (or if it fails) a click searches on YouTube.
                guard videoLists.isEmpty, !DiscogsSyncService.shared.busy, !DiscogsSyncService.shared.tracklistsLoading else { return }
                try? await DiscogsSyncService.shared.loadTracklist(for: release, context: context)
                return
            }
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
        .appPopoverSurface()
    }

    /// Each track opens its video on YouTube – the one Discogs lists for it,
    /// or else a search for it. At rest the list looks as before; a row
    /// lights up under the pointer like every other clickable row.
    private func trackList(_ tracks: [Track]) -> some View {
        let links = TrackVideoLink.urls(for: tracks, videos: videoLists.first?.videos ?? [], artist: release?.artist ?? "")
        return ScrollView {
            VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
                ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                    TrackLinkRow(track: track, url: links[index], positionWidth: positionWidth)
                }
            }
            .font(.callout)
            // The widest position sets the column, like the grid did before.
            .background {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(Set(tracks.map(\.position))), id: \.self) { Text($0).monospaced() }
                }
                .font(.callout).fixedSize().hidden()
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { positionWidth = $0 }
            }
        }
        // The rows' hover background reaches past the text; the list keeps
        // its edge in line with the heading above.
        .padding(.horizontal, -AppStyle.tightSpacing)
        .frame(maxHeight: 220)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary)
    }
}

/// A track in the popover's tracklist as a button: position, title and
/// duration as before, the hover background of the app's rows, and a hint
/// whether the click opens a video or a search.
private struct TrackLinkRow: View {
    let track: Track
    let url: URL
    let positionWidth: CGFloat
    @Environment(\.openURL) private var openURL
    @State private var hovering = false

    var body: some View {
        let isSearch = TrackVideoLink.isSearch(url)
        Button { openURL(url) } label: {
            HStack(alignment: .firstTextBaseline, spacing: AppStyle.rowSpacing) {
                Text(track.position).monospaced().foregroundStyle(.secondary)
                    .frame(width: positionWidth, alignment: .leading)
                Text(track.title).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(track.duration).monospacedDigit().foregroundStyle(.secondary)
            }
            .padding(.horizontal, AppStyle.tightSpacing)
            .padding(.vertical, AppStyle.hairSpacing)
            .contentShape(Rectangle())
            .appHoverable(hovering, cornerRadius: AppStyle.menuRowRadius)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(isSearch ? "Auf YouTube suchen" : "Video auf YouTube öffnen")
        .accessibilityLabel("\(track.position) \(track.title)")
        .accessibilityHint(isSearch ? "Sucht den Track auf YouTube" : "Öffnet das Video auf YouTube")
    }
}
