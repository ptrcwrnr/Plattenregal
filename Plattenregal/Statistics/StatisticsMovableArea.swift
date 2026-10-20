import SwiftUI

// MARK: - Card chrome

/// A section of the statistics page: its title (also the drag handle for
/// reordering) and content. In both designs it lies on the page like the
/// covers of Collection and Wantlist, a fine rule above it; only its tiles
/// bring a surface (see `statisticsTile`).
struct StatisticsMovableArea<Content: View>: View {
    let section: StatisticsSection
    /// The topmost section: without the rule above it.
    var first = false
    var accessory: AnyView?
    let move: (String, StatisticsSection) -> Bool
    @ViewBuilder let content: Content
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: StatisticsLayout.titleSpacing) {
            // Fixed-height title row, so content starts at the same height in every card.
            HStack(spacing: StatisticsLayout.gutter) {
                // Without an icon in front, so the title starts at the same
                // edge as the values and words below it.
                Text(section.title)
                    .font(.system(.title3, design: AppStyle.figureDesign, weight: .semibold))
                    .lineLimit(1)
                    .draggable("plattenregal-statistics:\(section.rawValue)")
                    .help("Am Titel ziehen, um den Bereich anzuordnen")
                    .accessibilityHint("Ziehen, um den Bereich zu verschieben")
                Spacer(minLength: 0)
                accessory
            }
            .frame(height: 28)
            content
        }
        // Flush with the page margins; the first title as far from the
        // toolbar as the covers on the other pages.
        .padding(.top, first ? 0 : StatisticsLayout.gutter)
        .padding(.bottom, StatisticsLayout.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .top) {
            if !first {
                Rectangle().fill(AppStyle.borderColor).frame(height: 1)
                    .offset(y: -StatisticsLayout.gutter / 2)
            }
        }
        // A frame only marks the drop target.
        .overlay {
            RoundedRectangle(cornerRadius: AppStyle.controlRadius)
                .strokeBorder(AppStyle.selectedBorder.opacity(isTargeted ? 1 : 0), lineWidth: 2)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let first = items.first else { return false }
            return move(first, section)
        } isTargeted: { isTargeted = $0 }
        .animation(AppStyle.quickAnimation, value: isTargeted)
    }
}

extension View {
    /// A tile inside a statistics section (figures, facts, labels), the same
    /// in both designs: one fill for every tile, a fine rim that takes the
    /// selection color under the pointer and a shadow that grows with it.
    /// Klassisch: a cream sleeve with a gold rim; Modern: a light tile, the
    /// rim in the accent.
    func statisticsTile(hovering: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppStyle.cardRadius)
        return background {
            if AppStyle.isAtelier {
                shape.fill(AtelierPalette.surface)
                    .overlay(shape.strokeBorder(hovering ? AtelierPalette.gold : AtelierPalette.border, lineWidth: 1))
                    .shadow(color: AtelierPalette.shadow, radius: hovering ? 8 : 5, y: hovering ? 3 : 2)
            } else {
                shape.fill(.background.opacity(0.6))
                    .overlay(shape.strokeBorder(hovering ? AppStyle.selectedBorder.opacity(0.6) : AppStyle.borderColor, lineWidth: 1))
                    .shadow(color: .black.opacity(hovering ? 0.12 : 0.05), radius: hovering ? 8 : 5, y: hovering ? 3 : 2)
            }
        }
    }
}
