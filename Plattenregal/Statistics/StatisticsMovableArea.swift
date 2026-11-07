import SwiftUI

// MARK: - Card chrome

/// A section of the statistics page: its title (also the drag handle for
/// reordering) and content. In both designs it lies on the page like the
/// covers of Collection and Wantlist, a fine rule above it; only its tiles
/// bring a surface (see `statisticsTile`). Drops are taken by the page as a
/// whole (see `StatisticsSectionDrop`); here only the frame shows the target.
struct StatisticsMovableArea<Content: View>: View {
    let section: StatisticsSection
    /// The topmost section: without the rule above it.
    var first = false
    /// A dragged section is over this one.
    var isTargeted = false
    var accessory: AnyView?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: StatisticsLayout.titleSpacing) {
            // Fixed-height title row, so content starts at the same height in every card.
            HStack(spacing: StatisticsLayout.gutter) {
                // Without an icon in front, so the title starts at the same
                // edge as the values and words below it.
                Text(section.title)
                    .font(AppStyle.figureHeading)
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
                .strokeBorder(AppStyle.selectedBorder.opacity(isTargeted ? 1 : 0), lineWidth: AppStyle.selectionLineWidth)
        }
        .animation(AppStyle.quickAnimation, value: isTargeted)
    }
}

// MARK: - Reordering

/// Where each section lies, in the coordinate space of the scroll view
/// (where the drop target is). A plain class, not observed: the frames
/// change as the page scrolls, and nothing needs to be drawn for that.
@MainActor final class StatisticsSectionFrames {
    nonisolated static let space = "statistics-sections"
    var frames: [StatisticsSection: CGRect] = [:]
    func section(at point: CGPoint) -> StatisticsSection? {
        frames.first { $0.value.contains(point) }?.key
    }
}

/// One drop target for the whole page instead of one per section: each
/// `dropDestination` brought an AppKit view of its own into the scrolling
/// page, and the ten of them were moved and hit-tested on every scrolled
/// frame (a quarter of the frames were dropped). The section under the
/// pointer is looked up in `frames`.
struct StatisticsSectionDrop: DropDelegate {
    let frames: StatisticsSectionFrames
    @Binding var target: StatisticsSection?
    let move: (String, StatisticsSection) -> Bool

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.plainText]) }
    func dropEntered(info: DropInfo) { follow(info) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        // Between two sections nothing takes the drop, as before. Not
        // `.cancel`: that ended the drag for the whole page.
        return follow(info) == nil ? DropProposal(operation: .forbidden) : nil
    }
    func dropExited(info: DropInfo) { target = nil }
    func performDrop(info: DropInfo) -> Bool {
        target = nil
        guard let section = frames.section(at: info.location),
              let provider = info.itemProviders(for: [.plainText]).first else { return false }
        _ = provider.loadTransferable(type: String.self) { result in
            guard case .success(let payload) = result else { return }
            Task { @MainActor in _ = move(payload, section) }
        }
        return true
    }
    @discardableResult private func follow(_ info: DropInfo) -> StatisticsSection? {
        let section = frames.section(at: info.location)
        if section != target { target = section }
        return section
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
                    .overlay(shape.strokeBorder(hovering ? AtelierPalette.gold : AtelierPalette.border, lineWidth: AppStyle.borderWidth))
                    .shadow(color: AtelierPalette.shadow, radius: hovering ? 8 : 5, y: hovering ? 3 : 2)
            } else {
                shape.fill(.background.opacity(0.6))
                    .overlay(shape.strokeBorder(hovering ? AppStyle.selectedBorder.opacity(0.6) : AppStyle.borderColor, lineWidth: AppStyle.borderWidth))
                    .shadow(color: .black.opacity(hovering ? 0.12 : 0.05), radius: hovering ? 8 : 5, y: hovering ? 3 : 2)
            }
        }
    }
}
