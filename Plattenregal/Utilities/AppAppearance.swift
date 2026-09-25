import SwiftUI
import AppKit
import ObjectiveC

/// Shared typography, spacing, color and motion tokens for every window, sheet,
/// dashboard and card in the app. Views should pull from here instead of writing
/// their own literals, so the whole app reads as one consistent design system.
enum AppStyle {
    // MARK: Spacing
    static let pagePadding: CGFloat = 24
    /// Height of every header-bar control, matching the segmented pickers.
    static let controlHeight: CGFloat = 26
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 20
    static let rowSpacing: CGFloat = 12
    static let itemSpacing: CGFloat = 8
    static let tightSpacing: CGFloat = 4

    // MARK: Corner radii
    // Shared corner radius for secondary surfaces (search fields, result
    // dropdowns, metric chips) so they read as one consistent system instead
    // of each picking its own rounding.
    static let surfaceRadius: CGFloat = 12
    /// Cards: record covers, shelf cards, dashboard/metric cards.
    static let cardRadius: CGFloat = 12
    /// Larger control surfaces: toolbars, control bars, prominent panels.
    static let controlRadius: CGFloat = 18

    // MARK: Typography
    static let pageTitle = Font.system(.title, design: .rounded, weight: .semibold)
    static let sectionTitle = Font.system(.title3, design: .rounded, weight: .semibold)
    static let dialogTitle = Font.system(.title2, design: .rounded, weight: .semibold)

    // MARK: Colors
    // All dynamic/system-based so Light and Dark mode stay correct automatically.
    static let hoverBackground = Color.primary.opacity(0.05)
    /// The accent chosen in the settings (or the system's). Read in `body`,
    /// so views redraw when it changes.
    static var accent: Color { AppPreferences.shared.accent.color }
    static var selectedBackground: Color { accent.opacity(0.12) }
    static var selectedBorder: Color { accent }
    static let borderColor = Color.primary.opacity(0.08)
    static let successColor = Color.green
    static let warningColor = Color.orange
    static let errorColor = Color.red

    // MARK: Wording
    /// "1 Platte", "12 Platten", "1.234 Platten".
    static func records(_ count: Int) -> String { count == 1 ? "1 Platte" : "\(count.formatted()) Platten" }

    // MARK: Motion
    // One curve for the whole app: `.smooth`, a critically damped spring — no
    // visible overshoot, and it retargets cleanly when interrupted (e.g. the
    // sidebar toggled again mid-animation). Only the duration varies.
    // With "Reduce motion" on, nothing travels: movement is dropped and only
    // fades remain.

    /// System setting "Bewegung reduzieren"; read when an animation starts.
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Hover/selection feedback — short and unobtrusive.
    static let quickAnimation = Animation.smooth(duration: 0.2)
    /// State changes — dimming, showing/hiding, focus changes.
    static let standardAnimation = Animation.smooth(duration: 0.25)
    /// Crossfade between pages, sections and grid ↔ list. Kept with reduce motion.
    static let fadeAnimation = Animation.smooth(duration: 0.25)
    /// Anything that moves or resizes: records travelling to a new sort
    /// position, columns reflowing, the sidebar sliding. `nil` (= instant)
    /// with reduce motion.
    static var layoutAnimation: Animation? { reduceMotion ? nil : .smooth(duration: 0.3) }
    /// Insert/remove transition matching the above: slide + fade, or just fade.
    /// The app's one transition for anything that appears or disappears as a
    /// block (cards, banners, status lines, expanding lists, toasts): it pours
    /// out of the edge it hangs from like from a funnel – narrower and squashed
    /// at first, then opening up – and back in on removal. It stays in place
    /// instead of sliding across whatever sits next to it. Text swapped inside
    /// a fixed slot and small badges just fade.
    static func funnelTransition(from edge: VerticalEdge = .top) -> AnyTransition {
        reduceMotion ? .opacity : .modifier(active: FunnelEffect(progress: 1, anchor: edge == .top ? .top : .bottom),
                                            identity: FunnelEffect(progress: 0, anchor: edge == .top ? .top : .bottom))
    }
}

private struct FunnelEffect: ViewModifier {
    /// 0 = fully shown, 1 = poured back into the funnel.
    let progress: CGFloat
    let anchor: UnitPoint
    func body(content: Content) -> some View {
        content
            .scaleEffect(x: 1 - 0.12 * progress, y: 1 - 0.45 * progress, anchor: anchor)
            .opacity(1 - progress)
    }
}
extension View {
    func appAppearance() -> some View { modifier(AppAppearanceModifier()) }
}

private struct AppAppearanceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.body).fontDesign(.rounded).controlSize(.regular)
            // SwiftUI's own focus effect; AppKit-backed controls are handled by
            // `FocusRings.disableGlobally()` at launch.
            .focusEffectDisabled()
            // Controls, links and `.tint` styles follow the chosen accent.
            .tint(AppStyle.accent)
            .onAppear { AppPreferences.shared.applyAppearance() }
    }
}

extension View {
    func appGlassSurface(cornerRadius: CGFloat) -> some View {
        glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }

    /// Standard hover feedback (subtle background tint) shared by every interactive
    /// card/row in the app, so hover always looks and animates the same way.
    func appHoverable(_ hovering: Bool, cornerRadius: CGFloat = AppStyle.cardRadius) -> some View {
        self.background(hovering ? AppStyle.hoverBackground : Color.clear, in: RoundedRectangle(cornerRadius: cornerRadius))
            .animation(AppStyle.quickAnimation, value: hovering)
    }
}


/// One button vocabulary for the whole app: Primary (main action), Secondary
/// (normal action), Ghost (low-emphasis/secondary action), Icon (compact icon-only).
struct PrimaryButton: View {
    let title: String
    var action: () -> Void
    var body: some View {
        Button(title, action: action).buttonStyle(.borderedProminent)
    }
}
struct SecondaryButton: View {
    let title: String
    var action: () -> Void
    var body: some View {
        Button(title, action: action).buttonStyle(.bordered)
    }
}
struct GhostButton: View {
    let title: String
    var action: () -> Void
    var body: some View {
        Button(title, action: action).buttonStyle(.borderless)
    }
}
struct IconButton: View {
    let systemImage: String
    var help: String = ""
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// One search-field chrome for the whole app: icon, text field, clear button
/// on a slim, quiet fill (same look as the search on the shelf page).
struct AppSearchField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: (() -> Void)?
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .onSubmit { onSubmit?() }
                // Esc clears the query; with an empty field it passes through
                // (e.g. to close the sheet the field sits in).
                .onKeyPress(.escape) {
                    guard !text.isEmpty else { return .ignored }
                    text = ""
                    return .handled
                }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: AppStyle.controlHeight)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
    }
}


/// Capsule badge/pill used for genres, styles and filters. `prominent` marks the
/// active/selected state; both use the same tokens as card selection elsewhere.
struct AppBadge: View {
    let title: String
    var systemImage: String?
    var prominent: Bool = false
    var body: some View {
        Group {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .font(.caption2.weight(prominent ? .semibold : .regular))
        .foregroundStyle(prominent ? AppStyle.accent : .secondary)
        .padding(.horizontal, AppStyle.itemSpacing + 2)
        .padding(.vertical, AppStyle.tightSpacing)
        .background(prominent ? AppStyle.selectedBackground : AppStyle.hoverBackground.opacity(1.2), in: Capsule())
    }
}

/// Standard sheet header: title, optional subtitle, close/cancel button, divider.
/// Used by every modal sheet so they all read as one dialog language.
struct AppSheetHeader: View {
    let title: String
    var closeTitle: String = "Schließen"
    var onClose: (() -> Void)?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(AppStyle.dialogTitle)
                Spacer()
                if let onClose {
                    GhostButton(title: closeTitle, action: onClose)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(AppStyle.pagePadding)
            Divider()
        }
    }
}

/// A "cover + details + trailing action" result card: the shared shape behind
/// every Discogs/wantlist result row, so they read as one component instead of
/// independently duplicated hover/glass/layout code. `trailing` receives the
/// current hover state (e.g. to fade an affordance icon in/out).

/// Inline status/error/warning banner. One visual language for anything that
/// needs the user's attention inline, instead of ad hoc colored text per view.
struct AppBanner: View {
    enum Kind { case info, success, warning, error
        var color: Color {
            switch self {
            case .info: AppStyle.accent
            case .success: AppStyle.successColor
            case .warning: AppStyle.warningColor
            case .error: AppStyle.errorColor
            }
        }
        var systemImage: String {
            switch self {
            case .info: "info.circle"
            case .success: "checkmark.circle"
            case .warning: "exclamationmark.triangle"
            case .error: "exclamationmark.triangle"
            }
        }
    }
    let message: String
    var kind: Kind = .warning
    var actionTitle: String?
    var action: (() -> Void)?
    var onDismiss: (() -> Void)?
    var body: some View {
        HStack {
            Image(systemName: kind.systemImage).foregroundStyle(kind.color)
            Text(message)
            Spacer()
            if let actionTitle, let action {
                GhostButton(title: actionTitle, action: action)
            }
            if let onDismiss {
                IconButton(systemImage: "xmark", action: onDismiss)
            }
        }
        .font(.callout)
        .padding(AppStyle.itemSpacing + 2)
        .background(kind.color.opacity(0.1), in: RoundedRectangle(cornerRadius: AppStyle.surfaceRadius))
    }
}

/// One predictable layout for empty and initial states throughout the app.
struct AppEmptyState: View {
    let title: String
    let systemImage: String
    let description: Text
    var actionTitle: String?
    var action: (() -> Void)?
    init(_ title: String, systemImage: String, description: Text,
         actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title; self.systemImage = systemImage; self.description = description
        self.actionTitle = actionTitle; self.action = action
    }
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .light)).foregroundStyle(.tertiary)
                .frame(width: 56, height: 56).accessibilityHidden(true)
            Text(title).font(AppStyle.sectionTitle)
            description.font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent).padding(.top, 4)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 420)
        .padding(AppStyle.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

/// Turns off the blue focus ring app-wide while keeping keyboard focus itself.
/// Buttons, text fields and tables are AppKit controls under the hood and draw
/// their ring based on `focusRingType`, which SwiftUI's `focusEffectDisabled()`
/// doesn't reach — so the getter is overridden once for NSView, NSControl and
/// NSCell (where controls forward it) to always answer `.none`.
enum FocusRings {
    static func disableGlobally() {
        let selector = #selector(getter: NSView.focusRingType)
        let block: @convention(block) (AnyObject) -> UInt = { _ in NSFocusRingType.none.rawValue }
        let implementation = imp_implementationWithBlock(block)
        for cls in [NSView.self, NSControl.self, NSCell.self] as [AnyClass] {
            guard let method = class_getInstanceMethod(cls, selector) else { continue }
            class_replaceMethod(cls, selector, implementation, method_getTypeEncoding(method))
        }
    }
}

/// Cover grids fill their content width exactly, so the outer covers line up
/// with the header bar above them. `minimum` is the minimum cover width; the
/// column count follows from the *current* width and the columns are
/// `.flexible`, so each cell (and the cover filling it) is always exactly
/// its share of the width — covers grow slightly to use up the space that
/// would otherwise be left over, and can never be wider than their cell.
/// Raster/Liste switch, in the page headers (icons only) and the settings.
struct OverviewLayoutPicker: View {
    @Binding var selection: OverviewLayout
    var iconOnly = false

    var body: some View {
        Picker("Darstellung", selection: $selection) {
            ForEach(OverviewLayout.allCases) { layout in
                label(for: layout).tag(layout)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented).fixedSize()
        .help("Zwischen Raster und Liste wechseln")
    }

    @ViewBuilder private func label(for layout: OverviewLayout) -> some View {
        if iconOnly {
            Label(layout.title, systemImage: layout.systemImage).labelStyle(.iconOnly)
        } else {
            Label(layout.title, systemImage: layout.systemImage)
        }
    }
}

enum CoverGrid {
    static let spacing: CGFloat = 8

    static func columnCount(available: CGFloat, minimum: CGFloat) -> Int {
        guard available.isFinite, minimum.isFinite, minimum > 0 else { return 1 }
        return max(1, Int((max(0, available) + spacing) / (minimum + spacing)))
    }

    /// Column count from `reference` (the width with the sidebar shown, see
    /// `gridReferenceWidth`), so the sidebar only scales the covers. Capped by
    /// the real width so covers never get much smaller than `minimum`.
    static func columnCount(available: CGFloat, reference: CGFloat?, minimum: CGFloat) -> Int {
        min(columnCount(available: reference ?? available, minimum: minimum),
            columnCount(available: available, minimum: minimum * 0.75))
    }

    static func columns(count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: count)
    }
}

extension View {
    /// Motion for a cover grid of `width` with `columnCount` columns.
    /// - The grid growing in one step (sidebar hidden, full screen, zoom)
    ///   animates; the column count stays the same, so every cover just scales
    ///   up within its own cell and none crosses another.
    /// - Shrinking applies at once, so a cover is never wider than the space
    ///   it is in — not even for a frame. Live window resizing follows the
    ///   pointer directly.
    /// - A new column count (reflow) is never animated: covers changing rows
    ///   would slide across each other.
    /// - Clipped to the grid's bounds as a last line of defence.
    func coverGridMotion(width: CGFloat, columnCount: Int) -> some View {
        modifier(CoverGridMotion(width: width, columnCount: columnCount))
    }
}

private struct CoverGridMotion: ViewModifier {
    let width: CGFloat
    let columnCount: Int
    /// Only tells growing from shrinking — never used for layout.
    @State private var previousWidth: CGFloat?

    func body(content: Content) -> some View {
        let grows = previousWidth.map { width > $0 } ?? false
        content
            .transaction(value: columnCount) { $0.animation = nil }
            .transaction(value: width) { transaction in
                let liveResize = NSApp.windows.contains(where: \.inLiveResize)
                transaction.animation = grows && !liveResize ? AppStyle.layoutAnimation : nil
            }
            .clipped()
            .onAppear { previousWidth = width }
            .onChange(of: width) { _, new in previousWidth = new }
    }
}

/// Pull-to-refresh for a ScrollView: pulling the page down past its top edge
/// fills a small ring; a full ring runs `action`. Works with the trackpad's
/// rubber band (fires as soon as the ring is full) and, when `allowsMouseDrag`
/// is on, with a click-drag of the page while it's at the top (fires on
/// release). ⌘R triggers the same action. Leave the mouse drag off where
/// dragging already means something (e.g. rubber-band selection).
private struct PullToRefresh: ViewModifier {
    let disabled: Bool
    let allowsMouseDrag: Bool
    let action: () -> Void
    /// The trackpad's rubber band is damped, so a few points more threshold
    /// already take a noticeably longer swipe.
    private let trackpadThreshold: CGFloat = 38
    private let mouseThreshold: CGFloat = 70
    @State private var overscroll: CGFloat = 0
    @State private var armed = true
    @State private var mousePull: CGFloat = 0
    @State private var atTop = true

    func body(content: Content) -> some View {
        content
            .offset(y: mousePull)
            .onScrollGeometryChange(for: CGFloat.self) { -($0.contentOffset.y + $0.contentInsets.top) } action: { _, distance in
                atTop = distance > -1
                overscroll = max(0, distance)
                if overscroll < 6 { armed = true }
                if overscroll >= trackpadThreshold, armed, !disabled {
                    armed = false
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                    action()
                }
            }
            .simultaneousGesture(mouseDrag, including: allowsMouseDrag ? .all : .subviews)
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
                if mousePull >= mouseThreshold, !disabled { action() }
                withAnimation(AppStyle.standardAnimation) { mousePull = 0 }
            }
    }

    @ViewBuilder private var indicator: some View {
        let progress = min(1, max(overscroll / trackpadThreshold, mousePull / mouseThreshold))
        let travel = max(overscroll, mousePull)
        if travel > 4 {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.1), lineWidth: 2.5)
                Circle().trim(from: 0, to: progress)
                    .stroke(AppStyle.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: progress >= 1 ? "checkmark" : "arrow.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(progress >= 1 ? AppStyle.accent : .secondary)
            }
            .frame(width: 26, height: 26)
            .opacity(progress)
            .padding(.top, max(0, travel / 2 - 13))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

extension View {
    /// ⌘R runs `action` — part of `pullToRefresh`, and on its own for views
    /// that can't be pulled (e.g. tables), so the shortcut works in every layout.
    func refreshShortcut(disabled: Bool = false, action: @escaping () -> Void) -> some View {
        background {
            Button("Aktualisieren", action: { if !disabled { action() } })
                .keyboardShortcut("r", modifiers: .command)
                .disabled(disabled)
                .opacity(0).frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    /// See `PullToRefresh`. Apply to the ScrollView itself.
    func pullToRefresh(disabled: Bool = false, allowsMouseDrag: Bool = true, action: @escaping () -> Void) -> some View {
        modifier(PullToRefresh(disabled: disabled, allowsMouseDrag: allowsMouseDrag, action: action))
    }
}

/// The app's own context menu: a popover with hover rows instead of the
/// native macOS menu. Plain `Button`s and `Divider`s inside `content` are
/// styled as menu rows; choosing one closes the menu first, then runs the
/// action (so a sheet it opens isn't fighting the closing popover).
struct AppMenu<Content: View>: View {
    let dismiss: () -> Void
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 1) { content }
            .buttonStyle(AppMenuButtonStyle(dismiss: dismiss))
            .padding(5)
            .frame(minWidth: 220, alignment: .leading)
            .fixedSize()
    }
}

/// Small caption over a group of rows in an `AppMenu`.
struct AppMenuSection: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }
}

private struct AppMenuButtonStyle: PrimitiveButtonStyle {
    let dismiss: () -> Void
    func makeBody(configuration: Configuration) -> some View {
        AppMenuRow(configuration: configuration, dismiss: dismiss)
    }
}

private struct AppMenuRow: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let dismiss: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false
    var body: some View {
        Button {
            dismiss()
            DispatchQueue.main.async { configuration.trigger() }
        } label: {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(configuration.role == .destructive ? AnyShapeStyle(AppStyle.errorColor) : AnyShapeStyle(.primary))
        .opacity(isEnabled ? 1 : 0.4)
        .appHoverable(hovering && isEnabled, cornerRadius: 6)
        .onHover { hovering = $0 }
    }
}

extension View {
    /// Right-click (or Control-click) on this view runs `action` with the
    /// click position as a unit point, e.g. to anchor an `AppMenu` popover
    /// there. Other clicks pass straight through to the view underneath.
    func onSecondaryClick(perform action: @escaping (UnitPoint) -> Void) -> some View {
        overlay(SecondaryClickCatcher(action: action))
    }
}

private struct SecondaryClickCatcher: NSViewRepresentable {
    let action: (UnitPoint) -> Void
    func makeNSView(context: Context) -> CatcherView { CatcherView() }
    func updateNSView(_ view: CatcherView, context: Context) { view.action = action }

    final class CatcherView: NSView {
        var action: ((UnitPoint) -> Void)?
        override var isFlipped: Bool { true }
        private static func isSecondary(_ event: NSEvent?) -> Bool {
            guard let event else { return false }
            return event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        }
        // Only claims the secondary click; everything else (clicks, hover,
        // drags, tooltips) goes to the SwiftUI view below.
        override func hitTest(_ point: NSPoint) -> NSView? {
            Self.isSecondary(NSApp.currentEvent) ? super.hitTest(point) : nil
        }
        override func rightMouseDown(with event: NSEvent) { fire(event) }
        override func mouseDown(with event: NSEvent) {
            if Self.isSecondary(event) { fire(event) } else { super.mouseDown(with: event) }
        }
        private func fire(_ event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            guard bounds.width > 0, bounds.height > 0 else { return }
            action?(UnitPoint(x: p.x / bounds.width, y: p.y / bounds.height))
        }
    }
}
