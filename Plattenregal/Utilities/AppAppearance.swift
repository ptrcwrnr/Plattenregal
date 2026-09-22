import SwiftUI

/// Shared typography, spacing, color and motion tokens for every window, sheet,
/// dashboard and card in the app. Views should pull from here instead of writing
/// their own literals, so the whole app reads as one consistent design system.
enum AppStyle {
    // MARK: Spacing
    static let pagePadding: CGFloat = 24
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
    static let selectedBackground = Color.accentColor.opacity(0.12)
    static let selectedBorder = Color.accentColor
    static let borderColor = Color.primary.opacity(0.08)
    static let successColor = Color.green
    static let warningColor = Color.orange
    static let errorColor = Color.red
    /// Ordered palette for charts/statistics so each chart picks a slot instead of an ad hoc hue.
    static let chartColors: [Color] = [.teal, .indigo, .orange, .purple]

    // MARK: Motion
    /// Hover/selection feedback — short and unobtrusive.
    static let quickAnimation = Animation.easeInOut(duration: 0.2)
    /// State and layout changes — dimming, showing/hiding, focus changes.
    static let standardAnimation = Animation.easeInOut(duration: 0.25)
    /// Magnetic/springy interactions (alphabet index, rack highlight).
    static let springAnimation = Animation.spring(response: 0.4, dampingFraction: 0.8)
}
extension View {
    func appAppearance() -> some View {
        self.font(.body).fontDesign(.rounded).controlSize(.regular)
    }
}

/// Headers keep their intrinsic height; results and empty states own the remaining space.
struct AppPageLayout<Header: View, Content: View>: View {
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header.frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(AppStyle.pagePadding)
                content.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
    }
}
struct AppPageHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(AppStyle.pageTitle)
            Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
extension View {
    @ViewBuilder func appGlassSurface(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.primary.opacity(0.08)))
        }
    }

    func appControlSurface() -> some View { appGlassSurface(cornerRadius: AppStyle.controlRadius) }

    @ViewBuilder func appGlassButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// Standard hover feedback (subtle background tint) shared by every interactive
    /// card/row in the app, so hover always looks and animates the same way.
    func appHoverable(_ hovering: Bool, cornerRadius: CGFloat = AppStyle.cardRadius) -> some View {
        self.background(hovering ? AppStyle.hoverBackground : Color.clear, in: RoundedRectangle(cornerRadius: cornerRadius))
            .animation(AppStyle.quickAnimation, value: hovering)
    }

    /// Standard selected-state treatment (tinted background + accent border) shared
    /// by cards, rows and grid items across the app.
    func appSelectable(_ selected: Bool, cornerRadius: CGFloat = AppStyle.cardRadius, lineWidth: CGFloat = 2) -> some View {
        self.background(selected ? AppStyle.selectedBackground : Color.clear, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(selected ? AppStyle.selectedBorder : Color.clear, lineWidth: lineWidth))
            .animation(AppStyle.quickAnimation, value: selected)
    }
}

/// A standard card container: glass surface, standard padding and corner radius,
/// with optional hover/selected feedback. Use for any card-like content —
/// record covers, shelf cards, dashboard/metric cards.
struct AppCard<Content: View>: View {
    var hovering: Bool = false
    var selected: Bool = false
    var padding: CGFloat = AppStyle.cardPadding
    var cornerRadius: CGFloat = AppStyle.cardRadius
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(padding)
            .appGlassSurface(cornerRadius: cornerRadius)
            .appHoverable(hovering, cornerRadius: cornerRadius)
            .appSelectable(selected, cornerRadius: cornerRadius)
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

/// One search-field chrome for the whole app: icon, text field, clear button,
/// on the shared glass surface.
struct AppSearchField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: (() -> Void)?
    var body: some View {
        HStack(spacing: AppStyle.itemSpacing) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .onSubmit { onSubmit?() }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppStyle.rowSpacing)
        .padding(.vertical, AppStyle.itemSpacing + 1)
        .appGlassSurface(cornerRadius: AppStyle.surfaceRadius)
    }
}

/// Icon + label + value chip used for statistics/metrics throughout the app.
struct StatCard: View {
    let systemImage: String
    let label: String
    let value: String
    var tint: Color = .accentColor
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.tightSpacing) {
            Label(label, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppStyle.rowSpacing)
        .appGlassSurface(cornerRadius: AppStyle.surfaceRadius)
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
        .foregroundStyle(prominent ? Color.accentColor : .secondary)
        .padding(.horizontal, AppStyle.itemSpacing + 2)
        .padding(.vertical, AppStyle.tightSpacing)
        .background(prominent ? AppStyle.selectedBackground : AppStyle.hoverBackground.opacity(1.2), in: Capsule())
    }
}
typealias FilterPill = AppBadge

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
                }
            }
            .padding(AppStyle.pagePadding)
            Divider()
        }
    }
}

/// Inline status/error/warning banner. One visual language for anything that
/// needs the user's attention inline, instead of ad hoc colored text per view.
struct AppBanner: View {
    enum Kind { case info, success, warning, error
        var color: Color {
            switch self {
            case .info: .accentColor
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
