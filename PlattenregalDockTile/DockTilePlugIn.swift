import AppKit
import os

/// Shows the chosen app icon in the Dock while Plattenregal is closed.
///
/// macOS loads this plug-in (named in the app's Info.plist under
/// `NSDockTilePlugIn`) into a sandboxed helper of the Dock for as long as
/// the app's icon is in the Dock, running or not. The app's settings lie in
/// its own sandbox container, out of reach from here, so the app tells the
/// plug-in the image's name: in a distributed notification, as its object
/// (a sandboxed app's `userInfo` never arrives), on every change and at
/// every launch, and when the plug-in asks after coming into the Dock (the
/// app's launch may pass before the plug-in listens). The plug-in keeps the
/// name in its own defaults and loads
/// the image from the app's asset catalog. An empty name is the standard:
/// without a content view the Dock shows the bundle's icon.
@objc(PlattenregalDockTilePlugIn)
final class DockTilePlugIn: NSObject, NSDockTilePlugIn {
    /// The same name as `AppIconChoice.dockTileNotification` in the app.
    private static let notification = Notification.Name("de.private.Plattenregal.appIconDidChange")
    /// The same name as `AppIconChoice.dockTileRequest` in the app.
    private static let request = Notification.Name("de.private.Plattenregal.dockTileNeedsIcon")
    private static let key = "appIconImage"
    private let defaults = UserDefaults(suiteName: "de.private.Plattenregal.DockTile")
    private var dockTile: NSDockTile?
    private var observer: (any NSObjectProtocol)?
    /// In the system log (Konsole, subsystem `de.private.Plattenregal`):
    /// the plug-in runs in the Dock, out of reach of the app's own log.
    private static let log = Logger(subsystem: "de.private.Plattenregal", category: "DockTile")

    /// Called with the app's tile when it comes into the Dock, with nil when
    /// it leaves. The Dock gives no word on the thread: everything runs on
    /// the main one.
    nonisolated func setDockTile(_ dockTile: NSDockTile?) {
        nonisolated(unsafe) let tile = dockTile
        DispatchQueue.main.async { MainActor.assumeIsolated { self.attach(tile) } }
    }

    private func attach(_ tile: NSDockTile?) {
        dockTile = tile
        Self.log.info("Dock-Kachel \(tile == nil ? "entfernt" : "da", privacy: .public)")
        guard tile != nil else {
            if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
            observer = nil
            return
        }
        if observer == nil {
            observer = DistributedNotificationCenter.default().addObserver(forName: Self.notification, object: nil, queue: .main) { [weak self] note in
                let name = note.object as? String ?? ""
                MainActor.assumeIsolated { self?.store(name) }
            }
        }
        show(defaults?.string(forKey: Self.key) ?? "")
        // A running app answers with its choice; a closed one keeps the stored one.
        DistributedNotificationCenter.default().postNotificationName(Self.request, object: nil, userInfo: nil, deliverImmediately: true)
    }

    private func store(_ name: String) {
        Self.log.info("Neues Symbol: \(name.isEmpty ? "Standard" : name, privacy: .public)")
        defaults?.set(name, forKey: Self.key)
        show(name)
    }

    private func show(_ name: String) {
        guard let dockTile else { return }
        if !name.isEmpty, let image = Self.appBundle?.image(forResource: name) {
            let view = NSImageView(frame: NSRect(origin: .zero, size: dockTile.size))
            view.image = image
            view.imageScaling = .scaleProportionallyUpOrDown
            dockTile.contentView = view
        } else {
            if !name.isEmpty { Self.log.error("Bild nicht gefunden: \(name, privacy: .public)") }
            dockTile.contentView = nil
        }
        dockTile.display()
    }

    /// Plattenregal.app, three folders up from Contents/PlugIns/<this plug-in>.
    private static var appBundle: Bundle? {
        let app = Bundle(for: DockTilePlugIn.self).bundleURL
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return Bundle(url: app)
    }
}
