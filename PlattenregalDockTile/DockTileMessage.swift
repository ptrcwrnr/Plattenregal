import Foundation

/// The messages between the app and its Dock plug-in, part of both targets.
/// Distributed notifications: the plug-in runs in a sandboxed helper of the
/// Dock and can't read the app's settings, and a sandboxed app's `userInfo`
/// never arrives – the image's name travels as the notification's object.
nonisolated enum DockTileMessage {
    /// App → plug-in: the image's name in the asset catalog, empty for the
    /// standard. On every change, at launch and when the plug-in asks.
    static let iconDidChange = Notification.Name("de.private.Plattenregal.appIconDidChange")
    /// Plug-in → app: just came into the Dock (the app's launch may have
    /// passed before it listened), please tell the choice.
    static let needsIcon = Notification.Name("de.private.Plattenregal.dockTileNeedsIcon")
    /// Plug-in → app: a choice arrived. Tells the app the Dock has loaded
    /// the plug-in for its tile.
    static let received = Notification.Name("de.private.Plattenregal.dockTileReceived")

    /// What the plug-in accepts – any process may post these names: empty
    /// (the standard) or one of the app's icon images, nothing else.
    static func isImageName(_ name: String) -> Bool {
        name.isEmpty || (name.hasPrefix("AppIcon-") && name.count <= 64
                         && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
    }
}
