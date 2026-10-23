import SwiftUI
import AppKit

/// The icon's paper, petrol and label gold. These colors only participate in
/// Signature Designs; the existing system/accent/ambient choices stay intact.
enum AtelierPalette {
    static let paper = adaptive(0xF4EFE5, 0x172B32)
    static let surface = adaptive(0xFFFAF2, 0x213940)
    static let soft = adaptive(0xEBE5DA, 0x1B3138)
    static let ink = adaptive(0x233A3E, 0xEEE8DB)
    static let muted = adaptive(0x63716E, 0xB3C1BE)
    static let border = adaptive(0xDCD7CB, 0x3E5155)
    static let petrol = adaptive(0x1D4C5B, 0x123C4B)
    static let accent = adaptive(0x246074, 0xA5CCCF)
    static let gold = Color(nsColor: rgb(0xE2B660))
    static let goldForeground = Color(nsColor: rgb(0x293C39))
    static let toolbarSelection = Color(nsColor: rgb(0xF4EFE5))
    static let toolbarInk = Color(nsColor: rgb(0x233A3E))
    /// The search field on the petrol toolbar: `surface` and `border` of the
    /// dark paper, fixed – not resolved from the toolbar's color scheme,
    /// which now and then reached the field as light (a white field).
    static let toolbarField = Color(nsColor: rgb(0x213940))
    static let toolbarFieldBorder = Color(nsColor: rgb(0x3E5155))
    static let shadow = adaptive(0x1D3C42, 0x000000).opacity(0.08)
    /// Signal colors (see `AppStyle.successColor` …): moss, ochre, brick.
    static let success = adaptive(0x3E7A55, 0x8FC4A0)
    static let warning = adaptive(0xA8711C, 0xE2B660)
    static let error = adaptive(0xA9443A, 0xE69384)
    /// Categories in charts (statistics): petrol and gold first, then muted
    /// earth tones that sit well on cream and on the dark paper.
    static let chart: [Color] = [0x2F6F80, 0xD9A441, 0x7FA38A, 0xC2714F, 0x5B7DA6, 0x8C5A7A, 0xA8A060]
        .map { Color(nsColor: rgb($0)) }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: Double((hex >> 16) & 0xFF) / 255,
                green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255, alpha: 1)
    }
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            rgb(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }
}

/// Toolbar preferences from a small background leaf, so switching designs
/// never changes the page hierarchy. Scheme and visibility are always set,
/// never left out: a window opened in Klassisch otherwise keeps its dark
/// toolbar after switching to Modern (gray glass, light labels on the light
/// bar) and its bar with the line under it. Modern hides the bar like the
/// settings window, so the ambient background runs on under the toolbar.
struct SignatureToolbarAppearance: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if AppStyle.isAtelier {
                Color.clear.frame(width: 0, height: 0)
                    .toolbarBackground(AtelierPalette.petrol, for: .windowToolbar)
                    .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
            } else {
                Color.clear.frame(width: 0, height: 0)
                    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            }
        }
        .toolbarColorScheme(AppStyle.isAtelier ? .dark : scheme, for: .windowToolbar)
        .background { FullScreenToolbarBackground() }
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
