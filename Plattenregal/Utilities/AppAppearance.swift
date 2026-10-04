import SwiftUI
import AppKit
import ObjectiveC

/// Shared typography, spacing, color and motion tokens for every window, sheet,
/// dashboard and card in the app. Views should pull from here instead of writing
/// their own literals, so the whole app reads as one consistent design system.
enum AppStyle {
    // MARK: Spacing
    static let pagePadding: CGFloat = 24
    /// Corners of a panel over the page (see `AppPanelModifier`).
    static let panelRadius: CGFloat = 20
    /// Height of every header-bar control, matching the segmented pickers.
    static let controlHeight: CGFloat = 26
    /// Search bars (Liquid Glass capsule, see `searchBarChrome`).
    static let searchBarHeight: CGFloat = 34
    /// Wide enough for any query; wider only looks empty.
    static let searchBarMaxWidth: CGFloat = 480
    /// A search bar sliding down out of the toolbar and back up, fading as it
    /// goes; the page below follows with the same curve. Only a fade with
    /// "Bewegung reduzieren".
    static var searchBarAnimation: Animation { reduceMotion ? fadeAnimation : .smooth(duration: 0.35) }
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
    static func records(_ count: Int) -> String { count == 1 ? String(localized: "1 Platte") : String(localized: "\(count.formatted()) Platten") }

    // MARK: Motion
    // One curve for the whole app: `.smooth`, a critically damped spring — no
    // visible overshoot, and it retargets cleanly when interrupted (e.g. the
    // a page switched again mid-animation). Only the duration varies.
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
    /// position, columns reflowing, a search bar sliding in. `nil` (= instant)
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
    /// A table on its glass card, the same on every page (collection,
    /// wantlist, shelf). Clipped to the card's corners: the header's frosted
    /// band would otherwise stick out square at the top.
    func appTableCard() -> some View {
        clipShape(RoundedRectangle(cornerRadius: AppStyle.cardRadius + 4))
            .appGlassSurface(cornerRadius: AppStyle.cardRadius + 4)
    }

    func appGlassSurface(cornerRadius: CGFloat) -> some View {
        glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }

    /// The large cards of the statistics and the settings: glass tinted
    /// toward the window color, so a card sets itself off the page softly
    /// instead of with a hard edge. The glass sits in its own layer clipped
    /// to the card, which cuts off its built-in drop shadow; a much fainter
    /// one takes its place.
    func appCardSurface(cornerRadius: CGFloat = AppStyle.controlRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        return background {
            Rectangle().fill(.clear)
                .glassEffect(.regular.tint(Color(nsColor: .windowBackgroundColor).opacity(0.45)), in: shape)
                .clipShape(shape)
                .shadow(color: .black.opacity(0.05), radius: 6, y: 1)
        }
    }

    /// Standard hover feedback (subtle background tint) shared by every interactive
    /// card/row in the app, so hover always looks and animates the same way.
    func appHoverable(_ hovering: Bool, cornerRadius: CGFloat = AppStyle.cardRadius) -> some View {
        self.background(hovering ? AppStyle.hoverBackground : Color.clear, in: RoundedRectangle(cornerRadius: cornerRadius))
            .animation(AppStyle.quickAnimation, value: hovering)
    }
}


/// The chosen ambient color (Einstellungen › Darstellung) as a faint glow from
/// the top of the window. Sits behind all pages and runs on under the
/// toolbar, so it never ends in an edge below the page switch.
struct AmbientGlow: View {
    @State private var preferences = AppPreferences.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geometry in
            if let color = preferences.ambient.color {
                RadialGradient(colors: [color.opacity(scheme == .dark ? 0.18 : 0.10), .clear],
                               center: .top, startRadius: 0,
                               endRadius: max(geometry.size.width, geometry.size.height) * 0.7)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .animation(AppStyle.fadeAnimation, value: preferences.ambient)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A quiet mood behind a page: a few covers washed out across the top edge,
/// heavily blurred. Gives the glass something to refract without competing
/// with the content.
struct AmbientBackdrop: View {
    /// At most three are used; each fades in only once loaded.
    var covers: [String] = []
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shown = Array(covers.prefix(3))
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                ForEach(shown, id: \.self) { url in
                    AmbientCover(url: url).transition(.opacity)
                }
            }
            .frame(maxWidth: shown.count == 1 ? 640 : .infinity)
            .frame(height: 340)
            .blur(radius: 100)
            .opacity(scheme == .dark ? 0.2 : 0.12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(AppStyle.fadeAnimation.speed(0.5), value: shown)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One cover of `AmbientBackdrop`; nothing at all until the image is there,
/// so no placeholder ever flashes behind the page.
private struct AmbientCover: View {
    let url: String
    @State private var image: NSImage?

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill().transition(.opacity)
                }
            }
            .clipped()
            .animation(AppStyle.fadeAnimation.speed(0.5), value: image != nil)
            .task(id: url) {
                guard let parsed = URL(string: url),
                      let loaded = try? await CoverCache.shared.image(parsed, maximumPixelSize: 96) else { return }
                image = NSImage(cgImage: loaded.image, size: .zero)
            }
    }
}

/// A panel over the page instead of a sheet: no close button – a click
/// beside it or Esc closes it.
struct AppPanelModifier<Item: Identifiable, Panel: View>: ViewModifier {
    @Binding var item: Item?
    var onDismiss: (() -> Void)?
    @ViewBuilder let panel: (Item) -> Panel

    func body(content: Content) -> some View {
        content
            .overlay {
                // Anchored at the top: a panel that grows (another list, a
                // column folding out) extends downwards, and nothing moves
                // under the pointer.
                ZStack(alignment: .top) {
                    if let shown = item {
                        // No dimming: the toolbar is drawn by the window and would
                        // stay bright above it, a hard edge. A shadow sets the
                        // panel off instead; the clear layer only catches clicks.
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { item = nil }
                            .transition(.opacity)
                        panel(shown)
                            .clipShape(RoundedRectangle(cornerRadius: AppStyle.panelRadius))
                            // Tinted with the window color: the page behind
                            // doesn't run through the text.
                            .glassEffect(.regular.tint(Color(nsColor: .windowBackgroundColor).opacity(0.65)),
                                         in: .rect(cornerRadius: AppStyle.panelRadius))
                            .shadow(color: .black.opacity(0.18), radius: 30, y: 10)
                            // Esc closes it, wherever the focus is.
                            .background { PanelEscapeMonitor { item = nil } }
                            .padding(AppStyle.pagePadding)
                            .transition(.scale(scale: 0.96).combined(with: .opacity))
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
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Panel
    ) -> some View {
        modifier(AppPanelModifier(item: item, onDismiss: onDismiss, panel: content))
    }
}

/// One button vocabulary for the whole app: Primary (main action), Secondary
/// (normal action), Ghost (low-emphasis/secondary action), Icon (compact icon-only).
/// Primary and Secondary are Liquid Glass; the main action is told apart by
/// the accent color of its title, like the chosen option of a
/// `GlassSegmentedPicker` – no filled blue.
struct PrimaryButton: View {
    let title: String
    var action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        // Disabled: no accent, so it dims like every other button instead of
        // looking clickable.
        Button(action: action) { Text(title).foregroundStyle(isEnabled ? AnyShapeStyle(AppStyle.accent) : AnyShapeStyle(.tertiary)) }
            .appGlassButton()
    }
}
struct SecondaryButton: View {
    let title: String
    var action: () -> Void
    var body: some View {
        Button(title, action: action).appGlassButton()
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

/// One search field for the whole app: icon, text field, clear button in a
/// Liquid Glass capsule (same look as the search on the shelf page).
struct AppSearchField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: (() -> Void)?
    /// Focus of the text field, for fields that ⌘F reveals (see `searchReveal`).
    var focus: FocusState<Bool>.Binding?
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            focusable(TextField(placeholder, text: $text).textFieldStyle(.plain).noTextAutoFill())
                .onSubmit { onSubmit?() }
                // Esc clears the query; with an empty field it gives up the
                // focus (which hides a revealed search bar) or, without one,
                // passes through (e.g. to close the sheet the field sits in).
                .onKeyPress(.escape) {
                    if !text.isEmpty { text = ""; return .handled }
                    guard let focus else { return .ignored }
                    focus.wrappedValue = false
                    return .handled
                }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .searchBarChrome()
    }

    @ViewBuilder private func focusable(_ field: some View) -> some View {
        if let focus { field.focused(focus) } else { field }
    }
}

/// A text field in the same Liquid Glass capsule as the search bars, for
/// names and the like – no gray box, no magnifying glass.
struct GlassTextField: View {
    let placeholder: String
    @Binding var text: String
    var secure = false
    var onSubmit: (() -> Void)?
    var focus: FocusState<Bool>.Binding?
    var body: some View {
        focusable(field.textFieldStyle(.plain))
            .onSubmit { onSubmit?() }
            .searchBarChrome()
    }
    @ViewBuilder private var field: some View {
        if secure { SecureField(placeholder, text: $text) } else { TextField(placeholder, text: $text).noTextAutoFill() }
    }
    @ViewBuilder private func focusable(_ field: some View) -> some View {
        if let focus { field.focused(focus) } else { field }
    }
}

/// ⌘F presses (and the search button in the toolbar), counted. One object
/// for the window, handed to every page (see `PageStack`); the page shown
/// answers each request by revealing its search (see `SearchReveal`).
@Observable final class SearchRequests {
    private(set) var count = 0
    func request() { count += 1 }
}

private struct SearchRequestsKey: EnvironmentKey {
    static let defaultValue: SearchRequests? = nil
}
extension EnvironmentValues {
    var searchRequests: SearchRequests? {
        get { self[SearchRequestsKey.self] }
        set { self[SearchRequestsKey.self] = newValue }
    }
}

/// How a page's search appears: hidden until ⌘F (or the search button in the
/// toolbar), then it slides in at the top with the cursor in it. It stays while
/// it holds a query and goes away again once it is empty and loses the focus
/// (Esc, clicking elsewhere, another page). ⌘F toggles: pressed again while
/// typing in it, it clears the query and closes the search; shown but not
/// focused, it puts the cursor back in first.
struct SearchReveal: ViewModifier {
    @Environment(\.pageVisibility) private var visibility
    @Environment(\.searchRequests) private var searchRequests
    @Binding var isPresented: Bool
    var focus: FocusState<Bool>.Binding
    @Binding var query: String

    func body(content: Content) -> some View {
        let pageShown = visibility?.isShown ?? true
        return content
            .onChange(of: searchRequests?.count ?? 0) {
                // Every page hears the request; only the visible one answers.
                guard pageShown else { return }
                if (isPresented || !query.isEmpty) && focus.wrappedValue {
                    withAnimation(AppStyle.searchBarAnimation) {
                        query = ""
                        isPresented = false
                    }
                    focus.wrappedValue = false
                    return
                }
                withAnimation(AppStyle.searchBarAnimation) { isPresented = true }
                // The field is inserted by this update; focus it once it exists.
                DispatchQueue.main.async { focus.wrappedValue = true }
            }
            .onChange(of: focus.wrappedValue) { _, focused in if !focused { hideIfEmpty() } }
            // Cleared from outside (e.g. picking a result) while not typing.
            .onChange(of: query) { _, new in if new.isEmpty && !focus.wrappedValue { hideIfEmpty() } }
            .onChange(of: pageShown) { _, shown in if !shown { hideIfEmpty() } }
    }

    private func hideIfEmpty() {
        guard isPresented, query.isEmpty else { return }
        withAnimation(AppStyle.searchBarAnimation) { isPresented = false }
    }
}

/// A search bar that is always there and only faded, slid and collapsed.
/// Inserted on the first ⌘F it popped in at full strength instead of fading:
/// its glass and text field were being set up in that very frame and the
/// insert transition skipped ahead. Mounted from the start, revealing it is
/// a plain animation of a view that already exists.
///
/// Collapsed it is 0 high, but a stack still puts its spacing on both sides:
/// give it no stack spacing and pad the content instead, so the padding
/// collapses with it (a negative padding can't take the spacing back).
private struct SearchBarSlot: ViewModifier {
    let shown: Bool
    /// Space inside the slot above the bar (its top padding): the fade
    /// described below ends where the bar begins.
    let topPadding: CGFloat
    /// Height of that fade; no more than the page padding, so it stays
    /// below the toolbar.
    private let fade: CGFloat = AppStyle.pagePadding
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || AppStyle.reduceMotion ? 0 : -AppStyle.searchBarHeight)
            .frame(height: shown ? nil : 0, alignment: .bottom)
            // Faded out softly above the bar, so sliding up it melts away
            // before the page's edge instead of running into the page switch
            // in the toolbar. Open to the sides and below for the glass and
            // the results list hanging under the shelf search.
            .mask(alignment: .top) {
                VStack(spacing: 0) {
                    LinearGradient(stops: Self.fadeStops, startPoint: .top, endPoint: .bottom)
                        .frame(height: fade)
                    Rectangle()
                }
                .padding(.top, topPadding - fade)
                .padding(.horizontal, -100)
                .padding(.bottom, -2000)
            }
            .allowsHitTesting(shown)
            // Not reachable with Tab while hidden.
            .disabled(!shown)
            .accessibilityHidden(!shown)
    }

    /// Smoothstep from clear to opaque: no visible start or end of the fade.
    private static let fadeStops: [Gradient.Stop] = (0...8).map {
        let t = Double($0) / 8
        return .init(color: .black.opacity(t * t * (3 - 2 * t)), location: t)
    }
}

extension View {
    /// Clear Liquid Glass for a button, as a capsule like every other glass
    /// control. Without `.tint(nil)` the glass takes the app-wide accent tint
    /// and turns into a filled blue button.
    func appGlassButton() -> some View {
        buttonStyle(.glass).buttonBorderShape(.capsule).tint(nil)
    }

    /// A card that says "this is where things happen" (location, placement,
    /// target shelf): glass with a faint accent tint.
    func accentGlassCard() -> some View {
        glassEffect(.regular.tint(AppStyle.accent.opacity(0.12)), in: .rect(cornerRadius: 16))
    }

    /// The Liquid Glass capsule every search bar sits in.
    func searchBarChrome() -> some View {
        padding(.horizontal, 12)
            .frame(height: AppStyle.searchBarHeight)
            .glassEffect(.regular.interactive(), in: .capsule)
    }

    /// Keeps a search bar (or a row holding one) mounted while hidden; see
    /// `SearchBarSlot`.
    /// `topPadding`: the padding above the bar inside the slot.
    func searchBarSlot(shown: Bool, topPadding: CGFloat = 0) -> some View {
        modifier(SearchBarSlot(shown: shown, topPadding: topPadding))
    }

    /// Marks a text field as not an AutoFill target. Without a content type
    /// macOS treats a field as "unannotated" and, the first time one gets the
    /// focus after launch, prepares its offer of received one-time codes
    /// (Messages, Mail): its suggestion window flashed up empty under the
    /// search bar on the first ⌘F. A type of our own that AutoFill doesn't
    /// know keeps it out; typing, spelling and the rest are unaffected.
    func noTextAutoFill() -> some View {
        textContentType(NSTextContentType(rawValue: "de.private.Plattenregal.noAutoFill"))
    }

    /// See `SearchReveal`. Show the search while `isPresented || !query.isEmpty`.
    func searchReveal(isPresented: Binding<Bool>, focus: FocusState<Bool>.Binding, query: Binding<String>) -> some View {
        modifier(SearchReveal(isPresented: isPresented, focus: focus, query: query))
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
            case .error: "exclamationmark.octagon"
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
                PrimaryButton(title: actionTitle, action: action).padding(.top, 4)
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

/// The glass bubble macOS shows over the cursor with the input source (or
/// Caps Lock) when a text field gets the focus. Turned off for this app by
/// writing the switch into its own preferences domain, where macOS reads it
/// – a registered default stays in this process and was not seen. Someone
/// who switched it on or off in macOS on purpose (global domain) keeps that.
enum InputSourceIndicator {
    static let key = "TSMLanguageIndicatorEnabled"

    static func disableForApp(_ defaults: UserDefaults = .standard) {
        let global = defaults.persistentDomain(forName: UserDefaults.globalDomain)
        if global?[key] != nil {
            // Chosen in macOS: follow that, and drop an earlier override of ours.
            defaults.removeObject(forKey: key)
        } else if defaults.object(forKey: key) as? Bool != false {
            defaults.set(false, forKey: key)
        }
    }
}

/// A choice between a few options in the app's Liquid Glass look: no gray
/// track and no gray pill behind the chosen option – it is marked by the
/// accent color alone. In the toolbar the toolbar's own glass is the
/// background (`glass: false`); anywhere else it brings its own capsule.
struct GlassSegmentedPicker<Value: Hashable, Label: View>: View {
    @Binding var selection: Value
    let options: [Value]
    var glass = true
    var small = false
    /// A faint line between neighbouring options (e.g. the cabinet tabs).
    var separators = false
    /// Right-click on an option, with the click position (see `onSecondaryClick`).
    var secondaryClick: ((Value, UnitPoint) -> Void)? = nil
    @ViewBuilder let label: (Value) -> Label

    var body: some View {
        let row = HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                if separators && option != options.first {
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 1, height: small ? 12 : 14)
                }
                Button { selection = option } label: {
                    label(option)
                        // Color only: a heavier weight would widen the label
                        // and shift its neighbours on every switch.
                        .foregroundStyle(selected ? AnyShapeStyle(AppStyle.accent) : AnyShapeStyle(.secondary))
                        .padding(.horizontal, small ? 9 : 12)
                        .frame(height: small ? 24 : 30)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .modifier(OptionalSecondaryClick(action: secondaryClick.map { click in { click(option, $0) } }))
            }
        }
        .font(small ? .callout : .body)
        .animation(AppStyle.quickAnimation, value: selection)
        .fixedSize()
        if glass {
            row.padding(.horizontal, 3).glassEffect(.regular.interactive(), in: .capsule)
        } else {
            row
        }
    }
}

private struct OptionalSecondaryClick: ViewModifier {
    let action: ((UnitPoint) -> Void)?
    func body(content: Content) -> some View {
        if let action { content.onSecondaryClick(perform: action) } else { content }
    }
}

/// A choice from a longer list, as a menu behind a Liquid Glass button that
/// shows the current value – the native pop-up button would be filled with
/// the accent color.
struct GlassMenuPicker<Value: Hashable, Options: View>: View {
    let title: String
    @Binding var selection: Value
    /// What the button shows for the current value.
    let current: String
    @ViewBuilder let options: Options

    var body: some View {
        Menu {
            Picker(title, selection: $selection) { options }
                .pickerStyle(.inline)
                .labelsHidden()
        } label: {
            HStack(spacing: 6) {
                Text(current)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        // A plain menu inside our own glass capsule: the button styles leave
        // a menu gray-filled.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .padding(.horizontal, 14)
        .frame(height: 30)
        .glassEffect(.regular.interactive(), in: .capsule)
        .fixedSize()
        .accessibilityLabel(title)
    }
}

/// Grid or list, as two icons.
struct OverviewLayoutPicker: View {
    @Binding var selection: OverviewLayout
    var glass = true

    var body: some View {
        GlassSegmentedPicker(selection: $selection, options: OverviewLayout.allCases, glass: glass) { layout in
            Image(systemName: layout.systemImage)
                .accessibilityLabel(layout.title)
                .help(layout.title)
        }
    }
}

enum CoverGrid {
    static let spacing: CGFloat = 8

    static func columnCount(available: CGFloat, minimum: CGFloat) -> Int {
        guard available.isFinite, minimum.isFinite, minimum > 0 else { return 1 }
        return max(1, Int((max(0, available) + spacing) / (minimum + spacing)))
    }

    static func columns(count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: count)
    }
}

extension View {
    /// Motion for a cover grid of `width` with `columnCount` columns.
    /// - The grid growing in one step (full screen, zoom)
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

/// − value + in a Liquid Glass capsule, in place of the gray system stepper.
struct GlassStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let label: (Int) -> String

    var body: some View {
        HStack(spacing: 2) {
            step("minus", by: -1).disabled(value <= range.lowerBound)
            Text(label(value))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
                .padding(.horizontal, 4)
            step("plus", by: 1).disabled(value >= range.upperBound)
        }
        .animation(AppStyle.quickAnimation, value: value)
        .padding(.horizontal, 6)
        .frame(height: 30)
        .glassEffect(.regular.interactive(), in: .capsule)
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityValue(label(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 1, range.upperBound)
            case .decrement: value = max(value - 1, range.lowerBound)
            @unknown default: break
            }
        }
    }

    private func step(_ systemImage: String, by offset: Int) -> some View {
        GlassStepButton(systemImage: systemImage) {
            value = min(max(value + offset, range.lowerBound), range.upperBound)
        }
    }
}

/// A small round icon button inside a glass capsule (stepper, nudges).
struct GlassStepButton: View {
    let systemImage: String
    var help: String = ""
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(hovering && isEnabled ? AppStyle.hoverBackground : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { hovering = $0 }
        .help(help)
    }
}


/// The app's activity ring: the same accent ring as the pull-to-refresh
/// indicator. `progress` fills it; `nil` lets a short arc spin (a still
/// arc with "Bewegung reduzieren").
struct ActivityRing: View {
    var progress: Double?
    var size: CGFloat = 16
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: 2.5)
            if let progress {
                arc(to: max(0.02, min(1, progress)))
                    .animation(.smooth(duration: 0.35), value: progress)
            } else if reduceMotion {
                arc(to: 0.3)
            } else {
                TimelineView(.animation) { context in
                    arc(to: 0.3)
                        .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func arc(to end: Double) -> some View {
        Circle().trim(from: 0, to: end)
            .stroke(AppStyle.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }
}

extension View {
    /// A floating status at the top of a page (sync, value refresh): a
    /// Liquid Glass capsule sliding in from where the pull ring was.
    func activityPillChrome() -> some View {
        padding(.horizontal, 14).padding(.vertical, 8)
            // Tinted with the window color: still glass, but covers underneath
            // don't run through the text.
            .glassEffect(.regular.tint(Color(nsColor: .windowBackgroundColor).opacity(0.65)), in: .capsule)
            // Lifts it off bright covers underneath.
            .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
            .padding(.top, 12)
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

extension NSView {
    /// A table sits next to its background and overlay views, not above
    /// them: search upwards for the nearest ancestor that contains one.
    func nearbyTable() -> NSTableView? {
        func table(in view: NSView) -> NSTableView? {
            if let table = view as? NSTableView { return table }
            for subview in view.subviews { if let found = table(in: subview) { return found } }
            return nil
        }
        var node = superview
        while let current = node {
            if let found = table(in: current) { return found }
            node = current.superview
        }
        return nil
    }
}

/// Right-click (or Control-click) and, optionally, double-click on a row of
/// the SwiftUI `Table` beneath this overlay: reports the row (in the table's
/// order) and the click position as a unit point of the overlay, e.g. to
/// anchor an `AppMenu` or a popover there. Every other event goes straight
/// through to the table.
struct TableRowClicks: NSViewRepresentable {
    var secondary: ((Int, UnitPoint) -> Void)?
    var double: ((Int, UnitPoint) -> Void)?

    func makeNSView(context: Context) -> Catcher { Catcher() }
    func updateNSView(_ view: Catcher, context: Context) {
        view.secondary = secondary
        view.double = double
    }
    static func dismantleNSView(_ view: Catcher, coordinator: ()) { view.stop() }

    final class Catcher: NSView {
        var secondary: ((Int, UnitPoint) -> Void)?
        var double: ((Int, UnitPoint) -> Void)? {
            didSet { if (double == nil) != (oldValue == nil) { viewDidMoveToWindow() } }
        }
        private var monitor: Any?
        override var isFlipped: Bool { true }

        private static func isSecondary(_ event: NSEvent?) -> Bool {
            guard let event else { return false }
            return event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        }
        override func hitTest(_ point: NSPoint) -> NSView? {
            Self.isSecondary(NSApp.currentEvent) ? super.hitTest(point) : nil
        }
        override func rightMouseDown(with event: NSEvent) { fire(event, secondary) }
        override func mouseDown(with event: NSEvent) {
            if Self.isSecondary(event) { fire(event, secondary) } else { super.mouseDown(with: event) }
        }

        // Double-clicks go to the table itself; they are only watched.
        override func viewDidMoveToWindow() {
            stop()
            guard window != nil, double != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, event.clickCount == 2, event.window === self.window,
                      let table = self.nearbyTable(),
                      self.window?.contentView?.hitTest(event.locationInWindow)?.isDescendant(of: table) == true
                else { return event }
                self.fire(event, self.double)
                return event
            }
        }
        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func fire(_ event: NSEvent, _ action: ((Int, UnitPoint) -> Void)?) {
            guard let action, let table = nearbyTable(), bounds.width > 0, bounds.height > 0 else { return }
            let row = table.row(at: table.convert(event.locationInWindow, from: nil))
            guard row >= 0 else { return }
            let p = convert(event.locationInWindow, from: nil)
            action(row, UnitPoint(x: p.x / bounds.width, y: p.y / bounds.height))
        }
    }
}
