import Foundation
import Testing
@testable import WhatCableDarwinBackend

// MARK: - Does the PHY watcher's match still reach every PHY class in the wild?
//
// The app reads per-lane transport state from `AppleT<chip>TypeCPhy` IOKit
// services. Until this test landed the watcher matched a hand-written list of
// seven leaf class names, and four leaves the corpus has were not on it
// (AppleT8103TypeCPhy on 162 probe-31 folders, AppleT6040TypeCPhy on 174,
// AppleT6050TypeCPhy on 72, AppleT8130TypeCPhy on 13, measured 2026-09-17).
// Every M1, M4 Pro, M4 Max, M5 Pro, M5 Max and A18 Pro machine published no
// PHY data at all, and nothing in the codebase said so.
//
// TWO PROBES, ONE QUESTION. Probe 31 says which leaf classes exist: its C
// source (`probes/test-kit/31_typec_phy_properties.c:131`) matches the base
// class `AppleTypeCPhy`, so IOKit hands it every subclass, including ones
// nobody has written down. That makes it an enumeration independent of the
// app's own list, the same reason `HPMPortControllerClassCoverageTests` reads
// probe 04 rather than probe 17. Probe 41 says how each leaf inherits: one
// tab-separated row per class carrying the kernel's own ancestry chain
// (`AppleT6040TypeCPhy`, `4`, `com.apple.driver.AppleT6040TypeCPhy`,
// `AppleTypeCPhy < IOService < IORegistryEntry < OSObject`).
//
// `IOServiceMatching(X)` returns X and every subclass of X, so a leaf is
// reachable from the watcher's match exactly when a name the watcher matches
// is the leaf itself or sits in that chain. That is what this test computes,
// from the corpus, against whatever the watcher matches today.
//
// Leaves are taken from both probes, and every chain must reach. Probe 31
// matches the base by the same string the watcher does, so a kernel that
// renamed the base would print no PHY section and probe 31 alone would
// never report the leaf. Probe 41 still would, and its chain would no
// longer contain the matched name, which is the miss this test is for.
//
// A leaf seen in probe 31 with no probe 41 row cannot be judged and is
// reported as a miss too. Probe 41 has shipped in the test kit since
// 2026-08-09, so a new chip arrives with both probes and a miss means "look".
@Suite("AppleTypeCPhy class coverage (probes 31 and 41)")
struct AppleTypeCPhyClassCoverageTests {

    /// Leaf class names from probe 31's base-class section headers,
    /// `--- AppleTypeCPhy[N] "AppleT6040TypeCPhy" ---`.
    ///
    /// Header lines only, on purpose. The probe also prints a
    /// `=== AppleT8132TypeCPhy ===` section banner on every machine whether
    /// or not that class exists there, so a whole-text scan would report
    /// T8132 on all 1354 dumps and the count floors below would mean nothing.
    private static func leafClassNames(in text: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(
            pattern: #"--- AppleTypeCPhy\[\d+\] "(AppleT\d+TypeCPhy)" ---"#
        ) else { return [] }
        let ns = text as NSString
        return Set(
            regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
                .map { ns.substring(with: $0.range(at: 1)) }
        )
    }

    /// Probe 41 rows for `AppleT<digits>TypeCPhy` classes: leaf name to the
    /// ancestry chains the kernel reports for it, root-most last, one entry
    /// per distinct chain.
    private static func ancestry(in text: String) -> [String: Set<[String]>] {
        var out: [String: Set<[String]>] = [:]
        for line in text.split(separator: "\n") {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard cols.count == 4,
                  cols[0].range(of: #"^AppleT\d+TypeCPhy$"#, options: .regularExpression) != nil
            else { continue }
            let chain = String(cols[3])
                .components(separatedBy: " < ")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            // A dump capped at 64 KiB can end mid-chain (`AppleTy`), and a
            // fragment would read as a base the watcher does not match.
            // Every complete chain ends at the root class.
            guard chain.last == "OSObject" else { continue }
            out[String(cols[0]), default: []].insert(chain)
        }
        return out
    }

    @Test("Every PHY class seen in the wild is one the watcher's match reaches")
    func watcherMatchReachesEveryObservedClass() {
        var probe31Dumps = 0
        var probe41Dumps = 0
        var observed: [String: Int] = [:]           // leaf -> probe-31 folders
        var chains: [String: Set<[String]>] = [:]    // leaf -> distinct kernel ancestry chains

        for folder in CorpusPowerProbes.folders() {
            if let text = CorpusPowerProbes.textAllowingTruncation(
                folder: folder, probe: "31_typec_phy_properties"
            ) {
                probe31Dumps += 1
                for name in Self.leafClassNames(in: text) {
                    observed[name, default: 0] += 1
                }
            }
            if let text = CorpusPowerProbes.textAllowingTruncation(
                folder: folder, probe: "41_class_discovery"
            ) {
                probe41Dumps += 1
                for (leaf, leafChains) in Self.ancestry(in: text) {
                    chains[leaf, default: []].formUnion(leafChains)
                }
            }
        }

        let matched = Set(AppleTypeCPhyWatcher.candidateClasses)
        // IOServiceMatching(X) returns X and every subclass of X. A leaf is
        // reached when the watcher matches it by name, or when every ancestry
        // chain the kernel has reported for it contains a matched class.
        // Every chain, not the union across folders: a kernel that parents
        // the leaf under a renamed base must not be hidden by another
        // folder's older chain.
        func reached(_ leaf: String) -> Bool {
            if matched.contains(leaf) { return true }
            guard let leafChains = chains[leaf], !leafChains.isEmpty else { return false }
            return leafChains.allSatisfy { chain in chain.contains(where: matched.contains) }
        }
        // Leaves from both probes. Probe 31 matches `AppleTypeCPhy` by the
        // same string the watcher does, so on a kernel that renamed the base
        // it prints no PHY section and never names the leaf. Probe 41 lists
        // every class from a kernel walk, so it still does.
        let leaves = Set(observed.keys).union(chains.keys)
        let missed = leaves.filter { !reached($0) }.sorted()

        let summary = observed
            .sorted { $0.value > $1.value }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        print("[PhyClassCoverage] \(probe31Dumps) probe-31 dumps, \(probe41Dumps) probe-41 dumps, observed: \(summary)")

        for name in missed {
            let chain = chains[name].map { leafChains in
                leafChains.map { $0.joined(separator: " < ") }.sorted().joined(separator: " | ")
            } ?? "no probe-41 row"
            Issue.record("""
            \(name) is in the corpus (probe 31 on \(observed[name] ?? 0) machine(s), probe 41 on \(chains[name]?.count ?? 0) chain(s)) but \
            AppleTypeCPhyWatcher.candidateClasses \(matched.sorted()) reaches neither it nor its \
            ancestry [\(chain)], so every PHY on those machines is invisible to the app.
            """)
        }

        // Fresh clone / worktree without the raw corpus: neither probe has
        // git-tracked fixtures, so skip the floors rather than assert on nothing.
        guard probe31Dumps >= 50 else {
            print("[PhyClassCoverage] only \(probe31Dumps) probe-31 dumps on disk, skipping the floors")
            return
        }

        // Floors at roughly 85% of the counts measured when this landed
        // (2026-09-17: 1354 probe-31 dumps, 189 probe-41 dumps, T8132 on 299
        // folders, T8130 on 13). Without these, a regex that matched nothing
        // would report "no misses" and pass, which is the
        // clean-result-from-new-parsing-code trap.
        #expect(probe31Dumps >= 1150,
            "only \(probe31Dumps) probe-31 dumps found, so the corpus or the loader has shrunk")
        #expect(probe41Dumps >= 160,
            "only \(probe41Dumps) probe-41 dumps found, so the corpus or the loader has shrunk")
        #expect((observed["AppleT8132TypeCPhy"] ?? 0) >= 250,
            "AppleT8132TypeCPhy seen on only \(observed["AppleT8132TypeCPhy"] ?? 0) folders, so the header scan has gone quiet")
        // The rare one. 13 folders out of 1354 is exactly what a hand review misses.
        #expect((observed["AppleT8130TypeCPhy"] ?? 0) >= 11,
            "AppleT8130TypeCPhy seen on only \(observed["AppleT8130TypeCPhy"] ?? 0) folders")
        // The ancestry parser is alive: the class this Mac mini runs has its row.
        #expect(chains["AppleT6040TypeCPhy"]?.contains { $0.contains("AppleTypeCPhy") } == true,
            "probe 41 shows no AppleTypeCPhy ancestor for AppleT6040TypeCPhy, so the ancestry parser has gone quiet")
    }

    @Test("The watcher matches the base class, not a list of leaves")
    func watcherMatchesTheBaseClass() {
        #expect(AppleTypeCPhyWatcher.candidateClasses == ["AppleTypeCPhy"],
            "a leaf list silently drops the next chip, match the base class instead: \(AppleTypeCPhyWatcher.candidateClasses)")
    }
}
