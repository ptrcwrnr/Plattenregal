import SwiftUI
import AppKit

extension View {
    /// The toolbar's look in every design, for a window's root view (main
    /// window, settings): the preferences from a background leaf and, in
    /// Klassisch and Vinyl, the colored band drawn over the page.
    func signatureToolbar() -> some View {
        background { SignatureToolbarAppearance() }
            .overlay { PaperToolbarBand() }
    }
}

/// Toolbar preferences from a small background leaf, so switching designs
/// never changes the page hierarchy. Scheme and visibility are always set,
/// never left out: a window opened in Klassisch otherwise keeps its dark
/// toolbar after switching to Modern (gray glass, light labels on the light
/// bar).
///
/// SwiftUI's own toolbar background stays hidden in every design. Shown in
/// a color (`toolbarBackground(_:for:)`, as Klassisch had it), it stopped
/// the window from being dragged by its toolbar on every page whose scroll
/// view carries a drag gesture – Collection, Wantlist and Statistik with
/// their pull to refresh –, only the shelf page could still be moved. The
/// paper designs draw their band themselves instead (`PaperToolbarBand`).
struct SignatureToolbarAppearance: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .toolbarColorScheme(AppStyle.isAtelier ? .dark : scheme, for: .windowToolbar)
            .background { FullScreenToolbarBackground() }
    }
}

/// Klassisch's petrol band (Vinyl's graphite) under the toolbar, as high as
/// the toolbar takes from the top. Drawn over the page, so what scrolls up
/// disappears beneath it as under an opaque bar; it takes no clicks, so the
/// toolbar's empty parts still move the window. Nothing in Modern.
private struct PaperToolbarBand: View {
    var body: some View {
        // The height is read outside: inside, `ignoresSafeArea` reports no
        // safe area at all (as in `AmbientGlow`).
        GeometryReader { outer in
            if AppStyle.isAtelier {
                AtelierPalette.petrol
                    .frame(height: outer.safeAreaInsets.top)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// In full screen macOS moves the toolbar into a window of its own
/// (`NSToolbarFullScreenWindow`), and there the system's titlebar
/// background (`NSTitlebarBackgroundView`) shows again – opaque white in
/// light mode. In Klassisch it covered the petrol bar SwiftUI draws beneath
/// it (light labels on white, only the search field with its fixed colors
/// stayed petrol); in Modern it cut the ambient color off under the bar. In
/// the normal window SwiftUI hides that background in both designs, so it
/// is hidden in full screen too and the bar looks the same in both.
///
/// Robust against AppKit showing it again: every background found is
/// watched (KVO on `hidden`) and hidden again at once, and the search runs
/// again on entering full screen, on a screen or appearance change and
/// when the toolbar window becomes key – in case AppKit builds a new one.
/// Leaving full screen needs nothing: the toolbar goes back into the
/// window, where SwiftUI keeps the background hidden anyway. If a later
/// macOS names these views differently, nothing is found and nothing
/// changes.
private struct FullScreenToolbarBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> Watcher { Watcher() }
    func updateNSView(_ view: Watcher, context: Context) {}
    static func dismantleNSView(_ view: Watcher, coordinator: ()) { view.stop() }

    final class Watcher: NSView {
        private var notifications: [NSObjectProtocol] = []
        private var appearanceWatch: NSKeyValueObservation?
        /// One watch on `hidden` per background found, by view.
        private var watches: [ObjectIdentifier: NSKeyValueObservation] = [:]

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window else { return }
            let center = NotificationCenter.default
            let reapply: @Sendable (Notification) -> Void = { [weak self] _ in
                MainActor.assumeIsolated { self?.apply() }
            }
            for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didChangeScreenNotification,
                         NSWindow.didChangeBackingPropertiesNotification] {
                notifications.append(center.addObserver(forName: name, object: window, queue: .main, using: reapply))
            }
            notifications.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                    object: nil, queue: .main, using: reapply))
            // The toolbar window turns key when the pointer reveals it.
            notifications.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification,
                                                    object: nil, queue: .main) { [weak self] note in
                guard let other = note.object, Self.isFullScreenToolbar(type(of: other)) else { return }
                MainActor.assumeIsolated { self?.apply() }
            })
            appearanceWatch = window.observe(\.effectiveAppearance) { [weak self] _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.apply() } }
            }
            apply()
        }

        func apply() {
            guard let window, window.styleMask.contains(.fullScreen) else { return }
            var found: [NSView] = []
            for toolbarWindow in NSApp.windows
            where Self.isFullScreenToolbar(type(of: toolbarWindow)) && belongs(toolbarWindow, to: window) {
                if let frame = toolbarWindow.contentView?.superview { collectBackgrounds(in: frame, into: &found) }
            }
            // Watches only for what is there now; a replaced view drops out.
            var next: [ObjectIdentifier: NSKeyValueObservation] = [:]
            for view in found {
                view.isHidden = true
                let id = ObjectIdentifier(view)
                next[id] = watches.removeValue(forKey: id) ?? view.observe(\.isHidden) { [weak self] view, _ in
                    MainActor.assumeIsolated {
                        guard !view.isHidden, self?.window?.styleMask.contains(.fullScreen) == true else { return }
                        view.isHidden = true
                    }
                }
            }
            watches.values.forEach { $0.invalidate() }
            watches = next
        }

        func stop() {
            notifications.forEach(NotificationCenter.default.removeObserver)
            notifications = []
            appearanceWatch = nil
            watches.values.forEach { $0.invalidate() }
            watches = [:]
        }

        private nonisolated static func isFullScreenToolbar(_ type: Any.Type) -> Bool {
            String(describing: type) == "NSToolbarFullScreenWindow"
        }

        /// The toolbar window of this window: its child if AppKit says so,
        /// otherwise the one on the same screen (one main window).
        private func belongs(_ toolbarWindow: NSWindow, to window: NSWindow) -> Bool {
            if let parent = toolbarWindow.parent { return parent === window }
            return toolbarWindow.screen == window.screen
        }

        private func collectBackgrounds(in view: NSView, into found: inout [NSView]) {
            if String(describing: type(of: view)) == "NSTitlebarBackgroundView" {
                found.append(view)
                return
            }
            for subview in view.subviews { collectBackgrounds(in: subview, into: &found) }
        }
    }
}
