import SwiftUI
import SwiftData
import AppKit

/// Shows one of several pages and keeps all of them alive, so every page keeps
/// its data, sorting, scroll position and search while another one is shown.
///
/// Each page lives in its own hosting view that stays in the window the whole
/// time; switching only fades the layers (see `PageHostingView`). A SwiftUI
/// `ZStack` with `.opacity(0)` did the same visually, but SwiftUI takes fully
/// transparent content out of the window: every switch tore down and rebuilt
/// the AppKit views behind tables and scroll views (100–200 ms on the main
/// thread) and the fade then redrew whole pages in every frame. Here the fade
/// is a pure Core Animation crossfade of what is already drawn.
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
            view.add(PageHost(visibility: visibility, searchRequests: searchRequests, content: content(page)), for: page)
        }
        Self.follow(selection, in: view)
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
    func appPageEnvironment(_ context: ModelContext) -> some View {
        appAppearance()
            .defaultAppStorage(AppDefaults.store)
            .modelContext(context)
    }
}

final class PageStackView<Page: Hashable>: NSView {
    fileprivate(set) var hosts: [Page: any PageHosting] = [:]
    private var shown: Page?
    /// Bumped per switch, so a fade that finishes late doesn't touch a page
    /// that has been selected again meanwhile.
    private var generation = 0

    override var isFlipped: Bool { true }

    fileprivate func add<Root: View>(_ root: Root, for page: Page) {
        let host = PageHostingView(rootView: root)
        // The page fills the stack; it must not push its own size onto the window.
        host.sizingOptions = []
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.alphaValue = 0
        addSubview(host)
        hosts[page] = host
    }

    /// Every switch fades, whichever way it was triggered (switch control,
    /// ⌘1…3, "Im Regal anzeigen"), with "Bewegung reduzieren" too: it is a
    /// fade, not a movement. The first page just appears.
    fileprivate func show(_ page: Page) {
        guard page != shown, let incoming = hosts[page] else { return }
        let outgoing = shown.flatMap { hosts[$0] }
        shown = page
        generation += 1
        let current = generation

        // Typing must not go on in a page that is fading out.
        if let outgoing, let responder = window?.firstResponder as? NSView, responder.isDescendant(of: outgoing) {
            window?.makeFirstResponder(nil)
        }
        for (key, host) in hosts {
            host.isShown = key == page
            // Pages still mid-fade from an earlier switch end now.
            if key != page && host !== outgoing { host.alphaValue = 0 }
        }
        guard let outgoing else {
            incoming.alphaValue = 1
            return
        }
        // Only the upper of the two pages fades, the lower one stays opaque,
        // so the window background never shows through. The subview order is
        // left alone: moving a view up means taking it out of the window and
        // back in, which is exactly the work this avoids.
        let incomingOnTop = (subviews.firstIndex(of: incoming) ?? 0) > (subviews.firstIndex(of: outgoing) ?? 0)
        incoming.alphaValue = incomingOnTop ? 0 : 1
        outgoing.alphaValue = 1
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            if incomingOnTop {
                incoming.animator().alphaValue = 1
            } else {
                outgoing.animator().alphaValue = 0
            }
        } completionHandler: { [weak self] in
            guard let self, self.generation == current else { return }
            outgoing.alphaValue = 0
        }
    }
}

/// The hosting view of one page, whatever its root view type.
protocol PageHosting: NSView {
    /// false: transparent and out of the way – no clicks, no keyboard
    /// shortcuts, no keyboard focus.
    var isShown: Bool { get set }
}

/// Pages that aren't shown stay in the window at zero opacity instead of
/// `isHidden`: hiding and showing a hosting view makes AppKit walk the whole
/// page (focus, cursor rects) and SwiftUI re-check every text's environment,
/// tens of milliseconds per switch. So what `isHidden` would do is done here.
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
