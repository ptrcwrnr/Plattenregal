import SwiftUI

// MARK: - Shared building blocks

/// Scrollable page of setting cards.
struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AppStyle.sectionSpacing) {
                    if DemoMode.showsBanner {
                        AppBanner(message: String(localized: "Demo: Diese Einstellungen gelten nur für die Demo. Deine eigenen bleiben, wie sie sind."), kind: .info,
                                  actionTitle: String(localized: "Demo beenden"), action: { DemoMode.end() })
                    }
                    content
                }
                    .padding(AppStyle.pagePadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // For a card that grows (`revealsWhenExpanded`).
                    .environment(\.settingsScroll, proxy)
            }
            // The edge effect draws a line under the toolbar when hovered.
            .scrollEdgeEffectHidden(true, for: .top)
            // In Modern the toolbar is see-through: scrolled cards ran on behind
            // the tab switch at full strength and looked broken. Now they fade
            // out just before it; the page starts at the toolbar's edge like the
            // main window's pages.
            .scrollsUnderToolbar(contentPadding: AppStyle.pagePadding, showsBehindBar: false)
        }
    }
}

extension EnvironmentValues {
    /// The scrolling of the `SettingsPage` around a view, nil outside one.
    @Entry var settingsScroll: ScrollViewProxy? = nil
}

extension View {
    /// When `expanded` turns true, scrolls the settings page so this view's
    /// top shows: a card low on its page that opens more rows (behind a
    /// switch) would otherwise grow below the window's edge, unseen.
    func revealsWhenExpanded(_ expanded: Bool) -> some View {
        modifier(RevealsWhenExpanded(expanded: expanded))
    }
}

private struct RevealsWhenExpanded: ViewModifier {
    let expanded: Bool
    @Environment(\.settingsScroll) private var scroll
    @State private var id = UUID()
    /// The latest state of the switch, read again once the page has settled.
    @State private var wanted = false

    func body(content: Content) -> some View {
        content
            .id(id)
            .onChange(of: expanded) { _, now in
                wanted = now
                guard now, let scroll else { return }
                Task { @MainActor in
                    // Not in this update yet: the page hasn't grown, and at
                    // its end there would be nowhere to scroll to.
                    await Task.yield()
                    reveal(scroll)
                    // Switched off and on again quickly, the page was still
                    // scrolling back and took this scroll along: once more
                    // after it settled. Changes nothing if it already shows.
                    try? await Task.sleep(for: .seconds(AppStyle.standardDuration * 2))
                    if wanted { reveal(scroll) }
                }
            }
    }

    private func reveal(_ scroll: ScrollViewProxy) {
        withAnimation(AppStyle.standardAnimation) { scroll.scrollTo(id, anchor: .top) }
    }
}

/// One glass card: title (+ subtitle), then its rows.
struct SettingsCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(AppStyle.sectionTitle)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            content
        }
        .padding(AppStyle.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The same glass cards as the statistics page.
        .appCardSurface()
    }
}

/// Label (+ optional badge after it, + optional hint) on the left, control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    var badge: String?
    var hint: String?
    @ViewBuilder let control: Control
    var body: some View {
        HStack(alignment: .center, spacing: AppStyle.rowSpacing) {
            VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
                HStack(spacing: AppStyle.itemSpacing) {
                    Text(title)
                    if let badge { StatusBadge(title: badge) }
                }
                if let hint {
                    Text(hint).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: AppStyle.rowSpacing)
            control
        }
    }
}

/// A small mark after a title, e.g. "Experimentell": the design's warning
/// color on a light tint of it, in a capsule.
struct StatusBadge: View {
    let title: String
    var body: some View {
        Text(title)
            .font(AppStyle.captionMark)
            .foregroundStyle(AppStyle.warningColor)
            .padding(.horizontal, AppStyle.itemSpacing)
            .padding(.vertical, AppStyle.hairSpacing)
            .background(AppStyle.warningColor.opacity(AppStyle.badgeTintOpacity), in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

struct SettingsNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
