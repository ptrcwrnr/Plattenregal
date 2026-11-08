import SwiftUI

// MARK: - Shared building blocks

/// Scrollable page of setting cards.
struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
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

/// Label (+ optional hint) on the left, control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    var hint: String?
    @ViewBuilder let control: Control
    var body: some View {
        HStack(alignment: .center, spacing: AppStyle.rowSpacing) {
            VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
                Text(title)
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

struct SettingsNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
