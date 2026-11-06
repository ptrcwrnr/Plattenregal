import SwiftUI
import AppKit

extension View {
    /// `windowBackground: false` for content that brings its own surface in
    /// a transparent window (the search in the menu bar): the paper designs
    /// would otherwise fill the whole window, the room for the shadow too.
    func appAppearance(windowBackground: Bool = true) -> some View {
        modifier(AppAppearanceModifier(windowBackground: windowBackground))
    }
}

private struct AppAppearanceModifier: ViewModifier {
    let windowBackground: Bool
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
                if windowBackground && AppStyle.isAtelier { AtelierPalette.paper.ignoresSafeArea() }
            }
            .onAppear { AppPreferences.shared.applyAppearance() }
    }
}

/// The chosen ambient color (Einstellungen › Darstellung) as a faint glow from
/// the top of the window. Sits behind all pages and runs on under the
/// toolbar, so it never ends in an edge below the page switch.
struct AmbientGlow: View {
    @State private var preferences = AppPreferences.shared
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // The toolbar's height is read outside: inside, `ignoresSafeArea`
        // reports no safe area at all.
        GeometryReader { outer in
            glow(toolbarHeight: outer.safeAreaInsets.top)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func glow(toolbarHeight: CGFloat) -> some View {
        GeometryReader { geometry in
            if preferences.signatureDesign.isPaper {
                // Petrol under the toolbar too, as high as the toolbar takes
                // from the top. In the window it lies hidden beneath the
                // petrol bar. On first entering full screen macOS shows the
                // bar's own window only about half a second after the
                // transition; until then this band shows instead of cream.
                AtelierPalette.paper
                    .overlay(alignment: .top) {
                        AtelierPalette.petrol.frame(height: toolbarHeight)
                    }
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
