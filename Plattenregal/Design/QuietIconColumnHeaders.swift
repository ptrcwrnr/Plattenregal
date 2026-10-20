import SwiftUI
import SwiftData

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
        anchor.atelier = AppStyle.isAtelier
        anchor.install()
    }

    final class Anchor: NSView {
        var atelier = AppStyle.isAtelier {
            didSet { if atelier != oldValue { nearbyTable()?.headerView?.needsDisplay = true } }
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
            let titleColor = atelier ? NSColor(AtelierPalette.toolbarSelection) : NSColor.labelColor
            let secondaryTitleColor = atelier ? titleColor.withAlphaComponent(0.8) : NSColor.secondaryLabelColor
            let dividerColor = atelier ? titleColor.withAlphaComponent(0.18) : NSColor.separatorColor
            let sortKey = table.sortDescriptors.first
            for (index, column) in table.tableColumns.enumerated() where !column.title.isEmpty {
                let cell = column.headerCell
                let rect = headerRect(ofColumn: index)
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
            for index in table.tableColumns.indices.dropLast() {
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
            // Skip dividers on an icon column, just before one and at the end
            // of the last column. The inset style's empty lead-in before the
            // first column has nothing to separate either.
            var edges: [CGFloat] = columns.isEmpty ? [] : [headerRect(ofColumn: 0).minX]
            for index in columns.indices {
                let isIcon = columns[index].title.isEmpty
                let beforeIcon = index + 1 < columns.count && columns[index + 1].title.isEmpty
                let isLast = index == columns.count - 1
                guard isIcon || beforeIcon || isLast else { continue }
                edges.append(headerRect(ofColumn: index).maxX)
            }
            drawColumnHeaders(table, dividers: edges)
        }
    }
}
