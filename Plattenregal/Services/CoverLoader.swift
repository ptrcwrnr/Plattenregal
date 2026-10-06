import AppKit
import CryptoKit
import ImageIO
import SwiftUI

actor CoverCache {
    static let shared = CoverCache()
    final class ImagePayload: @unchecked Sendable {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }
    private struct CacheKey: Hashable {
        let url: URL
        let maximumPixelSize: Int
    }
    private struct Entry { let payload: ImagePayload; let expires: Date; var lastAccess: Date }
    private var entries: [CacheKey: Entry] = [:]
    // Keyed by URL alone (not size): the disk cache file is also per-URL, so two
    // concurrent requests for the same cover at different sizes must share one
    // download/write instead of racing two writes to the same file.
    private var pending: [URL: Task<Data, Error>] = [:]
    /// Bumped by `clear()`: downloads started before it must not write their
    /// file afterwards and refill the cache that was just emptied.
    private var generation = 0
    private let cacheDirectory: URL?
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral; config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()
    private init() {
        // The demo keeps its own covers, so "Cover-Cache leeren" there can't
        // empty the real cache.
        let directory = DemoMode.isActive
            ? DemoMode.temporaryDirectory.appendingPathComponent("Covers", isDirectory: true)
            : try? FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Plattenregal/Covers", isDirectory: true)
        if let directory {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                cacheDirectory = directory
            } catch {
                cacheDirectory = nil
            }
        } else {
            cacheDirectory = nil
        }
    }
    func image(_ url: URL, maximumPixelSize: Int) async throws -> ImagePayload {
        let key = CacheKey(url: url, maximumPixelSize: maximumPixelSize)
        if var entry = entries[key] {
            if entry.expires > .now {
                entry.lastAccess = .now; entries[key] = entry
                return entry.payload
            }
            entries[key] = nil
        }
        // Demo covers are drawn, never downloaded or written to disk.
        if url.scheme == DemoCover.scheme {
            guard let image = DemoCover.render(url, pixelSize: maximumPixelSize) else { throw DiscogsError.invalidResponse }
            let payload = ImagePayload(image)
            storeInMemory(payload, for: key)
            return payload
        }
        if let fileURL = fileURL(for: url),
           let payload = await Self.thumbnail(fromFile: fileURL, maximumPixelSize: maximumPixelSize) {
            storeInMemory(payload, for: key)
            return payload
        }
        let data = try await downloadData(for: url)
        guard let payload = await Self.decoded(data, maximumPixelSize: maximumPixelSize) else {
            throw DiscogsError.invalidResponse
        }
        storeInMemory(payload, for: key)
        return payload
    }

    private func downloadData(for url: URL) async throws -> Data {
        if let task = pending[url] { return try await task.value }
        let fileURL = fileURL(for: url)
        let generation = generation
        let task = Task<Data, Error> {
            guard url.scheme == "https" else { throw DiscogsError.invalidResponse }
            let (data, response) = try await session.data(from: url)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw DiscogsError.invalidResponse
            }
            // An error page answered with 200 or a cut-off download must not
            // land on disk, where every later launch would find it again.
            guard Self.isImage(data) else { throw DiscogsError.invalidResponse }
            if let fileURL, generation == self.generation { try? data.write(to: fileURL, options: .atomic) }
            return data
        }
        pending[url] = task
        defer { pending[url] = nil }
        return try await task.value
    }

    private static func isImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0 && CGImageSourceGetStatus(source) == .statusComplete
    }

    /// Reading and decoding run beside the actor, not on it: covers coming
    /// into view are decoded in parallel instead of one after another.
    @concurrent nonisolated private static func thumbnail(fromFile fileURL: URL, maximumPixelSize: Int) async -> ImagePayload? {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = thumbnail(from: data, maximumPixelSize: maximumPixelSize) else { return nil }
        // Marks the file as used, so the cleanup at launch keeps it – once a
        // day is plenty for a cleanup that goes by months.
        let modified = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if modified.map({ Date.now.timeIntervalSince($0) > 24 * 3600 }) ?? true {
            try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: fileURL.path)
        }
        return payload
    }

    @concurrent nonisolated private static func decoded(_ data: Data, maximumPixelSize: Int) async -> ImagePayload? {
        thumbnail(from: data, maximumPixelSize: maximumPixelSize)
    }

    nonisolated private static func thumbnail(from data: Data, maximumPixelSize: Int) -> ImagePayload? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return ImagePayload(image)
    }

    /// Decoded covers are big (a 1000 px one takes 4 MB), so the count alone
    /// doesn't bound the memory: large grid covers would add up to more than a gigabyte.
    private static let memoryLimit = 256 * 1024 * 1024
    private static func cost(_ payload: ImagePayload) -> Int { payload.image.bytesPerRow * payload.image.height }

    private func storeInMemory(_ payload: ImagePayload, for key: CacheKey) {
        let now = Date.now
        entries = entries.filter { $0.key != key && $0.value.expires > now }
        var total = entries.values.reduce(0) { $0 + Self.cost($1.payload) } + Self.cost(payload)
        while !entries.isEmpty, entries.count >= 320 || total > Self.memoryLimit,
              let oldest = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess }) {
            total -= Self.cost(oldest.value.payload)
            entries.removeValue(forKey: oldest.key)
        }
        entries[key] = Entry(payload: payload, expires: Date().addingTimeInterval(3600), lastAccess: .now)
    }
    /// Bytes the covers take up on disk (for the settings).
    func diskUsage() -> Int64 {
        guard let cacheDirectory,
              let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey])
        else { return 0 }
        return files.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
    /// Covers not shown for this long are removed at launch (search and
    /// wantlist results, records sold long ago); they are simply downloaded
    /// again when needed. Past `diskLimit` the least recently used go first.
    private static let diskMaximumAge: TimeInterval = 90 * 24 * 3600
    private static let diskLimit: Int64 = 1024 * 1024 * 1024

    /// Once per launch, in the background.
    nonisolated func pruneDisk() {
        guard let directory = cacheDirectory else { return }
        Task.detached(priority: .background) {
            let removed = Self.prune(directory, now: .now)
            if removed > 0 { AppLog.info("Cover", "Cover-Cache aufgeräumt: \(removed) alte Dateien entfernt") }
        }
    }

    /// Returns the number of files removed.
    @discardableResult nonisolated static func prune(_ directory: URL, now: Date,
                                                     maximumAge: TimeInterval = diskMaximumAge, limit: Int64 = diskLimit) -> Int {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) else { return 0 }
        // Most recently used first: whatever runs past the limit is the oldest.
        let files = urls.compactMap { url -> (url: URL, used: Date, size: Int64)? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return (url, values.contentModificationDate ?? .distantPast, Int64(values.fileSize ?? 0))
        }
        .sorted { $0.used > $1.used }
        var total: Int64 = 0
        var removed = 0
        for file in files {
            total += file.size
            guard now.timeIntervalSince(file.used) > maximumAge || total > limit else { continue }
            if (try? FileManager.default.removeItem(at: file.url)) != nil { removed += 1 }
        }
        return removed
    }

    /// Drops every cached cover; they are downloaded again when next shown.
    /// Returns false when some files could not be removed.
    @discardableResult func clear() -> Bool {
        entries.removeAll()
        generation += 1
        guard let cacheDirectory,
              let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
        else { return true }
        var removedAll = true
        for file in files {
            do { try FileManager.default.removeItem(at: file) } catch { removedAll = false }
        }
        return removedAll
    }
    private func fileURL(for url: URL) -> URL? {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return cacheDirectory?.appendingPathComponent(digest, isDirectory: false)
    }
}
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

    private func load() async {
        // Only a new URL clears the old image; a sharper re-decode swaps in place.
        if loadedURL != url { image = nil; failed = false; loadedURL = url; loadedEdge = 0 }
        // Never re-decode smaller: a shrinking cover just draws the sharper image scaled down.
        guard let url, let parsed = URL(string: url), image == nil || decodeEdge > loadedEdge else { return }
        do {
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            let loaded = try await CoverCache.shared.image(
                parsed,
                maximumPixelSize: max(64, Int((CGFloat(decodeEdge) * scale).rounded(.up)))
            )
            try Task.checkCancellation()
            image = NSImage(cgImage: loaded.image, size: .zero); failed = false; loadedEdge = decodeEdge
        }
        catch is CancellationError {} catch { failed = true }
    }
}

extension EnvironmentValues {
    @Entry var coverCornerRadius: CGFloat = 6
}
