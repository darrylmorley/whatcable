import XCTest
@testable import WhatCable

/// Cover for the opt-in beta update channel: which endpoint gets hit, whether
/// a pre-release is allowed through the parser, and the rule that decides
/// which release out of a list is offered.
///
/// The picker is the part worth testing hardest. GitHub returns `/releases`
/// ordered by creation date, so anything that trusts the array order offers
/// the wrong build the first time a stable ships after a beta.
final class BetaUpdateChannelTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    private func release(_ tag: String, prerelease: Bool) -> String {
        """
        {
          "tag_name": "\(tag)",
          "html_url": "https://github.com/darrylmorley/whatcable/releases/tag/\(tag)",
          "prerelease": \(prerelease)
        }
        """
    }

    // MARK: - Endpoint selection

    func testStableChannelUsesReleasesLatest() {
        let url = UpdateChecker.makeReleaseRequest(includingBetas: false).url?.absoluteString
        XCTAssertEqual(
            url,
            "https://api.github.com/repos/darrylmorley/whatcable/releases/latest",
            "With betas off the request must be byte-for-byte what shipped before this feature: releases/latest never returns a pre-release, and that is the first layer keeping opted-out users off betas"
        )
    }

    func testDefaultIsTheStableChannel() {
        XCTAssertEqual(
            UpdateChecker.makeReleaseRequest().url,
            UpdateChecker.makeReleaseRequest(includingBetas: false).url,
            "Omitting the argument must mean stable-only, so a missed call site fails safe"
        )
    }

    func testBetaChannelUsesTheReleasesList() {
        let url = UpdateChecker.makeReleaseRequest(includingBetas: true).url?.absoluteString
        XCTAssertEqual(
            url,
            "https://api.github.com/repos/darrylmorley/whatcable/releases?per_page=10",
            "The list endpoint is the only one that can see a pre-release"
        )
    }

    // MARK: - Parser gate

    func testParserStillRejectsPrereleaseByDefault() {
        XCTAssertNil(
            UpdateChecker.parseRelease(from: data(release("v1.6.0-beta.1", prerelease: true))),
            "The client-side backstop must stay in force for anyone who has not opted in"
        )
    }

    func testParserAcceptsPrereleaseWhenAllowed() {
        let parsed = UpdateChecker.parseRelease(from: data(release("v1.6.0-beta.1", prerelease: true)), allowPrerelease: true)
        XCTAssertEqual(parsed?.version, "1.6.0-beta.1", "An opted-in user must be able to see a pre-release")
    }

    func testDraftIsNeverOfferedEvenOnTheBetaChannel() {
        let json = """
        {
          "tag_name": "v1.6.0-beta.2",
          "html_url": "https://github.com/darrylmorley/whatcable/releases/tag/v1.6.0-beta.2",
          "prerelease": true,
          "draft": true
        }
        """
        XCTAssertNil(
            UpdateChecker.newestRelease(from: data(json), allowPrerelease: true),
            "A draft has no published asset and must never be offered"
        )
    }

    // MARK: - Picking from a list

    func testPicksNewestNotFirstInTheList() {
        // Creation order puts the older build first, which is exactly what
        // GitHub does when a beta is re-cut after a stable.
        let json = "[\(release("v1.4.0", prerelease: false)),\(release("v1.5.0", prerelease: false))]"
        let picked = UpdateChecker.newestRelease(from: data(json), allowPrerelease: true)
        XCTAssertEqual(picked?.version, "1.5.0", "The picker must compare versions, not trust the array order")
    }

    func testStableSupersedesItsOwnBeta() {
        let json = "[\(release("v1.5.0-beta.3", prerelease: true)),\(release("v1.5.0", prerelease: false))]"
        let picked = UpdateChecker.newestRelease(from: data(json), allowPrerelease: true)
        XCTAssertEqual(
            picked?.version,
            "1.5.0",
            "A beta tester must be moved onto the stable the day it ships, not left on the pre-release"
        )
    }

    func testNewerBetaBeatsOlderBeta() {
        let json = "[\(release("v1.5.0-beta.2", prerelease: true)),\(release("v1.5.0-beta.3", prerelease: true))]"
        let picked = UpdateChecker.newestRelease(from: data(json), allowPrerelease: true)
        XCTAssertEqual(picked?.version, "1.5.0-beta.3", "beta.3 is newer than beta.2")
    }

    func testBetasAreFilteredOutOfAListWhenNotAllowed() {
        let json = "[\(release("v1.5.0-beta.3", prerelease: true)),\(release("v1.4.0", prerelease: false))]"
        let picked = UpdateChecker.newestRelease(from: data(json), allowPrerelease: false)
        XCTAssertEqual(
            picked?.version,
            "1.4.0",
            "Even handed a list containing a newer beta, an opted-out user gets the newest stable"
        )
    }

    func testSingleObjectResponseStillParses() {
        let picked = UpdateChecker.newestRelease(from: data(release("v1.4.0", prerelease: false)))
        XCTAssertEqual(picked?.version, "1.4.0", "releases/latest returns an object, not an array; both shapes must work")
    }

    func testEmptyListYieldsNothing() {
        XCTAssertNil(UpdateChecker.newestRelease(from: data("[]"), allowPrerelease: true))
    }

    // MARK: - Asset and host rules survive on the beta path

    func testBetaAssetIsFoundAndTrustedHostRuleStillApplies() {
        let json = """
        [{
          "tag_name": "v1.5.0-beta.3",
          "html_url": "https://github.com/darrylmorley/whatcable/releases/tag/v1.5.0-beta.3",
          "prerelease": true,
          "assets": [
            {"name": "WhatCable.zip", "browser_download_url": "https://objects.githubusercontent.com/x/WhatCable.zip"}
          ]
        }]
        """
        let picked = UpdateChecker.newestRelease(from: data(json), allowPrerelease: true)
        XCTAssertEqual(picked?.downloadURL?.absoluteString, "https://objects.githubusercontent.com/x/WhatCable.zip")
    }

    func testUntrustedHostStillRejectedOnTheBetaPath() {
        let json = """
        [{
          "tag_name": "v1.5.0-beta.3",
          "html_url": "https://github.com/darrylmorley/whatcable/releases/tag/v1.5.0-beta.3",
          "prerelease": true,
          "assets": [
            {"name": "WhatCable.zip", "browser_download_url": "https://evil.example.com/WhatCable.zip"}
          ]
        }]
        """
        let picked = UpdateChecker.newestRelease(from: data(json), allowPrerelease: true)
        XCTAssertNotNil(picked, "The release itself still parses")
        XCTAssertNil(picked?.downloadURL, "Opting into betas must not relax where a download may come from")
    }

    // MARK: - Homebrew detection
    //
    // The first version of this shipped a wrong premise: it assumed a cask
    // install runs from under the Caskroom. It does not. Homebrew MOVES the
    // app into /Applications and leaves a symlink in the Caskroom pointing
    // at it, so the running bundle is /Applications/WhatCable.app and the old
    // path test was false for every real install. These tests build the real
    // layout in a temp directory so the premise itself is under test.

    func testDetectsACaskInstallByItsCaskroomSymlink() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("brewlayout-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

        // /Applications/WhatCable.app: a real directory, as brew leaves it.
        let apps = root.appendingPathComponent("Applications")
        let installed = apps.appendingPathComponent("WhatCable.app")
        try fm.createDirectory(at: installed, withIntermediateDirectories: true)

        // Caskroom/whatcable/<version>/WhatCable.app: a symlink back to it.
        let versionDir = root.appendingPathComponent("Caskroom/whatcable/1.4.0")
        try fm.createDirectory(at: versionDir, withIntermediateDirectories: true)
        let link = versionDir.appendingPathComponent("WhatCable.app")
        try fm.createSymbolicLink(at: link, withDestinationURL: installed)

        XCTAssertTrue(
            UpdateChecker.isSameBundle(
                caskLinkTarget: link,
                bundlePath: installed.resolvingSymlinksInPath().path
            ),
            "A Caskroom symlink pointing at the running bundle identifies a Homebrew install"
        )
    }

    func testADirectInstallIsNotMistakenForACask() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("directlayout-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

        let installed = root.appendingPathComponent("Applications/WhatCable.app")
        try fm.createDirectory(at: installed, withIntermediateDirectories: true)
        let otherApp = root.appendingPathComponent("Caskroom/whatcable/1.4.0/WhatCable.app")
        try fm.createDirectory(at: otherApp, withIntermediateDirectories: true)

        XCTAssertFalse(
            UpdateChecker.isSameBundle(
                caskLinkTarget: otherApp,
                bundlePath: installed.resolvingSymlinksInPath().path
            ),
            "A Caskroom entry for a DIFFERENT copy must not claim the running one"
        )
    }

    // MARK: - Opting out must withdraw a beta already on offer
    //
    // Codex review findings 1 and 2. Without these, a tester could opt in, be
    // shown a beta, opt out, and still install it from the banner already on
    // screen, which makes the settings caption untrue.

    // The tests below read/write `AppSettings.shared`, backed by
    // `UserDefaults.standard`, a domain every `swift test` process on this
    // machine shares. Wrapped in `withScratchAppSettingsDefaults` so a
    // concurrent run can't flip these settings mid-assertion.

    @MainActor
    func testSuppressesPrereleaseOnlyWhenOptedOut() {
        withScratchAppSettingsDefaults {
            let settings = AppSettings.shared
            let original = settings.receiveBetaUpdates
            defer { settings.receiveBetaUpdates = original }

            let beta = AvailableUpdate(version: "1.5.0-beta.3", url: URL(string: "https://example.com")!, downloadURL: nil, notes: nil)
            let stable = AvailableUpdate(version: "1.5.0", url: URL(string: "https://example.com")!, downloadURL: nil, notes: nil)

            settings.receiveBetaUpdates = false
            XCTAssertTrue(settings.suppressesPrerelease(beta), "Opted out, a beta must be suppressed")
            XCTAssertFalse(settings.suppressesPrerelease(stable), "A stable is never suppressed")

            settings.receiveBetaUpdates = true
            XCTAssertFalse(settings.suppressesPrerelease(beta), "Opted in, a beta is allowed")
            XCTAssertFalse(settings.suppressesPrerelease(stable), "A stable is never suppressed")
        }
    }

    @MainActor
    func testOptingOutDiscardsABetaAlreadyOffered() {
        withScratchAppSettingsDefaults {
            let settings = AppSettings.shared
            let checker = UpdateChecker.shared
            let originalSetting = settings.receiveBetaUpdates
            let originalAvailable = checker.available
            defer {
                settings.receiveBetaUpdates = originalSetting
                if let originalAvailable { checker.updateAvailable(to: originalAvailable) }
            }

            settings.receiveBetaUpdates = true
            let beta = AvailableUpdate(version: "9.9.9-beta.1", url: URL(string: "https://example.com")!, downloadURL: nil, notes: nil)
            checker.updateAvailable(to: beta)
            XCTAssertEqual(checker.available?.version, "9.9.9-beta.1", "Precondition: the beta is on offer")

            settings.receiveBetaUpdates = false
            XCTAssertNil(
                checker.available,
                "Opting out must withdraw the beta already on offer, not just stop the next one"
            )
        }
    }

    // MARK: - Update notifications are independent of the cable-change toggle (issue #550)
    //
    // The two toggles used to be nested: "Notify on app updates" only fired
    // when "Notify on cable changes" was also on. This proves the gate now
    // reads notifyOnUpdates alone.

    func testUpdateNotificationFiresWithCableChangeToggleOff() {
        XCTAssertTrue(
            UpdateChecker.shouldNotify(notifyOnUpdates: true),
            "An update notification must fire on notifyOnUpdates alone, regardless of notifyOnChanges"
        )
    }

    func testUpdateNotificationStaysOffWhenItsOwnToggleIsOff() {
        XCTAssertFalse(
            UpdateChecker.shouldNotify(notifyOnUpdates: false),
            "Turning off notifyOnUpdates must still silence update notifications"
        )
    }

    // These two exercise `postNotification` itself, the real call site, not
    // just the pure `shouldNotify` rule above. The pure-function tests alone
    // pass even if the call site reintroduces `guard notifyOnChanges, ...`,
    // because they never call the site that would carry that guard. Driving
    // `postNotification` with an injected `notificationSink` closes that gap.

    @MainActor
    func testPostNotificationFiresWithCableChangeToggleOffButUpdatesOn() {
        withScratchAppSettingsDefaults {
            let settings = AppSettings.shared
            let checker = UpdateChecker.shared
            let originalNotifyOnChanges = settings.notifyOnChanges
            let originalNotifyOnUpdates = settings.notifyOnUpdates
            let originalSink = checker.notificationSink
            let originalEnsure = checker.ensureNotificationAuthorization
            let originalRequester = settings.requestNotificationAuthorization
            // Toggling a notification setting on requests OS permission, which
            // crashes under the `swift test` runner (no signed app bundle). Swap
            // in a no-op for the duration of this test.
            settings.requestNotificationAuthorization = {}
            defer {
                settings.notifyOnChanges = originalNotifyOnChanges
                settings.notifyOnUpdates = originalNotifyOnUpdates
                checker.notificationSink = originalSink
                checker.ensureNotificationAuthorization = originalEnsure
                settings.requestNotificationAuthorization = originalRequester
            }

            settings.notifyOnChanges = false
            settings.notifyOnUpdates = true

            var posted: AvailableUpdate?
            checker.notificationSink = { posted = $0 }
            checker.ensureNotificationAuthorization = { completion in completion(true) }
            let update = AvailableUpdate(version: "9.9.8", url: URL(string: "https://example.com")!, downloadURL: nil, notes: nil)
            checker.postNotification(update)

            XCTAssertEqual(
                posted?.version,
                "9.9.8",
                "postNotification itself must fire with notifyOnChanges off, not just the pure shouldNotify rule"
            )
        }
    }

    @MainActor
    func testPostNotificationStaysSilentWhenItsOwnToggleIsOff() {
        withScratchAppSettingsDefaults {
            let settings = AppSettings.shared
            let checker = UpdateChecker.shared
            let originalNotifyOnUpdates = settings.notifyOnUpdates
            let originalSink = checker.notificationSink
            let originalRequester = settings.requestNotificationAuthorization
            // Restoring notifyOnUpdates below may flip it back to true, which
            // requests OS permission; that crashes under the `swift test` runner
            // (no signed app bundle), same reasoning as the test above.
            settings.requestNotificationAuthorization = {}
            defer {
                settings.notifyOnUpdates = originalNotifyOnUpdates
                checker.notificationSink = originalSink
                settings.requestNotificationAuthorization = originalRequester
            }

            settings.notifyOnUpdates = false

            var posted: AvailableUpdate?
            checker.notificationSink = { posted = $0 }
            let update = AvailableUpdate(version: "9.9.7", url: URL(string: "https://example.com")!, downloadURL: nil, notes: nil)
            checker.postNotification(update)

            XCTAssertNil(posted, "postNotification must stay silent with notifyOnUpdates off")
        }
    }

    // MARK: - Authorization gate at post time (owner decision, issue #550)
    //
    // notifyOnUpdates now defaults on independent of notifyOnChanges, so
    // nothing is guaranteed to have requested notification permission before
    // the first update is found. postNotification requests it itself via the
    // injected ensureNotificationAuthorization, and must only stamp
    // notifiedVersion once a post genuinely happens: a denial must not stamp,
    // or a later grant for the same version would find it "already notified"
    // and stay silent forever.

    @MainActor
    func testPostNotificationDeniedAuthorizationDoesNotPostOrStamp() {
        let checker = UpdateChecker.shared
        let originalSink = checker.notificationSink
        let originalEnsure = checker.ensureNotificationAuthorization
        defer {
            checker.notificationSink = originalSink
            checker.ensureNotificationAuthorization = originalEnsure
        }

        var posted: [AvailableUpdate] = []
        checker.notificationSink = { posted.append($0) }
        let update = AvailableUpdate(version: "9.9.6", url: URL(string: "https://example.com")!, downloadURL: nil, notes: nil)

        checker.ensureNotificationAuthorization = { completion in completion(false) }
        checker.postNotification(update)
        XCTAssertTrue(posted.isEmpty, "A denied authorization request must not post")

        // Same version, now granted: must still fire. If the denial above had
        // stamped notifiedVersion, this retry would be silently swallowed.
        checker.ensureNotificationAuthorization = { completion in completion(true) }
        checker.postNotification(update)
        XCTAssertEqual(
            posted.map(\.version),
            ["9.9.6"],
            "A later grant for the same version must still post, since a denial must not stamp"
        )
    }

    @MainActor
    func testPostNotificationGrantedAuthorizationPostsAndStamps() {
        let checker = UpdateChecker.shared
        let originalSink = checker.notificationSink
        let originalEnsure = checker.ensureNotificationAuthorization
        defer {
            checker.notificationSink = originalSink
            checker.ensureNotificationAuthorization = originalEnsure
        }

        var posted: [AvailableUpdate] = []
        checker.notificationSink = { posted.append($0) }
        checker.ensureNotificationAuthorization = { completion in completion(true) }
        let update = AvailableUpdate(version: "9.9.5", url: URL(string: "https://example.com")!, downloadURL: nil, notes: nil)

        checker.postNotification(update)
        XCTAssertEqual(posted.map(\.version), ["9.9.5"], "A granted authorization request must post")

        checker.postNotification(update)
        XCTAssertEqual(
            posted.map(\.version),
            ["9.9.5"],
            "The same version must not post twice; a genuine post must stamp notifiedVersion"
        )
    }

    // Race: notifiedVersion is only stamped inside the async authorization
    // completion, but the guard against a duplicate is checked synchronously
    // at the top of postNotification. check(silent:) resets isChecking
    // before postNotification runs, so a second check (the 6h timer,
    // checkIfStale past its 30-minute throttle, or a manual "Check for
    // Updates" click) can call postNotification again for the same version
    // while the first call's authorization request is still pending, a wide
    // window while the system's .notDetermined permission dialog is open.
    // Without pendingAuthVersion both calls would start their own
    // authorization request and, if both grant, post twice.

    @MainActor
    func testPostNotificationOverlappingCallsForSameVersionPostOnlyOnce() {
        let checker = UpdateChecker.shared
        let originalSink = checker.notificationSink
        let originalEnsure = checker.ensureNotificationAuthorization
        defer {
            checker.notificationSink = originalSink
            checker.ensureNotificationAuthorization = originalEnsure
        }

        var posted: [AvailableUpdate] = []
        checker.notificationSink = { posted.append($0) }

        // Capture completions instead of invoking them, so both calls below
        // start (or attempt to start) their authorization request before
        // either resolves, reproducing the pending-dialog window.
        var completions: [(Bool) -> Void] = []
        checker.ensureNotificationAuthorization = { completion in completions.append(completion) }

        let update = AvailableUpdate(version: "9.9.4", url: URL(string: "https://example.com")!, downloadURL: nil, notes: nil)
        checker.postNotification(update)
        checker.postNotification(update)

        for completion in completions { completion(true) }

        XCTAssertEqual(
            posted.map(\.version),
            ["9.9.4"],
            "Two overlapping calls for the same version must post exactly once, even if both authorization requests grant"
        )

        // A further call for the same version, now settled, must still be
        // swallowed by the notifiedVersion stamp.
        checker.postNotification(update)
        XCTAssertEqual(posted.map(\.version), ["9.9.4"], "The version is already notified; a later call must not post again")
    }

    @MainActor
    func testOptingOutLeavesAStableOfferAlone() {
        withScratchAppSettingsDefaults {
            let settings = AppSettings.shared
            let checker = UpdateChecker.shared
            let originalSetting = settings.receiveBetaUpdates
            let originalAvailable = checker.available
            defer {
                settings.receiveBetaUpdates = originalSetting
                if let originalAvailable { checker.updateAvailable(to: originalAvailable) }
            }

            settings.receiveBetaUpdates = true
            let stable = AvailableUpdate(version: "9.9.9", url: URL(string: "https://example.com")!, downloadURL: nil, notes: nil)
            checker.updateAvailable(to: stable)

            settings.receiveBetaUpdates = false
            XCTAssertEqual(
                checker.available?.version,
                "9.9.9",
                "Opting out of betas must not throw away a legitimate stable update"
            )
        }
    }
}
