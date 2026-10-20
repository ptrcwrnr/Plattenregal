import SwiftUI
import AppKit
import ObjectiveC

/// A panel over the page instead of a sheet: no close button – a click
/// beside it or Esc closes it.
struct AppPanelModifier<Item: Identifiable, Panel: View>: ViewModifier {
    @Binding var item: Item?
    var onDismiss: (() -> Void)?
    /// `.top` by default: a panel that grows (another list, a column folding
    /// out) extends downwards, and nothing moves under the pointer. One of a
    /// fixed size, like the welcome, may sit in the middle.
    var alignment: Alignment = .top
    @ViewBuilder let panel: (Item) -> Panel

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
                            .glassEffect(AppStyle.isAtelier ? .identity : .regular.tint(Color(nsColor: .windowBackgroundColor).opacity(0.65)),
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
            .onChange(of: item?.id) { old, new in
                if old != nil && new == nil { onDismiss?() }
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
    /// See `AppPanelModifier`. `onDismiss` runs whenever the panel closes.
    func appPanel<Item: Identifiable, Panel: View>(
        item: Binding<Item?>,
        alignment: Alignment = .top,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Panel
    ) -> some View {
        modifier(AppPanelModifier(item: item, onDismiss: onDismiss, alignment: alignment, panel: content))
    }
}
