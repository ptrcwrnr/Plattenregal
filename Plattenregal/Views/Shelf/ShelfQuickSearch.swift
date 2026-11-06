import AppKit
import SwiftData
import SwiftUI

// MARK: - Search

/// The search behind the record in the menu bar: the same matches as the
/// shelf page's search (`KallaxView.applySearch`), fewer of them, and the
/// one under the arrow keys or the pointer with its place in the rack.
@Observable final class ShelfQuickSearchModel {
    /// Fewer than on the shelf page: the panel also shows the rack.
    static let placedLimit = 6
    static let unplacedLimit = 3

    var text = "" { didSet { if text != oldValue { search() } } }
    private(set) var results = ShelfSearchResults()
    private(set) var labels = ShelfLabels()
    /// The match the rack below the list shows.
    private(set) var highlighted: UUID?
    /// The match held by a click (or ↩): the pointer passing over other rows
    /// no longer moves the rack, so it can stay open while one looks for the
    /// record at the shelf. The arrow keys take the hold along.
    private(set) var pinned: UUID?
    /// Bumped once the panel is on screen: the field takes the cursor then
    /// (a focus set while the panel is hidden doesn't stick).
    private(set) var focusRequests = 0

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var index = SearchIndex<UUID>()
    /// Library and tracklists the index was built from, and how many records.
    @ObservationIgnored private var indexState: (library: Int, tracks: Int, count: Int)?
    @ObservationIgnored private let labelsCache = ShelfLabelsCache()
    /// The data state and label style `labels` were made for; they are only
    /// made again when one changes, not on every keystroke.
    @ObservationIgnored private var labelsState: [Int]?
    /// The place last worked out, for this record in this data state: the
    /// view asks on every redraw (the pointer moving over the list), and
    /// for a record without a shelf it walks every placed record.
    @ObservationIgnored private var placeCache: (key: [AnyHashable], place: QuickSearchPlace?)?
    /// Records per compartment for "Pos. x von y", in the data state they
    /// were counted in: every row and the rack ask on every redraw (the
    /// pointer, the arrow keys, each keystroke), and counting reads every
    /// record of the compartment.
    @ObservationIgnored private var recordCounts: (state: [Int], counts: [PersistentIdentifier: Int])?

    init(context: ModelContext) { self.context = context }

    private var records: LibraryRecords { .of(context) }

    /// The matches still in the store. A sync or a reset can delete one
    /// while the panel shows it, and the view may draw before `refresh`
    /// runs – reading a deleted record crashes (same check as the shelf page).
    var placed: [RecordCopy] { results.placed.filter(Self.exists) }
    var unplaced: [RecordCopy] { results.unplaced.filter(Self.exists) }
    private static func exists(_ copy: RecordCopy) -> Bool { !copy.isDeleted && copy.modelContext != nil }

    /// Placed matches first, then those without a shelf: the order of the
    /// list and of the arrow keys.
    var matches: [RecordCopy] { placed + unplaced }
    var highlightedCopy: RecordCopy? { matches.first { $0.id == highlighted } ?? matches.first }

    func requestFocus() { focusRequests += 1 }

    /// A fresh start each time the panel opens (not when it is opened again
    /// while still closing, see `ShelfQuickSearch.open`).
    func reset() {
        text = ""
        results = ShelfSearchResults()
        highlighted = nil
        pinned = nil
    }

    /// Up or down the list, stopping at both ends. A held match moves along.
    func move(_ offset: Int) {
        let matches = matches
        guard !matches.isEmpty else { return }
        let current = matches.firstIndex { $0.id == highlightedCopy?.id } ?? 0
        highlighted = matches[min(max(current + offset, 0), matches.count - 1)].id
        if pinned != nil { pinned = highlighted }
    }

    /// The pointer over a row picks it, like the arrow keys – unless a
    /// match is held.
    func hover(_ copy: RecordCopy) {
        // The same row again changes nothing: no redraw of the whole panel.
        guard pinned == nil, highlighted != copy.id else { return }
        highlighted = copy.id
    }

    /// A click on a row (or ↩ on the highlighted one) holds it; again on
    /// the held one lets go. Nothing opens the main window from here.
    func togglePin(_ copy: RecordCopy) {
        if pinned == copy.id {
            pinned = nil
        } else {
            pinned = copy.id
            highlighted = copy.id
        }
    }

    /// The records changed while the panel is open (a sync, a record
    /// sorted in or deleted): the matches are found again, so none points
    /// at a deleted record – reading one crashes. The index keeps itself
    /// up to date (`indexState`); places aren't part of it.
    func refresh() {
        search()
    }

    /// Changes with every write that can add, move or rename records,
    /// compartments or cabinets.
    var dataState: [Int] {
        let changes = LibraryChanges.shared
        return [changes.libraryVersion, changes.placementsVersion, changes.shelvesVersion, records.copies.count]
    }

    private func search() {
        let words = SearchIndex<UUID>.words(text)
        guard !words.isEmpty else { results = ShelfSearchResults(); highlighted = nil; pinned = nil; return }
        let records = records
        let copies = records.copies
        let changes = LibraryChanges.shared
        let state = (changes.libraryVersion, changes.tracksVersion, copies.count)
        if indexState.map({ $0 != state }) ?? true {
            index = SearchIndex(copies, id: \.id, text: SortingService.searchText)
            indexState = state
        }
        let excluded = Set(records.exclusions.map(\.copyID))
        let owner = DiscogsAccount.current(in: records.accounts)?.username
        var placed: [RecordCopy] = [], unplaced: [RecordCopy] = []
        for copy in copies where !copy.isDeleted && index.matches(copy.id, words) {
            // Same rules as the shelf page: put-away cabinets stay out, and
            // only records that may be sorted in are offered for it.
            if let shelf = copy.shelf { if shelf.isInUse { placed.append(copy) } }
            else if ShelfAssignmentPresentation.isCandidate(copy, owner: owner, excluding: excluded) { unplaced.append(copy) }
        }
        let shownPlaced = SortingService.first(Self.placedLimit, of: placed)
        let shownUnplaced = SortingService.first(Self.unplacedLimit, of: unplaced)
        results = ShelfSearchResults(
            placed: shownPlaced,
            unplaced: shownUnplaced,
            hidden: placed.count - shownPlaced.count + unplaced.count - shownUnplaced.count
        )
        let style = ShelfRangeLabels.currentStyle
        let labelsFor = dataState + [style == .range ? 0 : 1]
        if !matches.isEmpty && labelsState != labelsFor {
            labels = labelsCache.labels(for: records.shelves, style: style)
            labelsState = labelsFor
        }
        // A held match that no longer matches (or was deleted) lets go.
        if let pinned, !matches.contains(where: { $0.id == pinned }) { self.pinned = nil }
        if let pinned { highlighted = pinned }
        if !matches.contains(where: { $0.id == highlighted }) { highlighted = matches.first?.id }
    }

    /// `Shelf.recordCount()`, counted once per data state.
    func recordCount(in shelf: Shelf) -> Int {
        let state = dataState
        if recordCounts?.state != state { recordCounts = (state, [:]) }
        let key = shelf.persistentModelID
        if let count = recordCounts?.counts[key] { return count }
        let count = shelf.recordCount()
        recordCounts?.counts[key] = count
        return count
    }

    /// Where the highlighted match stands – or, without a shelf, where it
    /// belongs alphabetically.
    func place(of copy: RecordCopy) -> QuickSearchPlace? {
        guard Self.exists(copy) else { return nil }
        let key: [AnyHashable] = [copy.id, ShelfSecondaryOrder.current.rawValue] + dataState.map(AnyHashable.init)
        if let placeCache, placeCache.key == key { return placeCache.place }
        let place = findPlace(of: copy)
        placeCache = (key, place)
        return place
    }

    private func findPlace(of copy: RecordCopy) -> QuickSearchPlace? {
        if let shelf = copy.shelf {
            guard shelf.isInUse, let cabinet = shelf.cabinet else { return nil }
            return QuickSearchPlace(cabinet: cabinet, shelf: shelf, position: copy.positionInShelf, placed: true)
        }
        let placement = Placement(copy: copy, shelves: Shelf.inUse(records.shelves))
        guard let spot = placement.spot, let cabinet = spot.shelf.cabinet else { return nil }
        return QuickSearchPlace(cabinet: cabinet, shelf: spot.shelf, position: spot.position, placed: false)
    }

    var cabinetCount: Int { records.cabinets.filter(\.isActive).count }
}

struct QuickSearchPlace {
    let cabinet: Cabinet
    let shelf: Shelf
    let position: Int
    /// Standing there (`true`) or belonging there.
    let placed: Bool
}

// MARK: - Menu bar and panel

/// The record in the menu bar and the panel it opens, also from anywhere
/// with ⌥ Leertaste. AppKit here because SwiftUI's `MenuBarExtra` can't be
/// opened from code (the shortcut) and its window would bring the app with
/// its main window to the front: the panel takes the keyboard without
/// activating Plattenregal, like Spotlight.
@Observable final class ShelfQuickSearch: NSObject, NSWindowDelegate {
    static let shared = ShelfQuickSearch()
    /// Identifies the panel (`DebugSnapshot`).
    static let windowID = "quickSearch"

    /// macOS refused ⌥ Leertaste. It does not refuse a combination another
    /// app (or a second Plattenregal) holds too – both register, and only
    /// the one that registered first receives it (tried 30.10.2026).
    private(set) var hotKeyRefused = false
    /// A record picked in the widget „Platte des Tages“, for the main window:
    /// it opens the shelf page with the card for it (see `RootView`).
    var pendingCopy: UUID?
    /// The record is in the menu bar (switched on, the store is open) – the
    /// condition for running in the background (`AppLifecycle`).
    private(set) var showsStatusItem = false
    /// Opens the main window when it was closed; set by the windows' content (`ReleasedInBackground`).
    @ObservationIgnored var openMainWindow: (() -> Void)?

    /// The store to search; set at launch (see `PlattenregalApp`). Without
    /// one (the database couldn't be opened) the search stays off.
    @ObservationIgnored var container: ModelContainer?
    @ObservationIgnored private var model: ShelfQuickSearchModel?
    @ObservationIgnored private var statusItem: NSStatusItem?
    @ObservationIgnored private var panel: QuickSearchPanel?
    @ObservationIgnored private var hotKey: GlobalHotKey?
    /// Whether the search is shown or faded out (see `QuickSearchPresence`).
    @ObservationIgnored private let presence = QuickSearchPresence()
    /// Open, or opening. The panel stays on screen a moment after closing,
    /// while the search fades out.
    @ObservationIgnored private var isOpen = false
    /// Counts the openings: a close that ends after the panel was opened
    /// again leaves it on screen.
    @ObservationIgnored private var presentation = 0
    /// When the panel last closed because something else was clicked: a
    /// click on the record closes it that way first and must not reopen it.
    @ObservationIgnored private var closedAt = Date.distantPast
    /// The screen the panel opened on; it stays there while its height
    /// changes, wherever the pointer goes meanwhile.
    @ObservationIgnored private var openScreen: NSScreen?

    /// Called once the app has finished launching (see `AppDelegate`).
    func start() {
        guard let container else { return }
        model = ShelfQuickSearchModel(context: container.mainContext)
        applySettings()
        #if DEBUG
        if let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--preview-quicksearch=") }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
                open()
                model?.text = String(raw.dropFirst("--preview-quicksearch=".count))
                pressPreviewKeys()
            }
        }
        #endif
    }

    /// Shows or hides the record and registers or frees the shortcut, as set
    /// under Einstellungen → Allgemein.
    func applySettings() {
        guard container != nil else { return }
        let preferences = AppPreferences.shared
        if preferences.menuBarSearch, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            // Keeps the place the user ⌘-dragged it to. macOS stores it in
            // the standard defaults, which the demo shares with the real app:
            // a name of its own, like the main window (`DemoMode.mainWindowID`).
            item.autosaveName = "Plattenregal.quickSearch." + DemoMode.mainWindowID
            item.button?.image = RecordGlyph.menuBarImage
            item.button?.target = self
            item.button?.action = #selector(statusItemClicked)
            // Right-click (or ⌃-click) opens the menu with „Beenden“.
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            statusItem = item
        } else if !preferences.menuBarSearch, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        if showsStatusItem != (statusItem != nil) { showsStatusItem = statusItem != nil }
        if preferences.quickSearchHotKey && Self.mayRegisterHotKey {
            if hotKey == nil {
                let key = GlobalHotKey.quickSearch
                hotKey = GlobalHotKey(keyCode: key.keyCode, modifiers: key.modifiers) { [weak self] in self?.toggle() }
            }
            let registered = hotKey?.register() ?? false
            if !registered && !hotKeyRefused { AppLog.info("Menüleiste", "macOS hat ⌥ Leertaste nicht angenommen, Kürzel aus") }
            hotKeyRefused = !registered
        } else {
            hotKey?.unregister()
            hotKey = nil
            hotKeyRefused = false
        }
        // Names the shortcut only while it works.
        let title = String(localized: "Im Regal suchen")
        statusItem?.button?.toolTip = hotKey?.isRegistered == true ? AppShortcuts.help(title, keys: GlobalHotKey.quickSearch.title) : title
    }

    /// Screenshot runs (`--snapshot`) leave the shortcut to a running app.
    private static var mayRegisterHotKey: Bool {
        #if DEBUG
        !ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--snapshot=") }
        #else
        true
        #endif
    }

    @objc private func statusItemClicked() {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
            return
        }
        guard Date.now.timeIntervalSince(closedAt) > 0.3 else { return }
        toggle()
    }

    /// The record's menu: the search, the main window and quitting – the one
    /// way to quit while the app runs in the background. Quitting here always
    /// quits completely; the settings are in the main window (⌘,).
    private func showMenu() {
        guard let statusItem else { return }
        close()
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        add(String(localized: "Im Regal suchen"), #selector(menuSearch))
        menu.addItem(.separator())
        add(String(localized: "Plattenregal öffnen"), #selector(menuOpenMainWindow))
        // Found by the automatic check while running here in the background.
        if let release = UpdateChecker.shared.announcedRelease {
            add(String(localized: "Plattenregal \(release.version.description) ist da …"), #selector(menuShowUpdate))
        }
        menu.addItem(.separator())
        add(String(localized: "Plattenregal beenden"), #selector(menuQuit))
        // Attached for this one click only: a left click keeps opening the search.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // After the menu has closed, so the panel can take the keyboard.
    @objc private func menuSearch() { DispatchQueue.main.async { self.open() } }
    @objc private func menuOpenMainWindow() { showMainWindow() }
    @objc private func menuQuit() { AppLifecycle.shared.quitCompletely() }
    @objc private func menuShowUpdate() { UpdateChecker.shared.showAvailableRelease() }

    #if DEBUG
    /// --preview-quicksearch-keys=down,up,return: presses these keys in the
    /// panel, through the window like real ones (no accessibility permission
    /// needed inside the app), half a second apart. Also `escape`, `toggle`
    /// (as the record or ⌥ Leertaste would), `type:abc` (types letters),
    /// `closemain` / `minimizemain` (the main window closed or in the Dock),
    /// `menubar` / `hotkey` / `background` (switch the settings), `quit` (⌘Q),
    /// `quitall` (the record's „Plattenregal beenden“), `openmain` (the
    /// record's menu), `loginon` / `loginoff` („Bei der Anmeldung öffnen“),
    /// `wait` (nothing) and `dumpwindows` (writes the state and every window
    /// to the protocol, category „Prüfung“).
    private func pressPreviewKeys() {
        guard let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--preview-quicksearch-keys=") }) else { return }
        let keys = raw.dropFirst("--preview-quicksearch-keys=".count).split(separator: ",")
        for (index, key) in keys.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 * Double(index + 1)) { [weak self] in
                guard let self else { return }
                if key == "toggle" { toggle(); return }
                // Switches the setting as Einstellungen → Allgemein would.
                if key == "menubar" { AppPreferences.shared.menuBarSearch.toggle(); return }
                if key == "hotkey" { AppPreferences.shared.quickSearchHotKey.toggle(); return }
                if key == "background" { AppPreferences.shared.keepsRunningInBackground.toggle(); return }
                if key == "quit" { AppLifecycle.shared.quitRequested(); return }
                if key == "quitall" { menuQuit(); return }
                if key == "openmain" { menuOpenMainWindow(); return }
                if key == "loginon" || key == "loginoff" {
                    LoginItem.shared.set(key == "loginon")
                    AppLog.info("Prüfung", "Anmeldeobjekt: Status \(LoginItem.shared.status.rawValue), an \(LoginItem.shared.isOn), abgelehnt \(LoginItem.shared.failed)")
                    return
                }
                if key == "dumpwindows" {
                    AppLog.info("Prüfung", "Prozess \(ProcessInfo.processInfo.processIdentifier) Symbol \(statusItem != nil), Kürzel registriert \(hotKey?.isRegistered == true), abgelehnt \(hotKeyRefused), Tooltip „\(statusItem?.button?.toolTip ?? "–")“, Hintergrund \(AppLifecycle.shared.isInBackground), Dock \(NSApp.activationPolicy() == .regular), aktiv \(NSApp.isActive)")
                    for window in NSApp.windows {
                        AppLog.info("Prüfung", "Prozess \(ProcessInfo.processInfo.processIdentifier) Fenster \(window.identifier?.rawValue ?? "–") \(type(of: window)) sichtbar \(window.isVisible) im Dock \(window.isMiniaturized) main \(window.canBecomeMain)")
                    }
                    return
                }
                // The main window closed or in the Dock, for the record's menu („Plattenregal öffnen“) from there.
                if key == "closemain" || key == "minimizemain" {
                    let main = NSApp.windows.first { $0.identifier?.rawValue == DemoMode.mainWindowID && $0.isVisible }
                    if key == "closemain" { main?.performClose(nil) } else { main?.miniaturize(nil) }
                    return
                }
                guard let panel, panel.isVisible else { return }
                let (code, characters): (UInt16, String) = switch key {
                case "down": (125, String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)))
                case "up": (126, String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)))
                case "escape": (53, "\u{1B}")
                case "return": (36, "\r")
                case let typed where typed.hasPrefix("type:"): (0, String(typed.dropFirst("type:".count)))
                default: (0, "")
                }
                guard !characters.isEmpty else { return }
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                    windowNumber: panel.windowNumber, context: nil, characters: characters,
                                                    charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) {
                        panel.sendEvent(event)
                    }
                }
            }
        }
    }
    #endif

    func toggle() {
        if isOpen { close() } else { open() }
    }

    /// Settles in: the search fades in while it comes down a few points
    /// and grows to its full size, like a page after a switch. With
    /// "Bewegung reduzieren" it only fades in. See `QuickSearchPresence`.
    func open() {
        guard let container, let model else { return }
        isOpen = true
        presentation += 1
        let panel = panel ?? makePanel(container: container, model: model)
        self.panel = panel
        // Fully closed: a fresh start, faded out. Opened again while it is
        // still fading out, it comes back from there, as it was: an emptied
        // field would shrink the panel while it moves.
        if !panel.isVisible {
            model.reset()
            presence.shown = false
        }
        // The screen with the pointer – also the record's, when it was clicked.
        openScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        position(panel, height: panel.frame.height)
        // Modern: the chosen look's appearance (dark for dark glass, light
        // for light glass and white), in light and dark mode alike, so
        // field, labels and rack match the surface. Klassisch: the app's
        // appearance. On every opening, as the design or look may have changed.
        panel.appearance = AppStyle.isAtelier ? nil : AppPreferences.shared.quickSearchLook.appearance
        panel.makeKeyAndOrderFront(nil)
        // Once the faded-out search is on screen, so it settles in from there.
        DispatchQueue.main.async { [self] in
            guard isOpen else { return }
            withAnimation(AppStyle.quickSearchInAnimation) { presence.shown = true }
            model.requestFocus()
        }
    }

    /// Fades out quickly, a little back up and smaller; only then the panel
    /// goes. A close that ends after the search was opened again leaves it.
    func close() {
        guard isOpen, let panel else { return }
        isOpen = false
        // Typing no longer goes into the fading field.
        panel.makeFirstResponder(nil)
        guard panel.isVisible else { return }
        let closing = presentation
        withAnimation(AppStyle.pageOutAnimation) {
            presence.shown = false
        } completion: { [weak self, weak panel] in
            guard let self, presentation == closing else { return }
            panel?.orderOut(nil)
        }
    }

    /// Closes the panel and shows the record in the main window, on the
    /// shelf page with the card "Hier steht …" or "Einsortieren …" – for the
    /// widget, and for a click in the search when set so (`QuickSearchClick`).
    func showInShelf(_ copy: RecordCopy) {
        close()
        pendingCopy = copy.id
        showMainWindow()
    }

    /// A click on a match or ↩, as set under Einstellungen → Allgemein →
    /// Menüleiste. Without a Discogs page (the demo's sample records) the
    /// match is held instead.
    func choose(_ copy: RecordCopy) {
        switch AppPreferences.shared.quickSearchClick {
        case .hold:
            model?.togglePin(copy)
        case .showInApp:
            showInShelf(copy)
        case .discogs:
            guard let url = copy.release?.sourceURL else { model?.togglePin(copy); return }
            close()
            NSWorkspace.shared.open(url)
        }
    }

    /// The main window in front, from the Dock or anew when it was closed –
    /// also out of the background, with the Dock icon back.
    func showMainWindow() {
        AppLifecycle.shared.leaveBackground()
        NSApp.activate()
        // Only a window on screen or in the Dock: a closed one may linger in
        // the list without its content, `openWindow` builds it anew. Not by
        // `canBecomeMain` – a window in the Dock answers false there, and
        // `openWindow` leaves it in the Dock.
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == DemoMode.mainWindowID && ($0.isVisible || $0.isMiniaturized) }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else if let openMainWindow {
            AppLog.info("Menüleiste", "Hauptfenster neu geöffnet")
            openMainWindow()
        } else {
            AppLog.error("Menüleiste", "Hauptfenster ließ sich nicht öffnen")
        }
    }

    private func makePanel(container: ModelContainer, model: ShelfQuickSearchModel) -> QuickSearchPanel {
        let panel = QuickSearchPanel()
        panel.identifier = NSUserInterfaceItemIdentifier(Self.windowID)
        panel.delegate = self
        let view = ShelfQuickSearchView(model: model, presence: presence, close: { [weak self] in self?.close() },
                                        choose: { [weak self] copy in self?.choose(copy) },
                                        resize: { [weak self, weak panel] height in
                                            guard let self, let panel else { return }
                                            position(panel, height: height)
                                        })
            .appPageEnvironment(container.mainContext)
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        panel.contentView = hosting
        return panel
    }

    /// At the top of the screen with the pointer, a little below the menu
    /// bar, its top edge fixed while the list grows (`QuickSearchPosition`):
    /// centred on the whole screen – on a MacBook right under the notch,
    /// which sits in the middle whatever the Dock does – or in the top right
    /// corner, as far from the right edge as from the menu bar.
    private func position(_ panel: NSPanel, height: CGFloat) {
        guard let screen = openScreen ?? NSScreen.main else { return }
        let room = QuickSearchPanel.shadowRoom
        let corner = Self.surfaceCorner(width: AppStyle.quickSearchWidth, screen: screen.frame, visible: screen.visibleFrame,
                                        position: AppPreferences.shared.quickSearchPosition)
        // The shadow room around the surface is transparent.
        let top = corner.y + room
        panel.setFrame(NSRect(x: corner.x - room, y: top - height, width: AppStyle.quickSearchWidth + 2 * room, height: height),
                       display: true)
    }

    /// The top left corner of the surface itself (without the shadow room),
    /// in screen coordinates: `tightSpacing` below the menu bar and, in the
    /// top right corner, as far from the edge. Apart from the panel for the tests.
    static func surfaceCorner(width: CGFloat, screen: CGRect, visible: CGRect, position: QuickSearchPosition) -> CGPoint {
        let gap = AppStyle.tightSpacing
        let x = switch position {
        case .center: min(max(screen.midX - width / 2, visible.minX + gap), visible.maxX - width - gap)
        // The visible area's edge: a Dock on the right stays clear.
        case .topRight: visible.maxX - width - gap
        }
        return CGPoint(x: x, y: visible.maxY - gap)
    }

    // A click anywhere else closes it, like a menu.
    func windowDidResignKey(_ notification: Notification) {
        guard isOpen else { return }
        closedAt = .now
        close()
    }
}

/// Takes the keyboard without activating the app, floats above other
/// windows and on every space; the SwiftUI content draws its surface.
final class QuickSearchPanel: NSPanel {
    /// Transparent room around the surface for its shadow.
    static let shadowRoom = AppStyle.sectionSpacing

    init() {
        // Placed and sized on opening (`ShelfQuickSearch.position`), then follows its content.
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Panel content

/// Whether the search panel shows its search or has faded it out. Set by
/// `ShelfQuickSearch.open` and `close` in their animations, drawn by
/// `ShelfQuickSearchView`.
@Observable final class QuickSearchPresence {
    var shown = false
}

/// Search field, the matches, and the rack with the place of the
/// highlighted one. ↑ ↓ or the pointer pick; a click or ↩ does what is set
/// (`QuickSearchClick`): hold the pick (again: let go), show it in the app
/// or open it on Discogs. Esc clears the field and then closes.
struct ShelfQuickSearchView: View {
    @Bindable var model: ShelfQuickSearchModel
    let presence: QuickSearchPresence
    let close: () -> Void
    /// A click on a match or ↩ on the highlighted one (`QuickSearchClick`).
    let choose: (RecordCopy) -> Void
    /// The panel follows the content's height.
    let resize: (CGFloat) -> Void
    @FocusState private var focused: Bool
    @AppStorage(DisplaySettings.missingListKey) private var missingEnabled = true
    @Environment(\.modelContext) private var context

    /// Records marked "Gesucht"; none while that list is switched off.
    private var missing: Set<UUID> {
        missingEnabled ? Set(LibraryRecords.of(context).missingMarks.map(\.copyID)) : []
    }

    var body: some View {
        // Once per redraw, not per row.
        let highlighted = model.highlightedCopy
        VStack(alignment: .leading, spacing: 0) {
            field
            if !SearchIndex<UUID>.words(model.text).isEmpty {
                Divider()
                results(highlighted: highlighted?.id)
                if let copy = highlighted, let place = model.place(of: copy) {
                    Divider()
                    QuickSearchRack(place: place, labels: model.labels, showsCabinet: model.cabinetCount > 1,
                                    recordCount: model.recordCount(in: place.shelf))
                        .padding(AppStyle.cardPadding)
                }
            }
        }
        .frame(width: AppStyle.quickSearchWidth)
        .searchPanelSurface(desktop: AppPreferences.shared.quickSearchLook)
        // Faded out: a few points higher and a little smaller, so it
        // settles in as it fades in (only the fade with "Bewegung reduzieren").
        .scaleEffect(presence.shown || AppStyle.reduceMotion ? 1 : AppStyle.quickSearchSettleScale, anchor: .top)
        .offset(y: presence.shown || AppStyle.reduceMotion ? 0 : -AppStyle.pageSettleDistance)
        .opacity(presence.shown ? 1 : 0)
        .allowsHitTesting(presence.shown)
        .padding(QuickSearchPanel.shadowRoom)
        // Its own height, whatever the panel's is; the panel follows it.
        .fixedSize()
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { resize($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { focused = true }
        .onChange(of: model.focusRequests) { focused = true }
        .onChange(of: model.dataState) { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .plattenregalDidReset)) { _ in model.reset() }
    }

    private var field: some View {
        HStack(spacing: AppStyle.itemSpacing) {
            Image(systemName: "magnifyingglass").foregroundStyle(SearchPanelInk.muted)
            TextField("Im Regal suchen", text: $model.text, prompt: Text("Im Regal suchen"))
                .textFieldStyle(.plain).noTextAutoFill()
                .font(AppStyle.searchFieldFont)
                .focused($focused)
                .onKeyPress(.downArrow) { model.move(1); return .handled }
                .onKeyPress(.upArrow) { model.move(-1); return .handled }
                .onSubmit { if let copy = model.highlightedCopy { choose(copy) } }
                .onKeyPress(.escape) {
                    if model.text.isEmpty { close() } else { model.text = "" }
                    return .handled
                }
            if !model.text.isEmpty {
                Button { model.text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(SearchPanelInk.muted)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Suche löschen"))
                .accessibilityLabel(String(localized: "Suche löschen"))
            }
        }
        .padding(.horizontal, AppStyle.cardPadding)
        .padding(.vertical, AppStyle.rowSpacing)
    }

    @ViewBuilder private func results(highlighted: UUID?) -> some View {
        let placed = model.placed, unplaced = model.unplaced
        let missing = missing
        let pinned = model.pinned
        if placed.isEmpty && unplaced.isEmpty {
            Text("Keine Treffer im Regal.")
                .font(.callout)
                .foregroundStyle(SearchPanelInk.muted)
                .padding(.horizontal, AppStyle.cardPadding)
                .padding(.vertical, AppStyle.rowSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(placed) { row($0, placeable: false, missing: missing, highlighted: highlighted, pinned: pinned) }
                if !unplaced.isEmpty {
                    ShelfSearchUnplacedTitle(first: placed.isEmpty)
                    ForEach(unplaced) { row($0, placeable: true, missing: missing, highlighted: highlighted, pinned: pinned) }
                }
                if model.results.hidden > 0 { ShelfSearchMoreNote(hidden: model.results.hidden) }
            }
            .padding(AppStyle.itemSpacing)
        }
    }

    private func row(_ copy: RecordCopy, placeable: Bool, missing: Set<UUID>, highlighted: UUID?, pinned: UUID?) -> some View {
        let isPinned = pinned == copy.id
        return Button { choose(copy) } label: {
            SearchResultRow(copy: copy, labels: model.labels, missing: missing.contains(copy.id),
                            placeable: placeable, highlighted: highlighted == copy.id, pinned: isPinned,
                            shelfCount: copy.shelf.map(model.recordCount(in:)))
        }
        .buttonStyle(.plain)
        // The pointer picks the match the rack shows, like the arrow keys –
        // unless a click holds one.
        .onHover { if $0 { model.hover(copy) } }
        .help(AppPreferences.shared.quickSearchClick.help(pinned: isPinned))
        .accessibilityAddTraits(isPinned ? .isSelected : [])
    }
}

/// The cabinet of the highlighted match in small: its compartments with
/// their labels, the one it stands in (or belongs in) marked like the
/// selected compartment on the shelf page. Above it, in words, where.
struct QuickSearchRack: View {
    let place: QuickSearchPlace
    let labels: ShelfLabels
    /// The cabinet's name only matters with more than one.
    let showsCabinet: Bool
    /// The records standing in the compartment (`Shelf.recordCount`).
    let recordCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyle.itemSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: AppStyle.itemSpacing) {
                Text(place.placed ? String(localized: "Steht in") : String(localized: "Gehört in"))
                    .font(AppStyle.captionLabel).foregroundStyle(SearchPanelInk.muted)
                Text(location).font(AppStyle.captionMark).foregroundStyle(SearchPanelInk.ink)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            grid
        }
    }

    private var shelfName: String {
        place.shelf.isReserved ? place.shelf.title : labels[place.shelf.id] ?? place.shelf.numberText
    }

    private var location: String {
        // Out of how many: a record that only belongs there would be one more.
        let position = place.shelf.positionText(place.position, joining: !place.placed, count: recordCount)
        let shelf = String(localized: "Fach „\(shelfName)“ · \(position)")
        return showsCabinet ? "\(place.cabinet.name) · \(shelf)" : shelf
    }

    private var grid: some View {
        let cabinet = place.cabinet
        // A compartment deleted meanwhile (a reset not reported yet) must
        // not be read: SwiftData traps on deleted objects.
        let shelves = Dictionary(cabinet.shelves.filter { !$0.isDeleted }.map { ("\($0.row)-\($0.column)", $0) }) { a, _ in a }
        return Grid(horizontalSpacing: AppStyle.tightSpacing, verticalSpacing: AppStyle.tightSpacing) {
            ForEach(1...max(cabinet.rows, 1), id: \.self) { row in
                GridRow {
                    ForEach(1...max(cabinet.columns, 1), id: \.self) { column in
                        cell(shelves["\(row)-\(column)"])
                    }
                }
            }
        }
        .padding(AppStyle.tightSpacing)
        .background(SearchPanelRack.body, in: RoundedRectangle(cornerRadius: AppStyle.rowRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(location)
    }

    private func cell(_ shelf: Shelf?) -> some View {
        let marked = shelf?.id == place.shelf.id
        let locked = shelf?.isReserved == true
        let shape = RoundedRectangle(cornerRadius: AppStyle.menuRowRadius)
        // A locked compartment by its name ("Deko"), as on the shelf page.
        return Text(shelf.map { $0.isReserved ? $0.name : labels[$0.id] ?? "" } ?? "")
            .font(AppStyle.badge)
            .foregroundStyle(marked ? SearchPanelInk.ink : SearchPanelInk.muted)
            .lineLimit(1).minimumScaleFactor(0.7)
            .padding(.horizontal, AppStyle.hairSpacing)
            .frame(maxWidth: .infinity, minHeight: AppStyle.smallControlHeight)
            // A locked compartment stays an empty well in the body's tone.
            .background(marked ? AppStyle.selectedBackground : locked ? SearchPanelRack.body : SearchPanelRack.cell, in: shape)
            .overlay(shape.strokeBorder(marked ? AppStyle.selectedBorder : .clear, lineWidth: AppStyle.selectionLineWidth))
    }
}

/// Surfaces of the small rack, like `ShelfFurniture` keeps its own: the
/// body slightly darker than the panel, the compartments lighter.
private enum SearchPanelRack {
    static var body: Color { AppStyle.isAtelier ? AtelierPalette.ink.opacity(0.06) : Color.primary.opacity(0.06) }
    static var cell: Color { AppStyle.isAtelier ? AtelierPalette.surface : Color.primary.opacity(0.05) }
}
