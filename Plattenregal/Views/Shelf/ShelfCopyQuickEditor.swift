import SwiftUI
import SwiftData

/// A compact editor for the position within the copy's current compartment.
struct ShelfCopyQuickEditor: View {
    let copy: RecordCopy
    @Environment(\.modelContext) private var context
    @State private var position = 1
    @State private var isSliding = false
    @State private var error: String?

    /// Walks the shelf's records: `body` reads it once (it runs again with
    /// every step of the slider), not in each of the places that show it.
    private var currentMaxPosition: Int {
        // The same copies the grid and table count (see `ShelfCopyItem.snapshot`).
        guard let shelf = copy.shelf else { return 1 }
        return shelf.copies.filter { !$0.isDeleted && $0.shelf?.id == shelf.id && $0.id != copy.id }.count + 1
    }

    var body: some View {
        let maxPosition = currentMaxPosition
        VStack(alignment: .leading, spacing: AppStyle.rowSpacing) {
            HStack(spacing: AppStyle.rowSpacing) {
                CoverView(url: copy.release?.coverURL, size: 44)
                    .atelierRecordSleeve()
                VStack(alignment: .leading, spacing: AppStyle.hairSpacing) {
                    Text(copy.release?.displayArtist ?? "—")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text(copy.release?.displayTitle ?? "—")
                        .font(.headline).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Slider(value: Binding(
                get: { Double(position) },
                set: { value in
                    let next = min(max(Int(value.rounded()), 1), maxPosition)
                    if isSliding { position = next } else { setPosition(next) }
                }
            ), in: 1...Double(max(maxPosition, 2)), onEditingChanged: { editing in
                isSliding = editing
                if !editing { setPosition(position) }
            })
            .tint(AppStyle.isAtelier ? AtelierPalette.accent : nil)
            .opacity(AppStyle.isAtelier ? 0.02 : 1)
            .overlay {
                if AppStyle.isAtelier {
                    GeometryReader { geometry in
                        let inset: CGFloat = 10
                        let travel = max(geometry.size.width - 2 * inset, 0)
                        let progress = CGFloat(position - 1) / CGFloat(max(maxPosition - 1, 1))
                        ZStack(alignment: .leading) {
                            Capsule().fill(AtelierPalette.accent.opacity(0.15))
                                .frame(height: 5)
                            Capsule().fill(AtelierPalette.accent.opacity(0.65))
                                .frame(width: inset + travel * progress, height: 5)
                            Circle().fill(AtelierPalette.accent)
                                .frame(width: 20, height: 20)
                                .shadow(color: AtelierPalette.shadow, radius: 2, y: 1)
                                .offset(x: travel * progress)
                        }
                        .frame(height: geometry.size.height)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .disabled(maxPosition <= 1)
            .accessibilityLabel("Position")
            .accessibilityValue(String(localized: "\(position) von \(maxPosition)"))
            .help(String(localized: "Position 1 bis \(maxPosition)"))
            .overlay {
                GeometryReader { geometry in
                    if isSliding {
                        Text(String(position))
                            .font(AppStyle.captionMark)
                            .monospacedDigit()
                            .foregroundStyle(AppStyle.accent)
                            .position(
                                x: 10 + CGFloat(position - 1) / CGFloat(max(maxPosition - 1, 1)) * max(geometry.size.width - 20, 0),
                                y: -7
                            )
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .padding(.top, AppStyle.cardPadding)
            .padding(.bottom, AppStyle.tightSpacing)
            if let error {
                Text(error).font(.caption).foregroundStyle(AppStyle.errorColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

        }
        .padding(AppStyle.cardPadding)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { position = min(max(copy.positionInShelf, 1), currentMaxPosition) }
        .onDisappear { setPosition(position) }
        .appPopoverSurface()
    }

    private func setPosition(_ value: Int) {
        // Removed while the popover was open ("Alles zurücksetzen"): once
        // saved, a deleted record only shows in its missing context.
        guard !copy.isDeleted, copy.modelContext != nil, let shelf = copy.shelf else { return }
        do {
            let clamped = min(max(value, 1), currentMaxPosition)
            if clamped != copy.positionInShelf {
                try PositionService(context: context).move(copy, to: shelf, position: clamped)
            }
            position = clamped
            error = nil
        } catch {
            position = min(max(copy.positionInShelf, 1), currentMaxPosition)
            self.error = error.reportedMessage()
        }
    }
}
