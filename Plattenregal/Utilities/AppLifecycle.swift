import AppKit
import ServiceManagement

/// Plattenregal in the background: ⌘Q, „Beenden“ in the Dock or closing the
/// last window close every window and keep the app running with only the
/// record in the menu bar – no Dock icon, not in ⌘-Tab – so the search there,
/// ⌥ Leertaste, the automatic export and the backups keep working. The
/// record's menu (right-click) and ⌥⌘Q quit completely.
///
/// Only while the record is in the menu bar: without it there'd be no way
/// to quit. Never in the demo (a showcase, ended by quitting) and never when
/// macOS quits the app for logout, restart or shutdown.
@Observable final class AppLifecycle {
    static let shared = AppLifecycle()

    /// Running without windows and Dock icon right now.
    private(set) var isInBackground = false

    @ObservationIgnored private var quittingCompletely = false
    /// Set while this class closes the windows itself: those closings must
    /// not start a second round.
    @ObservationIgnored private var closingWindows = false
    /// Launched at login into the background: the main window, still on its
    /// way, closes as soon as it is there instead of bringing the app back.
    @ObservationIgnored private var hidingLaunchWindow = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var started = false

    private static let terminationReason = "Plattenregal läuft im Hintergrund mit der Schallplatte in der Menüleiste"

    /// ⌘Q and closing the last window keep the app running: switched on,
    /// the record is in the menu bar, not the demo.
    var keepsRunning: Bool {
        AppPreferences.shared.keepsRunningInBackground && ShelfQuickSearch.shared.showsStatusItem && (!DemoMode.isActive || Self.demoMayKeepRunning)
    }

    /// Debug only: `--demo-background` tries the background with the demo's collection.
    private static var demoMayKeepRunning: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--demo-background")
        #else
        false
        #endif
    }

    /// Called once the app has finished launching, after the menu bar
    /// search (see `AppDelegate`).
    func start(launchedAtLogin: Bool) {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default
        // The last window closed by the user: on into the background. Checked
        // a moment later, when the window is gone from the screen.
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { notification in
            let window = notification.object as? NSWindow
            MainActor.assumeIsolated {
                guard let window, Self.isAppWindow(window) else { return }
                AppLifecycle.shared.windowWillClose()
            }
        })
        // Any window of the app in front again (opened from the record's
        // menu, the Finder, ↩ in the search): back with the Dock icon.
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { notification in
            let window = notification.object as? NSWindow
            MainActor.assumeIsolated {
                guard let window, Self.isAppWindow(window) else { return }
                AppLifecycle.shared.windowDidBecomeKey(window)
            }
        })
        // Logout, restart or shutdown quit for real; macOS also tells it in
        // the quit event (`terminateReply`), this is the second safeguard.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppLifecycle.shared.quittingCompletely = true }
        })
        if launchedAtLogin {
            if keepsRunning {
                AppLog.info("App", "Bei der Anmeldung gestartet, nur mit der Schallplatte in der Menüleiste")
                hidingLaunchWindow = true
                enterBackground()
                closeLaunchWindows()
            } else {
                AppLog.info("App", "Bei der Anmeldung gestartet")
            }
        }
    }

    // MARK: Quitting

    /// ⌘Q („Plattenregal beenden“ in the app menu).
    func quitRequested() {
        if keepsRunning { enterBackground() } else { NSApp.terminate(nil) }
    }

    /// The record's menu and ⌥⌘Q: quits, whatever the setting.
    func quitCompletely() {
        quittingCompletely = true
        NSApp.terminate(nil)
    }

    /// Asked by `AppDelegate.applicationShouldTerminate`.
    func terminateReply() -> NSApplication.TerminateReply {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let quitEvent = event.map { $0.eventClass == kCoreEventClass && $0.eventID == kAEQuitApplication } ?? false
        // Logout, restart and shutdown name a reason; the Dock, the Activity
        // Monitor or a script don't.
        let systemQuit = quitEvent && (event?.attributeDescriptor(forKeyword: kAEQuitReason) != nil
                                       || event?.paramDescriptor(forKeyword: kAEQuitReason) != nil)
        switch QuitDecision.decide(keepsRunning: keepsRunning, completely: quittingCompletely, quitEvent: quitEvent,
                                   systemQuit: systemQuit, inBackground: isInBackground) {
        case .quit:
            return .terminateNow
        case .background:
            // Not while macOS is still asking: windows close on the next turn.
            DispatchQueue.main.async { self.enterBackground() }
            return .terminateCancel
        }
    }

    // MARK: Background and foreground

    /// Closes every window and takes the Dock icon away; the record stays.
    func enterBackground() {
        guard keepsRunning else { return }
        ShelfQuickSearch.shared.close()
        closeAppWindows()
        guard !isInBackground else { return }
        isInBackground = true
        NSApp.setActivationPolicy(.accessory)
        // The next app in line comes to the front, as after quitting.
        NSApp.deactivate()
        // macOS may end an app without windows on its own; this one must stay.
        ProcessInfo.processInfo.disableAutomaticTermination(Self.terminationReason)
        // Decoded covers (up to 256 MB) aren't needed without windows; they come
        // back from the disk cache when the main window shows them again.
        CoverCache.shared.releaseMemory()
        AppLog.info("App", "Läuft im Hintergrund weiter, nur mit der Schallplatte in der Menüleiste")
    }

    /// Dock icon and app menu back – before a window of the app shows.
    func leaveBackground() {
        guard isInBackground else { return }
        isInBackground = false
        NSApp.setActivationPolicy(.regular)
        ProcessInfo.processInfo.enableAutomaticTermination(Self.terminationReason)
        AppLog.info("App", "Wieder im Vordergrund")
    }

    private func windowDidBecomeKey(_ window: NSWindow) {
        if hidingLaunchWindow {
            hidingLaunchWindow = false
            closeAppWindows()
            AppLog.info("App", "Startfenster nach der Anmeldung geschlossen")
        } else {
            leaveBackground()
        }
    }

    private func windowWillClose() {
        guard !closingWindows, !isInBackground, keepsRunning else { return }
        DispatchQueue.main.async { [self] in
            guard !isInBackground, keepsRunning, !NSApp.windows.contains(where: Self.isOpen) else { return }
            enterBackground()
        }
    }

    private func closeAppWindows() {
        closingWindows = true
        defer { closingWindows = false }
        for window in NSApp.windows where Self.isOpen(window) {
            // A sheet would hold the window open.
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
            window.close()
        }
    }

    /// At login the main window comes up while launching finishes, not
    /// always as the key window; it is closed as soon as it is there.
    /// Watched for two seconds at most – a window after that is the user's.
    private func closeLaunchWindows(attempt: Int = 0) {
        guard hidingLaunchWindow else { return }
        if NSApp.windows.contains(where: Self.isOpen) {
            hidingLaunchWindow = false
            closeAppWindows()
            AppLog.info("App", "Startfenster nach der Anmeldung geschlossen")
        } else if attempt < 20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.closeLaunchWindows(attempt: attempt + 1) }
        } else {
            hidingLaunchWindow = false
        }
    }

    /// Main window, settings and „Über Plattenregal“ – not the search panel,
    /// the record's own window in the menu bar or alerts.
    private static func isAppWindow(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.titled) && !(window is NSPanel)
    }

    /// On screen or in the Dock.
    private static func isOpen(_ window: NSWindow) -> Bool {
        isAppWindow(window) && (window.isVisible || window.isMiniaturized)
    }

    /// The launch was the login item's (see `LoginItem`): macOS says so in
    /// the open event. Read in `applicationDidFinishLaunching`.
    static var launchedAsLoginItem: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--simulate-login-launch") { return true }
        #endif
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == kCoreEventClass, event.eventID == kAEOpenApplication else { return false }
        return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}

/// What a quit request does, apart from AppKit so it can be tested.
nonisolated enum QuitDecision: Equatable {
    case quit, background

    /// `completely`: the record's menu or ⌥⌘Q. `quitEvent`: macOS or another
    /// app asked (Dock, Activity Monitor, a script); `systemQuit`: for logout,
    /// restart or shutdown. Without a quit event the app itself asked – a
    /// relaunch for the demo or the language –, and that always quits.
    /// Already in the background there is nothing left to hide: a request
    /// from outside then quits (Activity Monitor, an installer, the Finder
    /// replacing the app).
    static func decide(keepsRunning: Bool, completely: Bool, quitEvent: Bool, systemQuit: Bool, inBackground: Bool) -> QuitDecision {
        guard keepsRunning, !completely, !systemQuit, !inBackground, quitEvent else { return .quit }
        return .background
    }
}

/// „Bei der Anmeldung öffnen“: Plattenregal itself as a login item
/// (`SMAppService.mainApp`, no helper app). macOS keeps the switch –
/// it can also be changed under Systemeinstellungen → Allgemein →
/// Anmeldeobjekte –, so the status is read from there, never stored.
@Observable final class LoginItem {
    static let shared = LoginItem()

    private(set) var status = SMAppService.mainApp.status
    /// The last change macOS refused, for the hint in the settings.
    private(set) var failed = false

    var isOn: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            failed = false
            AppLog.info("App", on ? "Bei der Anmeldung öffnen: an" : "Bei der Anmeldung öffnen: aus")
        } catch {
            failed = true
            AppLog.error("App", "Anmeldeobjekt \(on ? "nicht eingetragen" : "nicht entfernt"): \(error)")
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
