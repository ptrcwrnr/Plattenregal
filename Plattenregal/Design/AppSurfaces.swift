import SwiftUI
import AppKit

extension View {
    /// A table on its glass card, the same on every page (collection,
    /// wantlist, shelf). Clipped to the card's corners: the header's frosted
    /// band would otherwise stick out square at the top.
    func appTableCard() -> some View {
        clipShape(RoundedRectangle(cornerRadius: AppStyle.cardRadius + 4))
            .appGlassSurface(cornerRadius: AppStyle.cardRadius + 4)
    }

    /// A table on its card at the foot of a page (collection, wantlist,
    /// shelf): the card ends `pageMargin` above the window's bottom edge, as
    /// far from it as a page's sides. Collection and wantlist keep room for
    /// the round button at their end (`floatingClearance`, see `RootView`);
    /// the cover grid scrolls on through it, a table stopped above it and
    /// left a band of empty window – ignored here. On the shelf page the card
    /// ran past the window's edge. Inside the card the last rows scroll clear
    /// of the buttons by `clearance` (measured from the window's edge;
    /// `TableBottomInset`, as `contentMargins` doesn't reach a macOS table);
    /// 0 where there is no button (the collection in a panel of the
    /// statistics).
    func appBottomTableCard(clearance: CGFloat = AppStyle.floatingClearance) -> some View {
        background(TableBottomInset(inset: max(0, clearance - AppStyle.pageMargin)))
            .appTableCard()
            .padding(.bottom, AppStyle.pageMargin)
            .ignoresSafeArea(.container, edges: .bottom)
    }

    func appGlassSurface(cornerRadius: CGFloat) -> some View {
        background {
            if AppStyle.isAtelier {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(AtelierPalette.surface)
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(AtelierPalette.border, lineWidth: AppStyle.borderWidth))
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
                    .overlay(shape.strokeBorder(AtelierPalette.border, lineWidth: AppStyle.borderWidth))
                    .shadow(color: AtelierPalette.shadow, radius: 7, y: 2)
            } else {
                Rectangle().fill(.clear)
                    .glassEffect(AppStyle.cardGlass, in: shape)
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

    /// The selection style for a row that stays chosen (tint and accent
    /// line), the same as a marked compartment; animates like the hover.
    func appSelected(_ selected: Bool, cornerRadius: CGFloat = AppStyle.cardRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        return self
            .background(selected ? AppStyle.selectedBackground : Color.clear, in: shape)
            .overlay(shape.strokeBorder(selected ? AppStyle.selectedBorder : .clear, lineWidth: AppStyle.selectionLineWidth))
            .animation(AppStyle.quickAnimation, value: selected)
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
    /// target shelf): glass with a faint accent tint. `tinted: false` keeps
    /// the glass neutral – the location card on the record sheet, already
    /// on a glass panel, where the blue cast looked out of place.
    /// Klassisch: paper with a gold edge either way.
    func accentGlassCard(tinted: Bool = true) -> some View {
        background {
            if AppStyle.isAtelier {
                RoundedRectangle(cornerRadius: AppStyle.featureRadius).fill(AtelierPalette.surface)
                    .overlay(RoundedRectangle(cornerRadius: AppStyle.featureRadius).strokeBorder(AtelierPalette.gold, lineWidth: AppStyle.borderWidth))
            }
        }
        .glassEffect(AppStyle.isAtelier ? .identity : tinted ? .regular.tint(AppStyle.accent.opacity(0.12)) : .regular,
                     in: .rect(cornerRadius: AppStyle.featureRadius))
    }

    /// A page's scroll view in Modern runs on up under the toolbar: the
    /// content starts at the bar's lower edge but scrolls on beneath the
    /// glass, which then has something to refract, and fades out softly
    /// instead of being cut off there. Klassisch keeps its petrol band,
    /// unchanged. `contentPadding` is the scroll content's own top padding;
    /// in Modern the content moves up by it (see `AppStyle.pageTopPadding`).
    /// `showsBehindBar`: covers may shimmer through the glass (the main
    /// window's pages); text would read as overlapping the bar, so pages of
    /// text (settings) fade out fully just before the toolbar's edge.
    func scrollsUnderToolbar(contentPadding: CGFloat, showsBehindBar: Bool = true) -> some View {
        modifier(ScrollsUnderToolbar(contentPadding: contentPadding, showsBehindBar: showsBehindBar))
    }

    /// The bar in the middle of a window's toolbar around the page switch:
    /// Liquid Glass in Modern, a darker band on the petrol in Klassisch. Its
    /// controls bring no background of their own.
    @ViewBuilder func toolbarBar() -> some View {
        if AppStyle.isAtelier {
            padding(.horizontal, AppStyle.controlInset)
                .background {
                    RoundedRectangle(cornerRadius: AppStyle.atelierControlRadius).fill(Color.black.opacity(0.16))
                        .overlay(RoundedRectangle(cornerRadius: AppStyle.atelierControlRadius).strokeBorder(Color.white.opacity(0.08), lineWidth: AppStyle.borderWidth))
                }
                // Always dark on the petrol, set here instead of taken from
                // the toolbar's scheme, which doesn't reliably reach views
                // hosted in the toolbar (the old search field came out white
                // now and then). The search's text, placeholder and separator
                // follow it.
                .environment(\.colorScheme, .dark)
        } else {
            padding(.horizontal, AppStyle.controlInset).glassEffect(.regular, in: .capsule)
        }
    }

    /// The round floating button and the actions around it (see
    /// `FloatingControls`): Liquid Glass in Modern; in Klassisch the main
    /// button petrol, the actions cream sleeves with a fine rim. `selected`
    /// (a button whose panel is open) adds the selection rim – gold in
    /// Klassisch, the accent in Modern – fading in and out.
    func floatingCircle(prominent: Bool, selected: Bool = false) -> some View {
        floatingCircleSurface(prominent: prominent)
            .overlay {
                Circle()
                    .strokeBorder(AppStyle.selectedBorder, lineWidth: AppStyle.selectionLineWidth)
                    .opacity(selected ? 1 : 0)
                    .animation(AppStyle.quickAnimation, value: selected)
                    .allowsHitTesting(false)
            }
    }

    @ViewBuilder private func floatingCircleSurface(prominent: Bool) -> some View {
        if AppStyle.isAtelier {
            background {
                Circle().fill(prominent ? AtelierPalette.petrol : AtelierPalette.surface)
                    .overlay(Circle().strokeBorder(prominent ? Color.clear : AtelierPalette.border, lineWidth: AppStyle.borderWidth))
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
                    .overlay(shape.strokeBorder(AtelierPalette.border, lineWidth: AppStyle.borderWidth))
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
                    .glassEffect(AppStyle.panelGlass, in: .rect)
            }
        }
    }

    /// The Liquid Glass capsule a text field sits in (paper in Klassisch).
    func searchBarChrome() -> some View {
        padding(.horizontal, AppStyle.rowSpacing)
            .frame(height: AppStyle.controlHeight)
            .background {
                if AppStyle.isAtelier {
                    RoundedRectangle(cornerRadius: AppStyle.atelierControlRadius)
                        .fill(AtelierPalette.surface)
                        .overlay(RoundedRectangle(cornerRadius: AppStyle.atelierControlRadius)
                            .strokeBorder(AtelierPalette.border, lineWidth: AppStyle.borderWidth))
                }
            }
            .glassEffect(AppStyle.isAtelier ? .identity : .regular.interactive(), in: .capsule)
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

/// See `scrollsUnderToolbar`. The toolbar's height is read where the scroll
/// view sits (its safe area) and handed to the content as a top margin,
/// less the content's own padding, so the first row starts right at the
/// bar's lower edge. The system's own soft edge needs the toolbar
/// background, which Modern hides (it would come back as an opaque white
/// titlebar), so the edges are drawn here (`ScrollEdgeFadeMask`).
private struct ScrollsUnderToolbar: ViewModifier {
    let contentPadding: CGFloat
    let showsBehindBar: Bool
    func body(content: Content) -> some View {
        if AppStyle.isAtelier {
            content
        } else {
            GeometryReader { proxy in
                // Above the first row at rest: the fade lies only there.
                let margin = max(0, proxy.safeAreaInsets.top - contentPadding)
                content
                    // The bar's full height, for what must start below it
                    // (the ring of `pullToRefresh`); `margin` is less by the
                    // content's own padding.
                    .environment(\.toolbarClearance, proxy.safeAreaInsets.top)
                    .contentMargins(.top, margin, for: .automatic)
                    .scrollEdgeEffectHidden(true, for: .top)
                    .mask {
                        ScrollEdgeFadeMask(top: showsBehindBar ? margin : proxy.safeAreaInsets.top,
                                           showsBehindBar: showsBehindBar, bottom: proxy.safeAreaInsets.bottom)
                    }
                    .ignoresSafeArea(.container, edges: .top)
            }
        }
    }
}

private struct ToolbarClearanceKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}
extension EnvironmentValues {
    /// How far the toolbar reaches over a page that scrolls on under it
    /// (`scrollsUnderToolbar`, Modern); 0 where the page starts below the bar.
    var toolbarClearance: CGFloat {
        get { self[ToolbarClearanceKey.self] }
        set { self[ToolbarClearanceKey.self] = newValue }
    }
}

/// The page's content fading out towards the top and bottom edge, no blur
/// (a blur strip drew a milky veil over the covers). Each fade follows a
/// smooth S-curve that starts and ends flat, so no line shows where it
/// begins. With `showsBehindBar` off nothing shows behind the bar: the
/// content fades in over `scrollEdgeTuck` just above the toolbar's edge.
/// Otherwise at the top only above the first row at rest – from
/// `scrollEdgeTopOpacity` at the window's edge to full where the content
/// starts –, so resting content is never touched; at the bottom over
/// `scrollEdgeFade` down to `scrollEdgeBottomOpacity` at the window's edge.
private struct ScrollEdgeFadeMask: View {
    let top: CGFloat
    let showsBehindBar: Bool
    let bottom: CGFloat
    var body: some View {
        VStack(spacing: 0) {
            if showsBehindBar {
                Self.fade(from: AppStyle.scrollEdgeTopOpacity, to: 1)
                    .frame(height: top)
            } else {
                // Nothing behind the bar, then in over the last stretch
                // above the toolbar's edge.
                Color.clear.frame(height: max(0, top - AppStyle.scrollEdgeTuck))
                Self.fade(from: 0, to: 1)
                    .frame(height: min(top, AppStyle.scrollEdgeTuck))
            }
            Color.black
            Self.fade(from: 1, to: AppStyle.scrollEdgeBottomOpacity)
                .frame(height: AppStyle.scrollEdgeFade)
        }
        .padding(.bottom, -bottom)
    }

    /// Top to bottom, eased (smoothstep) in a few stops.
    private static func fade(from start: Double, to end: Double) -> LinearGradient {
        let steps = 12
        let stops = (0...steps).map { step -> Gradient.Stop in
            let t = Double(step) / Double(steps)
            let eased = t * t * (3 - 2 * t)
            return .init(color: .black.opacity(start + (end - start) * eased), location: t)
        }
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }
}

/// Room after the last row of the SwiftUI `Table` beside this view, so it
/// can scroll clear of something lying over the table's lower end.
/// `contentMargins` has no effect on a macOS table, and setting the
/// `NSScrollView`'s insets directly replaces the room SwiftUI keeps there
/// itself; added to the scroll view's safe area, AppKit's automatic insets
/// keep both. Only while the rows reach that far: otherwise a list that fits
/// could be scrolled by the room, its first rows under the header.
struct TableBottomInset: NSViewRepresentable {
    let inset: CGFloat

    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {
        view.inset = inset
        view.apply()
    }
    static func dismantleNSView(_ view: Anchor, coordinator: ()) { view.stop() }

    final class Anchor: NSView {
        var inset: CGFloat = 0
        private var observers: [any NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            // The table joins the window in the same pass; look once it's there.
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }

        func stop() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
        }

        /// Again whenever rows come or go (the table's height) or the
        /// window is resized (the scroll view's).
        private func attach() {
            guard window != nil, let table = nearbyTable(), let scroll = table.enclosingScrollView else { return }
            for view in [table, scroll] as [NSView] {
                view.postsFrameChangedNotifications = true
                observers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.apply() }
                })
            }
            apply()
        }

        func apply() {
            guard window != nil, let table = nearbyTable(), let scroll = table.enclosingScrollView else { return }
            let added = scroll.additionalSafeAreaInsets.bottom
            // What the rows can fill without the added room: the scroll view
            // less the header and SwiftUI's own insets.
            let header = table.headerView?.frame.height ?? 0
            let available = scroll.frame.height - header - scroll.contentInsets.top - (scroll.contentInsets.bottom - added)
            let rows = table.numberOfRows > 0 ? table.rect(ofRow: table.numberOfRows - 1).maxY : 0
            let wanted = rows > available - inset ? inset : 0
            guard added != wanted else { return }
            scroll.additionalSafeAreaInsets.bottom = wanted
        }
    }
}
