import AppKit
import Carbon.HIToolbox

/// A key combination that works from every app, also while Plattenregal is
/// in the background. Carbon's hot keys are the one public way for that: they
/// work in the sandbox and need no accessibility permission, unlike watching
/// all key presses. Only the registered combination ever reaches the app.
final class GlobalHotKey {
    /// ⌥ Leertaste: two keys, not used by macOS itself (⌘ Leertaste is
    /// Spotlight, ⌃ Leertaste the input source).
    static let quickSearch = (keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), title: String(localized: "⌥ Leertaste"))

    private let keyCode: UInt32
    private let modifiers: UInt32
    private let action: () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.action = action
    }

    isolated deinit { unregister() }

    var isRegistered: Bool { hotKey != nil }

    /// False when another app (or a second Plattenregal) holds the combination.
    @discardableResult func register() -> Bool {
        guard hotKey == nil else { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
            // Carbon calls on the main thread; `data` is this object, kept
            // alive until the handler is removed in `unregister`.
            guard let data else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<GlobalHotKey>.fromOpaque(data).takeUnretainedValue().action()
            }
            return noErr
        }, 1, &spec, me, &handler)
        guard installed == noErr else { return false }
        let id = EventHotKeyID(signature: OSType(0x506C_6174), id: 1) // "Plat"
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
        guard status == noErr else {
            hotKey = nil
            unregister()
            return false
        }
        return true
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }
}
