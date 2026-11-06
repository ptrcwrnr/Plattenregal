import Foundation
import Testing
@testable import Plattenregal

extension AllTests {
    @MainActor struct SettingsTests {
        /// Own settings per test under a fixed name, emptied before and after.
        /// macOS keeps an empty `<suite>.plist` even after
        /// `removePersistentDomain` (and writes it again if deleted right
        /// away); with a new random name per run they had piled up to
        /// hundreds in the app's container. A fixed name leaves one per test.
        private func withSignatureDefaults(test: String = #function, _ check: (UserDefaults) throws -> Void) throws {
            let suite = "SignatureDesignTests-\(test.prefix { $0 != "(" })"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defaults.removePersistentDomain(forName: suite)
            defer { defaults.removePersistentDomain(forName: suite) }
            try check(defaults)
        }

        @Test func signatureDesignDefaultsAndUnknownValuesKeepCurrentAppearance() throws {
            try withSignatureDefaults { defaults in
                let preferences = AppPreferences(defaults: defaults)
                #expect(preferences.signatureDesign == .liquidGlass)
                #expect(preferences.appearance == .system)
                #expect(preferences.accent == .system)
                #expect(preferences.ambient == .blue)
                // Loading the default does not migrate or rewrite stored choices.
                #expect(defaults.object(forKey: AppPreferences.Key.signatureDesign) == nil)
                defaults.set("future-design", forKey: AppPreferences.Key.signatureDesign)
                #expect(AppPreferences(defaults: defaults).signatureDesign == .liquidGlass)
                #expect(defaults.string(forKey: AppPreferences.Key.signatureDesign) == "future-design")
            }
        }

        @Test func drawnCoversAreOffByDefaultAndPersist() throws {
            try withSignatureDefaults { defaults in
                let preferences = AppPreferences(defaults: defaults)
                #expect(!preferences.drawnCovers)
                preferences.drawnCovers = true
                #expect(AppPreferences(defaults: defaults).drawnCovers)
                preferences.reset()
                #expect(!AppPreferences(defaults: defaults).drawnCovers)
            }
        }

        /// The search in the menu bar and ⌥ Leertaste: on when nothing is
        /// stored, off when switched off – also from a launch argument
        /// ("-menuBarSearch NO" arrives as text, not as a Bool).
        @Test func menuBarSearchAndShortcutAreOnByDefaultAndPersist() throws {
            try withSignatureDefaults { defaults in
                let preferences = AppPreferences(defaults: defaults)
                #expect(preferences.menuBarSearch)
                #expect(preferences.quickSearchHotKey)
                preferences.menuBarSearch = false
                preferences.quickSearchHotKey = false
                #expect(!AppPreferences(defaults: defaults).menuBarSearch)
                #expect(!AppPreferences(defaults: defaults).quickSearchHotKey)
                preferences.reset()
                #expect(AppPreferences(defaults: defaults).menuBarSearch)
                #expect(AppPreferences(defaults: defaults).quickSearchHotKey)
                defaults.set("NO", forKey: AppPreferences.Key.menuBarSearch)
                defaults.set("YES", forKey: AppPreferences.Key.quickSearchHotKey)
                #expect(!AppPreferences(defaults: defaults).menuBarSearch)
                #expect(AppPreferences(defaults: defaults).quickSearchHotKey)
            }
        }

        /// „Im Hintergrund weiterlaufen“: on when nothing is stored, back on
        /// after a reset, "NO" from a launch argument switches it off.
        @Test func runningInTheBackgroundIsOnByDefaultAndPersists() throws {
            try withSignatureDefaults { defaults in
                let preferences = AppPreferences(defaults: defaults)
                #expect(preferences.keepsRunningInBackground)
                preferences.keepsRunningInBackground = false
                #expect(!AppPreferences(defaults: defaults).keepsRunningInBackground)
                preferences.reset()
                #expect(AppPreferences(defaults: defaults).keepsRunningInBackground)
                defaults.set("NO", forKey: AppPreferences.Key.keepsRunningInBackground)
                #expect(!AppPreferences(defaults: defaults).keepsRunningInBackground)
            }
        }

        /// The look of the search in the menu bar: dark glass unless chosen
        /// otherwise, kept across launches, back to dark glass on reset; an
        /// unknown stored value falls back to it too.
        @Test func quickSearchLookIsDarkGlassByDefaultAndPersists() throws {
            try withSignatureDefaults { defaults in
                let preferences = AppPreferences(defaults: defaults)
                #expect(preferences.quickSearchLook == .darkGlass)
                for look in QuickSearchLook.allCases {
                    preferences.quickSearchLook = look
                    #expect(AppPreferences(defaults: defaults).quickSearchLook == look)
                }
                preferences.reset()
                #expect(AppPreferences(defaults: defaults).quickSearchLook == .darkGlass)
                defaults.set("purple", forKey: AppPreferences.Key.quickSearchLook)
                #expect(AppPreferences(defaults: defaults).quickSearchLook == .darkGlass)
            }
        }

        /// Where the search in the menu bar opens: at the top in the middle
        /// unless chosen otherwise, kept across launches, back on reset; an
        /// unknown stored value – also the former "underRecord" – falls back to it.
        @Test func quickSearchPositionIsInTheMiddleByDefaultAndPersists() throws {
            try withSignatureDefaults { defaults in
                let preferences = AppPreferences(defaults: defaults)
                #expect(preferences.quickSearchPosition == .center)
                #expect(QuickSearchPosition.allCases == [.center, .topRight])
                for position in QuickSearchPosition.allCases {
                    preferences.quickSearchPosition = position
                    #expect(AppPreferences(defaults: defaults).quickSearchPosition == position)
                }
                preferences.reset()
                #expect(AppPreferences(defaults: defaults).quickSearchPosition == .center)
                for stored in ["left", "underRecord"] {
                    defaults.set(stored, forKey: AppPreferences.Key.quickSearchPosition)
                    #expect(AppPreferences(defaults: defaults).quickSearchPosition == .center)
                }
            }
        }

        /// Page names of one's own: at most twelve characters as typed, no
        /// line breaks; shown trimmed, an empty or blank one gives the page
        /// its own name back. Kept across launches, gone on reset.
        @Test func pageNamesAreLimitedTrimmedAndPersist() throws {
            #expect(PageNames.maxLength == 12)
            #expect(PageNames.limited("Meine Sammlung im Wohnzimmer") == "Meine Sammlu")
            #expect(PageNames.limited("Zwei\nZeilen") == "ZweiZeilen")
            #expect(PageNames.limited("Plattenkiste") == "Plattenkiste")
            // Counted as seen: an accented letter or an emoji is one.
            #expect(PageNames.limited("éééééééééééééé").count == 12)
            #expect(PageNames.limited("🎵🎵🎵🎵🎵🎵🎵🎵🎵🎵🎵🎵🎵") == "🎵🎵🎵🎵🎵🎵🎵🎵🎵🎵🎵🎵")
            #expect(PageNames.shown(nil) == nil)
            #expect(PageNames.shown("   ") == nil)
            #expect(PageNames.shown(" Kiste ") == "Kiste")
            #expect(PageNames.shown("Meine Sammlung im Wohnzimmer") == "Meine Sammlu")
            try withSignatureDefaults { defaults in
                let preferences = AppPreferences(defaults: defaults)
                #expect(preferences.pageNames.isEmpty)
                preferences.setPageName("Meine Sammlung im Wohnzimmer", for: .collection)
                preferences.setPageName("Kiste ", for: .shelf)
                let again = AppPreferences(defaults: defaults)
                #expect(again.pageNames == ["Collection": "Meine Sammlu", "Regal": "Kiste "])
                // Emptied: the page has its own name again.
                again.setPageName("", for: .shelf)
                #expect(AppPreferences(defaults: defaults).pageNames == ["Collection": "Meine Sammlu"])
                again.reset()
                #expect(AppPreferences(defaults: defaults).pageNames.isEmpty)
            }
            // The start page names its page the same way as the toolbar.
            #expect(StartPage.allCases.map(\.title) == StartPage.allCases.map(\.destination.title))
        }

        /// A click on a match in the search in the menu bar holds it unless
        /// chosen otherwise; the choice is kept, reset brings the hold back,
        /// an unknown stored value falls back to it.
        @Test func quickSearchClickHoldsByDefaultAndPersists() throws {
            try withSignatureDefaults { defaults in
                let preferences = AppPreferences(defaults: defaults)
                #expect(preferences.quickSearchClick == .hold)
                #expect(QuickSearchClick.allCases == [.hold, .showInApp, .discogs])
                for click in QuickSearchClick.allCases {
                    preferences.quickSearchClick = click
                    #expect(AppPreferences(defaults: defaults).quickSearchClick == click)
                }
                preferences.reset()
                #expect(AppPreferences(defaults: defaults).quickSearchClick == .hold)
                defaults.set("open", forKey: AppPreferences.Key.quickSearchClick)
                #expect(AppPreferences(defaults: defaults).quickSearchClick == .hold)
                // Holding names letting go on a held match; the others never do.
                #expect(QuickSearchClick.hold.help(pinned: true) != QuickSearchClick.hold.help(pinned: false))
                #expect(QuickSearchClick.discogs.help(pinned: true) == QuickSearchClick.discogs.help(pinned: false))
                // Without a Discogs page (the demo) a click holds instead – and says so.
                #expect(QuickSearchClick.discogs.resolved(hasDiscogsPage: false) == .hold)
                #expect(QuickSearchClick.discogs.resolved(hasDiscogsPage: true) == .discogs)
                #expect(QuickSearchClick.showInApp.resolved(hasDiscogsPage: false) == .showInApp)
            }
        }

        /// Dark glass draws the panel dark, light glass and white light – in
        /// light and dark mode alike.
        @Test func quickSearchLookSetsThePanelsAppearance() {
            #expect(QuickSearchLook.darkGlass.appearance?.name == .darkAqua)
            #expect(QuickSearchLook.lightGlass.appearance?.name == .aqua)
            #expect(QuickSearchLook.white.appearance?.name == .aqua)
        }

        /// Only ⌘Q-like requests from outside (Dock, script) go into the
        /// background; logout, „ganz beenden“, the app's own relaunch, a
        /// switched-off setting (or no record in the menu bar) and a request
        /// while already in the background always quit.
        @Test func quitRequestsGoIntoTheBackgroundOnlyWhenTheyMay() {
            func decide(keeps: Bool = true, completely: Bool = false, event: Bool = true, system: Bool = false, background: Bool = false) -> QuitDecision {
                QuitDecision.decide(keepsRunning: keeps, completely: completely, quitEvent: event, systemQuit: system, inBackground: background)
            }
            #expect(decide() == .background)
            #expect(decide(system: true) == .quit)
            #expect(decide(completely: true) == .quit)
            #expect(decide(event: false) == .quit)
            #expect(decide(keeps: false) == .quit)
            #expect(decide(background: true) == .quit)
        }

        @Test func drawnCoversReplaceTheDiscogsImageStably() {
            let release = Release(discogsID: 4711, artist: "Air (2)", title: "Moon Safari")
            release.coverURL = "https://i.discogs.com/cover.jpg"
            #expect(release.shownCoverURL(drawn: false) == "https://i.discogs.com/cover.jpg")
            let drawn = release.shownCoverURL(drawn: true)
            #expect(drawn == release.shownCoverURL(drawn: true))
            let url = drawn.flatMap(URL.init(string:))
            #expect(url?.scheme == DemoCover.scheme)
            // Shown names, without Discogs' "(2)".
            #expect(drawn?.contains("artist=Air&") == true)
            #expect(url.flatMap { DemoCover.render($0, pixelSize: 64) } != nil)
            // A record without a Discogs image gets one too.
            release.coverURL = nil
            #expect(release.shownCoverURL(drawn: true) == drawn)
        }

        @Test func drawnCoverHueStaysInRangeForAnyID() {
            // The demo's seeds keep their colours.
            for seed in [0, 1, 49, 100, 247] { #expect(DemoCover.hueDegrees(seed) == seed * 47 % 360) }
            // Real Discogs IDs and stray values neither overflow nor go negative.
            for seed in [Int.max, Int.min, -1, -359, 36_000_000_123] {
                #expect((0..<360).contains(DemoCover.hueDegrees(seed)))
            }
            let release = Release(discogsID: Int.max, artist: "", title: "")
            let url = release.shownCoverURL(drawn: true).flatMap(URL.init(string:))
            #expect(url.flatMap { DemoCover.render($0, pixelSize: 64) } != nil)
            // Names that need escaping come back unchanged.
            let tricky = Release(discogsID: 7, artist: "Simon & Garfunkel", title: "A=B + C #1 ?/%")
            let items = tricky.shownCoverURL(drawn: true).flatMap(URLComponents.init(string:))?.queryItems ?? []
            #expect(items.first { $0.name == "artist" }?.value == "Simon & Garfunkel")
            #expect(items.first { $0.name == "title" }?.value == "A=B + C #1 ?/%")
        }

        @Test func signatureDesignPersistsAndReloadsInItsOwnSettingsStore() throws {
            try withSignatureDefaults { defaults in
                let preferences = AppPreferences(defaults: defaults)
                preferences.signatureDesign = .atelier
                #expect(defaults.string(forKey: AppPreferences.Key.signatureDesign) == "atelier")
                #expect(AppPreferences(defaults: defaults).signatureDesign == .atelier)
                preferences.signatureDesign = .liquidGlass
                #expect(defaults.string(forKey: AppPreferences.Key.signatureDesign) == "none")
                #expect(AppPreferences(defaults: defaults).signatureDesign == .liquidGlass)
            }
        }

        @Test func choosingAndLeavingKlassischPreservesExistingAppearanceChoices() throws {
            try withSignatureDefaults { defaults in
                defaults.set("shelf", forKey: AppPreferences.Key.startPage)
                defaults.set("dark", forKey: AppPreferences.Key.appearance)
                defaults.set("purple", forKey: AppPreferences.Key.accent)
                defaults.set("yellow", forKey: AppPreferences.Key.ambient)
                let preferences = AppPreferences(defaults: defaults)
                for design in [SignatureDesign.atelier, .liquidGlass] {
                    preferences.signatureDesign = design
                    #expect(preferences.startPage == .shelf)
                    #expect(preferences.appearance == .dark)
                    #expect(preferences.accent == .purple)
                    #expect(preferences.ambient == .yellow)
                    #expect(defaults.string(forKey: AppPreferences.Key.startPage) == "shelf")
                    #expect(defaults.string(forKey: AppPreferences.Key.appearance) == "dark")
                    #expect(defaults.string(forKey: AppPreferences.Key.accent) == "purple")
                    #expect(defaults.string(forKey: AppPreferences.Key.ambient) == "yellow")
                    let reloaded = AppPreferences(defaults: defaults)
                    #expect(reloaded.signatureDesign == design)
                    #expect(reloaded.appearance == .dark)
                    #expect(reloaded.accent == .purple)
                    #expect(reloaded.ambient == .yellow)
                }
            }
        }

        @Test func designsKeepTheirStoredValuesUnderTheNewNames() {
            #expect(SignatureDesign.allCases.map(\.logName) == ["Klassisch", "Modern"])
            // The stored values from before the renaming stay readable.
            #expect(SignatureDesign(rawValue: "none") == .liquidGlass)
            #expect(SignatureDesign(rawValue: "atelier") == .atelier)
        }

        @Test func overviewOrderShufflesStablyAndSortsNewestFirst() {
            let items = Array(1...50)
            let alphabetical: ([Int]) -> [Int] = { $0.sorted() }
            func random(_ items: [Int], _ scope: String = "collection") -> [Int] {
                OverviewOrder.random.apply(items, scope: scope, alphabetical: alphabetical, key: { $0 }, added: { _ in nil })
            }
            let shuffled = random(items)
            // Same order within one launch, all items kept, not just the alphabetical one.
            #expect(shuffled == random(items.reversed()))
            #expect(shuffled.sorted() == items)
            #expect(shuffled != items)
            // Shuffling the wantlist anew leaves the collection's order alone.
            OverviewOrder.reshuffle("wantlist")
            #expect(random(items) == shuffled)
            OverviewOrder.reshuffle("collection")
            #expect(random(items) != shuffled)
            // Back from the background: both pages anew, each stable afterwards.
            let collection = random(items), wantlist = random(items, "wantlist")
            OverviewOrder.reshuffleAll()
            let collectionAfter = random(items), wantlistAfter = random(items, "wantlist")
            #expect(collectionAfter != collection)
            #expect(wantlistAfter != wantlist)
            #expect(random(items) == collectionAfter)
            #expect(random(items, "wantlist") == wantlistAfter)
            // Newest first; undated last, in alphabetical order.
            let date = { (n: Int) -> Date? in n > 3 ? nil : Date(timeIntervalSince1970: Double(n)) }
            #expect(OverviewOrder.recent.apply([5, 1, 4, 3, 2], scope: "collection", alphabetical: alphabetical, key: { $0 }, added: date) == [3, 2, 1, 4, 5])
        }

        @Test func obsoleteSettingsOfEarlierVersionsAreRemovedAndCurrentOnesKept() throws {
            let suite = "LegacyDefaultsTest"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defaults.removePersistentDomain(forName: suite)
            defer { defaults.removePersistentDomain(forName: suite) }
            let obsolete = [
                "NSWindow Frame SwiftUI.WindowGroup<SwiftUI._ConditionalContent<Plattenregal.RootView>>-1-AppWindow-1",
                "NSSplitView Subview Frames SwiftUI.WindowGroup<SwiftUI.ModifiedContent<Plattenregal.RootView>>-1-AppWindow-1, SidebarNavigationSplitView",
                "LibraryStorage.legacyShelfNameMigratedV5",
                "LibraryStorage.legacyShelfNameMigratedV5:file:///tmp/x.store",
                "missingColumnCollapsed",
            ]
            let current = ["NSWindow Frame main", "NSWindow Frame demo", "NSWindow Frame com_apple_SwiftUI_Settings_window",
                           AppPreferences.Key.signatureDesign, ShelfAutoBackup.keptCountKey, "windowBackgroundStyle"]
            for key in obsolete + current { defaults.set("x", forKey: key) }
            #expect(LegacyDefaults.removeObsolete(from: defaults, domain: suite) == obsolete.count)
            let left = try #require(defaults.persistentDomain(forName: suite))
            #expect(Set(left.keys) == Set(current))
            // A second launch finds nothing more.
            #expect(LegacyDefaults.removeObsolete(from: defaults, domain: suite) == 0)
        }

        @Test func inputSourceBubbleIsStoredOffForTheApp() throws {
            let suite = "InputSourceIndicatorTest"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defaults.removePersistentDomain(forName: suite)
            defer { defaults.removePersistentDomain(forName: suite) }
            // Only when macOS itself leaves it open.
            let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
            try #require(global?[InputSourceIndicator.key] == nil)
            defaults.set(true, forKey: InputSourceIndicator.key)
            InputSourceIndicator.disableForApp(defaults)
            // Persisted in the domain, not just registered in this process.
            #expect(defaults.persistentDomain(forName: suite)?[InputSourceIndicator.key] as? Bool == false)
        }

        /// In-memory stand-in for the keychain.
        private final class FakeKeychain {
            var token: String?
            var failLoad = false
            var failStore = false
            func load() throws -> String? {
                if failLoad { throw KeychainError(status: errSecInteractionNotAllowed) }
                return token
            }
            func store(_ value: String) throws {
                if failStore { throw KeychainError(status: errSecInteractionNotAllowed) }
                token = value.isEmpty ? nil : value
            }
        }
        private func model(_ keychain: FakeKeychain, syncRunning: @escaping () -> Bool = { false },
                           accepted: @escaping (String) -> Void = { _ in },
                           test: @escaping (String) async throws -> String) -> DiscogsSettingsModel {
            DiscogsSettingsModel(keychainLoad: { try keychain.load() }, keychainStore: { try keychain.store($0) },
                                 testToken: test, isSyncRunning: syncRunning, tokenAccepted: accepted)
        }

        @Test func secondStartDuringATestIsIgnoredAndCancelStopsTheFirst() async {
            let keychain = FakeKeychain(); keychain.token = "good"
            var calls = 0
            let model = model(keychain) { _ in calls += 1; try await Task.sleep(for: .seconds(30)); return "listener" }
            model.loadIfNeeded()
            model.token = "new"
            model.startTest()
            #expect(model.busy)
            model.startTest()
            try? await Task.sleep(for: .milliseconds(100))
            model.cancelTest()
            while model.busy { try? await Task.sleep(for: .milliseconds(10)) }
            #expect(calls == 1)
            #expect(keychain.token == "good")
            #expect(!model.failed)
        }
        @Test func storingOrRemovingTheTokenIsAnnounced() async {
            let keychain = FakeKeychain()
            var changes = 0
            let model = DiscogsSettingsModel(keychainLoad: { try keychain.load() }, keychainStore: { try keychain.store($0) },
                                             testToken: { _ in throw DiscogsError.unauthorized }, isSyncRunning: { false },
                                             tokenAccepted: { _ in }, tokenChanged: { changes += 1 })
            model.loadIfNeeded()
            #expect(changes == 0)
            model.token = "typo"
            await model.startTest()?.value            // rejected: nothing stored, nothing announced
            #expect(changes == 0)
            keychain.token = "good"; model.load()
            model.remove()
            #expect(changes == 1)
        }
        @Test func successfulTestClearsRejection() async {
            let keychain = FakeKeychain()
            var accepted: [String] = []
            let model = model(keychain, accepted: { accepted.append($0) }) { _ in "listener" }
            model.loadIfNeeded()
            model.token = "new"
            await model.startTest()?.value
            #expect(accepted == [DiscogsAPIClient.fingerprint(of: "new")])
        }

        @Test func tokenIsNotSwappedUnderASyncStartedDuringTheTest() async {
            let keychain = FakeKeychain(); keychain.token = "good"
            var running = false
            let model = model(keychain, syncRunning: { running }) { _ in running = true; return "listener" }
            model.loadIfNeeded()
            model.token = "new"
            await model.startTest()?.value
            #expect(keychain.token == "good")
            #expect(model.failed)
            #expect(model.verified == nil)
        }
        @Test func cancelledTestKeepsStoredToken() async {
            let keychain = FakeKeychain(); keychain.token = "good"
            let model = model(keychain) { _ in try await Task.sleep(for: .seconds(30)); return "listener" }
            model.loadIfNeeded()
            model.token = "new"
            let task = model.startTest()
            try? await Task.sleep(for: .milliseconds(100))
            model.cancelTest(); await task?.value
            #expect(keychain.token == "good")
            #expect(!model.busy)
            #expect(!model.failed)
            #expect(model.status.isEmpty)
        }
        @Test func unsavedTokenIsDetected() {
            let keychain = FakeKeychain(); keychain.token = "good"
            let model = model(keychain) { _ in "listener" }
            model.loadIfNeeded()
            #expect(!model.hasUnsavedToken)
            model.token = "new"
            #expect(model.hasUnsavedToken)
            model.token = "  good\n"
            #expect(!model.hasUnsavedToken)
            model.token = ""
            #expect(!model.hasUnsavedToken)
        }
        @Test func fingerprintFollowsStoredToken() async {
            let keychain = FakeKeychain(); keychain.token = "good"
            let model = model(keychain) { _ in "listener" }
            model.loadIfNeeded()
            #expect(model.storedFingerprint == DiscogsAPIClient.fingerprint(of: "good"))
            model.token = "new"
            await model.startTest()?.value
            #expect(model.storedFingerprint == DiscogsAPIClient.fingerprint(of: "new"))
            model.remove()
            #expect(model.storedFingerprint == nil)
        }

        @Test func malformedTokenIsNeitherTestedNorStored() async {
            let keychain = FakeKeychain(); keychain.token = "good"
            var tested = false
            let model = model(keychain) { _ in tested = true; return "listener" }
            model.loadIfNeeded()
            // A line break or space inside (pasted wrongly) must never reach the HTTP header.
            for bad in ["abc\ndef", "abc def", "abc\u{0}def", "tökén"] {
                model.token = bad
                await model.startTest()?.value
                #expect(!tested)
                #expect(keychain.token == "good")
                #expect(model.failed)
                #expect(!model.busy)
            }
            #expect(DiscogsAPIClient.isWellFormedToken("AbC123xyz"))
            #expect(!DiscogsAPIClient.isWellFormedToken(""))
        }

        @Test func rejectedTokenKeepsStoredOne() async {
            let keychain = FakeKeychain(); keychain.token = "good"
            let model = model(keychain) { _ in throw DiscogsError.unauthorized }
            model.loadIfNeeded()
            model.token = "typo"
            await model.startTest()?.value
            #expect(keychain.token == "good")
            #expect(model.hasStoredToken)
            #expect(model.failed)
            #expect(model.verified == nil)
        }
        @Test func acceptedTokenIsStoredTrimmed() async {
            let keychain = FakeKeychain()
            let model = model(keychain) { _ in "listener" }
            model.loadIfNeeded()
            model.token = "  new \n"
            await model.startTest()?.value
            #expect(keychain.token == "new")
            #expect(model.hasStoredToken)
            #expect(model.status == "Verbunden als listener")
        }
        @Test func offlineTestStillStoresToken() async {
            let keychain = FakeKeychain()
            let model = model(keychain) { _ in throw DiscogsError.offline }
            model.loadIfNeeded()
            model.token = "new"
            await model.startTest()?.value
            #expect(keychain.token == "new")
            #expect(model.hasStoredToken)
            #expect(model.failed)
        }
        @Test func failedRemovalKeepsField() {
            let keychain = FakeKeychain(); keychain.token = "good"
            let model = model(keychain) { _ in "listener" }
            model.loadIfNeeded()
            keychain.failStore = true
            model.remove()
            #expect(model.token == "good")
            #expect(model.hasStoredToken)
            keychain.failStore = false
            model.remove()
            #expect(model.token.isEmpty)
            #expect(!model.hasStoredToken)
            #expect(keychain.token == nil)
        }
        @Test func unreadableKeychainIsRetried() {
            let keychain = FakeKeychain(); keychain.token = "good"; keychain.failLoad = true
            let model = model(keychain) { _ in "listener" }
            model.loadIfNeeded()
            #expect(model.keychainUnreadable)
            #expect(!model.hasStoredToken)
            keychain.failLoad = false
            model.loadIfNeeded()
            #expect(!model.keychainUnreadable)
            #expect(model.hasStoredToken)
            #expect(model.status.isEmpty)
        }
        @Test func statisticsOrderDefaultDetection() {
            #expect(StatisticsSection.ordered(from: "") == StatisticsSection.allCases)
            #expect(StatisticsSection.ordered(from: "overview,unknown") == StatisticsSection.allCases)
            #expect(StatisticsSection.ordered(from: "recent").first == .recent)
        }
        /// Dropped onto a section below it lands after it, onto one above
        /// before it – also onto the direct neighbour (that used to do nothing).
        @Test func statisticsSectionMovesOntoEveryOtherSection() {
            let order: [StatisticsSection] = [.overview, .highlights, .valueHistory, .sound]
            #expect(StatisticsSection.moving(.overview, onto: .highlights, in: order) == [.highlights, .overview, .valueHistory, .sound])
            #expect(StatisticsSection.moving(.overview, onto: .sound, in: order) == [.highlights, .valueHistory, .sound, .overview])
            #expect(StatisticsSection.moving(.highlights, onto: .overview, in: order) == [.highlights, .overview, .valueHistory, .sound])
            #expect(StatisticsSection.moving(.sound, onto: .highlights, in: order) == [.overview, .sound, .highlights, .valueHistory])
            #expect(StatisticsSection.moving(.highlights, onto: .valueHistory, in: order) == [.overview, .valueHistory, .highlights, .sound])
            #expect(StatisticsSection.moving(.sound, onto: .sound, in: order) == nil)
            #expect(StatisticsSection.moving(.labels, onto: .sound, in: order) == nil)
            // Every pair changes the order and keeps every section once.
            for source in order { for target in order where target != source {
                let moved = StatisticsSection.moving(source, onto: target, in: order)
                #expect(moved != order && moved?.sorted(by: { $0.rawValue < $1.rawValue }) == order.sorted(by: { $0.rawValue < $1.rawValue }))
            } }
        }

        /// Covers unused for long go, and past the limit the least recently used ones.
        @Test func coverCacheDropsOldAndLeastRecentlyUsedFiles() throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let now = Date.now
            func file(_ name: String, daysAgo: Double, bytes: Int) throws {
                let url = directory.appendingPathComponent(name)
                try Data(count: bytes).write(to: url)
                try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-daysAgo * 86_400)], ofItemAtPath: url.path)
            }
            try file("fresh", daysAgo: 1, bytes: 400)
            try file("recent", daysAgo: 10, bytes: 400)
            try file("older", daysAgo: 20, bytes: 400)
            try file("stale", daysAgo: 100, bytes: 10)

            #expect(CoverCache.prune(directory, now: now, maximumAge: 90 * 86_400, limit: 1_000) == 2)
            let left = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
            #expect(left == ["fresh", "recent"])
        }
    }
}
