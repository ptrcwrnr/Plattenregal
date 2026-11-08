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
    static let modernMatColor = PaletteColor.adaptive(.white, NSColor(white: 1, alpha: 0.1))

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

    /// One structure for every frame, only the values differ: a branch per
    /// frame rebuilt every cover – its loaded image included – on a switch
    /// between Modern and Klassisch. What a frame doesn't use is clear and
    /// of radius 0, which SwiftUI skips.
    func body(content: Content) -> some View {
        let lit = scheme == .light
        let sleeve = frame == .sleeve
        let shape = RoundedRectangle(cornerRadius: DesignScale.cardRadius)
        content
            .padding(sleeve ? 0 : RecordFrame.matWidth)
            .background {
                if !sleeve {
                    shape
                        .fill(frame == .classicMat ? AtelierPalette.surface : RecordFrame.modernMatColor)
                        .overlay {
                            shape.strokeBorder(frame == .classicMat ? AtelierPalette.border : DesignScale.modernBorder,
                                               lineWidth: DesignScale.borderWidth)
                        }
                }
            }
            .overlay {
                if sleeve {
                    RoundedRectangle(cornerRadius: DesignScale.sleeveRadius)
                        .strokeBorder(AtelierPalette.ink.opacity(0.14), lineWidth: DesignScale.hairlineWidth)
                }
            }
            // The sleeve: a close and a soft shadow; a mat: one soft shadow.
            .shadow(color: lit && sleeve ? AtelierPalette.petrol.opacity(0.18) : .clear,
                    radius: lit && sleeve ? 1 : 0, y: lit && sleeve ? 1 : 0)
            .shadow(color: !lit ? .clear : sleeve ? AtelierPalette.petrol.opacity(0.14) : .black.opacity(0.08),
                    radius: !lit ? 0 : sleeve ? 10 : 8, y: !lit ? 0 : sleeve ? 6 : 3)
    }
}
