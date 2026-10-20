import SwiftUI

/// A plain click on the already selected row clears the selection, as a
/// click on the pulled-out spine does. `NSTableView` keeps the row selected
/// (only ⌘-click deselects), so this watches mouse-downs on the table itself.
/// The deselection waits out the double-click interval: a double-click opens
/// the quick editor and must leave the row selected. Clicks in icon columns
/// (untitled: cover, row buttons) are left alone.
struct TableRowClickToggle: NSViewRepresentable {
    let deselect: () -> Void

    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) { view.deselect = deselect }
    static func dismantleNSView(_ view: Anchor, coordinator: ()) { view.stop() }

    final class Anchor: NSView {
        var deselect: (() -> Void)?
        private var monitor: Any?
        private var pending: DispatchWorkItem?

        override func viewDidMoveToWindow() {
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        func stop() {
            pending?.cancel(); pending = nil
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ event: NSEvent) {
            pending?.cancel(); pending = nil
            guard let table = nearbyTable(), event.window === table.window, event.clickCount == 1,
                  event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty else { return }
            let point = table.convert(event.locationInWindow, from: nil)
            // Not when something covers the table there (a popover, the search results).
            guard table.visibleRect.contains(point),
                  table.window?.contentView?.hitTest(event.locationInWindow)?.isDescendant(of: table) == true else { return }
            let row = table.row(at: point), column = table.column(at: point)
            guard row >= 0, row == table.selectedRow, table.numberOfSelectedRows == 1,
                  table.tableColumns.indices.contains(column), !table.tableColumns[column].title.isEmpty else { return }
            let item = DispatchWorkItem { [weak self, weak table] in
                guard let table, table.selectedRow == row else { return }
                self?.deselect?()
            }
            pending = item
            DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: item)
        }
    }
}
