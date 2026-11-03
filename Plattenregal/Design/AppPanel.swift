import SwiftUI
import AppKit

/// A panel over the page instead of a sheet: no close button – a click
/// beside it or Esc closes it.
struct AppPanelModifier<Item: Identifiable, Panel: View>: ViewModifier {
    @Binding var item: Item?
    /// Gets the panel that left: closed, or replaced by another one.
    var onDismiss: ((Item) -> Void)?
    /// `.top` by default: a panel that grows (another list, a column folding
    /// out) extends downwards, and nothing moves under the pointer. One of a
    /// fixed size, like the welcome, may sit in the middle.
    var alignment: Alignment = .top
    @ViewBuilder let panel: (Item) -> Panel
    /// The item on screen, kept to hand to `onDismiss` once it is gone –
    /// only with an `onDismiss`, so no other panel holds on to its item
    /// (a record may be deleted meanwhile).
    @State private var onScreen: Item?

    func body(content: Content) -> some View {
        content
            .overlay {
                ZStack(alignment: alignment) {
                    if let shown = item {
                        // No dimming: the toolbar is drawn by the window and would
                        // stay bright above it, a hard edge. A shadow sets the
                        // panel off instead; the clear layer only catches clicks.
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { item = nil }
                            .transition(.opacity.combined(with: .releasesClicks))
                        panel(shown)
                            .clipShape(RoundedRectangle(cornerRadius: AppStyle.panelRadius))
                            .background {
                                if AppStyle.isAtelier {
                                    RoundedRectangle(cornerRadius: AppStyle.panelRadius).fill(AtelierPalette.surface)
                                }
                            }
                            // Tinted with the window color: the page behind
                            // doesn't run through the text.
                            .glassEffect(AppStyle.isAtelier ? .identity : AppStyle.panelGlass,
                                         in: .rect(cornerRadius: AppStyle.panelRadius))
                            .shadow(color: .black.opacity(0.18), radius: 30, y: 10)
                            // Esc closes it, wherever the focus is.
                            .background { PanelEscapeMonitor { item = nil } }
                            .padding(AppStyle.pagePadding)
                            // Only a fade: scaling made AppKit lay out every
                            // row of a table inside (and the window's drag
                            // regions) on each frame – ~200 ms of a fully busy
                            // main thread while "Platte hinzufügen" opened.
                            .transition(.opacity.combined(with: .releasesClicks))
                            .id(shown.id)
                    }
                }
                .animation(AppStyle.standardAnimation, value: item?.id)
            }
            .onChange(of: item?.id, initial: true) { _, new in
                let left = onScreen
                onScreen = onDismiss == nil ? nil : item
                if let left, left.id != new { onDismiss?(left) }
            }
    }
}

/// While a panel fades out, the click layer and the panel would still catch
/// clicks: a compartment clicked right after closing didn't react. Removing
/// lets clicks through at once; showing keeps them caught from the start.
private struct ClickRelease: ViewModifier {
    let released: Bool
    func body(content: Content) -> some View { content.allowsHitTesting(!released) }
}

private extension AnyTransition {
    static var releasesClicks: AnyTransition {
        .asymmetric(insertion: .identity,
                    removal: .modifier(active: ClickRelease(released: true), identity: ClickRelease(released: false)))
    }
}

/// Esc for a panel. A page is its own SwiftUI root (see `PageStack`), where
/// a `.cancelAction` shortcut never sees the key, so the key is caught before
/// the window handles it – only for the panel's own window (a popover, sheet
/// or the settings window in front gets its Esc itself) and only while the
/// panel's page is shown.
private struct PanelEscapeMonitor: NSViewRepresentable {
    let close: () -> Void
    @Environment(\.pageVisibility) private var visibility

    func makeNSView(context: Context) -> MonitorView { MonitorView() }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.close = close
        view.isShown = { [visibility] in visibility?.isShown ?? true }
    }

    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.stop() }

    final class MonitorView: NSView {
        var close: () -> Void = {}
        var isShown: () -> Bool = { true }
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.keyCode == 53,
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                      let window = self.window, event.window === window, window.attachedSheet == nil,
                      self.isShown() else { return event }
                self.close()
                return nil
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

extension View {
    /// See `AppPanelModifier`. `onDismiss` runs whenever a panel leaves –
    /// closed, or replaced by another – and gets the one that left.
    func appPanel<Item: Identifiable, Panel: View>(
        item: Binding<Item?>,
        alignment: Alignment = .top,
        onDismiss: ((Item) -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Panel
    ) -> some View {
        modifier(AppPanelModifier(item: item, onDismiss: onDismiss, alignment: alignment, panel: content))
    }
}

extension View {
    /// For a window of its own that should behave like a panel (the
    /// settings): a click into another window of the app – the main window,
    /// say – closes it, instead of leaving it open behind that window.
    /// Its own sheets, alerts, file dialogs and popovers keep it open, as do
    /// floating panels (the search in the menu bar) and other apps.
    func closesOnClickElsewhere() -> some View {
        background(ClickElsewhereCloser())
    }
}

private struct ClickElsewhereCloser: NSViewRepresentable {
    func makeNSView(context: Context) -> Watcher { Watcher() }
    func updateNSView(_ view: Watcher, context: Context) {}

    final class Watcher: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            guard window != nil else { return }
            NotificationCenter.default.addObserver(self, selector: #selector(otherWindowBecameKey(_:)),
                                                   name: NSWindow.didBecomeKeyNotification, object: nil)
        }

        @objc private func otherWindowBecameKey(_ notification: Notification) {
            guard let own = window, own.isVisible,
                  let other = notification.object as? NSWindow, other !== own,
                  // Only a real window of the app: titled, not a panel.
                  other.styleMask.contains(.titled), !(other is NSPanel),
                  !Self.belongs(other, to: own) else { return }
            own.close()
        }

        /// A sheet or child window of `own`, however deep.
        private static func belongs(_ window: NSWindow, to own: NSWindow) -> Bool {
            var node: NSWindow? = window
            while let current = node {
                if current === own { return true }
                node = current.sheetParent ?? current.parent
            }
            return false
        }
    }
}

extension View {
    /// Hides the window's close, minimize and zoom buttons – for a small
    /// window whose every state has its own button to close (the update
    /// window). Esc and ⌘W still close it. `titleBarHeight` gets the height
    /// of the now empty title bar (with `.hiddenTitleBar`), so the content
    /// can reach up into it.
    func hidesWindowControls(titleBarHeight: Binding<CGFloat>) -> some View {
        background(WindowControlsHider(titleBarHeight: titleBarHeight))
    }
}

private struct WindowControlsHider: NSViewRepresentable {
    @Binding var titleBarHeight: CGFloat

    func makeNSView(context: Context) -> HiderView { HiderView() }
    func updateNSView(_ view: HiderView, context: Context) {
        view.report = { height in if titleBarHeight != height { titleBarHeight = height } }
    }

    final class HiderView: NSView {
        var report: (CGFloat) -> Void = { _ in }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(kind)?.isHidden = true
            }
            let height = window.frame.height - window.contentLayoutRect.height
            // Not during the view update that put this view in the window.
            DispatchQueue.main.async { [report] in report(max(0, height)) }
        }
    }
}
