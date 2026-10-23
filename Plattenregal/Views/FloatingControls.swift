import SwiftUI
import SwiftData

/// The round button at the bottom right of the window. On collection and
/// wantlist a click fans the page's actions out around it on a quarter
/// circle – grid or list, sync, settings – and closes them again; so does
/// Esc, a click beside them or choosing one. On the shelf page it opens
/// "Einsortieren" right away: the records without a shelf and where they go;
/// above it one of the same size opens the "Verlauf".
struct FloatingControls: View {
    let selection: PageSelection<Destination>
    let shelfRequests: ShelfRequests
    @Environment(\.modelContext) private var context
    @Environment(\.openSettings) private var openSettings
    @State private var sync = DiscogsSyncService.shared
    @AppStorage(DisplaySettings.collectionLayoutKey) private var collectionLayout = OverviewLayout.grid
    @AppStorage(DisplaySettings.wantlistLayoutKey) private var wantlistLayout = OverviewLayout.grid
    /// The actions fanned out (debug: `--preview-actions` starts with them).
    @State private var expanded = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--preview-actions")
        #else
        false
        #endif
    }()

    private enum Action: Hashable, CaseIterable { case layout, sync, settings }

    var body: some View {
        let page = selection.current
        ZStack {
            if page.hasActions {
                controls(page: page).transition(.scale(scale: 0.6).combined(with: .opacity))
            } else if page == .shelf {
                VStack(spacing: AppStyle.rowSpacing) {
                    shelfButton("clock.arrow.circlepath", help: AppShortcuts.help(String(localized: "Verlauf – zuletzt einsortiert, verschoben, herausgenommen"), keys: "⌘Y"),
                                label: String(localized: "Verlauf")) { shelfRequests.showingHistory = true }
                    shelfButton("plus", help: String(localized: "Einsortieren – noch nicht einsortierte Platten und wohin sie gehören"),
                                label: String(localized: "Einsortieren")) { shelfRequests.sortingIn = true }
                }
                .padding(AppStyle.floatingMargin)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(AppStyle.quickAnimation, value: page.hasActions)
        .animation(AppStyle.quickAnimation, value: page == .shelf)
        .onChange(of: page) { collapse() }
    }

    private func controls(page: Destination) -> some View {
        let actions = Action.allCases
        return ZStack {
            ForEach(Array(actions.enumerated()), id: \.element) { index, action in
                actionButton(action, page: page)
                    .offset(expanded ? Self.offset(index, of: actions.count) : .zero)
                    .scaleEffect(expanded ? 1 : 0.3)
                    .opacity(expanded ? 1 : 0)
                    .allowsHitTesting(expanded)
                    .accessibilityHidden(!expanded)
                    .animation(AppStyle.reduceMotion ? .default : AppStyle.moveAnimation
                        .delay(expanded ? Double(index) * 0.03 : 0), value: expanded)
            }
            mainButton
        }
        // A click anywhere beside the button and the actions – page,
        // list, toolbar – closes them.
        .background {
            if expanded {
                OutsideClickWatcher(spots: [.zero] + actions.indices.map { Self.offset($0, of: actions.count) }) { collapse() }
            }
        }
        .padding(AppStyle.floatingMargin)
        // Esc closes the fanned-out actions.
        .background {
            if expanded {
                Button("") { collapse() }.keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true)
            }
        }
    }

    // MARK: Main button and actions

    private var mainButton: some View {
        Button {
            withAnimation(AppStyle.reduceMotion ? .default : AppStyle.moveAnimation) { expanded.toggle() }
        } label: {
            Image(systemName: "ellipsis")
                .font(AppStyle.floatingSymbol)
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .foregroundStyle(AppStyle.isAtelier ? AnyShapeStyle(AtelierPalette.toolbarSelection) : AnyShapeStyle(.primary))
                .frame(width: AppStyle.floatingButtonSize, height: AppStyle.floatingButtonSize)
                .floatingCircle(prominent: true)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(expanded ? String(localized: "Aktionen schließen") : String(localized: "Aktionen"))
        .accessibilityLabel(String(localized: "Aktionen"))
        .accessibilityValue(expanded ? String(localized: "geöffnet") : "")
    }

    /// The shelf page's two buttons, one above the other, both the size of
    /// the main button: one click each, no fan.
    private func shelfButton(_ systemImage: String, help: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(AppStyle.floatingSymbol)
                .foregroundStyle(AppStyle.isAtelier ? AnyShapeStyle(AtelierPalette.toolbarSelection) : AnyShapeStyle(.primary))
                .frame(width: AppStyle.floatingButtonSize, height: AppStyle.floatingButtonSize)
                .floatingCircle(prominent: true)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(label)
    }

    /// On a quarter circle from straight left to straight up of the button.
    private static func offset(_ index: Int, of count: Int) -> CGSize {
        let degrees = count == 1 ? 135 : 180 - Double(index) * 90 / Double(count - 1)
        let radians = degrees * .pi / 180
        let radius = AppStyle.floatingButtonSize + 34
        return CGSize(width: radius * cos(radians), height: -radius * sin(radians))
    }

    @ViewBuilder private func actionButton(_ action: Action, page: Destination) -> some View {
        switch action {
        case .layout:
            let layout = layoutBinding(for: page)
            let next: OverviewLayout = layout?.wrappedValue == .grid ? .list : .grid
            item(next.systemImage, next == .list ? String(localized: "Als Liste anzeigen") : String(localized: "Als Raster anzeigen"),
                 keys: next == .list ? "⌥⌘2" : "⌥⌘1") {
                layout?.wrappedValue = next
            }
        case .sync:
            item("arrow.clockwise", String(localized: "Synchronisieren"), keys: "⌘R") {
                sync.start(page == .wantlist ? .wantlist : .collection, container: context.container)
            }
            // Discogs is off in the demo.
            .disabled(sync.busy || DemoMode.isActive)
        case .settings:
            item("gearshape", String(localized: "Einstellungen"), keys: "⌘,") { openSettings() }
        }
    }

    /// One of the fanned-out actions; choosing it closes the fan.
    private func item(_ systemImage: String, _ title: String, keys: String, perform: @escaping () -> Void) -> some View {
        Button {
            collapse()
            perform()
        } label: {
            Image(systemName: systemImage)
                .font(AppStyle.floatingItemSymbol)
                .foregroundStyle(AppStyle.isAtelier ? AnyShapeStyle(AtelierPalette.ink) : AnyShapeStyle(.primary))
                .frame(width: AppStyle.floatingItemSize, height: AppStyle.floatingItemSize)
                .floatingCircle(prominent: false)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(AppShortcuts.help(title, keys: keys))
        .accessibilityLabel(title)
    }

    private func layoutBinding(for page: Destination) -> Binding<OverviewLayout>? {
        switch page {
        case .collection: $collectionLayout.animation(AppStyle.fadeAnimation)
        case .wantlist: $wantlistLayout.animation(AppStyle.fadeAnimation)
        case .shelf, .statistics: nil
        }
    }

    private func collapse() {
        guard expanded else { return }
        withAnimation(AppStyle.reduceMotion ? .default : AppStyle.moveAnimation) { expanded = false }
    }
}

/// Watches the window's clicks while the actions are fanned out and reports
/// one that misses the button and every action. It watches instead of
/// catching, so the click still reaches what is under it – a list, the
/// toolbar, a cover – the same as beside an open menu.
private struct OutsideClickWatcher: NSViewRepresentable {
    /// The centers of the button and the actions, relative to the button's.
    let spots: [CGSize]
    let outside: () -> Void

    func makeNSView(context: Context) -> Watcher { Watcher() }
    func updateNSView(_ view: Watcher, context: Context) {
        view.spots = spots
        view.outside = outside
    }
    static func dismantleNSView(_ view: Watcher, coordinator: ()) { view.stop() }

    final class Watcher: NSView {
        var spots: [CGSize] = []
        var outside: (() -> Void)?
        private var monitor: Any?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                let p = self.convert(event.locationInWindow, from: nil)
                let reach = AppStyle.floatingButtonSize / 2 + 4
                let hit = self.spots.contains { spot in
                    hypot(p.x - (self.bounds.midX + spot.width), p.y - (self.bounds.midY + spot.height)) <= reach
                }
                if !hit { self.outside?() }
                return event
            }
        }
        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
