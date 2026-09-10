import Foundation
import Testing
@testable import WhatCableDarwinBackend

// MARK: - Does the app's port-controller class list still cover real hardware?
//
// The app finds USB-C and MagSafe port controllers by matching a fixed list of
// IOKit class names (`HPMPortControllerClasses.named`). If Apple ships a Mac
// with a class not on that list, every port on it disappears from the app, and
// nothing in the codebase would say so.
//
// WHY PROBE 04, AND NOT THE OBVIOUS ONE. Probe 17 is the natural place to look
// (it dumps HPM port blocks with their class names) and it is the WRONG place:
// its C source enumerates `AppleHPMInterfaceType10` and `Type11` from a
// hardcoded list of its own, so asking it "which classes exist?" only ever
// returns the two it was told to look for. Checking the app's list against it
// would be a check that reads the same source as the thing it checks, which
// this project has been burned by before and which the house rules call out by name.
// The difference is not academic: probe 17 shows two classes, probe 04 shows
// five, and the three it adds (`AppleTCControllerType10` on 325 machines,
// `AppleTCControllerType11` on 199, `AppleHPMInterfaceType18` on 5) are exactly
// the ones a probe-17 check would have silently failed to notice.
//
// Probe 04 matches `AppleHPMInterfaceType` as a BASE class, so IOKit hands it
// every subclass including ones nobody has written down, and it then recurses
// through each subtree. That makes it an independent enumeration rather than a
// restatement of the app's own list.
//
// WHAT THIS CANNOT ANSWER. Whether a port controller exists outside these two
// families entirely, which is the open question behind the `IOPort` catch-all
// in `AppleHPMInterfaceWatcher.candidateClasses`. Every probe held enumerates
// from some hardcoded root list, so none of them can see a class nobody
// anticipated. Settling that needs a probe that walks `IOPort` subclasses
// generically. Recorded here rather than glossed, because the catch-all's fate
// depends on it.
@Suite("HPM port-controller class coverage (probe 04)")
struct HPMPortControllerClassCoverageTests {

    /// Any `AppleHPMInterfaceTypeN` / `AppleTCControllerTypeN` name in the text.
    ///
    /// Matches mentions anywhere in the dump, not just node headers. That is
    /// deliberately over-broad: a class named only in some other node's
    /// property value still counts as "this name exists in the wild", and for a
    /// coverage check erring towards finding MORE names is the safe direction.
    /// A false positive here fails the test and gets investigated; a false
    /// negative silently drops a real class.
    private static func classNames(in text: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(
            pattern: #"\b(?:AppleHPMInterfaceType|AppleTCControllerType)\d+\b"#
        ) else { return [] }
        let ns = text as NSString
        return Set(
            regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
                .map { ns.substring(with: $0.range) }
        )
    }

    @Test("Every port-controller class seen in the wild is one the app matches")
    func appListCoversEveryObservedClass() {
        var filesScanned = 0
        var observed: [String: Int] = [:]

        for folder in CorpusPowerProbes.folders() {
            guard let text = CorpusPowerProbes.textAllowingTruncation(
                folder: folder, probe: "04_raw_registry_dump"
            ) else { continue }
            filesScanned += 1
            for name in Self.classNames(in: text) {
                observed[name, default: 0] += 1
            }
        }

        let known = Set(HPMPortControllerClasses.named)
        let unknown = observed.keys.filter { !known.contains($0) }.sorted()

        let summary = observed
            .sorted { $0.value > $1.value }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        print("[HPMClassCoverage] \(filesScanned) probe-04 dumps, observed: \(summary)")

        for name in unknown {
            let machines = observed[name] ?? 0
            Issue.record("""
            \(name) is published on \(machines) machine(s) in the corpus but is not in \
            HPMPortControllerClasses.named, so every port on those machines is invisible to the app. \
            Add it to that list (and check whether AppleHPMInterfaceWatcher's IOPort catch-all was \
            what was quietly covering for it).
            """)
        }

        // Fresh clone / worktree without the raw corpus fetched: probe 04 has no
        // git-tracked fixtures, so skip rather than assert on nothing.
        guard filesScanned >= 50 else {
            print("[HPMClassCoverage] only \(filesScanned) probe-04 dumps on disk, skipping the floors")
            return
        }

        // Floors at roughly 85% of the counts measured when this landed (771
        // dumps; Type10 on 434 machines, TCType10 on 325, Type11 on 347,
        // TCType11 on 199, Type18 on 5). Without these, a regex that matched
        // nothing would report "no unknown classes" and pass, which is the
        // clean-result-from-new-parsing-code trap.
        #expect(filesScanned >= 650, "only \(filesScanned) probe-04 dumps found; the corpus or the loader has shrunk")
        #expect((observed["AppleHPMInterfaceType10"] ?? 0) >= 370,
            "AppleHPMInterfaceType10 seen on only \(observed["AppleHPMInterfaceType10"] ?? 0) machines; the scan has gone quiet")
        #expect((observed["AppleTCControllerType10"] ?? 0) >= 275,
            "AppleTCControllerType10 seen on only \(observed["AppleTCControllerType10"] ?? 0) machines")
        // The rare one. It is the whole reason this test is worth having: a
        // class on 5 machines out of 771 is exactly what a hand review misses.
        #expect((observed["AppleHPMInterfaceType18"] ?? 0) >= 4,
            "AppleHPMInterfaceType18 seen on only \(observed["AppleHPMInterfaceType18"] ?? 0) machines")
    }

    @Test("The two readers agree on the named classes, and differ only by the documented catch-all")
    func readersShareOneList() {
        // `PowerService.hpmPortKeysWithRIDs` walks
        // `HPMPortControllerClasses.named` directly, so the only thing left to
        // pin is that the watcher's own list is that list plus the catch-all
        // and nothing else. Before they were shared, the two lists could drift
        // apart with nothing to notice.
        let watcherList = AppleHPMInterfaceWatcher.candidateClasses
        #expect(watcherList == HPMPortControllerClasses.named + ["IOPort"],
            "AppleHPMInterfaceWatcher.candidateClasses is no longer the shared list plus the IOPort catch-all: \(watcherList)")
        #expect(!HPMPortControllerClasses.named.contains("IOPort"),
            "the catch-all must stay out of the shared list; adding it there widens the telemetry reader silently")
    }
}
