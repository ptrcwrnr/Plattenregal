import SwiftUI
import SwiftData

/// The round button at the bottom right of the window, on every page. A click
/// opens the page's actions in a column straight above it, each the size of
/// the button itself, springing out one after the other
/// (`AppStyle.floatingOpenAnimation`); they close again calmly, and so does Esc, a
/// click beside them or choosing one. Which actions and in which order is
/// `FloatingAction.actions(on:)`.
///
/// A view of its own, read by nothing else: opening and closing redraws only
/// the button and its column, never the page beneath. The watcher for clicks
/// and Esc runs only while the column is open.
struct FloatingControls: View {
    let selection: PageSelection<Destination>
    let shelfRequests: ShelfRequests
    let statistics: StatisticsViewModel
    @Environment(\.modelContext) private var context
    @Environment(\.openSettings) private var openSettings
    @State private var sync = DiscogsSyncService.shared
    @AppStorage(DisplaySettings.collectionLayoutKey) private var collectionLayout = OverviewLayout.grid
    @AppStorage(DisplaySettings.wantlistLayoutKey) private var wantlistLayout = OverviewLayout.grid
    /// The column open (debug: `--preview-actions` starts with it).
    @State private var expanded = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--preview-actions")
        #else
        false
        #endif
    }()
    /// The page whose actions stand in the column. Set when it opens and kept
    /// while it closes, so a page switch doesn't swap the actions as they
    /// slide back into the button.
    @State private var columnPage: Destination

    init(selection: PageSelection<Destination>, shelfRequests: ShelfRequests, statistics: StatisticsViewModel) {
        self.selection = selection
        self.shelfRequests = shelfRequests
        self.statistics = statistics
        _columnPage = State(initialValue: selection.current)
    }

    var body: some View {
        let page = selection.current
        let actions = FloatingAction.actions(on: columnPage)
        // "Bewegung reduzieren": the actions wait at their places, full size,
        // and only fade in and out.
        let still = AppStyle.reduceMotion
        ZStack {
            // Every action is always there, hidden in the button while it
            // isn't in the column: a view that only appeared together with
            // `expanded` would stand at its place at once instead of
            // springing out (the column of another page has other actions).
            ForEach(FloatingAction.allCases, id: \.self) { action in
                let slot = actions.firstIndex(of: action)
                let shown = expanded && slot != nil
                item(spec(action, on: columnPage))
                    .offset(shown || still ? Self.offset(slot ?? 0) : .zero)
                    .scaleEffect(shown || still ? 1 : AppStyle.floatingHiddenScale)
                    .opacity(shown ? 1 : 0)
                    .allowsHitTesting(shown)
                    .accessibilityHidden(!shown)
                    // Out one after the other from the button upwards, back in together and calm.
                    .animation(expanded ? Self.openAnimation.delay(Double(slot ?? 0) * AppStyle.floatingStagger) : Self.closeAnimation,
                               value: expanded)
            }
            mainButton(page: page)
        }
        // A click anywhere beside the button and the column – page, list,
        // toolbar – closes it, and so does Esc.
        .background {
            if expanded {
                FloatingActionsWatcher(spots: [.zero] + actions.indices.map(Self.offset)) { collapse() }
            }
        }
        .padding(AppStyle.floatingMargin)
        .onChange(of: page) { collapse() }
    }

    // MARK: Main button and actions

    private func mainButton(page: Destination) -> some View {
        // A panel opened from the column (shelf page) shows on the button
        // while the column is closed, as it does on its action when open.
        let panelOpen = page == .shelf && shelfRequests.panel?.button != nil
        return Button {
            if !expanded { columnPage = page }
            withAnimation(expanded ? Self.closeAnimation : Self.openAnimation) { expanded.toggle() }
        } label: {
            ActionDots(upright: expanded, openAnimation: Self.openAnimation, closeAnimation: Self.closeAnimation)
                .foregroundStyle(AppStyle.isAtelier ? AnyShapeStyle(AtelierPalette.bandInk) : AnyShapeStyle(.primary))
                .frame(width: AppStyle.floatingButtonSize, height: AppStyle.floatingButtonSize)
                .floatingCircle(prominent: true, selected: panelOpen && !expanded)
                .contentShape(Circle())
        }
        .buttonStyle(FloatingButtonStyle())
        .help(expanded ? String(localized: "Aktionen schließen") : String(localized: "Aktionen"))
        .accessibilityLabel(String(localized: "Aktionen"))
        .accessibilityValue(expanded ? String(localized: "geöffnet") : "")
    }

    /// Straight above the button: the first action next to it, each further
    /// one a button and `floatingStackSpacing` higher.
    private static func offset(_ slot: Int) -> CGSize {
        CGSize(width: 0, height: -CGFloat(slot + 1) * (AppStyle.floatingButtonSize + AppStyle.floatingStackSpacing))
    }

    /// What an action shows and does on a page. One kind of view for every
    /// action, so a page switch changes only values, never the views.
    private struct ItemSpec {
        let systemImage: String
        /// For VoiceOver.
        let title: String
        /// The tooltip, with the shortcut.
        let help: String
        var disabled = false
        /// Its panel is open (shelf page).
        var selected = false
        let perform: () -> Void
    }

    private func spec(_ action: FloatingAction, on page: Destination) -> ItemSpec {
        switch action {
        case .reload where page == .statistics:
            let title = String(localized: "Aktualisieren")
            return ItemSpec(systemImage: "arrow.clockwise", title: title, help: AppShortcuts.help(title, keys: "⌘R"),
                            disabled: statistics.busy || sync.busy) {
                // Same as pulling the page or ⌘R (see `StatisticsView.refresh`).
                guard !statistics.busy, !sync.busy else { return }
                Task { await statistics.refresh(container: context.container) }
            }
        case .reload:
            let title = String(localized: "Synchronisieren")
            // Discogs is off in the demo.
            return ItemSpec(systemImage: "arrow.clockwise", title: title, help: AppShortcuts.help(title, keys: "⌘R"),
                            disabled: sync.busy || DemoMode.isActive) {
                guard !sync.busy, !DemoMode.isActive else { return }
                sync.start(page == .wantlist ? .wantlist : .collection, container: context.container)
            }
        case .layout:
            let layout = layoutBinding(for: page)
            let next: OverviewLayout = layout?.wrappedValue == .grid ? .list : .grid
            let title = next == .list ? String(localized: "Als Liste anzeigen") : String(localized: "Als Raster anzeigen")
            return ItemSpec(systemImage: next.systemImage, title: title,
                            help: AppShortcuts.help(title, keys: next == .list ? "⌥⌘2" : "⌥⌘1"), disabled: layout == nil) {
                layout?.wrappedValue = next
            }
        case .sortingIn, .history:
            let button: ShelfButton = action == .history ? .history : .sortingIn
            let isOpen = shelfRequests.panel?.button == button
            // The page opens the panel – or closes it, if it is this one's.
            return ItemSpec(systemImage: button.systemImage, title: button.title, help: button.help(isOpen: isOpen),
                            selected: isOpen) {
                shelfRequests.pressed = button
            }
        case .settings:
            let title = String(localized: "Einstellungen")
            return ItemSpec(systemImage: "gearshape", title: title, help: AppShortcuts.help(title, keys: "⌘,")) {
                openSettings()
            }
        }
    }

    /// One action in the column, the size of the button below it; choosing it
    /// closes the column.
    private func item(_ spec: ItemSpec) -> some View {
        Button {
            collapse()
            spec.perform()
        } label: {
            Image(systemName: spec.systemImage)
                .font(AppStyle.floatingSymbol)
                .foregroundStyle(AppStyle.isAtelier ? AnyShapeStyle(AtelierPalette.ink) : AnyShapeStyle(.primary))
                .opacity(spec.disabled ? AppStyle.dimmedOpacity : 1)
                .frame(width: AppStyle.floatingButtonSize, height: AppStyle.floatingButtonSize)
                .floatingCircle(prominent: false, selected: spec.selected)
                .contentShape(Circle())
        }
        .buttonStyle(FloatingButtonStyle())
        .disabled(spec.disabled)
        .help(spec.help)
        .accessibilityLabel(spec.title)
        .accessibilityValue(spec.selected ? String(localized: "geöffnet") : "")
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
        withAnimation(Self.closeAnimation) { expanded = false }
    }

    /// Springing out and calm closing, both ending on time (see
    /// `AppStyle.floatingOpenAnimation`); with reduce motion the column only
    /// fades in and out (see `body`).
    private static var openAnimation: Animation { AppStyle.floatingOpenAnimation }
    private static var closeAnimation: Animation { AppStyle.floatingCloseAnimation }
}

/// The round button and its actions. Unlike `.plain`, a disabled one isn't
/// faded as a whole – its paper or glass would turn see-through over the
/// covers; the action dims only its symbol (`dimmedOpacity`). Pressed, it
/// gives way a little.
private struct FloatingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? AppStyle.floatingPressedScale : 1)
            .animation(AppStyle.quickAnimation, value: configuration.isPressed)
    }
}

/// The three dots of the round button: side by side while the column is
/// closed; opening it, they go up into a line like the column itself – the
/// left one first, the same curve and the same beat apart – and come back
/// calmly together. Drawn instead of the `ellipsis` symbol, whose dots can
/// only turn as a whole.
private struct ActionDots: View {
    let upright: Bool
    let openAnimation: Animation
    let closeAnimation: Animation

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                // -1, 0, 1: left to right, and bottom to top once upright.
                let step = CGFloat(index - 1) * AppStyle.floatingDotSpacing
                Circle()
                    .frame(width: AppStyle.floatingDotSize, height: AppStyle.floatingDotSize)
                    .offset(upright ? CGSize(width: 0, height: -step) : CGSize(width: step, height: 0))
                    .animation(upright ? openAnimation.delay(Double(index) * AppStyle.floatingStagger) : closeAnimation, value: upright)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The actions in the column above the round button.
enum FloatingAction: Hashable, CaseIterable {
    /// Collection and wantlist: sync with Discogs; statistics: count again
    /// and fetch the value (both also ⌘R and pulling the page).
    case reload
    /// Grid or list (⌥⌘1, ⌥⌘2).
    case layout
    /// Shelf page: „Einsortieren“, every record without a place.
    case sortingIn
    /// Shelf page: the „Verlauf“ (⌘Y).
    case history
    case settings

    /// A page's actions from the button upwards: the first stands right
    /// above it, the settings always at the top.
    static func actions(on page: Destination) -> [FloatingAction] {
        switch page {
        case .collection, .wantlist: [.reload, .layout, .settings]
        case .shelf: [.sortingIn, .history, .settings]
        case .statistics: [.reload, .settings]
        }
    }

    /// How far the open column reaches up from the window's bottom edge, on
    /// the page with the most actions.
    static let columnReach: CGFloat = {
        let most = Destination.allCases.map { actions(on: $0).count }.max() ?? 0
        return AppStyle.floatingMargin + AppStyle.floatingButtonSize
            + CGFloat(most) * (AppStyle.floatingButtonSize + AppStyle.floatingStackSpacing)
    }()
}

/// While a column is open, Esc belongs to it: a panel over the page (see
/// `PanelEscapeMonitor`) leaves the key alone in this window, whichever of
/// the two watchers macOS asks first.
enum FloatingActionsEscape {
    static weak var window: NSWindow?
}

/// Watches the window's clicks and Esc while the column is open, and reports
/// a click that misses the button and every action, or Esc. Clicks are
/// watched, not caught, so they still reach what is under them – a list,
/// the toolbar, a cover – the same as beside an open menu; Esc is taken.
private struct FloatingActionsWatcher: NSViewRepresentable {
    /// The centers of the button and the actions, relative to the button's.
    let spots: [CGSize]
    let close: () -> Void

    func makeNSView(context: Context) -> Watcher { Watcher() }
    func updateNSView(_ view: Watcher, context: Context) {
        view.spots = spots
        view.close = close
    }
    static func dismantleNSView(_ view: Watcher, coordinator: ()) { view.stop() }

    final class Watcher: NSView {
        var spots: [CGSize] = []
        var close: (() -> Void)?
        private var monitor: Any?
        /// The window whose Esc this watcher claimed (`FloatingActionsEscape`).
        private weak var claimed: NSWindow?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window else { return }
            FloatingActionsEscape.window = window
            claimed = window
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                if event.type == .keyDown {
                    // Esc alone, and not for a sheet in front.
                    guard event.keyCode == 53, window.attachedSheet == nil,
                          event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return event }
                    self.close?()
                    return nil
                }
                let p = self.convert(event.locationInWindow, from: nil)
                let reach = AppStyle.floatingButtonSize / 2 + AppStyle.tightSpacing
                let hit = self.spots.contains { spot in
                    hypot(p.x - (self.bounds.midX + spot.width), p.y - (self.bounds.midY + spot.height)) <= reach
                }
                if !hit { self.close?() }
                return event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            if let claimed, FloatingActionsEscape.window === claimed { FloatingActionsEscape.window = nil }
            claimed = nil
        }
    }
}

/// How the shelf page's actions look and what their tooltips say.
private extension ShelfButton {
    var systemImage: String {
        switch self {
        case .history: "clock.arrow.circlepath"
        case .sortingIn: "plus"
        }
    }

    var title: String {
        switch self {
        case .history: String(localized: "Verlauf")
        case .sortingIn: String(localized: "Einsortieren")
        }
    }

    func help(isOpen: Bool) -> String {
        switch self {
        case .history:
            AppShortcuts.help(isOpen ? String(localized: "Verlauf schließen")
                                     : String(localized: "Verlauf – zuletzt einsortiert, verschoben, herausgenommen"), keys: "⌘Y")
        case .sortingIn:
            isOpen ? String(localized: "Einsortieren schließen")
                   : String(localized: "Einsortieren – noch nicht einsortierte Platten und wohin sie gehören")
        }
    }
}
