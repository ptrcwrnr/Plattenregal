import SwiftUI
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
        CoverView(url: copy.release?.shownCoverURL, size: nil)
            .atelierRecordSleeve()
            .overlay(alignment: .bottomTrailing) {
                if copyCount > 1 {
                    Text("\(copyCount)×")
                        .font(AppStyle.captionMark)
                        .foregroundStyle(AppStyle.isAtelier ? AnyShapeStyle(AtelierPalette.ink) : AnyShapeStyle(.primary))
                        .padding(.horizontal, AppStyle.itemSpacing)
                        .padding(.vertical, AppStyle.tightSpacing)
                        .appChipSurface(in: Capsule())
                        .padding(AtelierCoverFrame.chipInset)
                }
            }
    }
}

/// How Klassisch frames a cover. `sleeve` (default): the cover as a real
/// LP sleeve (see `RecordFrame.sleeve`). `passepartout`: the earlier cream mat
/// with rounded corners, kept to switch back:
/// `defaults write <bundle id> atelierCoverFrame passepartout`.
enum AtelierCoverFrame: String {
    case sleeve, passepartout
    /// Read once per launch: every cover cell asks for it on every redraw
    /// (in Klassisch and Vinyl), and a lookup in the defaults took about
    /// 0.4 µs each time. Changed with `defaults write`, it applies from the
    /// next launch.
    static let current: AtelierCoverFrame =
        UserDefaults.standard.string(forKey: "atelierCoverFrame").flatMap(Self.init) ?? .sleeve
    /// Distance of the number chip on a cover (position, „2×“) from its edge, the mat included.
    static var chipInset: CGFloat { usesMat ? 11 : 8 }
    /// The cover lies on a mat: Klassisch's passepartout, and always in Modern.
    static var usesMat: Bool { frame != .sleeve }
    /// The frame of the design shown.
    static var frame: RecordFrame { AppStyle.isAtelier ? (current == .sleeve ? .sleeve : .classicMat) : .modernMat }
}

extension View {
    /// Atelier's frame around the existing image. The unchanged cover
    /// remains in the tree, including its loading state, in every design.
    @ViewBuilder func atelierRecordSleeve() -> some View {
        let frame = AtelierCoverFrame.frame
        environment(\.coverCornerRadius, frame.coverRadius).recordFrame(frame)
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
    }
}
