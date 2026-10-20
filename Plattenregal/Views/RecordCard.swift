import SwiftUI
import SwiftData
import AppKit

struct RecordCard: View {
    let copy: RecordCopy
    var copyCount = 1
    /// Found by one of its tracks while searching: shown instead of the title.
    var matchedTrack: Track? = nil
    var body: some View {
        // The cover's address may come with a sync (see `RecordCaption`).
        let _ = LibraryChanges.shared.libraryVersion
        VStack(alignment: .leading, spacing: CoverGrid.captionSpacing) {
            cover
            RecordCaption(release: copy.release, matchedTrack: matchedTrack)
        }
        .contentShape(Rectangle())
    }

    private var cover: some View {
        CoverView(url: copy.release?.coverURL, size: nil)
            .atelierRecordSleeve()
            .overlay(alignment: .bottomTrailing) {
                if copyCount > 1 {
                    Text("\(copyCount)×")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppStyle.isAtelier ? AnyShapeStyle(AtelierPalette.ink) : AnyShapeStyle(.primary))
                        .padding(.horizontal, AppStyle.itemSpacing)
                        .padding(.vertical, AppStyle.tightSpacing)
                        .appChipSurface(in: Capsule())
                        .padding(AtelierCoverFrame.badgeInset)
                }
            }
    }
}

/// How Klassisch frames a cover. `sleeve` (default): the cover as a real
/// LP sleeve – nearly square corners, a fine printed edge, lying on the paper
/// with a close and a soft shadow. `passepartout`: the earlier cream mat with
/// rounded corners, kept to switch back:
/// `defaults write <bundle id> atelierCoverFrame passepartout`.
enum AtelierCoverFrame: String {
    case sleeve, passepartout
    static var current: AtelierCoverFrame {
        UserDefaults.standard.string(forKey: "atelierCoverFrame").flatMap(Self.init) ?? .sleeve
    }
    /// Distance of the tags on a cover from its edge, the mat included.
    static var badgeInset: CGFloat { usesMat ? 11 : 8 }
    /// The cover lies on a mat: Klassisch's passepartout, and always in Modern.
    static var usesMat: Bool { !(AppStyle.isAtelier && current == .sleeve) }
    /// Modern's mat: white in light mode; a light veil in dark mode, so it
    /// sits a little above the window like Klassisch's surface on its paper.
    static let modernMat = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.1) : .white
    })
}

extension View {
    /// Atelier's frame around the existing image. The unchanged cover
    /// remains in the tree, including its loading state, in every design.
    @ViewBuilder func atelierRecordSleeve() -> some View {
        if !AtelierCoverFrame.usesMat {
            environment(\.coverCornerRadius, 2)
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(AtelierPalette.ink.opacity(0.14), lineWidth: 0.5)
                }
                .shadow(color: AtelierPalette.petrol.opacity(0.18), radius: 1, y: 1)
                .shadow(color: AtelierPalette.petrol.opacity(0.14), radius: 10, y: 6)
        } else {
            // The mat in both designs; Modern only takes the system's surface
            // and edge instead of cream.
            padding(6)
                .background {
                    RoundedRectangle(cornerRadius: AppStyle.cardRadius)
                        .fill(AppStyle.isAtelier ? AtelierPalette.surface : AtelierCoverFrame.modernMat)
                        .overlay {
                            RoundedRectangle(cornerRadius: AppStyle.cardRadius)
                                .strokeBorder(AppStyle.borderColor, lineWidth: 1)
                        }
                }
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        }
    }
}

/// "♪ A2 · Title" under a cover, replacing the release title while a search
/// found the record by one of its tracks.
struct MatchedTrackLine: View {
    let track: Track
    var body: some View {
        HStack(spacing: AppStyle.tightSpacing) {
            Image(systemName: "music.note")
            Text(track.position.isEmpty ? track.title : "\(track.position) · \(track.title)")
        }
        .font(.caption)
        .foregroundStyle(.tint)
        .lineLimit(1)
        .help("Gefunden über den Track „\(track.title)“")
    }
}
