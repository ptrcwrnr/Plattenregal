import SwiftUI

/// The caption under a cover in every cover grid (Collection, Wantlist,
/// compartment), the same in both designs: artist, title (or the track a
/// search found it by), year · label. Only the colors follow the design.
struct RecordCaption: View {
    let release: Release?
    var matchedTrack: Track? = nil
    /// Shown while the release is missing, as in the current design.
    var fallbackArtist = String(localized: "Unbekannt")
    var fallbackTitle = "—"
    /// The selected copy in a compartment: its artist in the accent.
    var emphasized = false
    var body: some View {
        // Release data a sync saved in its own context changes no property
        // this view observes; redrawn with the library's state, it shows it.
        let _ = LibraryChanges.shared.libraryVersion
        let ink = AppStyle.isAtelier ? AnyShapeStyle(AtelierPalette.ink) : AnyShapeStyle(.primary)
        let muted = AppStyle.isAtelier ? AnyShapeStyle(AtelierPalette.muted) : AnyShapeStyle(.secondary)
        VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
            Text(release?.displayArtist ?? fallbackArtist)
                .font(.callout.weight(.medium)).foregroundStyle(emphasized ? AnyShapeStyle(AppStyle.accent) : ink)
                .lineLimit(1)
            if let matchedTrack {
                MatchedTrackLine(track: matchedTrack)
            } else {
                Text(release?.displayTitle ?? fallbackTitle)
                    .font(.caption).foregroundStyle(muted).lineLimit(1)
            }
            let metadata = [release?.year.map(String.init), release.flatMap { $0.label.isEmpty ? nil : $0.displayLabel }]
                .compactMap { $0 }.joined(separator: " · ")
            if !metadata.isEmpty {
                Text(metadata).font(.caption2).foregroundStyle(muted).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
