import SwiftUI

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
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: AppStyle.progressLineWidth)
            if let progress {
                arc(to: max(0.02, min(1, progress)))
                    .animation(AppStyle.progressAnimation, value: progress)
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
            .stroke(AppStyle.accent, style: StrokeStyle(lineWidth: AppStyle.progressLineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }
}

extension View {
    /// A floating status at the top of a page (sync, value refresh): a
    /// Liquid Glass capsule sliding in from where the pull ring was.
    func activityPillChrome() -> some View {
        padding(.horizontal, AppStyle.cardPadding).padding(.vertical, AppStyle.itemSpacing)
            // Klassisch: matte paper. Modern: tinted with the window color –
            // still glass, but covers underneath don't run through the text.
            .background {
                if AppStyle.isAtelier {
                    Capsule().fill(AtelierPalette.surface)
                        .overlay(Capsule().strokeBorder(AtelierPalette.border, lineWidth: AppStyle.borderWidth))
                }
            }
            .glassEffect(AppStyle.isAtelier ? .identity : .regular.tint(Color(nsColor: .windowBackgroundColor).opacity(0.65)), in: .capsule)
            // Lifts it off bright covers underneath.
            .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
            .padding(.top, AppStyle.rowSpacing)
    }
}
