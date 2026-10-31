import SwiftUI

/// The steps every view takes its spacing, corners, lines and weighted fonts
/// from – in the app (through `AppStyle`, which names them for its views) and
/// in the widget alike. Part of both targets, so it depends on nothing of the
/// app: no settings, no design switch.
nonisolated enum DesignScale {
    // MARK: Spacing
    // Steps of 4, and 2 for the lines of one caption.
    /// Lines of one caption: a title and what stands under it.
    static let hairSpacing: CGFloat = 2
    static let tightSpacing: CGFloat = 4
    static let itemSpacing: CGFloat = 8
    static let rowSpacing: CGFloat = 12
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 20
    static let pagePadding: CGFloat = 24

    // MARK: Corner radii
    /// Secondary surfaces: search fields, result dropdowns, metric chips.
    static let surfaceRadius: CGFloat = 12
    /// Cards: record covers on their mat, shelf cards, dashboard cards.
    static let cardRadius: CGFloat = 12
    /// Rows and small tiles and the hover or selection tint behind them.
    static let rowRadius: CGFloat = 8
    /// Cards that mark where something happens (placement card).
    static let featureRadius: CGFloat = 16
    /// Larger control surfaces: toolbars, control bars, prominent panels.
    static let controlRadius: CGFloat = 18
    /// A cover as an LP sleeve (Klassisch): nearly square.
    static let sleeveRadius: CGFloat = 2

    // MARK: Lines
    /// Fine rims of drawn miniatures and sleeves.
    static let hairlineWidth: CGFloat = 0.5
    /// Every ordinary rim: cards, fields, buttons, chips.
    static let borderWidth: CGFloat = 1
    /// The rim that marks a selection or a drop target, and the record's
    /// compartment in the widget's rack when it only belongs there.
    static let selectionLineWidth: CGFloat = 1.5

    // MARK: Symbols
    /// The large symbol of an empty page or widget.
    static let emptyStateSymbol = Font.system(size: 40, weight: .light)

    // MARK: Colors
    /// Every ordinary rim in Modern (Klassisch has `AtelierPalette.border`).
    static let modernBorder = Color.primary.opacity(0.08)

    // MARK: Weighted fonts
    // The running text takes the system's text styles as they are; weighted
    // variants have a role of their own.
    /// The name in a list row: artist, label, record, option.
    static let rowTitle = Font.callout.weight(.medium)
    /// Small numbers and marks with weight: positions on covers, a kicker
    /// over a card, a change in a figure.
    static let captionMark = Font.caption.weight(.semibold)
    /// Small labels with weight: hints and actions inside a result row.
    static let captionLabel = Font.caption.weight(.medium)
}
