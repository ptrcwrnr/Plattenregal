import SwiftUI
import AppKit
import ObjectiveC

/// Shared typography, spacing, color and motion tokens for every window, sheet,
/// dashboard and card in the app. Views should pull from here instead of writing
/// their own literals, so the whole app reads as one consistent design system.
enum AppStyle {
    // MARK: Spacing
    // One scale for every distance: steps of 4, and 2 for the lines of one
    // caption. Views take a step from here instead of a number of their own,
    // so edges that belong together land on the same line.
    /// Lines of one caption: a title and what stands under it.
    static let hairSpacing: CGFloat = 2
    static let tightSpacing: CGFloat = 4
    static let itemSpacing: CGFloat = 8
    static let rowSpacing: CGFloat = 12
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 20
    static let pagePadding: CGFloat = 24
    /// A page's side margins: its covers, cards and tables start here.
    static let pageMargin: CGFloat = 28
    /// Between the big blocks of a page: banners, header, rack, compartment.
    static let blockSpacing: CGFloat = pageMargin
    /// Corners of a panel over the page (see `AppPanelModifier`).
    static let panelRadius: CGFloat = 20
    /// Height of every header-bar control, matching the segmented pickers.
    static let controlHeight: CGFloat = 26
    /// Search bars (Liquid Glass capsule, see `searchBarChrome`).
    static let searchBarHeight: CGFloat = 34
    /// The search field at the right end of the toolbar (see `ToolbarSearchField`).
    static let toolbarSearchWidth: CGFloat = 300
    /// Topped up to the toolbar's own right margin (8, measured), so the
    /// field ends at the pages' margin (`pageMargin`), flush with the
    /// covers below it.
    static let toolbarSearchInset: CGFloat = pageMargin - 8
    /// The round button at the bottom right and the actions around it.
    static let floatingButtonSize: CGFloat = 52
    static let floatingItemSize: CGFloat = 40
    /// Its distance from the window's edges.
    static let floatingMargin: CGFloat = 20
    /// Room at the end of every page, so content scrolls clear of the button.
    static let floatingClearance: CGFloat = floatingButtonSize + floatingMargin + itemSpacing
    /// Leaving a search: the hits fade out quickly, then the whole list fades
    /// in where it was before the search – timed like a page switch (see
    /// `PageStackView.show`). Gliding hundreds of covers back in looked busy.
    static var searchExitFadeOut: Animation { .easeIn(duration: 0.1) }
    static var searchExitFadeIn: Animation { .easeOut(duration: 0.22) }

    // MARK: Corner radii
    // Shared corner radius for secondary surfaces (search fields, result
    // dropdowns, metric chips) so they read as one consistent system instead
    // of each picking its own rounding.
    static let surfaceRadius: CGFloat = 12
    /// Cards: record covers, shelf cards, dashboard/metric cards.
    static let cardRadius: CGFloat = 12
    /// Larger control surfaces: toolbars, control bars, prominent panels.
    static let controlRadius: CGFloat = 18
    /// Rows and small tiles (lists, cabinet and compartment chips, legend
    /// entries) and the hover or selection tint behind them.
    static let rowRadius: CGFloat = 8
    /// Cards that mark where something happens: the placement card, the
    /// target shelf above "Platte hinzufügen" (see `accentGlassCard`).
    static let featureRadius: CGFloat = 16

    // MARK: Typography
    static let pageTitle = Font.system(.title, design: .rounded, weight: .semibold)
    static let sectionTitle = Font.system(.title3, design: .rounded, weight: .semibold)
    /// Figures and headings on the statistics: rounded in Modern, plain in
    /// Klassisch like the captions under its covers.
    static var figureDesign: Font.Design { isAtelier ? .default : .rounded }
    static let dialogTitle = Font.system(.title2, design: .rounded, weight: .semibold)
    /// The one large figure at the top of the statistics (collection value or count).
    static var heroFigure: Font { .system(size: 44, weight: .bold, design: figureDesign) }

    // MARK: Symbols
    // Symbols beside text take that text's font. Only symbols standing on
    // their own get a fixed size, and one of these four: the same role
    // looks the same everywhere.
    /// The glyph in the small round buttons ("Platte hinzufügen" on a
    /// compartment, "Bei Discogs öffnen", the steppers).
    static let buttonSymbol = Font.system(size: 11, weight: .semibold)
    /// Leading a status line or a list step next to a headline ("Alles in
    /// Ordnung", "Alles umgestellt", a ticked-off step).
    static let statusSymbol = Font.system(size: 22)
    /// Leading a card next to a page title (where a record stands).
    static let cardSymbol = Font.system(size: 30)
    /// The large symbol of an empty page.
    static let emptyStateSymbol = Font.system(size: 40, weight: .light)

    // MARK: Colors
    // All dynamic/system-based so Light and Dark mode stay correct automatically.
    static var isAtelier: Bool { AppPreferences.shared.signatureDesign == .atelier }
    static var hoverBackground: Color { isAtelier ? AtelierPalette.ink.opacity(0.05) : Color.primary.opacity(0.05) }
    /// The accent chosen in the settings (or the system's). Read in `body`,
    /// so views redraw when it changes.
    static var accent: Color { isAtelier ? AtelierPalette.accent : AppPreferences.shared.accent.color }
    /// Klassisch: the deeper cream of its paper, not a tint of the petrol
    /// (which turns the cream gray); the gold border marks the choice.
    static var selectedBackground: Color { isAtelier ? AtelierPalette.soft : accent.opacity(0.12) }
    static var selectedBorder: Color { isAtelier ? AtelierPalette.gold : accent }
    static var borderColor: Color { isAtelier ? AtelierPalette.border : Color.primary.opacity(0.08) }
    /// Klassisch keeps the meaning but takes earthy tones that sit on cream
    /// and on the dark paper, instead of the system's bright ones.
    static var successColor: Color { isAtelier ? AtelierPalette.success : Color.green }
    static var warningColor: Color { isAtelier ? AtelierPalette.warning : Color.orange }
    static var errorColor: Color { isAtelier ? AtelierPalette.error : Color.red }

    // MARK: Wording
    /// "1 Platte", "12 Platten", "1.234 Platten".
    static func records(_ count: Int) -> String { count == 1 ? String(localized: "1 Platte") : String(localized: "\(count.formatted()) Platten") }

    // MARK: Motion
    // One curve for the whole app: `.smooth`, a critically damped spring — no
    // visible overshoot, and it retargets cleanly when interrupted (e.g. the
    // a page switched again mid-animation). Only the duration varies.
    // With "Reduce motion" on, nothing travels: movement is dropped and only
    // fades remain.

    /// System setting "Bewegung reduzieren"; read when an animation starts.
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Hover/selection feedback — short and unobtrusive.
    static let quickAnimation = Animation.smooth(duration: 0.2)
    /// State changes — dimming, showing/hiding, focus changes.
    static let standardAnimation = Animation.smooth(duration: 0.25)
    /// Crossfade between pages, sections and grid ↔ list. Kept with reduce motion.
    static let fadeAnimation = Animation.smooth(duration: 0.25)
    /// Anything that moves or resizes: records travelling to a new sort
    /// position, columns reflowing, a search bar sliding in. `nil` (= instant)
    /// with reduce motion.
    static var layoutAnimation: Animation? { reduceMotion ? nil : .smooth(duration: 0.3) }
    /// Insert/remove transition matching the above: slide + fade, or just fade.
    /// The app's one transition for anything that appears or disappears as a
    /// block (cards, banners, status lines, expanding lists, toasts): it pours
    /// out of the edge it hangs from like from a funnel – narrower and squashed
    /// at first, then opening up – and back in on removal. It stays in place
    /// instead of sliding across whatever sits next to it. Text swapped inside
    /// a fixed slot and small badges just fade.
    static func funnelTransition(from edge: VerticalEdge = .top) -> AnyTransition {
        reduceMotion ? .opacity : .modifier(active: FunnelEffect(progress: 1, anchor: edge == .top ? .top : .bottom),
                                            identity: FunnelEffect(progress: 0, anchor: edge == .top ? .top : .bottom))
    }
}

private struct FunnelEffect: ViewModifier {
    /// 0 = fully shown, 1 = poured back into the funnel.
    let progress: CGFloat
    let anchor: UnitPoint
    func body(content: Content) -> some View {
        content
            .scaleEffect(x: 1 - 0.12 * progress, y: 1 - 0.45 * progress, anchor: anchor)
            .opacity(1 - progress)
    }
}
