import SwiftUI
import AppKit

/// How a cover is framed, in the app (`atelierRecordSleeve`) and in the
/// widget alike. Part of both targets: the caller says which frame, nothing
/// here reads the settings.
nonisolated enum RecordFrame: String, Codable, Sendable {
    /// Klassisch: the cover as a real LP sleeve – nearly square corners, a
    /// fine printed edge, lying on the paper with a close and a soft shadow.
    case sleeve
    /// Klassisch's cream passepartout (kept to switch back to).
    case classicMat
    /// Modern's mat: white in light mode, a light veil in dark mode.
    case modernMat

    /// How wide the mat shows around the cover.
    static let matWidth: CGFloat = 6
    /// Modern's mat: white in light mode; a light veil in dark mode, so it
    /// sits a little above the window like Klassisch's surface on its paper.
    static let modernMatColor = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.1) : .white
    })

    /// The corner radius the cover itself takes inside this frame: on a mat
    /// its corners run parallel to the mat's.
    var coverRadius: CGFloat { self == .sleeve ? DesignScale.sleeveRadius : DesignScale.cardRadius - Self.matWidth }
}

extension View {
    /// The frame around a cover that already has its own corners (see
    /// `RecordFrame.coverRadius` for the sleeve's).
    @ViewBuilder func recordFrame(_ frame: RecordFrame) -> some View {
        switch frame {
        case .sleeve:
            overlay {
                RoundedRectangle(cornerRadius: DesignScale.sleeveRadius)
                    .strokeBorder(AtelierPalette.ink.opacity(0.14), lineWidth: DesignScale.hairlineWidth)
            }
            .shadow(color: AtelierPalette.petrol.opacity(0.18), radius: 1, y: 1)
            .shadow(color: AtelierPalette.petrol.opacity(0.14), radius: 10, y: 6)
        case .classicMat, .modernMat:
            padding(RecordFrame.matWidth)
                .background {
                    let shape = RoundedRectangle(cornerRadius: DesignScale.cardRadius)
                    shape
                        .fill(frame == .classicMat ? AtelierPalette.surface : RecordFrame.modernMatColor)
                        .overlay {
                            shape.strokeBorder(frame == .classicMat ? AtelierPalette.border : DesignScale.modernBorder,
                                               lineWidth: DesignScale.borderWidth)
                        }
                }
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        }
    }
}
