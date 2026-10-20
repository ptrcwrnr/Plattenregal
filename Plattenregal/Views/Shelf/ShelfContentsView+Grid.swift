import SwiftUI
import SwiftData

extension ShelfContentsView {
    func grid(_ proxy: ScrollViewProxy) -> some View {
        GeometryReader { geometry in
            let width = max(0, geometry.size.width - 4)
            let columns = CoverGrid.columnCount(available: width, minimum: 135)
            ScrollView {
                // Every tile carries a glass tag (Modern): one container for
                // all of them renders them together, ~10 % less per scroll step.
                GlassEffectContainer(spacing: 0) {
                    LazyVGrid(columns: CoverGrid.columns(count: columns), alignment: .leading, spacing: CoverGrid.spacing) {
                        ForEach(items) { item in
                            Button { activate(item.copy) } label: { tile(item) }
                                .buttonStyle(.plain)
                                .id(item.id)
                                .popover(isPresented: quickEditBinding(item.id), arrowEdge: .trailing) {
                                    quickEditor(item.copy)
                                }
                                .gridSecondaryClickCell(item.id, in: gridClicks)
                                .popover(isPresented: menuBinding(item.id),
                                         attachmentAnchor: .point(menuFor?.anchor ?? .center), arrowEdge: .trailing) {
                                    actionMenu(item.copy)
                                }
                                .help("Position \(item.position) · \(item.artist) · \(item.title)\nKlick: Exemplar bearbeiten. Rechtsklick: weitere Aktionen.")
                                .accessibilityLabel("Position \(item.position), \(item.artist), \(item.title)")
                                .accessibilityAddTraits(focusCopy?.id == item.id ? .isSelected : [])
                                .accessibilityAction(named: Text("Exemplar bearbeiten")) { edit(item.copy) }
                        }
                    }
                    .scrollTargetLayout()
                    .gridSecondaryClickGrid(gridClicks)
                    .coverGridMotion(width: width, columnCount: columns)
                    // Room for the covers' shadows inside the scroll view, which
                    // clips; the negative padding below keeps the covers flush
                    // with the rack.
                    .padding(.horizontal, AppStyle.hairSpacing + CoverGrid.shadowRoom)
                    .padding(.top, AppStyle.hairSpacing)
                    // The last covers scroll clear of the round button.
                    .padding(.bottom, CoverGrid.spacing + AppStyle.floatingClearance)
                }
            }
            .onGridSecondaryClick(gridClicks) { id, point in
                quickEditID = nil
                menuFor = (id, point)
            }
            .padding(.horizontal, -CoverGrid.shadowRoom)
            .scrollPosition(tracking: scrollPosition(for: .grid))
            .opacity(gridRevealPending != nil && gridRevealPending == loadedShelfID ? 0 : 1)
            .id(loadedShelfID)
            .task(id: loadedShelfID) {
                let shelfID = shelf.id
                let saved = session.gridScrollPositions[shelfID]
                gridRestorePending = true
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(25))
                guard !Task.isCancelled, layout == .grid, loadedShelfID == shelfID else { return }
                // On mount SwiftUI can publish row zero before applying an
                // existing scrollPosition. Keep capture closed until an
                // explicit restore has laid out the saved copy. An external
                // focus request takes precedence over a remembered position.
                let hasFocusRequest = focusScroll?.shelfID == shelfID && focusScroll?.layout == .grid
                if !hasFocusRequest, let saved, items.contains(where: { $0.id == saved }) {
                    withAnimation(nil) {
                        session.gridScrollPositions[shelfID] = saved
                        proxy.scrollTo(saved, anchor: .top)
                    }
                }
                // Opened for a record: jump to it while still invisible.
                if gridRevealPending == shelfID, let request = focusScroll, request.shelfID == shelfID,
                   items.contains(where: { $0.id == request.copyID }) {
                    withAnimation(nil) {
                        session.gridScrollPositions[shelfID] = request.copyID
                        proxy.scrollTo(request.copyID, anchor: .center)
                    }
                }
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(25))
                if gridRevealPending == shelfID {
                    withAnimation(AppStyle.fadeAnimation) { gridRevealPending = nil }
                }
                guard !Task.isCancelled, layout == .grid, loadedShelfID == shelfID else { return }
                gridRestorePending = false
            }
        }
    }

    private func tile(_ item: ShelfCopyItem) -> some View {
        let selected = focusCopy?.id == item.id
        return VStack(alignment: .leading, spacing: CoverGrid.captionSpacing) {
            CoverView(url: item.copy.release?.coverURL, size: nil)
                .atelierRecordSleeve()
                .overlay {
                    RoundedRectangle(cornerRadius: AtelierCoverFrame.usesMat ? AppStyle.cardRadius : 2)
                        .strokeBorder(selected ? AppStyle.selectedBorder : .clear, lineWidth: 2)
                }
                .overlay(alignment: .topLeading) {
                    Text(String(item.position))
                        .font(.caption.weight(.semibold)).monospacedDigit()
                        .padding(.horizontal, AppStyle.itemSpacing).padding(.vertical, AppStyle.tightSpacing)
                        .appChipSurface(in: Capsule())
                        .padding(AtelierCoverFrame.badgeInset)
                }
            // The same caption as in Collection and Wantlist.
            RecordCaption(release: item.copy.release, emphasized: selected)
            VStack(alignment: .leading, spacing: AppStyle.tightSpacing) {
                if item.missing { MissingBadge() }
                if item.forSale { SaleBadge() }
                if item.sold {
                    Text("Nicht in der Collection")
                        .font(.caption2.weight(.medium)).foregroundStyle(AppStyle.warningColor)
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
            }
            .frame(minHeight: 14, alignment: .topLeading)
        }
        .contentShape(Rectangle())
    }
}
