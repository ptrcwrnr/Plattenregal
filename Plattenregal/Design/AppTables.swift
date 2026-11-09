import SwiftUI
import AppKit

// The lists' tables (collection, wantlist, shelf): column names, the column
// menu and fitting, the header, the room after the last row and the row hover.

/// The fixed names of the lists' columns, under which their order and
/// visibility are stored (`AppPreferences.collectionColumns` …). Never
/// rename a case's value: a stored arrangement would lose that column.
enum TableColumnID: String, CaseIterable {
    case cover, artist, title, year, label, genre, shelf, position, tags, note, added, link

    /// The column's header: the tables take it from here
    /// (`TableColumn(TableColumnID.year.title)`), and the column menu finds
    /// a clicked header's column by it. Empty for the icon columns.
    var title: String {
        switch self {
        case .cover, .link: ""
        case .artist: String(localized: "Interpret")
        case .title: String(localized: "Titel")
        case .year: String(localized: "Jahr")
        case .label: String(localized: "Label")
        case .genre: String(localized: "Genre")
        case .shelf: String(localized: "Fach")
        case .position: String(localized: "Pos.")
        case .tags: String(localized: "Tags")
        case .note: String(localized: "Notiz")
        case .added: String(localized: "Hinzugefügt")
        }
    }

    /// Artist and title always stay, so a list never ends up empty; the
    /// untitled icon columns have no entry in the menu to switch them.
    var hideable: Bool { !title.isEmpty && self != .artist && self != .title }

    /// The column a header title belongs to; nil for an unknown one.
    static func titled(_ title: String) -> TableColumnID? {
        guard !title.isEmpty else { return nil }
        return allCases.first { $0.title == title }
    }
}

extension TableColumnContent {
    /// The column's name for its stored order and visibility.
    func tableColumnID(_ id: TableColumnID) -> some TableColumnContent<TableRowValue, TableColumnSortComparator> {
        customizationID(id.rawValue)
            .disabledCustomizationBehavior(id.hideable ? [] : .visibility)
    }
}

extension View {
    /// A table on its card at the foot of a page (collection, wantlist,
    /// shelf): the card ends `pageMargin` above the window's bottom edge, as
    /// far from it as a page's sides. Collection and wantlist keep room for
    /// the round button at their end (`floatingClearance`, see `RootView`);
    /// the cover grid scrolls on through it, a table stopped above it and
    /// left a band of empty window – ignored here. On the shelf page the card
    /// ran past the window's edge. Inside the card the last rows scroll clear
    /// of the buttons by `clearance` (measured from the window's edge;
    /// `TableBottomInset`, as `contentMargins` doesn't reach a macOS table);
    /// 0 where there is no button (the collection in a panel of the
    /// statistics). The rows light up under the pointer (`TableRowHover`).
    func appBottomTableCard(clearance: CGFloat = AppStyle.floatingClearance) -> some View {
        background(TableRowHover())
            .overlay(TableBottomInset(inset: max(0, clearance - AppStyle.pageMargin)))
            .appTableCard()
            .padding(.bottom, AppStyle.pageMargin)
            .ignoresSafeArea(.container, edges: .bottom)
    }

    /// The lists' column menu: a right-click on the header row opens the
    /// app's own menu (`AppMenu`, so it looks like every other menu in the
    /// design) to hide the clicked column, switch each column on or off and
    /// show them all again. Replaces SwiftUI's native header menu. Put on
    /// the `Table` itself, so the menu points at the click.
    func tableColumnMenu<Row: Identifiable>(_ columns: Binding<TableColumnCustomization<Row>>) -> some View {
        modifier(TableColumnMenu(columns: columns))
    }
}

/// What the header reported for one right-click: the columns' headers in
/// their current order (hidden ones included), the one clicked, where, and
/// the table, to fit its columns after a change.
private struct TableColumnMenuRequest {
    let order: [TableColumnID]
    let clicked: TableColumnID?
    let anchor: UnitPoint
    weak var table: NSTableView?
}

private struct TableColumnMenu<Row: Identifiable>: ViewModifier {
    @Binding var columns: TableColumnCustomization<Row>
    @State private var request: TableColumnMenuRequest?

    func body(content: Content) -> some View {
        content
            .overlay(TableHeaderClicks { table, titles, clicked, anchor in
                let order = titles.compactMap(TableColumnID.titled)
                request = TableColumnMenuRequest(order: order, clicked: clicked.flatMap(TableColumnID.titled), anchor: anchor, table: table)
            })
            // Its own layer: the tables already present popovers of their own.
            .background {
                Color.clear.popover(isPresented: Binding(get: { request != nil }, set: { if !$0 { request = nil } }),
                                    attachmentAnchor: .point(request?.anchor ?? .top), arrowEdge: .bottom) {
                    if let request {
                        AppMenu(dismiss: { self.request = nil }) { entries(request) }
                    }
                }
            }
    }

    private func isShown(_ id: TableColumnID) -> Bool { columns[visibility: id.rawValue] != .hidden }
    private func set(_ ids: [TableColumnID], shown: Bool, in request: TableColumnMenuRequest) {
        for id in ids { columns[visibility: id.rawValue] = shown ? .visible : .hidden }
        // A column shown again comes back at its old width without the
        // others giving way: the columns ran past the card. Once SwiftUI
        // has applied the change, they are fitted into the table's width.
        let table = request.table
        DispatchQueue.main.async { table?.fitColumnsIfTheyOverflow() }
    }

    @ViewBuilder private func entries(_ request: TableColumnMenuRequest) -> some View {
        if let clicked = request.clicked, clicked.hideable {
            Button(String(localized: "„\(clicked.title)“ ausblenden")) { set([clicked], shown: false, in: request) }
            AppMenuDivider()
        }
        ForEach(request.order.filter { !$0.title.isEmpty }, id: \.self) { id in
            let shown = isShown(id)
            Button { set([id], shown: !shown, in: request) } label: {
                Label { Text(id.title) } icon: { Image(systemName: "checkmark").opacity(shown ? 1 : 0) }
            }
            .disabled(!id.hideable)
            .accessibilityAddTraits(shown ? .isSelected : [])
        }
        if request.order.contains(where: { $0.hideable && !isShown($0) }) {
            AppMenuDivider()
            Button(String(localized: "Alle einblenden")) {
                set(request.order.filter(\.hideable), shown: true, in: request)
            }
        }
    }
}

extension NSTableView {
    /// Fits the shown columns into the visible width when together they run
    /// past it (SwiftUI restores a shown-again or stored column at its old
    /// width without the others giving way). Columns that fit stay as they
    /// are, so widths dragged by hand are kept.
    func fitColumnsIfTheyOverflow() {
        guard let clip = enclosingScrollView?.contentView else { return }
        let shown = tableColumns.filter { !$0.isHidden }
        let used = shown.reduce(0) { $0 + $1.width } + intercellSpacing.width * CGFloat(shown.count)
        guard used > clip.bounds.width + 1 else { return }
        sizeToFit()
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

/// Room after the last row of the SwiftUI `Table` beneath this view, so it
/// can scroll clear of something lying over the table's lower end.
/// `contentMargins` has no effect on a macOS table, and setting the
/// `NSScrollView`'s insets directly replaces the room SwiftUI keeps there
/// itself; added to the scroll view's safe area, AppKit's automatic insets
/// keep both. Only while the rows reach that far: otherwise a list that fits
/// could be scrolled by the room, its first rows under the header.
///
/// Rows scrolling through that room are visible but SwiftUI hands them no
/// clicks, scrolling or hover there (any bottom inset does that, also one
/// set on the clip view). So this view lies over the table and passes what
/// lands in the room on to the table's own views; everywhere else it lets
/// everything through.
struct TableBottomInset: NSViewRepresentable {
    let inset: CGFloat

    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {
        view.inset = inset
        view.apply()
    }
    static func dismantleNSView(_ view: Anchor, coordinator: ()) { view.stop() }

    final class Anchor: NSView {
        var inset: CGFloat = 0
        private var observers: [any NSObjectProtocol] = []
        private weak var table: NSTableView?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            // The table joins the window in the same pass; look once it's there.
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }

        func stop() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            table = nil
        }

        /// Again whenever rows come or go (the table's height) or the
        /// window is resized (the scroll view's).
        private func attach() {
            guard window != nil, let table = nearbyTable(), let scroll = table.enclosingScrollView else { return }
            self.table = table
            for view in [table, scroll] as [NSView] {
                view.postsFrameChangedNotifications = true
                observers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.apply() }
                })
            }
            apply()
        }

        func apply() {
            guard window != nil, let table = table ?? nearbyTable(), let scroll = table.enclosingScrollView else { return }
            let added = scroll.additionalSafeAreaInsets.bottom
            // What the rows can fill without the added room: the scroll view
            // less the header and SwiftUI's own insets.
            let header = table.headerView?.frame.height ?? 0
            let available = scroll.frame.height - header - scroll.contentInsets.top - (scroll.contentInsets.bottom - added)
            let rows = table.numberOfRows > 0 ? table.rect(ofRow: table.numberOfRows - 1).maxY : 0
            let wanted = rows > available - inset ? inset : 0
            guard added != wanted else { return }
            scroll.additionalSafeAreaInsets.bottom = wanted
        }

        /// The table's own view under a point in the added room, else nil
        /// (the event goes on to whatever lies beneath, the table included).
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let table, let scroll = table.enclosingScrollView, let clip = table.superview,
                  let superview, scroll.additionalSafeAreaInsets.bottom > 0 else { return nil }
            let inWindow = superview.convert(point, to: nil)
            let inScroll = scroll.convert(inWindow, from: nil)
            guard scroll.bounds.contains(inScroll) else { return nil }
            // The room: from where the rows' visible area ends down by the
            // added inset (the scroll view's bounds are flipped like the table).
            let roomTop = scroll.bounds.maxY - scroll.contentInsets.bottom
            let flippedY = scroll.isFlipped ? inScroll.y : scroll.bounds.maxY - inScroll.y
            guard flippedY >= roomTop, flippedY < roomTop + scroll.additionalSafeAreaInsets.bottom else { return nil }
            return table.hitTest(clip.convert(inWindow, from: nil))
        }
    }
}

/// The row under the pointer in the SwiftUI `Table` beside this view, lit
/// by a band of `hoverBackground` that runs out to the left and right
/// (`rowHoverFadeShare`). SwiftUI doesn't report which row of a macOS table
/// the pointer is over, so this works on the `NSTableView` itself:
/// - One band for the whole table, a layer-backed view beneath the row views
///   (they are transparent). It scrolls with the rows by itself; moving it to
///   another row is a frame change, nothing is drawn again.
/// - The scroll view's tracking area reports moves only while the window is
///   key. A hit test makes sure nothing lying over the table (header, round
///   buttons, a panel) lights the row beneath it. It walks the whole window,
///   so it runs only when the row changes or near the table's upper and
///   lower edge, where header and buttons lie; moving along a row elsewhere
///   costs one row lookup.
/// - While the list scrolls nothing is looked up: the band goes and comes
///   back once the list has rested for `hoverSettleDelay` – one check
///   scheduled per pause, not one per scrolled frame.
struct TableRowHover: NSViewRepresentable {
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {
        // Resolved here, so light/dark and the design follow on their own.
        view.band.tint = NSColor(cgColor: AppStyle.hoverBackground.resolve(in: context.environment).cgColor) ?? .clear
    }
    static func dismantleNSView(_ view: Anchor, coordinator: ()) { view.stop() }

    final class Anchor: NSView {
        let band = Band()
        private weak var table: NSTableView?
        /// The scroll view: its tracking area covers the rows that scroll
        /// through the bottom insets, which the table's visible rect leaves out.
        private weak var tracked: NSView?
        private var tracking: NSTrackingArea?
        private var observers: [any NSObjectProtocol] = []
        /// The lit row, -1 for none.
        private var row = -1
        private var lastScroll = Date.distantPast
        private var settleCheckPending = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            // The table joins the window in the same pass; look once it's there.
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }

        private func attach() {
            guard window != nil, table == nil, let table = nearbyTable() else { return }
            self.table = table
            band.alphaValue = 0
            table.addSubview(band, positioned: .below, relativeTo: nil)
            let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                      owner: self, userInfo: nil)
            let host: NSView = table.enclosingScrollView ?? table
            host.addTrackingArea(area)
            tracked = host
            tracking = area
            let center = NotificationCenter.default
            if let clip = table.enclosingScrollView?.contentView {
                clip.postsBoundsChangedNotifications = true
                observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.scrolled() }
                })
            }
            // Rows came or went (a search, a sync) or the window was resized.
            table.postsFrameChangedNotifications = true
            observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: table, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            })
            observers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: table.window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.show(-1) }
            })
        }

        func stop() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            if let tracking { tracked?.removeTrackingArea(tracking) }
            tracking = nil
            tracked = nil
            band.removeFromSuperview()
            table = nil
            row = -1
        }

        override func mouseEntered(with event: NSEvent) { update() }
        override func mouseMoved(with event: NSEvent) { update() }
        override func mouseExited(with event: NSEvent) { show(-1) }

        private func scrolled() {
            lastScroll = Date()
            show(-1, animated: false)
            guard !settleCheckPending else { return }
            settleCheckPending = true
            settleCheck(after: AppStyle.hoverSettleDelay)
        }

        private func settleCheck(after delay: TimeInterval) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                let rested = Date().timeIntervalSince(self.lastScroll)
                if rested < AppStyle.hoverSettleDelay {
                    self.settleCheck(after: AppStyle.hoverSettleDelay - rested)
                } else {
                    self.settleCheckPending = false
                    self.update()
                }
            }
        }

        private func update() {
            guard !settleCheckPending, let table, let window = table.window, window.isKeyWindow,
                  !table.isHiddenOrHasHiddenAncestor else { show(-1); return }
            let pointer = window.mouseLocationOutsideOfEventStream
            let point = table.convert(pointer, from: nil)
            let hovered = table.row(at: point)
            // The clip view's whole area: `visibleRect` leaves out its insets,
            // and with them the rows that scroll through the room kept for
            // the round button (`TableBottomInset`).
            let visible = table.enclosingScrollView.map { $0.contentView.convert($0.contentView.bounds, to: table) } ?? table.visibleRect
            guard hovered >= 0, visible.contains(point) else { show(-1); return }
            // Still the same row away from the edges: nothing new can lie
            // over it there, so no hit test (it walks the whole window). At
            // the bottom the round button's open column can.
            let edge = FloatingAction.columnReach
            if hovered == row, point.y > visible.minY + edge, point.y < visible.maxY - edge { return }
            guard window.contentView?.hitTest(pointer)?.isDescendant(of: table) == true else { show(-1); return }
            show(hovered)
        }

        private func show(_ newRow: Int, animated: Bool = true) {
            guard newRow != row, let table else { return }
            let appearing = row < 0
            row = newRow
            if newRow < 0 {
                fade(to: 0, animated: animated)
                return
            }
            // The row view's frame, as wide as its separators (inset style).
            band.frame = table.rowView(atRow: newRow, makeIfNecessary: false)?.frame ?? table.rect(ofRow: newRow)
            if appearing { fade(to: 1, animated: animated) }
        }

        private func fade(to alpha: CGFloat, animated: Bool) {
            guard animated, !AppStyle.reduceMotion else {
                NSAnimationContext.runAnimationGroup { $0.duration = 0; band.alphaValue = alpha }
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = AppStyle.quickDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                band.animator().alphaValue = alpha
            }
        }
    }

    /// The band: a gradient layer, transparent at both ends.
    final class Band: NSView {
        var tint: NSColor = .clear { didSet { if tint != oldValue { updateColors() } } }
        private let gradient = CAGradientLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            gradient.startPoint = CGPoint(x: 0, y: 0.5)
            gradient.endPoint = CGPoint(x: 1, y: 0.5)
            let fade = AppStyle.rowHoverFadeShare
            gradient.locations = [0, NSNumber(value: Double(fade)), NSNumber(value: Double(1 - fade)), 1]
            wantsLayer = true
            updateColors()
        }
        required init?(coder: NSCoder) { fatalError("not used") }

        override func makeBackingLayer() -> CALayer { gradient }

        /// Never in the way of clicks or the table's own hit tests.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private func updateColors() {
            let full = tint.cgColor, clear = tint.withAlphaComponent(0).cgColor
            CATransaction.begin(); CATransaction.setDisableActions(true)
            gradient.colors = [clear, full, full, clear]
            CATransaction.commit()
        }
    }
}
