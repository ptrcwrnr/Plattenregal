import SwiftUI

/// Shared typography and spacing for windows, sheets, dashboards and record cards.
enum AppStyle {
    static let pagePadding: CGFloat = 24
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 20
    static let rowSpacing: CGFloat = 12
    // Shared corner radius for secondary surfaces (search fields, result
    // dropdowns, metric chips) so they read as one consistent system instead
    // of each picking its own rounding.
    static let surfaceRadius: CGFloat = 12
    static let pageTitle = Font.system(.title, design: .rounded, weight: .semibold)
    static let sectionTitle = Font.system(.title3, design: .rounded, weight: .semibold)
    static let dialogTitle = Font.system(.title2, design: .rounded, weight: .semibold)
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

    func appControlSurface() -> some View { appGlassSurface(cornerRadius: 18) }

    @ViewBuilder func appGlassButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
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
