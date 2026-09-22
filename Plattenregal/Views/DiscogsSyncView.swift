import SwiftUI
import SwiftData

struct DiscogsSyncView: View {
    @Environment(\.modelContext) private var context
    @Query private var accounts: [DiscogsAccount]
    @Query(sort: \DiscogsFolder.folderID) private var folders: [DiscogsFolder]
    @Query private var copies: [RecordCopy]
    @Query private var wants: [WantlistEntry]
    @State private var sync = DiscogsSyncService.shared
    private var account: DiscogsAccount? { accounts.max { ($0.lastFullSync ?? $0.lastCollectionSync ?? $0.lastWantlistSync ?? .distantPast) < ($1.lastFullSync ?? $1.lastCollectionSync ?? $1.lastWantlistSync ?? .distantPast) } }
    var body: some View {
        Section("Synchronisierung") {
            if let account {
                Label("Verbunden als \(account.username)", systemImage: "checkmark.circle")
                timestamp("Collection", account.lastCollectionSync)
                timestamp("Wantlist", account.lastWantlistSync)
                timestamp("Ordner", account.lastFolderSync)
                Text("Collection: \(copies.filter { $0.discogsOwner == account.username && $0.discogsActive == true }.count) · Wantlist: \(wants.filter { $0.owner == account.username }.count)").foregroundStyle(.secondary)
            }
            Button("Collection synchronisieren") { start(.collection) }
                .disabled(sync.busy)
            DiscogsSyncStatusView()
        }
        Section("Discogs-Ordner") {
            ForEach(folders.filter { $0.owner == account?.username }) { folder in
                HStack {
                    Text(folder.name); Spacer(); Text("\(folder.count)").foregroundStyle(.secondary)
                    Button("Ordner synchronisieren") { sync.start(.folder(folder.folderID), container: context.container, expectedOwner: folder.owner) }.disabled(sync.busy)
                }
            }
            Text("Discogs-Ordner organisieren deine Collection. KALLAX-Fächer bleiben unabhängige physische Standorte.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func start(_ scope: DiscogsSyncScope) { sync.start(scope, container: context.container) }
    private func timestamp(_ title: String, _ date: Date?) -> some View {
        LabeledContent(title, value: date?.formatted(date: .abbreviated, time: .shortened) ?? "Noch nicht synchronisiert")
    }
}
struct DiscogsSyncStatusView: View {
    @State private var sync = DiscogsSyncService.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if sync.busy {
                HStack { ProgressView().controlSize(.small); Text(sync.status); Button("Abbrechen") { sync.cancel() } }
            } else if !sync.status.isEmpty { Text(sync.status) }
            if let error = sync.error { Text(error).foregroundStyle(AppStyle.errorColor).textSelection(.enabled) }
            if let summary = sync.summary { Text(summary).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
struct WantlistView: View {
    @Environment(\.modelContext) private var context
    @Query private var entries: [WantlistEntry]
    @State private var sync = DiscogsSyncService.shared
    @State private var query = ""
    @State private var hasRequestedSync = false

    var body: some View {
        let visibleEntries = WantlistPresentation.entries(entries, matching: query)
        VStack(spacing: 0) {
            controls(count: visibleEntries.count)
                .padding(.horizontal, AppStyle.pagePadding)
                .padding(.vertical, 12)
            if hasRequestedSync && (sync.busy || !sync.status.isEmpty || sync.error != nil || sync.summary != nil) {
                DiscogsSyncStatusView()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppStyle.pagePadding)
                    .padding(.bottom, 12)
            }
            if entries.isEmpty {
                AppEmptyState(
                    "Wantlist ist leer",
                    systemImage: "heart.text.clipboard",
                    description: Text("Synchronisiere die Wantlist hier manuell mit Discogs.")
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleEntries.isEmpty {
                AppEmptyState(
                    "Keine Treffer",
                    systemImage: "magnifyingglass",
                    description: Text("Versuche einen anderen Titel, Interpreten oder ein anderes Label.")
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 360, maximum: 520), spacing: 20, alignment: .top)],
                        alignment: .leading,
                        spacing: 20
                    ) {
                        ForEach(visibleEntries) { entry in
                            WantlistCard(entry: entry)
                        }
                    }
                    .padding(AppStyle.pagePadding)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func controls(count: Int) -> some View {
        HStack(spacing: AppStyle.rowSpacing) {
            AppSearchField(placeholder: "Wantlist durchsuchen", text: $query)
                .frame(minWidth: 260, maxWidth: 460)

            Text(count == 1 ? "1 Veröffentlichung" : "\(count) Veröffentlichungen")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize()
            Spacer()
            Button {
                hasRequestedSync = true
                sync.start(.wantlist, container: context.container)
            } label: {
                Label("Wantlist synchronisieren", systemImage: "arrow.clockwise")
            }
            .disabled(sync.busy)
        }
        .padding(AppStyle.cardPadding)
        .appControlSurface()
    }
}

private struct WantlistCard: View {
    let entry: WantlistEntry
    @Environment(\.openURL) private var openURL

    private var sourceURL: URL {
        entry.release?.sourceURL ?? URL(string: "https://www.discogs.com/release/\(entry.releaseID)")!
    }

    var body: some View {
        LinkResultCard(coverURL: entry.release?.coverURL, onOpen: { openURL(sourceURL) }) {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.release?.displayTitle ?? "Release #\(entry.releaseID)")
                    .font(.headline)
                    .lineLimit(2)
                Text(entry.release?.displayArtist ?? "Unbekannter Interpret")
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let date = WantlistPresentation.date(entry.dateAdded) {
                    Label("Hinzugefügt \(date.formatted(date: .abbreviated, time: .omitted))", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let rating = entry.rating, rating > 0 {
                    Label("Bewertung: \(rating)/5", systemImage: "star")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let notes = entry.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.callout)
                        .lineLimit(3)
                        .padding(.top, 2)
                }
            }
        } trailing: { hovering in
            Image(systemName: "arrow.up.forward.square")
                .foregroundStyle(.secondary)
                .opacity(hovering ? 1 : 0.4)
        }
    }
}

enum WantlistPresentation {
    static func entries(_ entries: [WantlistEntry], matching query: String) -> [WantlistEntry] {
        let needle = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
        let filtered = needle.isEmpty ? entries : entries.filter { entry in
            guard let release = entry.release else {
                return String(entry.releaseID).contains(needle)
            }
            let fields = [
                release.displayArtist, release.displayTitle, release.label,
                release.catalogNumber, release.country, release.format,
                release.genres.joined(separator: " "), release.styles.joined(separator: " "),
                entry.notes ?? "", String(entry.releaseID)
            ]
            return normalized(fields.joined(separator: " ")).contains(needle)
        }
        return filtered.map { ($0, date($0.dateAdded)) }.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return (lhs.1 ?? .distantPast) > (rhs.1 ?? .distantPast) }
            let leftArtist = lhs.0.release?.displayArtist ?? ""
            let rightArtist = rhs.0.release?.displayArtist ?? ""
            let artistOrder = leftArtist.localizedStandardCompare(rightArtist)
            if artistOrder != .orderedSame { return artistOrder == .orderedAscending }
            let leftTitle = lhs.0.release?.displayTitle ?? ""
            let rightTitle = rhs.0.release?.displayTitle ?? ""
            let titleOrder = leftTitle.localizedStandardCompare(rightTitle)
            if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
            return lhs.0.releaseID < rhs.0.releaseID
        }.map(\.0)
    }

    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
