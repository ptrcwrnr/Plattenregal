import SwiftUI

/// The fixed names of the lists' columns, under which their order and
/// visibility are stored (`AppPreferences.collectionColumns` …). Never
/// rename a case's value: a stored arrangement would lose that column.
enum TableColumnID: String {
    case cover, artist, title, year, label, genre, shelf, position, tags, note, added, link
}

extension TableColumnContent {
    /// The column's name for its stored order and visibility. Not
    /// `hideable`: artist and title, so a list never ends up empty, and the
    /// untitled icon columns, which would show as a blank entry in the
    /// header's right-click menu.
    func tableColumnID(_ id: TableColumnID, hideable: Bool = true) -> some TableColumnContent<TableRowValue, TableColumnSortComparator> {
        customizationID(id.rawValue)
            .disabledCustomizationBehavior(hideable ? [] : .visibility)
    }
}

/// Icon columns (untitled: cover, row actions) don't need dividers in the
/// table header, and neither does the end of the last column. SwiftUI offers
/// no switch for that, so this swaps in a header view that leaves those out.
/// Used by every table in the app, so their headers look the same.
struct QuietIconColumnHeaders: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Anchor() }
    func updateNSView(_ view: NSView, context: Context) {
        guard let anchor = view as? Anchor else { return }
        // Read here, so switching the design updates the header right away;
        // AppKit draws it on its own and would keep the old look until the
        // next scroll or resize.
        anchor.design = AppPreferences.shared.signatureDesign
        anchor.install()
    }

    final class Anchor: NSView {
        /// The design itself, not only paper or glass: Klassisch and Vinyl
        /// paint the band in different colors.
        var design = AppPreferences.shared.signatureDesign {
            didSet { if design != oldValue { nearbyTable()?.headerView?.needsDisplay = true } }
        }
        override func viewDidMoveToWindow() { install() }

        /// The table may not exist yet when this is placed (e.g. a window
        /// opened in the background); then it looks again a few times.
        func install(attempt: Int = 0) {
            DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0 : 0.2)) { [weak self] in
                guard let self, self.window != nil else { return }
                guard let table = self.nearbyTable(), let header = table.headerView else {
                    if attempt < 10 { self.install(attempt: attempt + 1) }
                    return
                }
                if !(header is Header) {
                    let replacement = Header(frame: header.frame)
                    replacement.tableView = table
                    // SwiftUI's right-click menu for showing and hiding columns
                    // (lists with `TableColumnID`) hangs on its own header.
                    replacement.menu = header.menu
                    table.headerView = replacement
                }
                table.headerView?.tableView = table
                table.headerView?.needsDisplay = true
            }
        }
    }

    final class Header: NSTableHeaderView {
        /// Frosted glass behind the header: the rows scroll underneath it, and
        /// the see-through header let their text mix with the column titles.
        private let frost: NSVisualEffectView = {
            let view = NSVisualEffectView()
            view.material = .headerView
            view.blendingMode = .withinWindow
            view.state = .active
            return view
        }()
        // Klassisch paints its opaque petrol background in the same draw
        // pass as its titles, avoiding sibling layer ordering on remount.
        private var frameObserver: NSObjectProtocol?

        /// Vibrancy would darken the cream titles into the petrol.
        override var allowsVibrancy: Bool { AppStyle.isAtelier ? false : super.allowsVibrancy }

        override func viewWillDraw() {
            super.viewWillDraw()
            frost.isHidden = AppStyle.isAtelier
        }

        /// Draw the titles explicitly in both designs: SwiftUI's header cells
        /// can leave a replacement header blank when asked to draw themselves.
        /// Modern keeps its frosted backdrop; Klassisch paints the petrol band.
        private func drawColumnHeaders(_ table: NSTableView, dividers: [CGFloat]) {
            let atelier = AppStyle.isAtelier
            if atelier {
                NSColor(AtelierPalette.petrol).setFill()
                bounds.fill()
            }
            let titleColor = atelier ? NSColor(AtelierPalette.bandInk) : NSColor.labelColor
            let secondaryTitleColor = atelier ? titleColor.withAlphaComponent(0.8) : NSColor.secondaryLabelColor
            let dividerColor = atelier ? titleColor.withAlphaComponent(0.18) : NSColor.separatorColor
            let sortKey = table.sortDescriptors.first
            // A column being dragged to another place (lists with
            // `TableColumnID`) follows the pointer, on its own background so
            // it never writes over the title it passes.
            let dragged = draggedColumn
            // The dragged one last, over the others.
            let order = table.tableColumns.indices.filter { $0 != dragged } + (table.tableColumns.indices.contains(dragged) ? [dragged] : [])
            // Hidden columns (switched off with a right-click) keep their
            // place in `tableColumns` with no width: nothing to draw.
            for index in order where !table.tableColumns[index].title.isEmpty && !table.tableColumns[index].isHidden {
                let column = table.tableColumns[index]
                let cell = column.headerCell
                var rect = headerRect(ofColumn: index)
                if index == dragged {
                    rect = rect.offsetBy(dx: draggedDistance, dy: 0)
                    (atelier ? NSColor(AtelierPalette.petrol) : NSColor.controlBackgroundColor).setFill()
                    rect.fill()
                }
                let sorted = sortKey != nil && column.sortDescriptorPrototype?.key == sortKey?.key
                let font = NSFont.systemFont(ofSize: cell.font?.pointSize ?? NSFont.systemFontSize,
                                             weight: sorted ? .semibold : .regular)
                let title = NSAttributedString(string: column.title, attributes: [
                    .font: font, .foregroundColor: sorted ? titleColor : secondaryTitleColor,
                ])
                let size = title.size()
                // Over the column's content, as the system header places its titles.
                let origin = NSPoint(x: rect.minX + 10, y: rect.midY - size.height / 2)
                title.draw(at: origin)
                if sorted, let ascending = sortKey?.ascending,
                   let arrow = NSImage(systemSymbolName: ascending ? "chevron.up" : "chevron.down", accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: font.pointSize * 0.75, weight: .semibold).applying(.init(paletteColors: [titleColor]))) {
                    let arrowRect = NSRect(x: origin.x + size.width + 6, y: rect.midY - arrow.size.height / 2,
                                           width: arrow.size.width, height: arrow.size.height)
                    arrow.draw(in: arrowRect)
                }
            }
            dividerColor.setFill()
            // No dividers while a column is dragged: their places change under it.
            let shown = table.tableColumns.indices.filter { !table.tableColumns[$0].isHidden }
            for index in shown.dropLast() where dragged < 0 {
                let x = headerRect(ofColumn: index).maxX
                guard !dividers.contains(where: { abs($0 - x) < 1 }) else { continue }
                NSRect(x: x - 0.5, y: bounds.midY - 7, width: 1, height: 14).fill()
            }
            if !atelier {
                NSRect(x: bounds.minX, y: isFlipped ? bounds.maxY - 1 : bounds.minY,
                       width: bounds.width, height: 1).fill()
            }
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
            frameObserver = nil
            guard let clip = superview, let scroll = clip.superview else {
                frost.removeFromSuperview()
                return
            }
            // Sits in the scroll view right below the header's clip view, so it
            // covers the rows but never the column titles.
            scroll.addSubview(frost, positioned: .below, relativeTo: clip)
            frost.frame = clip.frame
            clip.postsFrameChangedNotifications = true
            frameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: clip, queue: .main) { [weak self, weak clip] _ in
                guard let clip else { return }
                MainActor.assumeIsolated {
                    self?.frost.frame = clip.frame
                }
            }
        }

        isolated deinit {
            if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
        }

        override func draw(_ dirtyRect: NSRect) {
            guard let table = tableView else { return super.draw(dirtyRect) }
            let columns = table.tableColumns
            // Only the columns shown; hidden ones keep a place without width.
            let shown = columns.indices.filter { !columns[$0].isHidden }
            // Skip dividers on an icon column, just before one and at the end
            // of the last column. The inset style's empty lead-in before the
            // first column has nothing to separate either.
            var edges: [CGFloat] = shown.first.map { [headerRect(ofColumn: $0).minX] } ?? []
            for (position, index) in shown.enumerated() {
                let isIcon = columns[index].title.isEmpty
                let next = position + 1 < shown.count ? shown[position + 1] : nil
                let beforeIcon = next.map { columns[$0].title.isEmpty } ?? false
                let isLast = next == nil
                guard isIcon || beforeIcon || isLast else { continue }
                edges.append(headerRect(ofColumn: index).maxX)
            }
            drawColumnHeaders(table, dividers: edges)
        }
    }
}
