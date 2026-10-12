import SwiftUI
import AppKit
import ObjectiveC

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

/// The caption under a cover in every cover grid (Collection, Wantlist,
/// compartment), the same in both designs: artist, title (or the track a
/// search found it by), year · label. Only the colors follow the design.
struct RecordCaption: View {
    let release: Release?
    var matchedTrack: Track? = nil
    /// Shown while the release is missing, as in the current design.
    var fallbackArtist = String(localized: "Unbekannt")
    var fallbackTitle = "—"
    /// The selected copy in a compartment: its artist in the accent.
    var emphasized = false
    var body: some View {
        // Release data a sync saved in its own context changes no property
        // this view observes; redrawn with the library's state, it shows it.
        let _ = LibraryChanges.shared.libraryVersion
        let ink = AppStyle.isAtelier ? AnyShapeStyle(AtelierPalette.ink) : AnyShapeStyle(.primary)
        let muted = AppStyle.isAtelier ? AnyShapeStyle(AtelierPalette.muted) : AnyShapeStyle(.secondary)
        VStack(alignment: .leading, spacing: 2) {
            Text(release?.displayArtist ?? fallbackArtist)
                .font(.callout.weight(.medium)).foregroundStyle(emphasized ? AnyShapeStyle(AppStyle.accent) : ink)
                .lineLimit(1)
            if let matchedTrack {
                MatchedTrackLine(track: matchedTrack)
            } else {
                Text(release?.displayTitle ?? fallbackTitle)
                    .font(.caption).foregroundStyle(muted).lineLimit(1)
            }
            let metadata = [release?.year.map(String.init), release.flatMap { $0.label.isEmpty ? nil : $0.displayLabel }]
                .compactMap { $0 }.joined(separator: " · ")
            if !metadata.isEmpty {
                Text(metadata).font(.caption2).foregroundStyle(muted).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AtelierButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .foregroundStyle(primary ? AtelierPalette.goldForeground : AtelierPalette.ink)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(primary ? AtelierPalette.gold : configuration.isPressed ? AtelierPalette.soft : AtelierPalette.surface,
                        in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(primary ? AtelierPalette.gold : AtelierPalette.border, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.45)
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
    }
}

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
    /// The search field at the right end of the toolbar (see `ToolbarSearchField`).
    static let toolbarSearchWidth: CGFloat = 300
    /// Topped up to the toolbar's own right margin (8, measured), so the
    /// field ends at the pages' margin (`pagePadding + 4`), flush with the
    /// covers below it.
    static let toolbarSearchInset: CGFloat = pagePadding + 4 - 8
    /// The round button at the bottom right and the actions around it.
    static let floatingButtonSize: CGFloat = 52
    static let floatingItemSize: CGFloat = 40
    /// Its distance from the window's edges.
    static let floatingMargin: CGFloat = 20
    /// Room at the end of every page, so content scrolls clear of the button.
    static let floatingClearance: CGFloat = floatingButtonSize + floatingMargin + 8
    /// Leaving a search: the hits fade out quickly, then the whole list fades
    /// in where it was before the search – timed like a page switch (see
    /// `PageStackView.show`). Gliding hundreds of covers back in looked busy.
    static var searchExitFadeOut: Animation { .easeIn(duration: 0.1) }
    static var searchExitFadeIn: Animation { .easeOut(duration: 0.22) }
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
    /// Figures and headings on the statistics: rounded in Modern, plain in
    /// Klassisch like the captions under its covers.
    static var figureDesign: Font.Design { isAtelier ? .default : .rounded }
    static let dialogTitle = Font.system(.title2, design: .rounded, weight: .semibold)

    // MARK: Colors
    // All dynamic/system-based so Light and Dark mode stay correct automatically.
    static var isAtelier: Bool { AppPreferences.shared.signatureDesign == .atelier }
    static var hoverBackground: Color { isAtelier ? AtelierPalette.ink.opacity(0.05) : Color.primary.opacity(0.05) }
    /// The accent chosen in the settings (or the system's). Read in `body`,
    /// so views redraw when it changes.
    static var accent: Color { isAtelier ? AtelierPalette.accent : AppPreferences.shared.accent.color }
    /// Klassisch: the deeper cream of its paper, not a tint of the petrol
    /// (which turns the cream gray); the gold border marks the choice.
    static var selectedBackground: Color { isAtelier ? AtelierPalette.soft : accent.opacity(0.12) }
    static var selectedBorder: Color { isAtelier ? AtelierPalette.gold : accent }
    static var borderColor: Color { isAtelier ? AtelierPalette.border : Color.primary.opacity(0.08) }
    /// Klassisch keeps the meaning but takes earthy tones that sit on cream
    /// and on the dark paper, instead of the system's bright ones.
    static var successColor: Color { isAtelier ? AtelierPalette.success : Color.green }
    static var warningColor: Color { isAtelier ? AtelierPalette.warning : Color.orange }
    static var errorColor: Color { isAtelier ? AtelierPalette.error : Color.red }

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
        let isAtelier = AppStyle.isAtelier
        content.font(.body).fontDesign(.rounded).controlSize(.regular)
            // SwiftUI's own focus effect; AppKit-backed controls are handled by
            // `FocusRings.disableGlobally()` at launch.
            .focusEffectDisabled()
            // Controls, links and `.tint` styles follow the chosen accent.
            .tint(AppStyle.accent)
            .transformEnvironment(\.backgroundStyle) { style in
                if isAtelier { style = AnyShapeStyle(AtelierPalette.surface) }
            }
            .background {
                if AppStyle.isAtelier { AtelierPalette.paper.ignoresSafeArea() }
            }
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
        background {
            if AppStyle.isAtelier {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(AtelierPalette.surface)
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(AtelierPalette.border, lineWidth: 1))
                    .shadow(color: AtelierPalette.shadow, radius: 7, y: 2)
            }
        }
        .glassEffect(AppStyle.isAtelier ? .identity : .regular, in: .rect(cornerRadius: cornerRadius))
    }

    /// The large cards of the statistics and the settings: glass tinted
    /// toward the window color, so a card sets itself off the page softly
    /// instead of with a hard edge. The glass sits in its own layer clipped
    /// to the card, which cuts off its built-in drop shadow; a much fainter
    /// one takes its place.
    func appCardSurface(cornerRadius: CGFloat = AppStyle.controlRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        return background {
            if AppStyle.isAtelier {
                shape.fill(AtelierPalette.surface)
                    .overlay(shape.strokeBorder(AtelierPalette.border, lineWidth: 1))
                    .shadow(color: AtelierPalette.shadow, radius: 7, y: 2)
            } else {
                Rectangle().fill(.clear)
                    .glassEffect(.regular.tint(Color(nsColor: .windowBackgroundColor).opacity(0.45)), in: shape)
                    .clipShape(shape)
                    .shadow(color: .black.opacity(0.05), radius: 6, y: 1)
            }
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
            if preferences.signatureDesign == .atelier {
                AtelierPalette.paper
            } else if let color = preferences.ambient.color {
                // Modern's counterpart to the paper: the whole window faintly
                // in the ambient color, brightest at the top, with a second
                // glow from the bottom corner – a room for the glass to sit in.
                let dark = scheme == .dark
                let reach = max(geometry.size.width, geometry.size.height)
                ZStack {
                    LinearGradient(colors: [color.opacity(dark ? 0.12 : 0.07), color.opacity(dark ? 0.04 : 0.02)],
                                   startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [color.opacity(dark ? 0.22 : 0.14), .clear],
                                   center: .top, startRadius: 0, endRadius: reach * 0.7)
                    RadialGradient(colors: [color.opacity(dark ? 0.10 : 0.06), .clear],
                                   center: .bottomTrailing, startRadius: 0, endRadius: reach * 0.6)
                }
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
            .opacity(AppStyle.isAtelier ? 0 : scheme == .dark ? 0.2 : 0.12)
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

/// One button vocabulary for the whole app: Primary (main action), Secondary
/// (normal action), Ghost (low-emphasis/secondary action), Icon (compact icon-only).
/// Primary and Secondary are Liquid Glass; the main action is told apart by
/// the accent color of its title, like the chosen option of a
/// `GlassSegmentedPicker` – no filled blue.
struct PrimaryButton: View {
    let title: String
    var action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @ViewBuilder
    var body: some View {
        if AppStyle.isAtelier {
            Button(title, action: action).buttonStyle(AtelierButtonStyle(primary: true))
        } else {
        // Disabled: no accent, so it dims like every other button instead of
        // looking clickable.
        Button(action: action) { Text(title).foregroundStyle(isEnabled ? AnyShapeStyle(AppStyle.accent) : AnyShapeStyle(.tertiary)) }
            .appGlassButton()
        }
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
    /// Focus of the text field, for the search field in the toolbar (⌘F).
    var focus: FocusState<Bool>.Binding?
    /// Shown at the end of the field, before the clear button.
    var accessory: AnyView?
    /// Sits on the window's toolbar (see `searchBarChrome(onToolbar:)`).
    var onToolbar = false
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
            if let accessory { accessory }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Suche löschen"))
            }
        }
        .searchBarChrome(onToolbar: onToolbar)
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

/// ⌘F presses, counted, and whether the search field in the toolbar has the
/// focus. One object for the window, handed to every page (see `PageStack`):
/// the field answers each request by taking the focus (see
/// `ToolbarSearchField`); pages ask whether typing goes into it (the shelf's
/// ⌘Z, for example, belongs to the field's text then).
@Observable final class SearchRequests {
    private(set) var count = 0
    var fieldFocused = false
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

extension View {
    /// Clear Liquid Glass for a button, as a capsule like every other glass
    /// control. Without `.tint(nil)` the glass takes the app-wide accent tint
    /// and turns into a filled blue button.
    @ViewBuilder func appGlassButton() -> some View {
        if AppStyle.isAtelier {
            buttonStyle(AtelierButtonStyle())
        } else {
            buttonStyle(.glass).buttonBorderShape(.capsule).tint(nil)
        }
    }

    /// A button that reads as a link in the text: the system's link blue in
    /// Modern, petrol in Klassisch, where the blue would be the only one.
    @ViewBuilder func appLinkButton() -> some View {
        if AppStyle.isAtelier {
            buttonStyle(.plain).foregroundStyle(AppStyle.accent)
        } else {
            buttonStyle(.link)
        }
    }

    /// A card that says "this is where things happen" (location, placement,
    /// target shelf): glass with a faint accent tint.
    func accentGlassCard() -> some View {
        background {
            if AppStyle.isAtelier {
                RoundedRectangle(cornerRadius: 16).fill(AtelierPalette.surface)
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AtelierPalette.gold, lineWidth: 1))
            }
        }
        .glassEffect(AppStyle.isAtelier ? .identity : .regular.tint(AppStyle.accent.opacity(0.12)), in: .rect(cornerRadius: 16))
    }

    /// The bar in the middle of a window's toolbar around the page switch:
    /// Liquid Glass in Modern, a darker band on the petrol in Klassisch. Its
    /// controls bring no background of their own.
    @ViewBuilder func toolbarBar() -> some View {
        if AppStyle.isAtelier {
            padding(.horizontal, 3)
                .background {
                    RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.16))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                }
        } else {
            padding(.horizontal, 3).glassEffect(.regular, in: .capsule)
        }
    }

    /// The round floating button and the actions around it (see
    /// `FloatingControls`): Liquid Glass in Modern; in Klassisch the main
    /// button petrol, the actions cream sleeves with a fine rim.
    @ViewBuilder func floatingCircle(prominent: Bool) -> some View {
        if AppStyle.isAtelier {
            background {
                Circle().fill(prominent ? AtelierPalette.petrol : AtelierPalette.surface)
                    .overlay(Circle().strokeBorder(prominent ? Color.clear : AtelierPalette.border, lineWidth: 1))
                    .shadow(color: .black.opacity(prominent ? 0.18 : 0.1), radius: prominent ? 10 : 6, y: prominent ? 4 : 2)
            }
        } else {
            glassEffect(.regular.interactive(), in: .circle)
                .shadow(color: .black.opacity(prominent ? 0.12 : 0.06), radius: prominent ? 10 : 6, y: prominent ? 4 : 2)
        }
    }

    /// A small capsule or circle on the page – tags on covers, steppers,
    /// toasts, round row buttons: Liquid Glass in Modern; in Klassisch the
    /// cards' matte paper with a fine rim, never see-through.
    /// Klassisch leaves the glass out altogether: even as `.identity` it
    /// sets up the glass machinery, for every cover tag of a scrolling grid.
    @ViewBuilder func appChipSurface<S: InsettableShape>(in shape: S, interactive: Bool = false) -> some View {
        if AppStyle.isAtelier {
            background {
                shape.fill(AtelierPalette.surface)
                    .overlay(shape.strokeBorder(AtelierPalette.border, lineWidth: 1))
            }
        } else {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        }
    }

    /// The background of a popover: in Modern glass tinted with the window
    /// color (like the panels over the page and the sync pill), so a bright
    /// cover underneath doesn't run through the text; the cards' matte paper
    /// in Klassisch. On the popover's content.
    @ViewBuilder func appPopoverSurface() -> some View {
        if AppStyle.isAtelier {
            presentationBackground(AtelierPalette.surface)
        } else {
            presentationBackground {
                Rectangle().fill(.clear)
                    .glassEffect(.regular.tint(Color(nsColor: .windowBackgroundColor).opacity(0.65)), in: .rect)
            }
        }
    }

    /// The Liquid Glass capsule every search bar sits in. `onToolbar`: in
    /// Klassisch always dark on the petrol bar, with fixed colors and scheme
    /// instead of following the toolbar's (see `AtelierPalette.toolbarField`).
    @ViewBuilder func searchBarChrome(onToolbar: Bool = false) -> some View {
        let field = padding(.horizontal, 12)
            .frame(height: AppStyle.searchBarHeight)
            .background {
                if AppStyle.isAtelier {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(onToolbar ? AtelierPalette.toolbarField : AtelierPalette.surface)
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(onToolbar ? AtelierPalette.toolbarFieldBorder : AtelierPalette.border, lineWidth: 1))
                }
            }
            .glassEffect(AppStyle.isAtelier ? .identity : .regular.interactive(), in: .capsule)
        if onToolbar && AppStyle.isAtelier {
            field.environment(\.colorScheme, .dark)
        } else {
            field
        }
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
        // Like every other tag: glass in Modern, paper with a rim in
        // Klassisch – no gray fill of its own.
        .modifier(BadgeSurface(prominent: prominent))
    }
}

private struct BadgeSurface: ViewModifier {
    let prominent: Bool
    func body(content: Content) -> some View {
        if prominent {
            content.background(AppStyle.selectedBackground, in: Capsule())
        } else {
            content.appChipSurface(in: Capsule())
        }
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
        .background {
            let shape = RoundedRectangle(cornerRadius: AppStyle.surfaceRadius)
            if AppStyle.isAtelier {
                // Klassisch: a paper card; the kind shows in the icon and a
                // faint wash, not in a see-through tint.
                shape.fill(AtelierPalette.surface)
                    .overlay(shape.fill(kind.color.opacity(kind == .info ? 0 : 0.06)))
                    .overlay(shape.strokeBorder(AtelierPalette.border, lineWidth: 1))
            } else {
                shape.fill(kind.color.opacity(0.1))
            }
        }
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

/// A choice between a few options. The chosen one sits on a pill that glides
/// to a new choice, the same in both designs: in Modern a Liquid Glass lens
/// (never a gray or blue fill) with the label in the accent, in Klassisch
/// cream paper. In the toolbar the toolbar's bar is the background
/// (`glass: false`, see `toolbarBar`); anywhere else it brings its own capsule.
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
    /// The selection pill is one view sliding between the options.
    @Namespace private var pill

    var body: some View {
        let row = HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                let selected = option == selection
                if separators && index > 0 {
                    // Not beside the pill: it marks its own edges, and the
                    // line would touch it.
                    let besidePill = selected || options[index - 1] == selection
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 1, height: small ? 12 : 14)
                        .opacity(besidePill ? 0 : 1)
                }
                Button { selection = option } label: {
                    label(option)
                        // Color only: a heavier weight would widen the label
                        // and shift its neighbours on every switch.
                        .foregroundStyle(AppStyle.isAtelier
                            ? AnyShapeStyle(selected ? (glass ? AtelierPalette.ink : AtelierPalette.toolbarInk) : glass ? AtelierPalette.muted : Color.white.opacity(0.8))
                            : selected ? AnyShapeStyle(AppStyle.accent) : AnyShapeStyle(.secondary))
                        .padding(.horizontal, small ? 9 : 12)
                        .frame(height: small ? 24 : 30)
                        .background {
                            if selected {
                                if AppStyle.isAtelier {
                                    RoundedRectangle(cornerRadius: 7).fill(glass ? AtelierPalette.surface : AtelierPalette.toolbarSelection)
                                        .padding(.vertical, 3)
                                        .matchedGeometryEffect(id: "pill", in: pill)
                                } else {
                                    Capsule().fill(.clear)
                                        .glassEffect(.regular, in: .capsule)
                                        .padding(.vertical, 3)
                                        .matchedGeometryEffect(id: "pill", in: pill)
                                }
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .modifier(OptionalSecondaryClick(action: secondaryClick.map { click in { click(option, $0) } }))
            }
        }
        .font(small ? .callout : .body)
        .animation(.smooth(duration: 0.3), value: selection)
        .fixedSize()
        // A group: a label given to the picker (`.accessibilityLabel("Modus")`)
        // names the group instead of replacing every option's name.
        .accessibilityElement(children: .contain)
        if glass {
            row.padding(.horizontal, 3)
                .background {
                    if AppStyle.isAtelier {
                        RoundedRectangle(cornerRadius: 10).fill(AtelierPalette.soft)
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AtelierPalette.border, lineWidth: 1))
                    }
                }
                .glassEffect(AppStyle.isAtelier ? .identity : .regular.interactive(), in: .capsule)
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
        .background {
            if AppStyle.isAtelier {
                RoundedRectangle(cornerRadius: 9).fill(AtelierPalette.surface)
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(AtelierPalette.border, lineWidth: 1))
            }
        }
        .glassEffect(AppStyle.isAtelier ? .identity : .regular.interactive(), in: .capsule)
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
    /// The same in both designs (Modern used to be tighter, 8 pt).
    static let spacing: CGFloat = 18
    /// Space between a cover and its caption.
    static let captionSpacing: CGFloat = 9
    /// Extra room above the grid's own padding (`spacing`), so the first
    /// covers start 18 pt below the toolbar.
    static var topSpace: CGFloat { max(0, 18 - spacing) }
    /// How far a cover's shadow reaches beyond it (`atelierRecordSleeve`).
    static let shadowRoom: CGFloat = 16

    static func columnCount(available: CGFloat, minimum: CGFloat) -> Int {
        guard available.isFinite, minimum.isFinite, minimum > 0 else { return 1 }
        return max(1, Int((max(0, available) + spacing) / (minimum + spacing)))
    }

    static func columns(count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: count)
    }
}

/// The item at the top of a scrolled page, for `.scrollPosition(id:)`. An
/// object, not `@State` of the page: the scroll view writes it every time
/// another row reaches the top, and a state value would rebuild the whole
/// page with all its covers each time. Through Observation only views that
/// read `id` in their `body` follow it – usually none.
@Observable final class ScrollAnchor<ID: Hashable> {
    var id: ID?
}

extension View {
    /// `.scrollPosition(id:anchor: .top)` bound to `anchor` (see `scrollPosition(tracking:)`).
    /// The binding is made inside the modifier: making it reads `id`, and
    /// made in a grid's closure it tied that closure to every new top row.
    func scrollPosition<ID: Hashable>(_ anchor: ScrollAnchor<ID>) -> some View {
        modifier(AnchoredScrollPosition(anchor: anchor))
    }

    /// `.scrollPosition(id:anchor: .top)` in a modifier of its own. The
    /// scroll view reads the position where the modifier is built; built
    /// inline in a grid's closure, every new top row re-ran that closure –
    /// and with it every cover cell of the grid.
    func scrollPosition<ID: Hashable>(tracking position: Binding<ID?>) -> some View {
        modifier(TrackedScrollPosition(position: position))
    }
}

extension View {
    /// `onChange(of:)` for a value read from an observed object (e.g.
    /// `LibraryChanges`), read in a modifier of its own: read in a page's
    /// `body`, every change re-ran the whole page with all its cover cells –
    /// even when the handler had nothing to do.
    func onObservedChange<V: Equatable>(of value: @escaping () -> V, perform action: @escaping (V, V) -> Void) -> some View {
        modifier(ObservedChange(value: value, action: action))
    }

    /// `task(id:)` with the id read in a modifier of its own (see `onObservedChange`).
    func observedTask<ID: Equatable>(id: @escaping () -> ID, _ action: @escaping @MainActor () async -> Void) -> some View {
        modifier(ObservedTask(id: id, action: action))
    }
}

private struct ObservedChange<V: Equatable>: ViewModifier {
    let value: () -> V
    let action: (V, V) -> Void
    func body(content: Content) -> some View { content.onChange(of: value(), action) }
}

private struct ObservedTask<ID: Equatable>: ViewModifier {
    let id: () -> ID
    let action: @MainActor () async -> Void
    func body(content: Content) -> some View { content.task(id: id(), action) }
}

private struct AnchoredScrollPosition<ID: Hashable>: ViewModifier {
    let anchor: ScrollAnchor<ID>
    func body(content: Content) -> some View {
        content.scrollPosition(id: Bindable(anchor).id, anchor: .top)
    }
}

private struct TrackedScrollPosition<ID: Hashable>: ViewModifier {
    let position: Binding<ID?>
    func body(content: Content) -> some View {
        content.scrollPosition(id: position, anchor: .top)
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
    /// - Clipped to the grid's bounds plus `shadowRoom` as a last line of
    ///   defence; the room keeps the covers' own shadows (Klassisch) whole.
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
            // Wider than the grid by the shadow's reach, so the outer
            // columns' shadows aren't cut off in a straight line.
            .padding(CoverGrid.shadowRoom)
            .clipped()
            .padding(-CoverGrid.shadowRoom)
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
        .appChipSurface(in: Capsule(), interactive: true)
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
                .foregroundStyle(AppStyle.isAtelier ? AnyShapeStyle(AtelierPalette.muted) : AnyShapeStyle(.secondary))
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
    /// A page that isn't shown still draws (see `PageStack`): its ring stands
    /// still there. Collection and wantlist both show the sync's, the hidden
    /// statistics its own while calculating at launch – every frame of them
    /// was drawn for nobody.
    @Environment(\.pageVisibility) private var visibility

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: 2.5)
            if let progress {
                arc(to: max(0.02, min(1, progress)))
                    .animation(.smooth(duration: 0.35), value: progress)
            } else if reduceMotion {
                arc(to: 0.3)
            } else {
                TimelineView(.animation(paused: !(visibility?.isShown ?? true))) { context in
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
            // Klassisch: matte paper. Modern: tinted with the window color –
            // still glass, but covers underneath don't run through the text.
            .background {
                if AppStyle.isAtelier {
                    Capsule().fill(AtelierPalette.surface)
                        .overlay(Capsule().strokeBorder(AtelierPalette.border, lineWidth: 1))
                }
            }
            .glassEffect(AppStyle.isAtelier ? .identity : .regular.tint(Color(nsColor: .windowBackgroundColor).opacity(0.65)), in: .capsule)
            // Lifts it off bright covers underneath.
            .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
            .padding(.top, 12)
    }
}

/// Pull-to-refresh for a ScrollView: pulling the page down past its top edge
/// fills a small ring; a full ring runs `action`. Works with the trackpad's
/// rubber band (fires as soon as the ring is full, but only while the fingers
/// pull – a fast swipe whose momentum bounces off the top doesn't count) and,
/// when `allowsMouseDrag`
/// is on, with a click-drag of the page while it's at the top (fires on
/// release). ⌘R triggers the same action. Leave the mouse drag off where
/// dragging already means something (e.g. rubber-band selection).
private struct PullToRefresh: ViewModifier {
    /// Asked when needed, not handed in as a value: read in a page's `body`,
    /// the sync starting and ending re-ran the whole page with all its cover
    /// cells – right when the sync capsule animates in (see `onObservedChange`).
    let disabled: () -> Bool
    let allowsMouseDrag: Bool
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
    func pullToRefresh(disabled: @escaping () -> Bool = { false }, allowsMouseDrag: Bool = true, action: @escaping () -> Void) -> some View {
        modifier(PullToRefresh(disabled: disabled, allowsMouseDrag: allowsMouseDrag, action: action))
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

/// The app's own context menu: a popover with hover rows instead of the
/// native macOS menu, without separators. Plain `Button`s inside `content`
/// are styled as menu rows; choosing one closes the menu first, then runs the
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
            .appPopoverSurface()
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
    /// Not for the cells of a scrolling grid: see `GridSecondaryClicks`.
    func onSecondaryClick(perform action: @escaping (UnitPoint) -> Void) -> some View {
        overlay(SecondaryClickCatcher { point, size in
            action(UnitPoint(x: point.x / size.width, y: point.y / size.height))
        })
    }
}

/// Right-clicks on the cells of a scrolling cover grid. An AppKit view in
/// every cell (`onSecondaryClick`) made AppKit work out the window's drag
/// regions again for every frame of scrolling, walking all cells – about a
/// quarter of each scroll step. Here a single catcher lies over the scroll
/// view and finds the cell from the frames the cells report in the grid's
/// own space (which scrolling doesn't change) and where the grid stands.
/// Plain storage, not state: nothing re-renders when it changes.
final class GridSecondaryClicks<ID: Hashable> {
    fileprivate var cells: [ID: CGRect] = [:]
    fileprivate var gridOrigin: CGPoint = .zero
    fileprivate let gridSpace = UUID()
    fileprivate let scrollSpace = UUID()
}

extension View {
    /// On each cell of the grid.
    func gridSecondaryClickCell<ID: Hashable>(_ id: ID, in clicks: GridSecondaryClicks<ID>) -> some View {
        onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(clicks.gridSpace)) }) { clicks.cells[id] = $0 }
            .onDisappear { clicks.cells[id] = nil }
    }

    /// On the lazy grid inside the scroll view.
    func gridSecondaryClickGrid<ID: Hashable>(_ clicks: GridSecondaryClicks<ID>) -> some View {
        coordinateSpace(.named(clicks.gridSpace))
            .onGeometryChange(for: CGPoint.self, of: { $0.frame(in: .named(clicks.scrollSpace)).origin }) { clicks.gridOrigin = $0 }
    }

    /// On the scroll view: a right-click on a cell runs `action` with the
    /// cell and the click position as a unit point of the cell.
    func onGridSecondaryClick<ID: Hashable>(_ clicks: GridSecondaryClicks<ID>, perform action: @escaping (ID, UnitPoint) -> Void) -> some View {
        coordinateSpace(.named(clicks.scrollSpace))
            .overlay(SecondaryClickCatcher { point, _ in
                let p = CGPoint(x: point.x - clicks.gridOrigin.x, y: point.y - clicks.gridOrigin.y)
                guard let (id, frame) = clicks.cells.first(where: { $0.value.contains(p) }),
                      frame.width > 0, frame.height > 0 else { return }
                action(id, UnitPoint(x: (p.x - frame.minX) / frame.width, y: (p.y - frame.minY) / frame.height))
            })
    }
}

private struct SecondaryClickCatcher: NSViewRepresentable {
    /// The click's position in the view (from the top left) and the view's size.
    let action: (CGPoint, CGSize) -> Void
    func makeNSView(context: Context) -> CatcherView { CatcherView() }
    func updateNSView(_ view: CatcherView, context: Context) { view.action = action }

    final class CatcherView: NSView {
        var action: ((CGPoint, CGSize) -> Void)?
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
            guard bounds.width > 0, bounds.height > 0 else { return }
            action?(convert(event.locationInWindow, from: nil), bounds.size)
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
