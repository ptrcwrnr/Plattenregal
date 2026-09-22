import SwiftUI

struct DiscogsSearchView: View {
    @State private var model = DiscogsSearchModel()
    var body: some View {
        @Bindable var model = model
        AppPageLayout {
            VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                AppPageHeading(title: "Finde die richtige Pressung.",
                    subtitle: "Die Suche zeigt konkrete Vinyl-Releases. Prüfe Land, Katalognummer und Format vor dem Übernehmen.")
                HStack(spacing: AppStyle.rowSpacing) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Zum Beispiel: Depeche Mode Violator", text: $model.query)
                        .textFieldStyle(.plain).frame(maxWidth: .infinity)
                        .onSubmit { Task { await model.search() } }
                    if model.busy { ProgressView().controlSize(.small) }
                    PrimaryButton(title: "Suchen") { Task { await model.search() } }
                        .fixedSize()
                        .disabled(model.busy || model.query.trimmingCharacters(in: .whitespaces).isEmpty)
                }.padding(AppStyle.cardPadding).appControlSurface()
                if let error = model.error { AppBanner(message: error, kind: .error) }
            }
        } content: {
            if model.fresh && !model.results.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 360, maximum: 520), spacing: 20, alignment: .top)],
                            alignment: .leading,
                            spacing: 20
                        ) {
                            ForEach(model.results) { result in
                                DiscogsSearchResultCard(result: result, busy: model.busy) {
                                    Task { await model.select(result) }
                                }
                            }
                        }
                        if model.page < model.pages {
                            Button("Weitere Pressungen laden (Seite \(model.page) von \(model.pages))") { Task { await model.search(more: true) } }
                                .disabled(model.busy)
                        }
                    }.padding(AppStyle.pagePadding)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if model.fresh {
                AppEmptyState("Keine passenden Vinyl-Releases", systemImage: "magnifyingglass", description: Text("Versuche einen anderen Titel, Künstler oder eine Katalognummer."))
            } else {
                AppEmptyState(model.searched ? "Suche bitte erneut ausführen" : "Discogs durchsuchen", systemImage: "magnifyingglass", description: Text(model.searched ? "Die Suchdaten sind abgelaufen." : "Hinterlege zuerst deinen persönlichen Token in den Einstellungen."))
            }
        }
        .sheet(item: $model.preview) { release in DiscogsPreviewView(release: release) }
    }
}
private struct DiscogsSearchResultCard: View {
    let result: DiscogsSearchResult
    let busy: Bool
    let onSelect: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        LinkResultCard(coverURL: result.thumb, onOpen: { openURL(result.sourceURL) }) {
            VStack(alignment: .leading, spacing: 5) {
                Text(result.title).font(.headline).lineLimit(2)
                Text([result.year, result.country, result.catno].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                Text((result.label ?? []).joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text((result.format ?? []).joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        } trailing: { hovering in
            VStack(spacing: AppStyle.rowSpacing) {
                Button(action: onSelect) {
                    Image(systemName: "list.bullet")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .help("Tracklist prüfen")

                Image(systemName: "arrow.up.forward.square")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .opacity(hovering ? 1 : 0.4)
            }
        }
    }
}
struct DiscogsPreviewView: View {
    @Environment(\.metadataClock) private var metadataClock
    let release: Release
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let _ = metadataClock
        VStack(spacing: 0) {
            AppSheetHeader(title: "Tracklist · Release #\(release.discogsID ?? 0)", onClose: { dismiss() })
            ScrollView { ReleaseMetadataView(release: release).padding(AppStyle.pagePadding) }
        }.frame(width: 820, height: 700)
    }
}
