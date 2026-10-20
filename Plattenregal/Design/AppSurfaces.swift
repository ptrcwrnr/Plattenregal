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
                RoundedRectangle(cornerRadius: AppStyle.featureRadius).fill(AtelierPalette.surface)
                    .overlay(RoundedRectangle(cornerRadius: AppStyle.featureRadius).strokeBorder(AtelierPalette.gold, lineWidth: 1))
            }
        }
        .glassEffect(AppStyle.isAtelier ? .identity : .regular.tint(AppStyle.accent.opacity(0.12)), in: .rect(cornerRadius: AppStyle.featureRadius))
    }

    /// The bar in the middle of a window's toolbar around the page switch:
    /// Liquid Glass in Modern, a darker band on the petrol in Klassisch. Its
    /// controls bring no background of their own.
    @ViewBuilder func toolbarBar() -> some View {
        if AppStyle.isAtelier {
            padding(.horizontal, 3)
                .background {
                    RoundedRectangle(cornerRadius: AppStyle.atelierControlRadius).fill(Color.black.opacity(0.16))
                        .overlay(RoundedRectangle(cornerRadius: AppStyle.atelierControlRadius).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
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
        let field = padding(.horizontal, AppStyle.rowSpacing)
            .frame(height: AppStyle.searchBarHeight)
            .background {
                if AppStyle.isAtelier {
                    RoundedRectangle(cornerRadius: AppStyle.atelierControlRadius)
                        .fill(onToolbar ? AtelierPalette.toolbarField : AtelierPalette.surface)
                        .overlay(RoundedRectangle(cornerRadius: AppStyle.atelierControlRadius)
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
