import SwiftUI
import AppKit
import Charts

/// Shared typography, spacing, color and motion tokens for every window, sheet,
/// dashboard and card in the app. Views should pull from here instead of writing
/// their own literals, so the whole app reads as one consistent design system.
enum AppStyle {
    // MARK: Spacing
    // One scale for every distance: steps of 4, and 2 for the lines of one
    // caption. Views take a step from here instead of a number of their own,
    // so edges that belong together land on the same line. The steps
    // themselves live in `DesignScale`, which the widget shares.
    /// Lines of one caption: a title and what stands under it.
    static let hairSpacing = DesignScale.hairSpacing
    static let tightSpacing = DesignScale.tightSpacing
    static let itemSpacing = DesignScale.itemSpacing
    static let rowSpacing = DesignScale.rowSpacing
    static let cardPadding = DesignScale.cardPadding
    static let sectionSpacing = DesignScale.sectionSpacing
    static let pagePadding = DesignScale.pagePadding
    /// A page's side margins: its covers, cards and tables start here.
    static let pageMargin: CGFloat = 28
    /// Between the big blocks of a page: banners, header, rack, compartment.
    static let blockSpacing: CGFloat = pageMargin
    /// How far the soft fade at a scroll view's bottom edge runs into the
    /// page (Modern, see `scrollsUnderToolbar`). Long, so its start can't be
    /// made out. At the top the fade lies behind the toolbar only.
    static let scrollEdgeFade: CGFloat = 2 * blockSpacing
    /// Pages of text (settings): how far above the toolbar's edge their
    /// content has faded out completely, so nothing reads through the bar.
    static let scrollEdgeTuck: CGFloat = sectionSpacing
    /// How much of the content still shows at the window's top edge, under
    /// the toolbar's glass.
    static let scrollEdgeTopOpacity: Double = 0.35
    /// How much still shows at the window's bottom edge: only a hint of the
    /// fade, so the covers there don't look washed out.
    static let scrollEdgeBottomOpacity: Double = 0.6
    /// A page's padding above its first content, under the toolbar: in
    /// Modern every page starts right at the toolbar's lower edge (scrolling
    /// pages via `scrollsUnderToolbar`), in Klassisch `padding` below the
    /// petrol band.
    static func pageTopPadding(_ padding: CGFloat) -> CGFloat { isAtelier ? padding : 0 }
    /// Corners of a panel over the page (see `AppPanelModifier`).
    static let panelRadius: CGFloat = 20
    // MARK: Control sizes
    // One height for every control that stands in a row with others: the
    // segmented pickers (the page switch in the toolbar too), the search and
    // text fields, menu pickers, steppers. Side by side they end on the same
    // lines. `smallControlHeight` for the compact pickers inside a card, and
    // as the diameter of the small round buttons.
    static let controlHeight: CGFloat = 30
    static let smallControlHeight: CGFloat = 24
    /// How far a selection pill sits inside its bar (all around), so its
    /// corners run parallel to the bar's (`atelierControlRadius - controlInset`).
    static let controlInset: CGFloat = 3
    /// The search field opened in the toolbar's bar, glass included (see
    /// `AppSearchField`).
    static let toolbarSearchWidth: CGFloat = 240
    /// The list of hits that drops from the toolbar's bar on the shelf page:
    /// wide enough for artist and title beside the cover.
    static let searchResultsWidth: CGFloat = 360
    /// The most a control may take beside a row's title in the settings
    /// before it gives way to a menu (the start page with long page names
    /// of one's own); the title keeps room to stay on one or two lines.
    static let settingsControlMaxWidth: CGFloat = 480
    /// A short name typed in the settings (a cabinet, a page): room for
    /// `PageNames.maxLength` wide letters.
    static let nameFieldWidth: CGFloat = 220
    /// The search in the menu bar: narrower, it hangs under a small symbol
    /// and shows fewer hits. Still room for a rack of six columns (about
    /// 43 pt a compartment) and for most artists in full beside the cover;
    /// at 300 pt titles were cut to a few letters, 330 pt hardly helped
    /// the longest names.
    static let quickSearchWidth: CGFloat = 320
    /// The round button at the bottom right and the actions around it.
    static let floatingButtonSize: CGFloat = 52
    static let floatingItemSize: CGFloat = 40
    /// Its distance from the window's edges.
    static let floatingMargin: CGFloat = 20
    /// Room at the end of every page, so content scrolls clear of the button.
    static let floatingClearance: CGFloat = floatingButtonSize + floatingMargin + itemSpacing
    // MARK: Switching a whole area
    // A page (`PageStackView.show`) with the toolbar above it, a settings
    // tab, another cabinet: everything that changes fades out quickly on the
    // spot, then the new state fades in – one beat for the page, the search
    // field and its placeholder. Never both half visible on top of each
    // other. Areas settle down from `pageSettleDistance` above while fading
    // in. With "Bewegung reduzieren" only the fade. The pill of a switch
    // travels instead (`pillLeadAnimation`).
    static let pageFadeOut: TimeInterval = 0.1
    static let pageFadeInDelay: TimeInterval = 0.07
    static let pageFadeIn: TimeInterval = 0.22
    static let pageSettleDistance: CGFloat = itemSpacing
    /// The selection pill of a switch (`GlassSegmentedPicker`) travelling
    /// to a new option like a drop: the edge in front runs ahead on this
    /// taut spring, overshooting a little …
    static let pillLeadAnimation = Animation.spring(response: 0.28, dampingFraction: 0.7)
    /// … and the edge behind follows on this softer one, so the pill
    /// stretches on the way and pulls itself together at the new option.
    /// With "Bewegung reduzieren" the pill fades in the beat above instead.
    static let pillTrailAnimation = Animation.spring(response: 0.48, dampingFraction: 0.78)
    /// The search in the menu bar settles in like a page after a switch:
    /// fading in, it comes down `pageSettleDistance` and grows from this
    /// size to its full one, on a calm curve without overshoot. It fades
    /// out quickly (`pageOutAnimation`), going back the same little way.
    static let quickSearchSettleScale: CGFloat = 0.97
    static let quickSearchInAnimation = Animation.smooth(duration: 0.24)
    /// What goes away on a switch.
    static var pageOutAnimation: Animation { .easeIn(duration: pageFadeOut) }
    /// What comes in on a switch, once the old state is gone.
    static var pageInAnimation: Animation { .easeOut(duration: pageFadeIn).delay(pageFadeInDelay) }
    /// Only the fade of a switch, timing included (text swapped in place).
    static var pageFadeTransition: AnyTransition {
        .asymmetric(insertion: .opacity.animation(pageInAnimation), removal: .opacity.animation(pageOutAnimation))
    }
    /// A whole area switched: the fade, and the new one settles down.
    static var pageTransition: AnyTransition { settling(by: pageSettleDistance) }
    private static func settling(by distance: CGFloat) -> AnyTransition {
        let insertion: AnyTransition = reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -distance))
        return .asymmetric(insertion: insertion.animation(pageInAnimation), removal: .opacity.animation(pageOutAnimation))
    }
    /// Leaving a search: the hits fade out quickly, then the whole list fades
    /// in where it was before the search – timed like a page switch.
    /// Gliding hundreds of covers back in looked busy.
    static var searchExitFadeOut: Animation { pageOutAnimation }
    static var searchExitFadeIn: Animation { .easeOut(duration: pageFadeIn) }
    /// A far jump in the shelf's cover grid ("Im Regal anzeigen", a search
    /// hit further down): the covers fade out quickly, stand at the record
    /// and fade in – timed like leaving a search. Scrolling there animated
    /// through rows the lazy grid only built on the way: hasty and jerky.
    static var farJumpFadeOut: Animation { searchExitFadeOut }
    static var farJumpFadeOutDuration: TimeInterval { pageFadeOut }
    static var farJumpFadeIn: Animation { searchExitFadeIn }

    // MARK: Corner radii
    // Shared corner radius for secondary surfaces (search fields, result
    // dropdowns, metric chips) so they read as one consistent system instead
    // of each picking its own rounding.
    static let surfaceRadius = DesignScale.surfaceRadius
    /// Cards: record covers, shelf cards, dashboard/metric cards.
    static let cardRadius = DesignScale.cardRadius
    /// Larger control surfaces: toolbars, control bars, prominent panels.
    static let controlRadius = DesignScale.controlRadius
    /// Rows and small tiles (lists, cabinet and compartment chips, legend
    /// entries) and the hover or selection tint behind them.
    static let rowRadius = DesignScale.rowRadius
    /// Cards that mark where something happens: the placement card, the
    /// target shelf above "Platte hinzufügen" (see `accentGlassCard`).
    static let featureRadius = DesignScale.featureRadius
    /// Klassisch draws its controls and the bars around them as rounded
    /// rectangles where Modern uses capsules: buttons, pickers, the search
    /// field and the toolbar band. A selection inside such a bar sits
    /// `controlInset` in and takes `atelierControlRadius - controlInset`, so
    /// both corners run parallel.
    static let atelierControlRadius: CGFloat = 10
    /// The hover highlight of a row inside a menu.
    static let menuRowRadius: CGFloat = 6

    // MARK: Lines
    /// Fine rims of drawn miniatures and sleeves.
    static let hairlineWidth = DesignScale.hairlineWidth
    /// Every ordinary rim: cards, fields, buttons, chips.
    static let borderWidth = DesignScale.borderWidth
    /// The rim that marks a selection or a drop target (gold in Klassisch,
    /// the accent in Modern, see `selectedBorder`): the same strength on
    /// covers, compartments, rows and cards.
    static let selectionLineWidth = DesignScale.selectionLineWidth
    /// The track and arc of a progress ring (activity, pull to refresh).
    static let progressLineWidth: CGFloat = 2.5
    /// The line of a value chart (the sparkline on the statistics, the value
    /// history): this strength, a smooth curve that never overshoots its
    /// points, and the accent fading out below it.
    static let chartLineWidth: CGFloat = 2
    static let chartInterpolation: InterpolationMethod = .monotone
    static let chartAreaOpacity: Double = 0.25

    // MARK: Typography
    static let pageTitle = Font.system(.title, design: .rounded, weight: .semibold)
    static let sectionTitle = Font.system(.title3, design: .rounded, weight: .semibold)
    /// Figures and headings on the statistics: rounded in Modern, plain in
    /// Klassisch like the captions under its covers.
    static var figureDesign: Font.Design { isAtelier ? .default : .rounded }
    static let dialogTitle = Font.system(.title2, design: .rounded, weight: .semibold)
    /// The one large figure at the top of the statistics (collection value or count).
    static var heroFigure: Font { .system(size: 44, weight: .bold, design: figureDesign) }
    /// A key figure standing on its own (the centre of the donut, a stat
    /// figure under a chart).
    static var largeFigure: Font { .system(.title, design: figureDesign, weight: .semibold) }
    /// A figure beside a symbol or a readout (counts, peak, year).
    static var figure: Font { .system(.title2, design: figureDesign, weight: .semibold) }
    /// Headings of the statistics areas and the counts in their lists.
    static var figureHeading: Font { .system(.title3, design: figureDesign, weight: .semibold) }
    /// The rank in front of a list entry (podium, labels).
    static var rankFigure: Font { .system(.caption, design: figureDesign, weight: .bold) }
    // The running text takes the system's text styles as they are (`.body`,
    // `.callout`, `.caption`, `.caption2`, `.headline` for card titles).
    // Weighted variants have a role of their own and live here.
    /// The name in a list row: artist, label, record, option.
    static let rowTitle = DesignScale.rowTitle
    /// The text typed into the search in the menu bar: larger, as the panel
    /// is about this one field (like Spotlight).
    static let searchFieldFont = Font.title3
    /// The chosen option of a switch in Modern, in the size of the switch
    /// (`GlassSegmentedPicker`): heavier instead of in the accent color, so it
    /// reads on any background – also with covers passing under the toolbar.
    static let selectedOptionWeight: Font.Weight = .semibold
    /// A short value that stands out: a chip's name, a hovered readout.
    static let strongCallout = Font.callout.weight(.semibold)
    /// Small numbers and marks with weight: positions on covers, a kicker
    /// over a card, a change in a figure.
    static let captionMark = DesignScale.captionMark
    /// Small labels with weight: hints and actions inside a result row.
    static let captionLabel = DesignScale.captionLabel
    /// The tiny badges on covers and rows (sold, missing, status).
    static let badge = Font.caption2.weight(.medium)
    /// The small capitals over a group of rows in a menu.
    static let menuSectionTitle = Font.caption2.weight(.semibold)

    // MARK: Symbols
    // Symbols beside text take that text's font. Only symbols standing on
    // their own get a fixed size, and one of these: the same role looks the
    // same everywhere.
    /// The glyph in the small round buttons ("Platte hinzufügen" on a
    /// compartment, "Bei Discogs öffnen", the steppers).
    static let buttonSymbol = Font.system(size: 11, weight: .semibold)
    /// Leading a status line or a list step next to a headline ("Alles in
    /// Ordnung", "Alles umgestellt", a ticked-off step).
    static let statusSymbol = Font.system(size: 22)
    /// Leading a card next to a page title (where a record stands).
    static let cardSymbol = Font.system(size: 30)
    /// The large symbol of an empty page.
    static let emptyStateSymbol = DesignScale.emptyStateSymbol
    /// The symbol on a tinted tile leading a figure or a sync line (see `SymbolTile`).
    static let tileSymbol = Font.callout.weight(.semibold)
    /// The tile itself.
    static let symbolTileSize: CGFloat = 28
    /// The app icon heading „Über Plattenregal“.
    static let aboutIconSize: CGFloat = 72
    /// A list of changes in a small window („Über Plattenregal“, update window) scrolls beyond this height.
    static let changesMaxHeight: CGFloat = 240
    /// The little chevron of a menu button, the arrow between two places.
    static let indicatorSymbol = Font.caption2.weight(.semibold)
    /// The glyph in the large round floating button (see `FloatingControls`).
    static let floatingSymbol = Font.title3.weight(.semibold)
    /// The glyph in the smaller actions fanned out around it.
    static let floatingItemSymbol = Font.body.weight(.medium)

    // MARK: Colors
    // All dynamic/system-based so Light and Dark mode stay correct automatically.
    /// Klassisch or Vinyl: matte paper and a colored toolbar band instead of
    /// glass. Both are built the same way; `AtelierPalette` holds their colors.
    static var isAtelier: Bool { AppPreferences.shared.signatureDesign.isPaper }
    /// Labels and symbols on the toolbar's bar that aren't chosen: the
    /// page switch's options, the magnifying glass.
    static var toolbarLabel: AnyShapeStyle { isAtelier ? AnyShapeStyle(AtelierPalette.bandLabel) : AnyShapeStyle(.secondary) }
    /// What can't be used right now – a disabled button or menu entry, a
    /// choice that only applies to another design – and a move ticked off
    /// at the shelf: one step back, still readable.
    static let dimmedOpacity: Double = 0.45
    static var hoverBackground: Color { isAtelier ? AtelierPalette.ink.opacity(0.05) : Color.primary.opacity(0.05) }
    /// The accent chosen in the settings (or the system's). Read in `body`,
    /// so views redraw when it changes.
    static var accent: Color { isAtelier ? AtelierPalette.accent : AppPreferences.shared.accent.color }
    /// Klassisch: the deeper cream of its paper, not a tint of the petrol
    /// (which turns the cream gray); the gold border marks the choice.
    static var selectedBackground: Color { isAtelier ? AtelierPalette.soft : accent.opacity(0.12) }
    static var selectedBorder: Color { isAtelier ? AtelierPalette.gold : accent }
    static var borderColor: Color { isAtelier ? AtelierPalette.border : DesignScale.modernBorder }
    /// Klassisch keeps the meaning but takes earthy tones that sit on cream
    /// and on the dark paper, instead of the system's bright ones.
    static var successColor: Color { isAtelier ? AtelierPalette.success : Color.green }
    static var warningColor: Color { isAtelier ? AtelierPalette.warning : Color.orange }
    static var errorColor: Color { isAtelier ? AtelierPalette.error : Color.red }

    // MARK: Glass
    // The tints of Liquid Glass in Modern, by role. Klassisch draws paper instead.
    /// Panels, popovers and capsules over a page (the panel over the page,
    /// popovers, the sync capsule, the shelf's search results): tinted
    /// toward the window color, so a bright cover beneath doesn't run
    /// through the text.
    static var panelGlass: Glass { .regular.tint(Color(nsColor: .windowBackgroundColor).opacity(0.65)) }
    /// Cards on a page: lighter, the page shows through more.
    static var cardGlass: Glass { .regular.tint(Color(nsColor: .windowBackgroundColor).opacity(0.45)) }
    /// The search in the menu bar, over whatever lies on the desktop, as
    /// chosen (`QuickSearchLook`): a plain blur with a tint, not Liquid
    /// Glass – its lit rim drew bright lines along the top and bottom of the
    /// flat field and a pale band around the edge. Dark glass, in light and
    /// dark mode alike: black at 30 % over the blur is as light as the
    /// earlier 45 % on Liquid Glass, which read clearly over a bright, busy
    /// wallpaper without looking heavy. Light glass takes `panelGlass`'s
    /// tint in the light appearance.
    static let desktopPanelBlur: Material = .ultraThinMaterial
    static let darkDesktopTint = Color.black.opacity(0.3)
    static var lightDesktopTint: Color { Color(nsColor: .windowBackgroundColor).opacity(0.65) }
    /// White: opaque, without an edge line like every look of this search;
    /// its shadow sets it off a bright wallpaper.
    static let desktopPanelWhite = Color.white

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
    static var layoutAnimation: Animation? { reduceMotion ? nil : moveAnimation }
    /// Something opened from a button springs out of it, a little past its
    /// end and back: the search from its magnifying glass (which bounces
    /// once), the actions fanned out of the round button. Only these – page
    /// switches, moving records and panels stay calm (the selection pill has
    /// its own springs, `pillLeadAnimation`).
    /// `nil` (= instant) with reduce motion; callers that should still fade
    /// then choose their own fallback.
    static var openAnimation: Animation? { reduceMotion ? nil : .bouncy(duration: 0.45, extraBounce: 0.12) }
    /// Closing it again: calm, without the spring.
    static var closeAnimation: Animation? { layoutAnimation }
    /// The curve of `layoutAnimation`, for things that also animate with
    /// reduce motion on (they choose their own fallback).
    static let moveAnimation = Animation.smooth(duration: 0.3)
    /// Status lines and pills changing their text or coming and going
    /// (sync status, statistics busy).
    static let statusAnimation = Animation.smooth(duration: 0.45)
    /// Progress rings and bars following their value.
    static let progressAnimation = Animation.smooth(duration: 0.35)
    /// Statistics bars growing in when first shown (after `reduceMotion` is checked).
    static let growAnimation = Animation.smooth(duration: 0.7).delay(0.05)
    /// Statistics figures rolling to a new value (after `reduceMotion` is checked).
    static let rollAnimation = Animation.smooth(duration: 0.8)
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

/// The paper design's colors follow the design chosen in the settings.
extension AtelierPalette {
    static var colors: ClassicColors { AppPreferences.shared.signatureDesign.paperColors }
}
