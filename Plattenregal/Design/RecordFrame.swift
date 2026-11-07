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
    func recordFrame(_ frame: RecordFrame) -> some View {
        modifier(RecordFrameModifier(frame: frame))
    }
}

/// The cover's shadows lie on light ground only. On dark ground – Vinyl
/// always, Klassisch and Modern in dark mode – they can't be seen (measured:
/// at most 5 of 255 per channel), yet each costs a shadow pass per cover:
/// about a quarter of the window server's drawing while a grid scrolls.
/// There they get no color and radius 0, which SwiftUI skips; the views
/// stay the same, so switching light and dark rebuilds nothing.
private struct RecordFrameModifier: ViewModifier {
    let frame: RecordFrame
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let lit = scheme == .light
        switch frame {
        case .sleeve:
            content
                .overlay {
                    RoundedRectangle(cornerRadius: DesignScale.sleeveRadius)
                        .strokeBorder(AtelierPalette.ink.opacity(0.14), lineWidth: DesignScale.hairlineWidth)
                }
                .shadow(color: lit ? AtelierPalette.petrol.opacity(0.18) : .clear, radius: lit ? 1 : 0, y: lit ? 1 : 0)
                .shadow(color: lit ? AtelierPalette.petrol.opacity(0.14) : .clear, radius: lit ? 10 : 0, y: lit ? 6 : 0)
        case .classicMat, .modernMat:
            content
                .padding(RecordFrame.matWidth)
                .background {
                    let shape = RoundedRectangle(cornerRadius: DesignScale.cardRadius)
                    shape
                        .fill(frame == .classicMat ? AtelierPalette.surface : RecordFrame.modernMatColor)
                        .overlay {
                            shape.strokeBorder(frame == .classicMat ? AtelierPalette.border : DesignScale.modernBorder,
                                               lineWidth: DesignScale.borderWidth)
                        }
                }
                .shadow(color: lit ? .black.opacity(0.08) : .clear, radius: lit ? 8 : 0, y: lit ? 3 : 0)
        }
    }
}
