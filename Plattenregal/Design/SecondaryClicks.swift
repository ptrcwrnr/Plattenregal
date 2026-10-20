import SwiftUI
import AppKit

extension View {
    /// Right-click (or Control-click) on this view runs `action` with the
    /// click position as a unit point, e.g. to anchor an `AppMenu` popover
    /// there. Other clicks pass straight through to the view underneath.
    /// Not for the cells of a scrolling grid: see `GridSecondaryClicks`.
    func onSecondaryClick(perform action: @escaping (UnitPoint) -> Void) -> some View {
        overlay(SecondaryClickCatcher { point, size in
            action(UnitPoint(x: point.x / size.width, y: point.y / size.height))
        })
    }
}

/// Right-clicks on the cells of a scrolling cover grid. An AppKit view in
/// every cell (`onSecondaryClick`) made AppKit work out the window's drag
/// regions again for every frame of scrolling, walking all cells – about a
/// quarter of each scroll step. Here a single catcher lies over the scroll
/// view and finds the cell from the frames the cells report in the grid's
/// own space (which scrolling doesn't change) and where the grid stands.
/// Plain storage, not state: nothing re-renders when it changes.
final class GridSecondaryClicks<ID: Hashable> {
    fileprivate var cells: [ID: CGRect] = [:]
    fileprivate var gridOrigin: CGPoint = .zero
    fileprivate let gridSpace = UUID()
    fileprivate let scrollSpace = UUID()
}

extension View {
    /// On each cell of the grid.
    func gridSecondaryClickCell<ID: Hashable>(_ id: ID, in clicks: GridSecondaryClicks<ID>) -> some View {
        // The space's name alone goes into the geometry closure, which runs
        // off the main actor and must not take `clicks` (or `ID`) along.
        let space = clicks.gridSpace
        return onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(space)) }) { clicks.cells[id] = $0 }
            .onDisappear { clicks.cells[id] = nil }
    }

    /// On the lazy grid inside the scroll view.
    func gridSecondaryClickGrid<ID: Hashable>(_ clicks: GridSecondaryClicks<ID>) -> some View {
        let space = clicks.scrollSpace
        return coordinateSpace(.named(clicks.gridSpace))
            .onGeometryChange(for: CGPoint.self, of: { $0.frame(in: .named(space)).origin }) { clicks.gridOrigin = $0 }
    }

    /// On the scroll view: a right-click on a cell runs `action` with the
    /// cell and the click position as a unit point of the cell.
    func onGridSecondaryClick<ID: Hashable>(_ clicks: GridSecondaryClicks<ID>, perform action: @escaping (ID, UnitPoint) -> Void) -> some View {
        coordinateSpace(.named(clicks.scrollSpace))
            .overlay(SecondaryClickCatcher { point, _ in
                let p = CGPoint(x: point.x - clicks.gridOrigin.x, y: point.y - clicks.gridOrigin.y)
                guard let (id, frame) = clicks.cells.first(where: { $0.value.contains(p) }),
                      frame.width > 0, frame.height > 0 else { return }
                action(id, UnitPoint(x: (p.x - frame.minX) / frame.width, y: (p.y - frame.minY) / frame.height))
            })
    }
}

private struct SecondaryClickCatcher: NSViewRepresentable {
    /// The click's position in the view (from the top left) and the view's size.
    let action: (CGPoint, CGSize) -> Void
    func makeNSView(context: Context) -> CatcherView { CatcherView() }
    func updateNSView(_ view: CatcherView, context: Context) { view.action = action }

    final class CatcherView: NSView {
        var action: ((CGPoint, CGSize) -> Void)?
        override var isFlipped: Bool { true }
        private static func isSecondary(_ event: NSEvent?) -> Bool {
            guard let event else { return false }
            return event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        }
        // Only claims the secondary click; everything else (clicks, hover,
        // drags, tooltips) goes to the SwiftUI view below.
        override func hitTest(_ point: NSPoint) -> NSView? {
            Self.isSecondary(NSApp.currentEvent) ? super.hitTest(point) : nil
        }
        override func rightMouseDown(with event: NSEvent) { fire(event) }
        override func mouseDown(with event: NSEvent) {
            if Self.isSecondary(event) { fire(event) } else { super.mouseDown(with: event) }
        }
        private func fire(_ event: NSEvent) {
            guard bounds.width > 0, bounds.height > 0 else { return }
            action?(convert(event.locationInWindow, from: nil), bounds.size)
        }
    }
}

extension NSView {
    /// A table sits next to its background and overlay views, not above
    /// them: search upwards for the nearest ancestor that contains one.
    func nearbyTable() -> NSTableView? {
        func table(in view: NSView) -> NSTableView? {
            if let table = view as? NSTableView { return table }
            for subview in view.subviews { if let found = table(in: subview) { return found } }
            return nil
        }
        var node = superview
        while let current = node {
            if let found = table(in: current) { return found }
            node = current.superview
        }
        return nil
    }
}

/// Right-click (or Control-click) and, optionally, double-click on a row of
/// the SwiftUI `Table` beneath this overlay: reports the row (in the table's
/// order) and the click position as a unit point of the overlay, e.g. to
/// anchor an `AppMenu` or a popover there. Every other event goes straight
/// through to the table.
struct TableRowClicks: NSViewRepresentable {
    var secondary: ((Int, UnitPoint) -> Void)?
    var double: ((Int, UnitPoint) -> Void)?

    func makeNSView(context: Context) -> Catcher { Catcher() }
    func updateNSView(_ view: Catcher, context: Context) {
        view.secondary = secondary
        view.double = double
    }
    static func dismantleNSView(_ view: Catcher, coordinator: ()) { view.stop() }

    final class Catcher: NSView {
        var secondary: ((Int, UnitPoint) -> Void)?
        var double: ((Int, UnitPoint) -> Void)? {
            didSet { if (double == nil) != (oldValue == nil) { viewDidMoveToWindow() } }
        }
        private var monitor: Any?
        override var isFlipped: Bool { true }

        private static func isSecondary(_ event: NSEvent?) -> Bool {
            guard let event else { return false }
            return event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        }
        override func hitTest(_ point: NSPoint) -> NSView? {
            Self.isSecondary(NSApp.currentEvent) ? super.hitTest(point) : nil
        }
        override func rightMouseDown(with event: NSEvent) { fire(event, secondary) }
        override func mouseDown(with event: NSEvent) {
            if Self.isSecondary(event) { fire(event, secondary) } else { super.mouseDown(with: event) }
        }

        // Double-clicks go to the table itself; they are only watched.
        override func viewDidMoveToWindow() {
            stop()
            guard window != nil, double != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, event.clickCount == 2, event.window === self.window,
                      let table = self.nearbyTable(),
                      self.window?.contentView?.hitTest(event.locationInWindow)?.isDescendant(of: table) == true
                else { return event }
                self.fire(event, self.double)
                return event
            }
        }
        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func fire(_ event: NSEvent, _ action: ((Int, UnitPoint) -> Void)?) {
            guard let action, let table = nearbyTable(), bounds.width > 0, bounds.height > 0 else { return }
            let row = table.row(at: table.convert(event.locationInWindow, from: nil))
            guard row >= 0 else { return }
            let p = convert(event.locationInWindow, from: nil)
            action(row, UnitPoint(x: p.x / bounds.width, y: p.y / bounds.height))
        }
    }
}
