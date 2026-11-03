import Foundation
import Testing
import Synchronization
@testable import Plattenregal

extension AllTests {
    /// „Nach Updates suchen“: version numbers, GitHub's answers and failures,
    /// the release notes, and when the daily check asks.
    @MainActor struct UpdateTests {
        // MARK: Version numbers

        @Test func versionsCompareByTheirParts() throws {
            let v = { (text: String) throws -> AppVersion in try #require(AppVersion(text)) }
            #expect(try v("v1.0.2") == v("1.0.2"))
            #expect(try v("V1.0.2") == v("1.0.2"))
            #expect(try v("1.1") == v("1.1.0"))
            #expect(try v("1.0.10") > v("1.0.9"))
            #expect(try v("2.0") > v("1.99.99"))
            #expect(try v("1.0.1") < v("1.0.2"))
            #expect(try v(" 1.0.2\n") == v("1.0.2"))
            // A suffix doesn't count; "latest" on GitHub never names a pre-release anyway.
            #expect(try v("1.0.3-beta.1") == v("1.0.3"))
            #expect(try v("1.0.3+77") == v("1.0.3"))
            #expect(try v("1.0.2").description == "1.0.2")
        }

        @Test func brokenVersionsAreRejected() {
            for text in ["", "v", "1..2", ".1", "1.", "abc", "1.0.x", "1.2.3.4.5", "١.٢", "1.-2", "1234567.0", "v 1.0"] {
                #expect(AppVersion(text) == nil, "\(text)")
            }
        }

        /// „Über Plattenregal“: the newest entry is this build's version, the
        /// others older and earlier, none empty – checked at every new version.
        @Test func changelogStartsWithThisVersion() throws {
            let entries = Changelog.entries
            let newest = try #require(entries.first)
            #expect(AppVersion(newest.version) == AppVersion.current)
            for (newer, older) in zip(entries, entries.dropFirst()) {
                #expect(try #require(AppVersion(newer.version)) > #require(AppVersion(older.version)))
                #expect(newer.date >= older.date)
            }
            for entry in entries {
                #expect(!entry.changes.isEmpty)
                #expect(entry.changes.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
                #expect(entry.date < .now.addingTimeInterval(14 * 24 * 60 * 60), "Datum von \(entry.version)")
            }
        }

        // MARK: GitHub's answer

        @Test func releaseIsReadWithItsDMG() throws {
            let release = try UpdateService.release(from: Self.releaseJSON(), response: Self.http(200))
            #expect(release.version == AppVersion("1.0.3"))
            #expect(release.pageURL.absoluteString == "https://github.com/ptrcwrnr/Plattenregal/releases/tag/v1.0.3")
            // The fixed name first, even though the versioned DMG comes earlier.
            #expect(release.downloadURL?.lastPathComponent == "Plattenregal.dmg")
            #expect(release.downloadSize == 11_270_713)
            #expect(release.publishedAt == Date(timeIntervalSince1970: 1_793_000_000))
        }

        @Test func dmgFallsBackToVersionedOrAnyDMGOrThePage() throws {
            let versioned = try UpdateService.release(from: Self.releaseJSON(assets: [
                Self.asset("Quellcode.zip"), Self.asset("Plattenregal-1.0.3.dmg"), Self.asset("Other.dmg"),
            ]), response: Self.http(200))
            #expect(versioned.downloadURL?.lastPathComponent == "Plattenregal-1.0.3.dmg")
            let any = try UpdateService.release(from: Self.releaseJSON(assets: [Self.asset("Notes.txt"), Self.asset("Plattenregal 1.0.3.DMG")]),
                                                response: Self.http(200))
            #expect(any.downloadURL?.lastPathComponent == "Plattenregal 1.0.3.DMG")
            // Not yet uploaded, or somewhere other than GitHub: not offered.
            let none = try UpdateService.release(from: Self.releaseJSON(assets: [
                Self.asset("Plattenregal.dmg", state: "starter"),
                Self.asset("Plattenregal-1.0.3.dmg", url: "https://example.com/Plattenregal-1.0.3.dmg"),
                Self.asset("Plattenregal-1.0.3.dmg", url: "http://github.com/x/Plattenregal-1.0.3.dmg"),
            ]), response: Self.http(200))
            #expect(none.downloadURL == nil)
            #expect(none.downloadSize == nil)
            let noAssets = try UpdateService.release(from: Self.releaseJSON(assets: nil), response: Self.http(200))
            #expect(noAssets.downloadURL == nil)
        }

        @Test func oddFilesAtTheReleaseDontSpoilTheAnswer() throws {
            // A file without name or address is passed over, the DMG still found.
            let release = try UpdateService.release(from: Self.releaseJSON(assets: [
                ["state": "uploaded", "size": 5], ["name": "Plattenregal.dmg", "state": "uploaded"], Self.asset("Plattenregal.dmg"),
            ]), response: Self.http(200))
            #expect(release.downloadURL?.lastPathComponent == "Plattenregal.dmg")
            #expect(release.downloadSize == 11_270_713)
        }

        @Test func foreignOrMissingPageFallsBackToTheReleasesPage() throws {
            let foreign = try UpdateService.release(from: Self.releaseJSON(page: "https://evil.example/releases"), response: Self.http(200))
            #expect(foreign.pageURL == UpdateService.releasesPageURL)
            let missing = try UpdateService.release(from: Self.releaseJSON(page: nil), response: Self.http(200))
            #expect(missing.pageURL == UpdateService.releasesPageURL)
        }

        @Test func everyHTTPFailureHasItsOwnError() throws {
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            func error(_ status: Int, _ headers: [String: String] = [:], body: Data = Data("{}".utf8)) -> UpdateCheckError? {
                do { _ = try UpdateService.release(from: body, response: Self.http(status, headers), now: now); return nil }
                catch { return error as? UpdateCheckError }
            }
            #expect(error(404) == .noRelease)
            #expect(error(500) == .server(500))
            #expect(error(503) == .server(503))
            #expect(error(401) == .refused(401))
            #expect(error(403) == .refused(403))
            #expect(error(301) == .refused(301))
            // Out of requests: the minutes until GitHub takes more, rounded up, at most an hour.
            #expect(error(403, ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "\(Int(now.timeIntervalSince1970) + 7 * 60 + 5)"]) == .rateLimited(minutes: 8))
            #expect(error(403, ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "\(Int(now.timeIntervalSince1970) - 30)"]) == .rateLimited(minutes: 1))
            #expect(error(403, ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "99999999999"]) == .rateLimited(minutes: 60))
            #expect(error(403, ["X-RateLimit-Remaining": "0"]) == .rateLimited(minutes: nil))
            #expect(error(429, ["Retry-After": "120"]) == .rateLimited(minutes: 2))
            #expect(error(429) == .rateLimited(minutes: nil))
            #expect(error(403, ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "bald"]) == .rateLimited(minutes: nil))
        }

        @Test func unreadableAnswersAreInvalid() throws {
            func error(_ body: Data, response: URLResponse = Self.http(200)) -> UpdateCheckError? {
                do { _ = try UpdateService.release(from: body, response: response); return nil }
                catch { return error as? UpdateCheckError }
            }
            // A public network's login page instead of GitHub's answer.
            #expect(error(Data("<html><body>Bitte anmelden</body></html>".utf8)) == .invalidResponse)
            #expect(error(Data()) == .invalidResponse)
            #expect(error(Data("[]".utf8)) == .invalidResponse)
            #expect(error(Self.releaseJSON(tag: "nightly")) == .invalidResponse)
            #expect(error(Self.releaseJSON(), response: URLResponse(url: UpdateService.latestReleaseURL, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)) == .invalidResponse)
            #expect(error(Data(repeating: 32, count: UpdateService.maximumResponseSize + 1)) == .invalidResponse)
            // Drafts and pre-releases aren't for everyone yet.
            #expect(error(Self.releaseJSON(draft: true)) == .noRelease)
            #expect(error(Self.releaseJSON(prerelease: true)) == .noRelease)
        }

        @Test func connectionFailuresSayWhatHappened() {
            func mapped(_ code: URLError.Code) -> UpdateCheckError? { UpdateService.error(for: URLError(code)) as? UpdateCheckError }
            #expect(mapped(.notConnectedToInternet) == .offline)
            #expect(mapped(.networkConnectionLost) == .offline)
            #expect(mapped(.dataNotAllowed) == .offline)
            #expect(mapped(.cannotFindHost) == .unreachable)
            #expect(mapped(.cannotConnectToHost) == .unreachable)
            #expect(mapped(.dnsLookupFailed) == .unreachable)
            #expect(mapped(.timedOut) == .timedOut)
            #expect(mapped(.serverCertificateUntrusted) == .insecureConnection)
            #expect(mapped(.serverCertificateHasBadDate) == .insecureConnection)
            #expect(mapped(.secureConnectionFailed) == .insecureConnection)
            #expect(mapped(.badServerResponse) == .invalidResponse)
            #expect(mapped(.unknown) == .unreachable)
            #expect(UpdateService.error(for: URLError(.cancelled)) is CancellationError)
        }

        @Test func requestAsksGitHubWithoutAnythingPersonal() async throws {
            let seen = Mutex<URLRequest?>(nil)
            let service = UpdateService { request in
                seen.withLock { $0 = request }
                return (Self.releaseJSON(), Self.http(200))
            }
            _ = try await service.latestRelease()
            let request = try #require(seen.withLock { $0 })
            #expect(request.url == UpdateService.latestReleaseURL)
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Plattenregal/") == true)
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        }

        @Test func serviceTurnsConnectionErrorsIntoMessages() async {
            for (thrown, expected) in [(URLError(.notConnectedToInternet), UpdateCheckError.offline), (URLError(.timedOut), .timedOut)] {
                let service = UpdateService { _ in throw thrown }
                await #expect(throws: expected) { try await service.latestRelease() }
            }
            let cancelled = UpdateService { _ in throw URLError(.cancelled) }
            await #expect(throws: CancellationError.self) { try await cancelled.latestRelease() }
            let other = UpdateService { _ in throw CocoaError(.fileReadUnknown) }
            await #expect(throws: UpdateCheckError.unreachable) { try await other.latestRelease() }
        }

        @Test func everyErrorHasTitleAndMessage() {
            let errors: [UpdateCheckError] = [.offline, .unreachable, .timedOut, .insecureConnection, .rateLimited(minutes: 5),
                                              .rateLimited(minutes: 1), .rateLimited(minutes: nil), .noRelease, .server(502),
                                              .refused(418), .invalidResponse]
            let messages = errors.map { $0.errorDescription ?? "" }
            #expect(messages.allSatisfy { !$0.isEmpty })
            #expect(Set(messages).count == errors.count)
            #expect(errors.allSatisfy { !$0.title.isEmpty })
            // Through the app's own message path, not the generic sentence.
            #expect((UpdateCheckError.offline as any Error).userMessage == UpdateCheckError.offline.errorDescription)
            #expect(UpdateCheckError.rateLimited(minutes: 5).errorDescription?.contains("5") == true)
            #expect(UpdateCheckError.server(502).errorDescription?.contains("502") == true)
        }

        // MARK: Release notes

        @Test func highlightsComeFromTheListInTheAppLanguage() {
            let german = ReleaseNotes.highlights(in: Self.notes, english: false)
            #expect(german == ["Die Plattenkarte ist aufgeräumt.", "„Im Regal anzeigen“ kommt **ruhig** an, auch bei weiten Sprüngen im Fach."])
            let english = ReleaseNotes.highlights(in: Self.notes, english: true)
            #expect(english == ["The record card is tidier.", "“Show on Shelf” arrives calmly."])
            // Windows line ends change nothing.
            #expect(ReleaseNotes.highlights(in: Self.notes.replacingOccurrences(of: "\n", with: "\r\n"), english: false) == german)
        }

        @Test func highlightsCopeWithOtherNotes() {
            // Only one language: the same list either way.
            let single = "**Neu**\n* Eins\n+ Zwei\n"
            #expect(ReleaseNotes.highlights(in: single, english: true) == ["Eins", "Zwei"])
            #expect(ReleaseNotes.highlights(in: "", english: false).isEmpty)
            #expect(ReleaseNotes.highlights(in: "Nur ein Satz ohne Liste.", english: false).isEmpty)
            #expect(ReleaseNotes.highlights(in: "---\n\n---\n- Erst nach Strichen\n", english: false) == ["Erst nach Strichen"])
            // Empty points are dropped; at most twelve.
            #expect(ReleaseNotes.highlights(in: "- \n- A\n", english: false) == ["A"])
            let long = (1...20).map { "- Punkt \($0)" }.joined(separator: "\n")
            #expect(ReleaseNotes.highlights(in: long, english: false).count == ReleaseNotes.maximumCount)
            // Bold and links stay readable; broken Markdown shows as it is.
            #expect(String(UpdateView.markdown("**fett** und `code`").characters) == "fett und code")
            #expect(String(UpdateView.markdown("[offen").characters) == "[offen")
        }

        @Test func highlightsFollowTheHeadingNotJustTheRules() {
            // A rule inside the German part: English is still the list under "New in".
            let ruled = """
                **Neu in 1.0.3**
                - Eins

                ---
                **Aktualisieren:** laden.
                - Kein Punkt
                ---
                ## New in 1.0.3
                - One
                """
            #expect(ReleaseNotes.highlights(in: ruled, english: false) == ["Eins"])
            #expect(ReleaseNotes.highlights(in: ruled, english: true) == ["One"])
            // English first: each language still finds its own list.
            let swapped = "New in 1.0.3:\n- One\n\n---\n\nNeu in 1.0.3:\n- Eins\n"
            #expect(ReleaseNotes.highlights(in: swapped, english: false) == ["Eins"])
            #expect(ReleaseNotes.highlights(in: swapped, english: true) == ["One"])
            // "Neu installieren" is no heading; the list before it counts.
            #expect(ReleaseNotes.highlights(in: "- Eins\n\n**Neu installieren:** so.\n- Schritt\n", english: false) == ["Eins"])
            // Blank lines between points (a loose list), a paragraph inside a point.
            let loose = "**Neu in 1.0.3**\n\n- Eins\n\n- Zwei\n\n  mit mehr\n\nText danach\n- Nicht mehr\n"
            #expect(ReleaseNotes.highlights(in: loose, english: false) == ["Eins", "Zwei mit mehr"])
            // Old Mac line ends.
            #expect(ReleaseNotes.highlights(in: "- A\r- B", english: false) == ["A", "B"])
            // The notes of 1.0.0: numbered install steps, no "Neu in" – nothing to show.
            let first = "Die erste Ausgabe.\n\n**Installieren**\n1. Laden.\n2. Öffnen.\n\n---\n\nThe first release.\n\n**Install**\n1. Download.\n"
            #expect(ReleaseNotes.highlights(in: first, english: false).isEmpty)
            #expect(ReleaseNotes.highlights(in: first, english: true).isEmpty)
        }

        // MARK: The check

        @Test func manualCheckFindsNewerVersionAndRemembersTheDay() async throws {
            try await withDefaults { defaults in
                let clock = TestClock()
                let checker = UpdateChecker(service: Self.answering(tag: "v1.0.3"), defaults: defaults,
                                            currentVersion: AppVersion("1.0.2"), automaticChecksEnabled: { true }, now: { clock.now })
                #expect(checker.lastCheck == nil)
                checker.checkNow()
                #expect(checker.state == .checking)
                try await Self.waitUntil { checker.state != .checking }
                guard case .available(let release) = checker.state else { Issue.record("\(checker.state)"); return }
                #expect(release.version == AppVersion("1.0.3"))
                #expect(checker.lastCheck == clock.now)
                #expect(defaults.object(forKey: UpdateChecker.Key.lastCheck) as? Date == clock.now)
                #expect(checker.announcedRelease == release)
                // Skipped: no more hint in the menu bar, but a manual check still shows it.
                checker.skip(release)
                #expect(checker.skippedVersion == AppVersion("1.0.3"))
                #expect(checker.announcedRelease == nil)
                #expect(UpdateChecker(defaults: defaults, currentVersion: AppVersion("1.0.2")).skippedVersion == AppVersion("1.0.3"))
            }
        }

        @Test func sameOrOlderVersionOnGitHubIsUpToDate() async throws {
            try await withDefaults { defaults in
                for (installed, published) in [("1.0.2", "v1.0.2"), ("1.0.3", "v1.0.2"), ("1.1", "1.1.0")] {
                    let checker = UpdateChecker(service: Self.answering(tag: published), defaults: defaults,
                                                currentVersion: AppVersion(installed), automaticChecksEnabled: { true })
                    checker.checkNow()
                    try await Self.waitUntil { checker.state != .checking }
                    #expect(checker.state == .upToDate(latest: try #require(AppVersion(published))), "\(installed) / \(published)")
                    #expect(checker.announcedRelease == nil)
                }
            }
        }

        @Test func failedManualCheckShowsTheErrorAndKeepsTheLastDay() async throws {
            try await withDefaults { defaults in
                let earlier = Date(timeIntervalSince1970: 1_790_000_000)
                defaults.set(earlier, forKey: UpdateChecker.Key.lastCheck)
                let checker = UpdateChecker(service: UpdateService { _ in throw URLError(.notConnectedToInternet) }, defaults: defaults,
                                            currentVersion: AppVersion("1.0.2"), automaticChecksEnabled: { true })
                checker.checkNow()
                try await Self.waitUntil { checker.state != .checking }
                #expect(checker.state == .failed(.offline))
                #expect(checker.lastCheck == earlier)
            }
        }

        @Test func automaticCheckStaysQuietOnFailure() async throws {
            try await withDefaults { defaults in
                let checker = UpdateChecker(service: UpdateService { _ in throw URLError(.timedOut) }, defaults: defaults,
                                            currentVersion: AppVersion("1.0.2"), automaticChecksEnabled: { true })
                await checker.runAutomaticCheckIfDue()
                #expect(checker.state == .idle)
                #expect(checker.lastCheck == nil)
                // Still due: the hourly schedule tries again.
                #expect(checker.isAutomaticCheckDue())
            }
        }

        @Test func automaticCheckFindsNewerVersionButRespectsASkip() async throws {
            try await withDefaults { defaults in
                defaults.set("1.0.3", forKey: UpdateChecker.Key.skippedVersion)
                let skipped = UpdateChecker(service: Self.answering(tag: "v1.0.3"), defaults: defaults,
                                            currentVersion: AppVersion("1.0.2"), automaticChecksEnabled: { true })
                await skipped.runAutomaticCheckIfDue()
                #expect(skipped.announcedRelease == nil)
                // A version newer than the skipped one is named again (a day later).
                defaults.removeObject(forKey: UpdateChecker.Key.lastCheck)
                let newer = UpdateChecker(service: Self.answering(tag: "v1.0.4"), defaults: defaults,
                                          currentVersion: AppVersion("1.0.2"), automaticChecksEnabled: { true })
                #expect(newer.isAutomaticCheckDue())
                await newer.runAutomaticCheckIfDue()
                #expect(newer.announcedRelease?.version == AppVersion("1.0.4"))
            }
        }

        @Test func automaticCheckIsDueOnceADay() throws {
            try withDefaults { defaults in
                let clock = TestClock()
                var enabled = true
                let checker = UpdateChecker(service: Self.answering(tag: "v1.0.2"), defaults: defaults, currentVersion: AppVersion("1.0.2"),
                                            automaticChecksEnabled: { enabled }, now: { clock.now })
                #expect(checker.isAutomaticCheckDue())
                defaults.set(clock.now.addingTimeInterval(-60 * 60), forKey: UpdateChecker.Key.lastCheck)
                checker.automaticChecksChanged()
                #expect(!checker.isAutomaticCheckDue())
                defaults.set(clock.now.addingTimeInterval(-UpdateChecker.checkInterval), forKey: UpdateChecker.Key.lastCheck)
                checker.automaticChecksChanged()
                #expect(checker.isAutomaticCheckDue())
                // A day in the future: the clock was set back – check rather than wait.
                defaults.set(clock.now.addingTimeInterval(60 * 60), forKey: UpdateChecker.Key.lastCheck)
                checker.automaticChecksChanged()
                #expect(checker.isAutomaticCheckDue())
                enabled = false
                #expect(!checker.isAutomaticCheckDue())
            }
        }

        @Test func concurrentChecksAskGitHubOnce() async throws {
            try await withDefaults { defaults in
                let requests = Mutex(0)
                let service = UpdateService { _ in
                    requests.withLock { $0 += 1 }
                    try await Task.sleep(for: .milliseconds(200))
                    return (Self.releaseJSON(tag: "v1.0.3"), Self.http(200))
                }
                let checker = UpdateChecker(service: service, defaults: defaults, currentVersion: AppVersion("1.0.2"), automaticChecksEnabled: { true })
                // The daily check is asking; "Nach Updates suchen" joins it.
                let automatic = Task { await checker.runAutomaticCheckIfDue() }
                try await Task.sleep(for: .milliseconds(50))
                checker.checkNow()
                checker.checkNow()
                try await Self.waitUntil { checker.state != .checking }
                await automatic.value
                #expect(requests.withLock { $0 } == 1)
                #expect(checker.announcedRelease?.version == AppVersion("1.0.3"))
            }
        }

        @Test func joinedCheckAsksAgainWhenTheOtherIsCancelled() async throws {
            try await withDefaults { defaults in
                let requests = Mutex(0)
                let service = UpdateService { _ in
                    let number = requests.withLock { $0 += 1; return $0 }
                    // The first request hangs until it's cancelled.
                    if number == 1 { try await Task.sleep(for: .seconds(10)) }
                    return (Self.releaseJSON(tag: "v1.0.3"), Self.http(200))
                }
                let checker = UpdateChecker(service: service, defaults: defaults, currentVersion: AppVersion("1.0.2"), automaticChecksEnabled: { true })
                let automatic = Task { await checker.runAutomaticCheckIfDue() }
                try await Task.sleep(for: .milliseconds(50))
                checker.checkNow()
                try await Task.sleep(for: .milliseconds(50))
                // The schedule restarts (setting changed): its request ends, the window's check goes on.
                automatic.cancel()
                await automatic.value
                try await Self.waitUntil { checker.state != .checking }
                #expect(checker.announcedRelease?.version == AppVersion("1.0.3"))
                #expect(requests.withLock { $0 } == 2)
            }
        }

        @Test func automaticCheckSwitchedOffMeanwhileShowsNothing() async throws {
            try await withDefaults { defaults in
                final class Switch { var on = true }
                let setting = Switch()
                let service = UpdateService { _ in
                    try await Task.sleep(for: .milliseconds(150))
                    return (Self.releaseJSON(tag: "v1.0.3"), Self.http(200))
                }
                let checker = UpdateChecker(service: service, defaults: defaults, currentVersion: AppVersion("1.0.2"),
                                            automaticChecksEnabled: { setting.on })
                let automatic = Task { await checker.runAutomaticCheckIfDue() }
                try await Task.sleep(for: .milliseconds(30))
                setting.on = false
                await automatic.value
                #expect(checker.state == .idle)
                #expect(checker.announcedRelease == nil)
                // GitHub did answer: that counts as the day's check.
                #expect(checker.lastCheck != nil)
            }
        }

        @Test func cancelledCheckShowsNothing() async throws {
            try await withDefaults { defaults in
                let service = UpdateService { _ in
                    try await Task.sleep(for: .seconds(5))
                    return (Self.releaseJSON(tag: "v1.0.3"), Self.http(200))
                }
                let checker = UpdateChecker(service: service, defaults: defaults, currentVersion: AppVersion("1.0.2"), automaticChecksEnabled: { true })
                checker.checkNow()
                checker.cancelCheck()
                #expect(checker.state == .idle)
                try await Task.sleep(for: .milliseconds(300))
                #expect(checker.state == .idle)
                #expect(checker.lastCheck == nil)
                // A new check after cancelling works as usual.
                let answering = UpdateChecker(service: Self.answering(tag: "v1.0.3"), defaults: defaults,
                                              currentVersion: AppVersion("1.0.2"), automaticChecksEnabled: { true })
                // Cancelled and asked again at once: the new check doesn't take the cancelled answer.
                answering.checkNow()
                answering.cancelCheck()
                answering.checkNow()
                try await Self.waitUntil { answering.state != .checking }
                #expect(answering.announcedRelease?.version == AppVersion("1.0.3"))
            }
        }

        @Test func automaticChecksAreOnByDefaultAndPersist() throws {
            try withDefaults { defaults in
                let preferences = AppPreferences(defaults: defaults)
                #expect(preferences.automaticUpdateChecks)
                preferences.automaticUpdateChecks = false
                #expect(!AppPreferences(defaults: defaults).automaticUpdateChecks)
                preferences.reset()
                #expect(AppPreferences(defaults: defaults).automaticUpdateChecks)
                // "-automaticUpdateChecks NO" from a launch argument arrives as text.
                defaults.set("NO", forKey: AppPreferences.Key.automaticUpdateChecks)
                #expect(!AppPreferences(defaults: defaults).automaticUpdateChecks)
            }
        }

        // MARK: Helpers

        final class TestClock { var now = Date(timeIntervalSince1970: 1_800_000_000) }

        private func withDefaults(test: String = #function, _ check: (UserDefaults) async throws -> Void) async throws {
            let suite = "UpdateTests-\(test.prefix { $0 != "(" })"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defaults.removePersistentDomain(forName: suite)
            defer { defaults.removePersistentDomain(forName: suite) }
            try await check(defaults)
        }

        private func withDefaults(test: String = #function, _ check: (UserDefaults) throws -> Void) throws {
            let suite = "UpdateTests-\(test.prefix { $0 != "(" })"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defaults.removePersistentDomain(forName: suite)
            defer { defaults.removePersistentDomain(forName: suite) }
            try check(defaults)
        }

        private static func waitUntil(_ condition: () -> Bool) async throws {
            for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(20)) }
            #expect(condition(), "Zeit abgelaufen")
        }

        private static func answering(tag: String) -> UpdateService {
            UpdateService { _ in (releaseJSON(tag: tag), http(200)) }
        }

        nonisolated static func http(_ status: Int, _ headers: [String: String] = [:]) -> HTTPURLResponse {
            HTTPURLResponse(url: UpdateService.latestReleaseURL, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        }

        nonisolated static func asset(_ name: String, url: String? = nil, state: String = "uploaded") -> [String: Any] {
            ["name": name, "state": state, "size": 11_270_713,
             "browser_download_url": url ?? "https://github.com/ptrcwrnr/Plattenregal/releases/download/v1.0.3/\(name.replacingOccurrences(of: " ", with: "%20"))"]
        }

        nonisolated static func releaseJSON(tag: String = "v1.0.3", page: String? = "https://github.com/ptrcwrnr/Plattenregal/releases/tag/v1.0.3",
                                            draft: Bool = false, prerelease: Bool = false,
                                            assets: [[String: Any]]? = [asset("Plattenregal-1.0.3.dmg"), asset("Plattenregal.dmg")]) -> Data {
            var json: [String: Any] = ["tag_name": tag, "name": "Plattenregal 1.0.3", "draft": draft, "prerelease": prerelease,
                                       "published_at": "2026-10-26T07:33:20Z", "body": notes]
            if let page { json["html_url"] = page }
            if let assets { json["assets"] = assets }
            return try! JSONSerialization.data(withJSONObject: json)
        }

        nonisolated static let notes = """
            **Neu in 1.0.3**
            - Die Plattenkarte ist aufgeräumt.
            - „Im Regal anzeigen“ kommt **ruhig** an,
              auch bei weiten Sprüngen im Fach.

            **Aktualisieren:** `Plattenregal.dmg` laden.
            - Kein Punkt mehr für das Fenster

            ---

            **New in 1.0.3**
            - The record card is tidier.
            - “Show on Shelf” arrives calmly.

            **Update:** Download `Plattenregal.dmg`.
            """
    }
}
