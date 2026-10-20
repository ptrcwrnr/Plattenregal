import SwiftUI
import AppKit
import ObjectiveC

/// Turns off the blue focus ring app-wide while keeping keyboard focus itself.
/// Buttons, text fields and tables are AppKit controls under the hood and draw
/// their ring based on `focusRingType`, which SwiftUI's `focusEffectDisabled()`
/// doesn't reach — so the getter is overridden once for NSView, NSControl and
/// NSCell (where controls forward it) to always answer `.none`.
enum FocusRings {
    static func disableGlobally() {
        let selector = #selector(getter: NSView.focusRingType)
        let block: @convention(block) (AnyObject) -> UInt = { _ in NSFocusRingType.none.rawValue }
        let implementation = imp_implementationWithBlock(block)
        for cls in [NSView.self, NSControl.self, NSCell.self] as [AnyClass] {
            guard let method = class_getInstanceMethod(cls, selector) else { continue }
            class_replaceMethod(cls, selector, implementation, method_getTypeEncoding(method))
        }
    }
}

/// The glass bubble macOS shows over the cursor with the input source (or
/// Caps Lock) when a text field gets the focus. Turned off for this app by
/// writing the switch into its own preferences domain, where macOS reads it
/// – a registered default stays in this process and was not seen. Someone
/// who switched it on or off in macOS on purpose (global domain) keeps that.
enum InputSourceIndicator {
    static let key = "TSMLanguageIndicatorEnabled"

    static func disableForApp(_ defaults: UserDefaults = .standard) {
        let global = defaults.persistentDomain(forName: UserDefaults.globalDomain)
        if global?[key] != nil {
            // Chosen in macOS: follow that, and drop an earlier override of ours.
            defaults.removeObject(forKey: key)
        } else if defaults.object(forKey: key) as? Bool != false {
            defaults.set(false, forKey: key)
        }
    }
}
