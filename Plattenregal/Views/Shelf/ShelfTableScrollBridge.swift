import SwiftUI

/// SwiftUI's Table does not reliably publish or restore scrollPosition on
/// macOS. Keep the top visible copy through the native clip view instead.
/// A saved target is restored before any initial bounds change can replace it
/// with the new table's first row. External requests use their own token, so
/// asking to show the same copy again still centers it.
struct ShelfTableScrollBridge: NSViewRepresentable {
    let ids: [UUID]
    let position: Binding<UUID?>
    let revealID: UUID?
    let revealRequest: UUID?

    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {
        view.configure(ids: ids, position: position, revealID: revealID, revealRequest: revealRequest)
    }
    static func dismantleNSView(_ view: Anchor, coordinator: ()) { view.stop() }

    final class Anchor: NSView {
        private var ids: [UUID] = []
        private var position: Binding<UUID?>?
        private var restoreID: UUID?
        private var revealID: UUID?
        private var revealRequest: UUID?
        private var lastRevealRequest: UUID?
        private var lastObservedID: UUID?
        private var needsRestore = true
        private var restoring = true
        private weak var table: NSTableView?
        private var observer: NSObjectProtocol?
        private var pending: DispatchWorkItem?
        private var generation = 0
        private var stopped = false

        func configure(ids: [UUID], position: Binding<UUID?>, revealID: UUID?, revealRequest: UUID?) {
            if self.position == nil || self.ids != ids {
                self.ids = ids
                restoreID = position.wrappedValue
                needsRestore = true
                restoring = true
                lastObservedID = nil
            }
            self.position = position
            self.revealID = revealID
            self.revealRequest = revealRequest
            schedule()
        }

        override func viewDidMoveToWindow() {
            if window == nil { stop() }
            else {
                stopped = false
                restoreID = position?.wrappedValue
                needsRestore = true
                restoring = true
                lastObservedID = nil
                schedule()
            }
        }

        override func layout() {
            super.layout()
            // A table can finish mounting after the bounded install retries.
            if window != nil, !stopped, needsRestore { schedule() }
        }

        private func schedule(attempt: Int = 0) {
            pending?.cancel()
            generation += 1
            let revision = generation
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.stopped, self.generation == revision, self.window != nil else { return }
                self.install(attempt: attempt)
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0 : 0.025), execute: work)
        }

        private func install(attempt: Int) {
            guard let native = nearbyTable(), let scroll = native.enclosingScrollView,
                  native.numberOfRows == ids.count, !ids.isEmpty,
                  scroll.contentView.bounds.height > 0, native.bounds.height > 0 else {
                if attempt < 20 { schedule(attempt: attempt + 1) }
                return
            }
            if table !== native {
                if let observer { NotificationCenter.default.removeObserver(observer) }
                table = native
                let clip = scroll.contentView
                clip.postsBoundsChangedNotifications = true
                observer = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.capture() }
                }
            }
            let wantsReveal = revealRequest != nil && revealRequest != lastRevealRequest
            guard needsRestore || wantsReveal else { return }
            // A remembered copy that has left the compartment restores to the top.
            if !wantsReveal, let id = restoreID, !ids.contains(id) { restoreID = nil }
            let target = wantsReveal ? revealID : restoreID
            guard let row = target.flatMap({ ids.firstIndex(of: $0) }) ?? (needsRestore && target == nil ? 0 : nil) else {
                if attempt < 20 { schedule(attempt: attempt + 1) }
                return
            }
            restoring = true
            native.layoutSubtreeIfNeeded()
            let clip = scroll.contentView
            let rect = native.rect(ofRow: row)
            // Inset tables draw their fixed header over the clip view. Its
            // top inset is real document space: row zero starts at -topInset,
            // and a restored row belongs below that header, not behind it.
            let inset = scroll.contentInsets
            // An inset NSTableView has an implicit header inset even when
            // NSScrollView.contentInsets reports zero (its natural y is -28).
            let topInset = max(inset.top, native.headerView?.frame.height ?? 0)
            if target != nil {
                let y = wantsReveal
                    ? rect.midY - (clip.bounds.height + topInset - inset.bottom) / 2
                    : rect.minY - topInset
                let minimum = -topInset
                let maximum = max(minimum, native.bounds.height - clip.bounds.height + inset.bottom)
                clip.scroll(to: NSPoint(x: clip.bounds.minX, y: min(max(minimum, y), maximum)))
                scroll.reflectScrolledClipView(clip)
            }
            native.headerView?.needsDisplay = true
            needsRestore = false
            if wantsReveal { lastRevealRequest = revealRequest }
            restoring = false
            capture()
        }

        private func capture() {
            guard !stopped, !restoring, !needsRestore, let table,
                  table.numberOfRows == ids.count, !ids.isEmpty else { return }
            var visible = table.visibleRect
            if let scroll = table.enclosingScrollView {
                let clip = scroll.contentView.bounds
                let topInset = max(scroll.contentInsets.top, table.headerView?.frame.height ?? 0)
                let top = max(visible.minY, clip.minY + topInset)
                let bottom = min(visible.maxY, clip.maxY - scroll.contentInsets.bottom)
                visible = NSRect(x: visible.minX, y: top, width: visible.width, height: max(0, bottom - top))
            }
            let rows = table.rows(in: visible)
            guard rows.location != NSNotFound, ids.indices.contains(rows.location) else { return }
            let id = ids[rows.location]
            guard id != lastObservedID else { return }
            lastObservedID = id
            if position?.wrappedValue != id { position?.wrappedValue = id }
        }

        func stop() {
            stopped = true
            generation += 1
            pending?.cancel()
            pending = nil
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            table = nil
        }

        isolated deinit {
            pending?.cancel()
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
