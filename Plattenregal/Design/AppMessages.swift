import SwiftUI

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
                    .overlay(shape.strokeBorder(AtelierPalette.border, lineWidth: AppStyle.borderWidth))
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

/// A symbol on a small tinted round tile, leading a figure or a line: the
/// statistics' figures and facts, the sync lines in the settings. Modern tints
/// it in the symbol's color, Klassisch lays it on soft paper in petrol.
struct SymbolTile: View {
    let systemImage: String
    /// The symbol's color in Modern; the accent when none is given.
    var color: Color?
    var body: some View {
        let tint = color ?? AppStyle.accent
        Image(systemName: systemImage)
            .font(AppStyle.tileSymbol)
            .foregroundStyle(AppStyle.isAtelier ? AppStyle.accent : tint)
            .frame(width: AppStyle.symbolTileSize, height: AppStyle.symbolTileSize)
            .background(AppStyle.isAtelier ? AtelierPalette.soft : tint.opacity(0.12), in: Circle())
            .accessibilityHidden(true)
    }
}

/// One point of a list of changes: "Was ist neu" in „Über Plattenregal“ and
/// in the update window.
struct BulletPoint: View {
    let text: AttributedString
    init(_ text: String) { self.text = AttributedString(text) }
    init(_ text: AttributedString) { self.text = text }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppStyle.itemSpacing) {
            Text(verbatim: "•").foregroundStyle(.tertiary).accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }
}

/// The number of a step in a fine ring – no filled badge: the steps of the
/// welcome, the moves of the sort check. A step done shows a check instead.
/// `prominent` draws number and ring in the accent.
struct StepNumber: View {
    let number: Int
    var done = false
    var prominent = false
    var body: some View {
        Text(number, format: .number)
            .font(AppStyle.captionMark).monospacedDigit()
            .foregroundStyle(prominent ? AnyShapeStyle(AppStyle.accent) : AnyShapeStyle(.secondary))
            .opacity(done ? 0 : 1)
            .frame(width: AppStyle.smallControlHeight, height: AppStyle.smallControlHeight)
            .overlay {
                Circle()
                    .strokeBorder(prominent ? AppStyle.accent.opacity(0.6) : Color.secondary.opacity(0.4), lineWidth: AppStyle.borderWidth)
                    .opacity(done ? 0 : 1)
            }
            .overlay {
                if done {
                    Image(systemName: "checkmark.circle.fill").font(AppStyle.statusSymbol).foregroundStyle(AppStyle.successColor)
                }
            }
    }
}
