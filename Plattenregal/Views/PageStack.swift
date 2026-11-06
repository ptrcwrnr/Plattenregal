import SwiftUI
import SwiftData
import AppKit

/// Shows one of several pages and keeps all of them alive, so every page keeps
/// its data, sorting, scroll position and search while another one is shown.
///
/// Each page lives in its own hosting view that stays in the window the whole
/// time; switching only fades and nudges the layers (see `PageHostingView`,
/// `PageStackView.show`). A SwiftUI
/// `ZStack` with `.opacity(0)` did the same visually, but SwiftUI takes fully
/// transparent content out of the window: every switch tore down and rebuilt
/// the AppKit views behind tables and scroll views (100–200 ms on the main
/// thread) and the fade then redrew whole pages in every frame. Here the switch
/// is a pure Core Animation fade of what is already drawn.
///
/// - The selection is a `PageSelection` object, not a value: switching then
///   updates only the views that read it (the switch control, the pages'
///   visibility) instead of the view owning the pages – which would push its
///   environment into every page again and make each text re-check it.
/// - `content` is built once per page, and each page is its own view graph.
///   State shared with a page must live in an `@Observable` object that the
///   page gets and reads itself. A binding handed in keeps the value it had
///   when the page was built – whether to `@State` or from `Bindable`.
/// - Each page is its own SwiftUI root: of the surrounding environment it only
///   gets `pageVisibility` (shown, and its parent page shown too) and
///   `searchRequests`. Everything else it needs (model context, appearance,
///   settings store) `content` sets itself – see `appPageEnvironment`.
/// - Nothing in a page's environment changes on a switch: a changed value at
///   the top of a page makes SwiftUI re-check it for every text and control
///   below. Views that care ask `pageVisibility` (see `trackPageActivity`).
/// - A page that isn't shown gets no clicks, shortcuts, focus or VoiceOver.
/// - At launch only the page shown is built right away; the others follow
///   one by one once the window stands (or at once when switched to first).
///   Building all four up front kept the main thread busy for another ~0.6 s
///   with a large collection before the window answered.
struct PageStack<Page: Hashable, Content: View>: View {
    let pages: [Page]
    let selection: PageSelection<Page>
    @ViewBuilder let content: (Page) -> Content

    var body: some View {
        // `content` is only used once per page, so two stacks with the same
        // pages and selection are the same – whoever rebuilt this view.
        PageStackRepresentable(pages: pages, selection: selection, content: content).equatable()
    }
}

/// Which page a `PageStack` shows. Keep it in `@State` of the view that owns
/// the stack; controls take the object and bind to it with `@Bindable`.
@Observable final class PageSelection<Page: Hashable> {
    var current: Page
    init(_ page: Page) { current = page }
}

/// Whether one page of a stack is shown, its parent page included (for stacks
/// inside a page). Asking it goes through Observation, so the asking view
/// updates when the answer changes. Compared by identity: one per page, for
/// the page's whole life.
final class PageVisibility: Equatable {
    private let shown: () -> Bool
    fileprivate init(_ shown: @escaping () -> Bool) { self.shown = shown }
    var isShown: Bool { shown() }
    static func == (a: PageVisibility, b: PageVisibility) -> Bool { a === b }
}

private struct PageVisibilityKey: EnvironmentKey {
    static let defaultValue: PageVisibility? = nil
}
extension EnvironmentValues {
    /// The page this view is on, set by `PageStack`; nil outside of one
    /// (counts as shown). Stacks inside a page follow it.
    fileprivate(set) var pageVisibility: PageVisibility? {
        get { self[PageVisibilityKey.self] }
        set { self[PageVisibilityKey.self] = newValue }
    }
}

private struct PageStackRepresentable<Page: Hashable, Content: View>: NSViewRepresentable, Equatable {
    let pages: [Page]
    let selection: PageSelection<Page>
    let content: (Page) -> Content

    static func == (a: Self, b: Self) -> Bool { a.pages == b.pages && a.selection === b.selection }

    func makeNSView(context: Context) -> PageStackView<Page> {
        let view = PageStackView<Page>()
        // Both are objects set once for the window, never replaced: the pages
        // follow them through Observation, not through environment updates.
        let parent = context.environment.pageVisibility
        let searchRequests = context.environment.searchRequests
        for page in pages {
            let visibility = PageVisibility { [selection] in
                (parent?.isShown ?? true) && selection.current == page
            }
            view.add(page) { PageHost(visibility: visibility, searchRequests: searchRequests, content: content(page)) }
        }
        Self.follow(selection, in: view)
        view.buildRemainingPages()
        return view
    }

    /// Nothing to do: the stack never changes (see `==`), switches arrive
    /// through `follow`.
    func updateNSView(_ view: PageStackView<Page>, context: Context) {}

    /// Fills whatever space it is offered. Without this, SwiftUI asks AppKit
    /// for the stack's fitting size, which lays out every page to find it.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PageStackView<Page>, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    /// Shows the selected page now and after every change of the selection.
    private static func follow(_ selection: PageSelection<Page>, in view: PageStackView<Page>) {
        let page = withObservationTracking { selection.current } onChange: { [weak view] in
            // Called before the change is stored; show it once it is.
            DispatchQueue.main.async { if let view { follow(selection, in: view) } }
        }
        view.show(page)
    }
}

/// Root of one page's hosting view: which page it is (for whoever asks
/// whether it is shown) and where ⌘F requests come from.
private struct PageHost<Content: View>: View {
    let visibility: PageVisibility
    let searchRequests: SearchRequests?
    let content: Content
    var body: some View {
        content
            .environment(\.pageVisibility, visibility)
            .environment(\.searchRequests, searchRequests)
            // Invisible pages stay in the window (see `PageHostingView`).
            .accessibilityHidden(!visibility.isShown)
    }
}

extension View {
    /// What every page of a `PageStack` needs from the app around it: the
    /// app's look, its settings store and the database.
    func appPageEnvironment(_ context: ModelContext, windowBackground: Bool = true) -> some View {
        appAppearance(windowBackground: windowBackground)
            .defaultAppStorage(AppDefaults.store)
            .modelContext(context)
    }
}

final class PageStackView<Page: Hashable>: NSView {
    fileprivate(set) var hosts: [Page: any PageHosting] = [:]
    /// Pages not built yet (see `host(for:)`).
    private var builders: [Page: () -> any PageHosting] = [:]
    /// The pages in the order of the switch, for building them one by one.
    private var order: [Page] = []
    private var shown: Page?

    override var isFlipped: Bool { true }

    fileprivate func add<Root: View>(_ page: Page, root: @escaping () -> Root) {
        order.append(page)
        builders[page] = { [unowned self] in self.makeHost(root()) }
    }

    /// The page's hosting view, built on first use.
    private func host(for page: Page) -> (any PageHosting)? {
        if let host = hosts[page] { return host }
        guard let build = builders.removeValue(forKey: page) else { return nil }
        let host = build()
        hosts[page] = host
        return host
    }

    /// The pages not shown yet, one at a time whenever the main thread has
    /// nothing else to do: each is ready by the time anyone switches to it,
    /// and none of them holds up the first window.
    fileprivate func buildRemainingPages(after delay: TimeInterval = 0.8) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            // Once the run loop is about to wait for the next event.
            let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, false, 0) { _, _ in
                MainActor.assumeIsolated {
                    guard let self, let next = self.order.first(where: { self.hosts[$0] == nil }) else { return }
                    _ = self.host(for: next)
                    self.buildRemainingPages(after: 0.2)
                }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .defaultMode)
        }
    }

    private func makeHost<Root: View>(_ root: Root) -> any PageHosting {
        let host = PageHostingView(rootView: root)
        // The page fills the stack; it must not push its own size onto the window.
        host.sizingOptions = []
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.alphaValue = 0
        host.isHidden = true
        addSubview(host)
        return host
    }

    /// Timing and travel are the app's for switching a whole area
    /// (`AppStyle.pageFadeOut` …): the old page is gone before the new one shows up.
    private static var fadeOut: CFTimeInterval { AppStyle.pageFadeOut }
    private static var fadeInDelay: CFTimeInterval { AppStyle.pageFadeInDelay }
    private static var fadeIn: CFTimeInterval { AppStyle.pageFadeIn }
    private static var fadeKey: String { "pageFade" }
    private static var shiftKey: String { "pageShift" }

    /// Every switch fades through: the old page fades out quickly on the
    /// spot, then the new one fades in while settling down a little from
    /// above – whichever way it was
    /// triggered (switch control, ⌘1…4, "Im Regal anzeigen"). The two pages are never visible on top of each other: a
    /// crossfade showed both grids half transparent and, shifted against each
    /// other, covers of one page in the gaps of the other. In between there is
    /// only the window background with the ambient glow. With "Bewegung
    /// reduzieren" the settling is dropped, the fade stays. The first page just
    /// appears.
    ///
    /// Everything runs as explicit Core Animation on the hosting views'
    /// layers: the pages are not redrawn, the final values are set right away,
    /// and the model values AppKit manages (position, transform) are never
    /// touched – the shift exists only in the animation. The stack is not
    /// clipped: pages draw their background up under the toolbar, past its
    /// top edge.
    fileprivate func show(_ page: Page) {
        guard page != shown, let incoming = host(for: page) else { return }
        let outgoing = shown.flatMap { hosts[$0] }
        shown = page

        // Typing must not go on in a page that is fading out.
        if let outgoing, let responder = window?.firstResponder as? NSView, responder.isDescendant(of: outgoing) {
            window?.makeFirstResponder(nil)
        }
        for (key, host) in hosts {
            host.isShown = key == page
            // Pages still mid-switch from an earlier one end now.
            host.layer?.removeAnimation(forKey: Self.fadeKey)
            host.layer?.removeAnimation(forKey: Self.shiftKey)
            host.alphaValue = key == page ? 1 : 0
            if key == page { host.isHidden = false }
        }
        // Hidden once faded out: AppKit then hands it no pointer at all.
        // SwiftUI shows help texts (`.help`) through tracking areas it adds
        // whenever it likes, owned by its own tooltip manager – past `hitTest`
        // and the overrides of `PageHostingView` –, so a page with zero
        // opacity showed its help texts over the page shown.
        if let outgoing {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeOut) { [weak outgoing] in
                guard let outgoing, !outgoing.isShown else { return }
                outgoing.isHidden = true
            }
        }
        guard let outgoing, let incomingLayer = incoming.layer, let outgoingLayer = outgoing.layer else { return }
        // The pages' layers count downwards (seen in the window): a negative
        // offset starts the page above its place.
        let distance = AppStyle.reduceMotion ? 0 : -AppStyle.pageSettleDistance

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1
        fadeOut.toValue = 0
        fadeOut.duration = Self.fadeOut
        fadeOut.timingFunction = CAMediaTimingFunction(name: .easeIn)
        outgoingLayer.add(fadeOut, forKey: Self.fadeKey)

        // Until it starts, the delayed animation holds its start value
        // (`.backwards`), so the new page stays invisible meanwhile.
        let start = incomingLayer.convertTime(CACurrentMediaTime(), from: nil) + Self.fadeInDelay
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 1
        fadeIn.beginTime = start
        fadeIn.duration = Self.fadeIn
        fadeIn.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fadeIn.fillMode = .backwards
        incomingLayer.add(fadeIn, forKey: Self.fadeKey)
        if distance != 0 {
            // Critically damped like `AppStyle.layoutAnimation`: no overshoot.
            let push = CASpringAnimation(perceptualDuration: 0.3, bounce: 0)
            push.keyPath = "transform.translation.y"
            push.fromValue = distance
            push.toValue = 0
            push.beginTime = start
            push.duration = push.settlingDuration
            push.fillMode = .backwards
            incomingLayer.add(push, forKey: Self.shiftKey)
        }
    }
}

/// The hosting view of one page, whatever its root view type.
protocol PageHosting: NSView {
    /// false: transparent and out of the way – no clicks, no keyboard
    /// shortcuts, no keyboard focus.
    var isShown: Bool { get set }
}

/// Pages that aren't shown stay in the window: at zero opacity, and hidden
/// (`isHidden`) once faded out – only that keeps SwiftUI's help texts of a
/// page off the one shown (see `PageStackView.show`). Clicks, shortcuts and
/// focus are refused here as well, also while a page is still fading out.
private final class PageHostingView<Root: View>: NSHostingView<Root>, PageHosting {
    var isShown = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        isShown ? super.hitTest(point) : nil
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        isShown ? super.performKeyEquivalent(with: event) : false
    }
    override var acceptsFirstResponder: Bool { isShown && super.acceptsFirstResponder }
    override var canBecomeKeyView: Bool { isShown && super.canBecomeKeyView }
    // No hover either: the page's tracking areas stay in the window, and every
    // pointer movement over the page shown reached the invisible ones below
    // it too – a compartment or cover there lit up and was drawn again, and
    // the window worked out its drag regions anew each time (~70 % of the
    // main thread while moving the pointer over the statistics).
    override func mouseMoved(with event: NSEvent) { if isShown { super.mouseMoved(with: event) } }
    override func mouseEntered(with event: NSEvent) { if isShown { super.mouseEntered(with: event) } }
    override func mouseExited(with event: NSEvent) { if isShown { super.mouseExited(with: event) } }
}

/// Whether the page is shown, for pages that only need it in their handlers
/// (e.g. "catch up on a search once shown"). Asking `pageVisibility` in a
/// page's own `body` makes the whole page re-render on every switch; this
/// keeps the value in a plain reference instead, updated by
/// `trackPageActivity`, which also reports each change.
final class PageActivity {
    fileprivate(set) var isActive = true
}

private struct PageActivityTracker: ViewModifier {
    @Environment(\.pageVisibility) private var visibility
    let activity: PageActivity
    let onChange: (Bool) -> Void
    func body(content: Content) -> some View {
        // Only this modifier re-renders on a switch, not the page.
        let shown = visibility?.isShown ?? true
        // Set before any handler of this update reads it; not SwiftUI state,
        // so nothing re-renders because of it.
        activity.isActive = shown
        return content.onChange(of: shown) { _, active in onChange(active) }
    }
}

extension View {
    /// Keeps `activity` in step with `pageVisibility` and calls `onChange` when
    /// the page is shown or hidden – without making this view's body depend
    /// on it. See `PageActivity`.
    func trackPageActivity(_ activity: PageActivity, onChange: @escaping (Bool) -> Void = { _ in }) -> some View {
        modifier(PageActivityTracker(activity: activity, onChange: onChange))
    }
}
