import SwiftUI
import AppKit

enum CoverGrid {
    /// The same in both designs (Modern used to be tighter, 8 pt).
    static let spacing: CGFloat = AppStyle.sectionSpacing
    /// Space between a cover and its caption.
    static let captionSpacing: CGFloat = AppStyle.itemSpacing
    /// Extra room above the grid's own padding (`spacing`): none, the first
    /// covers start one `spacing` below the toolbar.
    static let topSpace: CGFloat = 0
    /// How far a cover's shadow reaches beyond it (`atelierRecordSleeve`).
    static let shadowRoom: CGFloat = 16

    static func columnCount(available: CGFloat, minimum: CGFloat) -> Int {
        guard available.isFinite, minimum.isFinite, minimum > 0 else { return 1 }
        return max(1, Int((max(0, available) + spacing) / (minimum + spacing)))
    }

    static func columns(count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: count)
    }

    /// Which cover's popover is shown after a click on the cover `clicked`
    /// while `shown`'s is open – so every click toggles, however fast.
    /// A single click on the open cover never gets here: AppKit closes the
    /// popover on its mouse-down and swallows the click. The later clicks of
    /// a fast series (click count 2 and up) leave the popover open, though,
    /// and do reach the cover; they close it here. No pause after closing is
    /// needed: the closing click never reaches the cover to reopen it.
    static func popover<ID: Equatable>(shown: ID?, afterClickOn clicked: ID) -> ID? {
        shown == clicked ? nil : clicked
    }
}

extension View {
    /// Motion for a cover grid of `width` with `columnCount` columns.
    /// - The grid growing in one step (full screen, zoom)
    ///   animates; the column count stays the same, so every cover just scales
    ///   up within its own cell and none crosses another.
    /// - Shrinking applies at once, so a cover is never wider than the space
    ///   it is in — not even for a frame. Live window resizing follows the
    ///   pointer directly.
    /// - A new column count (reflow) is never animated: covers changing rows
    ///   would slide across each other.
    /// - Clipped to the grid's bounds plus `shadowRoom` as a last line of
    ///   defence; the room keeps the covers' own shadows (Klassisch) whole.
    func coverGridMotion(width: CGFloat, columnCount: Int) -> some View {
        modifier(CoverGridMotion(width: width, columnCount: columnCount))
    }
}

private struct CoverGridMotion: ViewModifier {
    let width: CGFloat
    let columnCount: Int
    /// Only tells growing from shrinking — never used for layout.
    @State private var previousWidth: CGFloat?

    func body(content: Content) -> some View {
        let grows = previousWidth.map { width > $0 } ?? false
        content
            .transaction(value: columnCount) { $0.animation = nil }
            .transaction(value: width) { transaction in
                let liveResize = NSApp.windows.contains(where: \.inLiveResize)
                transaction.animation = grows && !liveResize ? AppStyle.layoutAnimation : nil
            }
            // Wider than the grid by the shadow's reach, so the outer
            // columns' shadows aren't cut off in a straight line.
            .padding(CoverGrid.shadowRoom)
            .clipped()
            .padding(-CoverGrid.shadowRoom)
            .onAppear { previousWidth = width }
            .onChange(of: width) { _, new in previousWidth = new }
    }
}
