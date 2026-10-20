import AppKit
import CryptoKit
import ImageIO
import SwiftUI
import Synchronization

/// Square record cover. With a fixed `size` it has exactly that edge length;
/// with `size == nil` it fills the width its parent offers (square via
/// `aspectRatio`), so it can never outgrow the cell of a flexible grid.
struct CoverView: View {
    let url: String?
    var size: CGFloat? = 160
    /// Rounding of the cover's corners (see `atelierRecordSleeve`).
    @Environment(\.coverCornerRadius) private var cornerRadius
    @State private var image: NSImage?
    @State private var failed = false
    /// Rendered edge length, only used for decode resolution and the
    /// placeholder glyph — never for layout.
    @State private var measured: CGFloat = 0
    @State private var loadedURL: String?
    @State private var loadedEdge = 0
    /// Before the first measurement a typical grid size is assumed, so a
    /// freshly appearing cell starts loading at once instead of flashing the
    /// placeholder for a frame.
    private var edge: CGFloat { size ?? (measured > 0 ? measured : 256) }
    /// Decode size, rounded up in 64 pt steps so live resizing doesn't reload
    /// the image on every frame but a clearly larger cover still gets sharper.
    private var decodeEdge: Int { Int((edge / 64).rounded(.up) * 64) }

    var body: some View {
        // A cover shown before (scrolled back into view) is there in the
        // first frame, without the placeholder flashing up.
        let image = image ?? memoryImage
        ZStack {
            Rectangle().fill(.quaternary)
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else {
                Image(systemName: failed ? "photo.badge.exclamationmark" : "opticaldisc")
                    .font(.system(size: edge * 0.28, weight: .ultraLight)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
            if size == nil, abs(width - measured) > 0.5 { measured = width }
        }
        .accessibilityLabel(failed ? "Cover konnte nicht geladen werden" : "Plattencover")
        .help(failed ? String(localized: "Cover konnte nicht geladen werden. Prüfe die Verbindung.") : String(localized: "Plattencover"))
        .task(id: LoadKey(url: url, edge: decodeEdge)) { await load() }
    }

    private struct LoadKey: Hashable { let url: String?; let edge: Int }

    /// Pixels to decode for `decodeEdge` points.
    private var pixelSize: Int {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        return max(64, Int((CGFloat(decodeEdge) * scale).rounded(.up)))
    }

    /// The cover at this size, if the cache has it decoded already.
    private var memoryImage: NSImage? {
        guard let url, let parsed = URL(string: url),
              let payload = CoverCache.shared.cachedImage(parsed, maximumPixelSize: pixelSize) else { return nil }
        return NSImage(cgImage: payload.image, size: .zero)
    }

    private func load() async {
        // Only a new URL clears the old image; a sharper re-decode swaps in place.
        if loadedURL != url { image = nil; failed = false; loadedURL = url; loadedEdge = 0 }
        // Never re-decode smaller: a shrinking cover just draws the sharper image scaled down.
        guard let url, let parsed = URL(string: url), image == nil || decodeEdge > loadedEdge else { return }
        if let cached = memoryImage {
            image = cached; failed = false; loadedEdge = decodeEdge
            return
        }
        do {
            let loaded = try await CoverCache.shared.image(parsed, maximumPixelSize: pixelSize)
            try Task.checkCancellation()
            image = NSImage(cgImage: loaded.image, size: .zero); failed = false; loadedEdge = decodeEdge
        }
        catch is CancellationError {} catch { failed = true }
    }
}

extension EnvironmentValues {
    @Entry var coverCornerRadius: CGFloat = 6
}
