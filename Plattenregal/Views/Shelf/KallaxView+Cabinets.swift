import SwiftUI
import SwiftData

extension KallaxView {
    /// One tab per active cabinet; ⌘← / ⌘→ step through them.
    var cabinetSwitcher: some View {
        HStack(spacing: AppStyle.itemSpacing) {
            GlassSegmentedPicker(
                selection: Binding(get: { shownCabinet?.id }, set: { id in
                    if let cabinet = activeCabinets.first(where: { $0.id == id }) { show(cabinet) }
                }),
                options: activeCabinets.map { Optional($0.id) },
                separators: true,
                secondaryClick: { id, point in if let id { cabinetMenu = (id, point) } }
            ) { id in
                cabinetTab(activeCabinets.first { $0.id == id })
            }
            .accessibilityLabel("Regal")
            Spacer()
            Button("Vorheriges Regal") { stepCabinet(-1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .hidden().frame(width: 0)
            Button("Nächstes Regal") { stepCabinet(1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .hidden().frame(width: 0)
        }
        // Tabs and rack belong together: a row's gap instead of a block's.
        .padding(.bottom, AppStyle.rowSpacing - AppStyle.blockSpacing)
        .help("Zwischen den Regalen wechseln: ⌘← / ⌘→")
    }

    /// A tab's name, carrying its right-click menu and the name popover –
    /// each on its own layer, two popovers on one view get in each other's way.
    @ViewBuilder private func cabinetTab(_ cabinet: Cabinet?) -> some View {
        if let cabinet {
            Text(cabinet.name)
                .popover(isPresented: Binding(
                    get: { cabinetMenu?.id == cabinet.id },
                    set: { if !$0, cabinetMenu?.id == cabinet.id { cabinetMenu = nil } }
                ), attachmentAnchor: .point(cabinetMenu?.anchor ?? .center), arrowEdge: .bottom) {
                    AppMenu(dismiss: { cabinetMenu = nil }) {
                        Button("Regal anzeigen") { show(cabinet) }
                        Button("Regal umbenennen …") { renamingCabinet = cabinet.id }
                    }
                    // Not the tab's accent or gray: popovers inherit it.
                    .foregroundStyle(.primary)
                }
                .background {
                    Color.clear.popover(isPresented: Binding(
                        get: { renamingCabinet == cabinet.id },
                        set: { if !$0, renamingCabinet == cabinet.id { renamingCabinet = nil } }
                    ), arrowEdge: .bottom) {
                        CabinetNamePopover(cabinet: cabinet).id(cabinet.id)
                            .foregroundStyle(.primary)
                    }
                }
        }
    }

    private func stepCabinet(_ offset: Int) {
        guard let current = shownCabinet, let index = activeCabinets.firstIndex(where: { $0.id == current.id }) else { return }
        let next = (index + offset + activeCabinets.count) % activeCabinets.count
        show(activeCabinets[next])
    }

    /// Selects the cabinet's starting compartment (see `startShelf(in:)`).
    func show(_ cabinet: Cabinet) {
        guard cabinet.id != shownCabinet?.id, let shelf = startShelf(in: cabinet) else { return }
        let from = activeCabinets.firstIndex { $0.id == shownCabinet?.id } ?? 0
        let to = activeCabinets.firstIndex { $0.id == cabinet.id } ?? 0
        cabinetEdge = to > from ? .trailing : .leading
        withAnimation(AppStyle.layoutAnimation ?? AppStyle.fadeAnimation) { selectShelf(shelf) }
    }

    /// The status controls (sold records still in the rack), right-aligned
    /// above the rack; absent when there are none, so the rack moves up.
    @ViewBuilder var header: some View {
        let sold = soldCount
        if sold > 0 {
            ShelfStatusControl(soldInShelves: sold, removeSold: { soldToRemove = sold; confirmRemoveSold = true })
                .frame(height: AppStyle.controlHeight)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.bottom, AppStyle.blockSpacing)
        }
    }
}
