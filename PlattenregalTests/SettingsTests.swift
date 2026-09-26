import Foundation
import Testing
@testable import Plattenregal

extension AllTests {
    @MainActor struct SettingsTests {
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
            // Newest first; undated last, in alphabetical order.
            let date = { (n: Int) -> Date? in n > 3 ? nil : Date(timeIntervalSince1970: Double(n)) }
            #expect(OverviewOrder.recent.apply([5, 1, 4, 3, 2], scope: "collection", alphabetical: alphabetical, key: { $0 }, added: date) == [3, 2, 1, 4, 5])
        }

        @Test func inputSourceBubbleIsStoredOffForTheApp() throws {
            let suite = "InputSourceIndicatorTest"
            let defaults = try #require(UserDefaults(suiteName: suite))
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
