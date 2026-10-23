import SwiftUI
import AppKit

/// Pull-to-refresh for a ScrollView: pulling the page down past its top edge
/// fills a small ring; a full ring runs `action`. Works with the trackpad's
/// rubber band (fires as soon as the ring is full, but only while the fingers
/// pull – a fast swipe whose momentum bounces off the top doesn't count) and
/// with a click-drag of the page while it's at the top (fires on release).
/// ⌘R triggers the same action.
private struct PullToRefresh: ViewModifier {
    /// Asked when needed, not handed in as a value: read in a page's `body`,
    /// the sync starting and ending re-ran the whole page with all its cover
    /// cells – right when the sync capsule animates in (see `onObservedChange`).
    let disabled: () -> Bool
    let action: () -> Void
    /// The trackpad's rubber band is damped, so a few points more threshold
    /// already take a noticeably longer swipe.
    private let trackpadThreshold: CGFloat = 40
    private let mouseThreshold: CGFloat = 70
    @State private var overscroll: CGFloat = 0
    @State private var armed = true
    @State private var mousePull: CGFloat = 0
    @State private var atTop = true
    /// Fingers on the trackpad (or the scroll bar dragged). The momentum
    /// after a fast swipe runs as `.decelerating` and rubber-bands at the top
    /// just like a pull: it must neither fill the ring nor fire.
    @State private var pulling = false
    @State private var bouncing = false

    func body(content: Content) -> some View {
        content
            .offset(y: mousePull)
            .onScrollPhaseChange { old, phase in
                pulling = phase == .interacting
                // A pull from rest is never a bounce, whichever of phase and
                // geometry reports first.
                if pulling, old == .idle { bouncing = false }
            }
            // Clamped: anywhere below the top is the same value, so scrolling
            // through the page doesn't call this on every frame.
            .onScrollGeometryChange(for: CGFloat.self) { max(-2, -($0.contentOffset.y + $0.contentInsets.top)) } action: { _, distance in
                atTop = distance > -1
                let travel = max(0, distance)
                if travel < 6 {
                    armed = true
                    bouncing = false
                } else if overscroll < 6, !pulling {
                    // Began without the fingers: stays a bounce until the
                    // page is back at rest, even if they touch down during it.
                    bouncing = true
                }
                overscroll = travel
                if overscroll >= trackpadThreshold, armed, pulling, !bouncing, !disabled() {
                    armed = false
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                    action()
                }
            }
            .simultaneousGesture(mouseDrag)
            .overlay(alignment: .top) { indicator }
            .refreshShortcut(disabled: disabled, action: action)
    }

    private var mouseDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard atTop, value.translation.height > abs(value.translation.width) else { return }
                let damped = pow(max(0, value.translation.height), 0.8)
                if mousePull < mouseThreshold, damped >= mouseThreshold {
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                }
                mousePull = damped
            }
            .onEnded { _ in
                if mousePull >= mouseThreshold, !disabled() { action() }
                withAnimation(AppStyle.standardAnimation) { mousePull = 0 }
            }
    }

    @ViewBuilder private var indicator: some View {
        let pull = bouncing ? 0 : overscroll
        let progress = min(1, max(pull / trackpadThreshold, mousePull / mouseThreshold))
        let travel = max(pull, mousePull)
        if travel > 4 {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.1), lineWidth: AppStyle.progressLineWidth)
                Circle().trim(from: 0, to: progress)
                    .stroke(AppStyle.accent, style: StrokeStyle(lineWidth: AppStyle.progressLineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: progress >= 1 ? "checkmark" : "arrow.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(progress >= 1 ? AppStyle.accent : .secondary)
            }
            .frame(width: 26, height: 26)
            .opacity(progress)
            // A little room to the page's top edge, then it follows the pull.
            .padding(.top, 8 + max(0, travel / 2 - 13))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

extension View {
    /// ⌘R runs `action` — part of `pullToRefresh`, and on its own for views
    /// that can't be pulled (e.g. tables), so the shortcut works in every layout.
    func refreshShortcut(disabled: @escaping () -> Bool = { false }, action: @escaping () -> Void) -> some View {
        modifier(RefreshShortcut(disabled: disabled, action: action))
    }

    /// See `PullToRefresh`. Apply to the ScrollView itself.
    func pullToRefresh(disabled: @escaping () -> Bool = { false }, action: @escaping () -> Void) -> some View {
        modifier(PullToRefresh(disabled: disabled, action: action))
    }
}

/// `disabled` is read here, in a modifier of its own (see `PullToRefresh`).
private struct RefreshShortcut: ViewModifier {
    let disabled: () -> Bool
    let action: () -> Void
    func body(content: Content) -> some View {
        let disabled = disabled()
        content.background {
            Button("Aktualisieren", action: { if !disabled { action() } })
                .keyboardShortcut("r", modifiers: .command)
                .disabled(disabled)
                .opacity(0).frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}
