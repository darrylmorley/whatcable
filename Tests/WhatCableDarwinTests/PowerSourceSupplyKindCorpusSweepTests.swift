import Testing
import Foundation
@testable import WhatCableDarwinBackend
@testable import WhatCableCore

/// Phase 2, item 2. Replays every `WinningPowerSourceOption` block in probe 17
/// through the real class-string parse.
///
/// The floor assertions matter more than the pass. A regex that matches
/// nothing returns a clean sweep, and this repo has been burned by exactly
/// that three times in one session. So the sweep asserts it FOUND blocks and
/// that it classified them, and a deliberate-break check proves it can go red.
///
/// WHAT THIS SWEEP CANNOT CHECK, and it is half the job. It validates block
/// FINDING, not Class READING. The corpus holds exactly one distinct `Class`
/// value across all 1122 blocks, so a reader that ignored the probe text
/// entirely and returned the expected string as a constant would pass this
/// sweep completely clean. That is inherent in the data, not a gap someone
/// forgot to close, and no amount of extra corpus work fixes it: there is no
/// second value in the corpus to tell a real parse from a hardcoded one.
/// Shown by PR #599's review gate.
///
/// The other half is covered by the companion unit test in this file,
/// ``failsClosedOnUnknownClass``, which feeds the classifier strings the
/// corpus does not contain and pins that they do NOT reach `.fixed`. That is
/// what proves the classifier is a function of its input rather than a
/// constant. Do not read a green sweep on its own as evidence the parse is
/// right; the two tests are only meaningful together.
@Suite("PowerSource supply kind corpus sweep")
struct PowerSourceSupplyKindCorpusSweepTests {

    @Test("Every winning option in the corpus carries a class string and parses as fixed")
    func everyWinningOptionParsesFixed() throws {
        let folders = CorpusPowerProbes.foldersWithProbe17()
        try #require(!folders.isEmpty, "corpus missing: run scripts/link-research.sh")

        var blocks = 0
        var fixed = 0
        var dashShapeBlocks = 0
        var equalsShapeBlocks = 0
        var missingClass: [String] = []
        var notFixed: [String] = []
        var contributingFolders: Set<String> = []
        var rawMarkerTotal = 0
        var perFolderCountMismatch: [String] = []
        var perFolderShapeExcess: [String] = []

        for folder in folders {
            guard let text = CorpusPowerProbes.probe17Text(folder) else { continue }
            let found = CorpusPowerProbes.winningOptionClassStrings(in: text)

            // An independent tally of the SAME thing, computed here and
            // sharing no code with the reader: a plain substring count of the
            // block marker. See the "per-folder invariants" note below for
            // why this, and not a numeric band, is what actually pins the
            // reader.
            let rawMarkers = text.components(separatedBy: "WinningPowerSourceOption: {").count - 1
            rawMarkerTotal += rawMarkers
            if found.count != rawMarkers {
                perFolderCountMismatch.append("\(folder): \(rawMarkers) markers, \(found.count) blocks")
            }

            var folderDash = 0
            var folderEquals = 0
            for block in found {
                blocks += 1
                contributingFolders.insert(folder)
                switch block.shape {
                case .dash: dashShapeBlocks += 1; folderDash += 1
                case .equals: equalsShapeBlocks += 1; folderEquals += 1
                case nil: break
                }
                guard let cls = block.classString else { missingClass.append(folder); continue }
                switch PowerSourceWatcher.supplyKind(fromOptionClass: cls) {
                case .fixed: fixed += 1
                case .nonFixed, .unknown: notFixed.append("\(folder): \(cls)")
                }
            }
            if folderDash > 1 || folderEquals > 2 {
                perFolderShapeExcess.append("\(folder): \(folderDash) dash, \(folderEquals) equals")
            }
        }

        // PER-FOLDER INVARIANTS. These, not the numeric bands below, are what
        // make this sweep hard to fool, and they are the part that does not
        // need re-measuring as the corpus grows.
        //
        // The bands were measured against the whole corpus, so they can only
        // ever say "the total looks about right", and PR #599's gate showed
        // how much room "about" left: duplicating every 4th dash block (165
        // extra) and dropping every 7th block (about 14%) BOTH passed the
        // previous bounds green. Reproduced here before changing anything,
        // by mutating `winningOptionClassStrings` and running the sweep.
        //
        // A per-folder invariant closes that, because both mutations change
        // the relationship between what a folder's text contains and what the
        // reader returned for it, no matter how many folders there are:
        //
        //  - block count against a raw marker tally. Measured 2026-09-03:
        //    the reader returns EXACTLY one block per
        //    `WinningPowerSourceOption: {` occurrence in all 1339 folders,
        //    zero exceptions. Any duplication or any drop breaks this, at any
        //    corpus size.
        //  - blocks per shape per folder. Measured over the same 1339: a
        //    folder yields 0 or 1 dash block (never 2), and 0, 1 or 2 equals
        //    blocks (883 folders with none, 451 with one, 5 with two). A
        //    shape-specific double-count breaks this even if the reader also
        //    dropped blocks elsewhere and kept the total plausible.
        //
        // If a future probe genuinely starts printing two dash blocks in one
        // folder, this fails and the right response is to re-measure and
        // widen it. It is not a reason to delete it.
        #expect(perFolderCountMismatch.isEmpty, "reader disagreed with a raw marker count: \(perFolderCountMismatch.prefix(5))")
        #expect(blocks == rawMarkerTotal, "\(blocks) blocks against \(rawMarkerTotal) raw markers in the same text")
        #expect(perFolderShapeExcess.isEmpty, "more blocks of one shape in a folder than the corpus has ever shown: \(perFolderShapeExcess.prefix(5))")

        // Floors: measured 2026-09-03 over 1339 folders carrying an
        // untruncated probe 17, twice with independent parsers (this sweep
        // itself, and a line-based Python reader that shares no code with
        // it). Both agreed exactly: 1122 winning blocks, 661 under the flat
        // dash header and 461 under the nested equals header, every one
        // carrying a Class key and every one fixed.
        //
        // SAY THE TOLERANCE PLAINLY, because the previous version of this
        // comment implied these bands were tight and they were not. Each
        // floor now sits 8% under its measured count and each ceiling 12%
        // above it. So the deliberate, remaining slack is: up to 8% of the
        // blocks of any shape can vanish, and up to 12% can be invented,
        // without this band noticing. That is not tight, and it is not the
        // tightest a band could be either. It is a choice with margin on both
        // sides of the two mutations PR #599's gate found: the 165-block dash
        // double-count is +25% on the dash count, and dropping every 7th
        // block takes the three counts to 962, 570 and 392 against 1122, 661
        // and 461, so about 14% off each. A floor at 14% would technically
        // still catch that drop and would have no margin at all, which is why
        // it is not set there. The slack these bands do leave is covered by
        // the per-folder invariants above, which have no tolerance at all.
        //
        // Ceilings are the side that will need maintenance, because growth
        // only pushes counts up: 12% growth in probe-17 machines carrying a
        // winning option and this test goes red on a healthy corpus. That is
        // intended. Re-measure and raise it; do not delete it. Floors are not
        // threatened by growth, only by a corpus that shrinks, which in
        // practice means a partial checkout.
        #expect(blocks >= 1032, "only \(blocks) winning-option blocks found against 1122 measured; parser is probably broken")
        #expect(missingClass.isEmpty, "winning options with no Class key: \(missingClass.prefix(5))")
        #expect(notFixed.isEmpty, "winning options that did not parse as fixed: \(notFixed.prefix(5))")
        #expect(fixed == blocks)

        // CEILINGS. Every bound above this point is a floor, and floors are
        // blind in one direction: a reader that counts the same block twice
        // sails through all of them, and doing so is not hypothetical. Probe
        // 32 genuinely prints its whole battery node twice (once under its
        // own section, again under `=== AppleACAdapter / ChargerData ===`),
        // and a probe-32 count that missed that is what put a fabricated
        // "unexplained discrepancy" into `PowerOption.SupplyKind` for two
        // rounds of this PR. Probe 17 has no such duplicate section today,
        // which is exactly why a reader that grew one would go unnoticed.
        //
        // Measured 2026-09-03 by a line-based Python reader sharing no code
        // with this sweep: 1122 blocks, 661 dash, 461 equals, spread over 672
        // of the 1339 folders carrying an untruncated probe 17.
        //
        // These were 40% above measured, which is where the 165-block dash
        // double-count got through: 826 dash blocks against a ceiling of 925.
        // At 12% the same mutation fails on the dash ceiling (740) and on the
        // total (1256 against 1287 blocks), which was checked by running it,
        // not by arithmetic alone.
        #expect(blocks <= 1256, "\(blocks) winning-option blocks found against 1122 measured; a reader counting the same block twice looks like this")
        #expect(dashShapeBlocks <= 740, "\(dashShapeBlocks) flat blocks against 661 measured; suspect double counting")
        #expect(equalsShapeBlocks <= 516, "\(equalsShapeBlocks) nested blocks against 461 measured; suspect double counting")

        // Folder-level tolerance, and what it does NOT cover. These two
        // floors catch a checkout whose research symlink resolved but reached
        // only part of the corpus. They say nothing about drops WITHIN a
        // retained folder: every folder can still be present and contributing
        // while the reader quietly loses blocks inside them, which is exactly
        // the every-7th-block mutation. The per-folder marker check above is
        // what covers that; these are a corpus-presence check, nothing more.
        // Measured 2026-09-03: 1339 folders scanned, 672 contributing. Both
        // floors sit 8% under, same rule as the block floors.
        #expect(folders.count >= 1231, "only \(folders.count) folders carry an untruncated probe 17 (measured 1339); the corpus link looks partial")
        #expect(contributingFolders.count >= 618, "only \(contributingFolders.count) folders contributed a winning-option block (measured 672)")

        // A bare total floor is not load-bearing on its own: a reader that
        // recognises only the flat `--- Class[N] ---` shape and silently
        // drops every nested `=== Class ===` block (M3+ only) still clears
        // any floor comfortably below the true count, and the corpus holds
        // enough M1/M2-only folders that the flat shape alone would too.
        // Both shapes must be represented, or the sweep is blind to whichever
        // one it lost. This is the exact bug PR #599's Claude adversarial
        // review found: a reader narrowed to one shape dropped 461 of 1122
        // blocks, spread across 456 folders, and the old floor of 400 stayed
        // green. (An earlier version of this comment said 11 folders. That
        // was wrong; re-derived 2026-09-03 and the equals-shape blocks span
        // 456 distinct folders.)
        //
        // Each shape gets a real floor rather than `> 0`, because one
        // surviving block of a shape satisfies `> 0` while telling us
        // nothing.
        #expect(dashShapeBlocks >= 608, "only \(dashShapeBlocks) flat '--- Class[N] ---' blocks found (measured 661); the reader may have narrowed to one shape")
        #expect(equalsShapeBlocks >= 424, "only \(equalsShapeBlocks) nested '=== Class ===' blocks found (measured 461); the reader may have narrowed to one shape")
        #expect(dashShapeBlocks + equalsShapeBlocks == blocks, "every block should be attributed to exactly one shape")
    }

    @Test("The parse fails closed on anything that is not the known fixed class")
    func failsClosedOnUnknownClass() {
        // No corpus machine has ever reported a non-fixed class, and no
        // active contract that resolves against its advertised PDO list is
        // augmented (re-derived 2026-09-03; the one non-fixed selection in the
        // corpus is Variable, on a losing port on `m1_macos26.5.2_af`, which
        // `PowerOption.SupplyKind` sets out in full). So we cannot know
        // what a PPS class string looks like. Anything unrecognised must not
        // reach `.fixed`. This is the deliberate-break check for the sweep
        // above: it proves the classifier can return something other than
        // `.fixed`, so a green sweep means the data is fixed rather than the
        // classifier being a constant.
        #expect(PowerSourceWatcher.supplyKind(fromOptionClass: "IOPortFeaturePowerSourceOptionAugmented") == .nonFixed)
        #expect(PowerSourceWatcher.supplyKind(fromOptionClass: "IOPortFeaturePowerSourceOptionBattery") == .nonFixed)
        #expect(PowerSourceWatcher.supplyKind(fromOptionClass: "SomethingElseEntirely") == .nonFixed)
        #expect(PowerSourceWatcher.supplyKind(fromOptionClass: "IOPortFeaturePowerSourceOptionFixed") == .fixed)
    }

    @Test("parseOption treats a present but non-string Class as reported, not absent")
    func parseOptionFailsClosedOnPresentNonStringClass() throws {
        // Finding 1, PR #599 gate (Codex, confidence 0.97). The old line was
        // `(dict["Class"] as? String).map(supplyKind(fromOptionClass:)) ?? .unknown`,
        // which cannot tell "the key is absent" from "the key is present but
        // holds something that does not cast to String" (an unexpected CF
        // type, or NSNull). Both landed on `.unknown`, the weaker branch that
        // falls back to the phase-1 voltage-tier proxy and ACCEPTS a contract
        // sitting at exactly 5/9/12/15/20 V. A malformed but definitely-present
        // Class value is positive evidence something was reported, so it must
        // classify as `.nonFixed`, never `.unknown`.
        //
        // An empty string is NOT one of those cases, and an earlier version of
        // this comment wrongly listed it as one. An empty string casts to
        // String perfectly well, so the old line ran it through
        // `supplyKind(fromOptionClass:)`, where it failed to equal the fixed
        // class and came out `.nonFixed`. It reaches `.nonFixed` under the new
        // code too, by the present-but-unreadable branch. Same verdict before
        // and after; measured both ways 2026-09-03. The behaviour this test
        // guards is the non-string case only.
        let malformed: [String: Any] = [
            "Voltage (mV)": NSNumber(value: 20_000),
            "Max Current (mA)": NSNumber(value: 4_700),
            "Class": NSNumber(value: 1),  // present, but not a string
        ]
        let winning = try #require(PowerSourceWatcher.parseOption(malformed))
        #expect(winning.supplyKind == .nonFixed)

        // End to end: at 20 V, a standard SPR tier, this must NOT resolve a
        // charging input. Under the old code it would have: a malformed
        // Class fell to `.unknown`, and `.unknown` at 20 V passes the tier
        // proxy.
        let source = PowerSource(
            id: 1, name: "USB-PD", parentPortType: 0x2, parentPortNumber: 4,
            options: [winning], winning: winning, hpmControllerUUID: nil
        )
        #expect(ChargingInputResolver.fingerprint(
            sources: [source], batteryInstalled: true, externalConnected: true, chargerAttached: true
        ) == nil)
    }
}
