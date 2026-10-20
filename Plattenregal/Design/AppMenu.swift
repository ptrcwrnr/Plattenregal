import SwiftUI

/// The app's own context menu: a popover with hover rows instead of the
/// native macOS menu, without separators. Plain `Button`s inside `content`
/// are styled as menu rows; choosing one closes the menu first, then runs the
/// action (so a sheet it opens isn't fighting the closing popover).
struct AppMenu<Content: View>: View {
    let dismiss: () -> Void
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.hairSpacing) { content }
            .buttonStyle(AppMenuButtonStyle(dismiss: dismiss))
            .padding(AppStyle.tightSpacing)
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
            .padding(.horizontal, AppStyle.itemSpacing)
            .padding(.top, AppStyle.itemSpacing)
            .padding(.bottom, AppStyle.hairSpacing)
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
                .padding(.horizontal, AppStyle.itemSpacing)
                .padding(.vertical, AppStyle.tightSpacing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(configuration.role == .destructive ? AnyShapeStyle(AppStyle.errorColor) : AnyShapeStyle(.primary))
        .opacity(isEnabled ? 1 : 0.4)
        .appHoverable(hovering && isEnabled, cornerRadius: AppStyle.menuRowRadius)
        .onHover { hovering = $0 }
    }
}
