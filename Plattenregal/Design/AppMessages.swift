import SwiftUI
import AppKit
import ObjectiveC

/// Capsule badge/pill used for styles and notes on a record.
struct AppBadge: View {
    let title: String
    var systemImage: String?
    var body: some View {
        Group {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, AppStyle.itemSpacing)
        .padding(.vertical, AppStyle.tightSpacing)
        // Like every other tag: glass in Modern, paper with a rim in
        // Klassisch – no gray fill of its own.
        .appChipSurface(in: Capsule())
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
                IconButton(systemImage: "xmark", help: String(localized: "Ausblenden"), action: onDismiss)
            }
        }
        .font(.callout)
        .padding(AppStyle.rowSpacing)
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
        VStack(spacing: AppStyle.rowSpacing) {
            Image(systemName: systemImage)
                .font(AppStyle.emptyStateSymbol).foregroundStyle(.tertiary)
                .frame(width: 56, height: 56).accessibilityHidden(true)
            Text(title).font(AppStyle.sectionTitle)
            description.font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                PrimaryButton(title: actionTitle, action: action).padding(.top, AppStyle.tightSpacing)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 420)
        .padding(AppStyle.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
