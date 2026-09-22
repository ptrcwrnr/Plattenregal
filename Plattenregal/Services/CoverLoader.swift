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
    private let cacheDirectory: URL?
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral; config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()
    private init() {
        let directory = try? FileManager.default.url(for: .applicationSupportDirectory,
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
        entries = entries.filter { $0.value.expires > .now }
        if var entry = entries[key] {
            entry.lastAccess = .now; entries[key] = entry
            return entry.payload
        }
        if let fileURL = fileURL(for: url),
           let data = try? Data(contentsOf: fileURL),
           let payload = Self.thumbnail(from: data, maximumPixelSize: maximumPixelSize) {
            storeInMemory(payload, for: key)
            return payload
        }
        let data = try await downloadData(for: url)
        guard let payload = Self.thumbnail(from: data, maximumPixelSize: maximumPixelSize) else {
            throw DiscogsError.invalidResponse
        }
        storeInMemory(payload, for: key)
        return payload
    }

    private func downloadData(for url: URL) async throws -> Data {
        if let task = pending[url] { return try await task.value }
        let fileURL = fileURL(for: url)
        let task = Task<Data, Error> {
            guard url.scheme == "https" else { throw DiscogsError.invalidResponse }
            let (data, response) = try await session.data(from: url)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw DiscogsError.invalidResponse
            }
            if let fileURL { try? data.write(to: fileURL, options: .atomic) }
            return data
        }
        pending[url] = task
        defer { pending[url] = nil }
        return try await task.value
    }

    private static func thumbnail(from data: Data, maximumPixelSize: Int) -> ImagePayload? {
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

    private func storeInMemory(_ payload: ImagePayload, for key: CacheKey) {
        if entries.count >= 320, let oldest = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key {
            entries.removeValue(forKey: oldest)
        }
        entries[key] = Entry(payload: payload, expires: Date().addingTimeInterval(3600), lastAccess: .now)
    }
    private func fileURL(for url: URL) -> URL? {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return cacheDirectory?.appendingPathComponent(digest, isDirectory: false)
    }
}
struct CoverView: View {
    let url: String?
    var size: CGFloat = 160
    @State private var image: NSImage?
    @State private var failed = false
    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else {
                Image(systemName: failed ? "photo.badge.exclamationmark" : "opticaldisc")
                    .font(.system(size: size * 0.28, weight: .ultraLight)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel(failed ? "Cover konnte nicht geladen werden" : "Plattencover")
        .help(failed ? "Cover konnte nicht geladen werden. Prüfe die Verbindung." : "Plattencover")
        .task(id: url) {
            image = nil; failed = false
            guard let url, let parsed = URL(string: url) else { return }
            do {
                let scale = NSScreen.main?.backingScaleFactor ?? 2
                let loaded = try await CoverCache.shared.image(
                    parsed,
                    maximumPixelSize: max(64, Int((size * scale).rounded(.up)))
                )
                try Task.checkCancellation()
                image = NSImage(cgImage: loaded.image, size: .zero)
            }
            catch is CancellationError {} catch { failed = true }
        }
    }
}
