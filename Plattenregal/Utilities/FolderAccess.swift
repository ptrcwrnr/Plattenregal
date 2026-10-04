import AppKit
import Foundation

/// A folder the user picked (e.g. in iCloud Drive), remembered across
/// launches. The app is sandboxed: it may only write there through a
/// security-scoped bookmark, which is stored in the user defaults.
nonisolated struct FolderAccess: Sendable {
    let key: String

    var isSet: Bool { AppDefaults.store.data(forKey: key) != nil }

    /// Resolves the bookmark; `nil` when none is set or the folder is gone.
    /// A stale bookmark (folder moved or renamed) is renewed on the way.
    /// A bookmark follows its folder into the trash: that counts as gone, or
    /// exports and backups would keep landing there unnoticed.
    var url: URL? {
        guard let data = AppDefaults.store.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale),
              !Self.isInTrash(url)
        else { return nil }
        if stale {
            // A new security-scoped bookmark needs the folder open, or it fails silently.
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let renewed = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                AppDefaults.store.set(renewed, forKey: key)
            }
        }
        return url
    }

    /// Remembers a folder chosen in an open panel (the panel grants access
    /// for this session; the bookmark keeps it for later ones).
    func set(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        AppDefaults.store.set(data, forKey: key)
    }

    func clear() { AppDefaults.store.removeObject(forKey: key) }

    /// Runs `body` with access to the folder open.
    func withAccess<T>(_ body: (URL) throws -> T) throws -> T {
        guard let url else { throw FileTransferError.folderUnavailable }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }

    /// The home trash ("~/.Trash") or an external drive's (".Trashes/501").
    static func isInTrash(_ url: URL) -> Bool {
        !Set(url.standardizedFileURL.pathComponents).isDisjoint(with: [".Trash", ".Trashes"])
    }

    /// "iCloud Drive › Plattenregal" rather than the path inside the container.
    static func displayName(of url: URL) -> String {
        let path = url.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // Inside the sandbox the home directory is the container; the real one sits above it.
        let realHome = home.components(separatedBy: "/Library/Containers/").first ?? home
        let cloud = realHome + "/Library/Mobile Documents/com~apple~CloudDocs"
        if path.hasPrefix(cloud) {
            return "iCloud Drive" + path.dropFirst(cloud.count).replacingOccurrences(of: "/", with: " › ")
        }
        if path.hasPrefix(realHome) {
            return "~" + path.dropFirst(realHome.count)
        }
        return path
    }

    /// Bytes of all files below `url` (for the storage overview).
    static func size(of url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
        else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }
}

/// The system's folder picker; grants the sandbox access to the choice.
enum FolderPicker {
    @MainActor static func choose(message: String, prompt: String = String(localized: "Wählen")) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }
}
