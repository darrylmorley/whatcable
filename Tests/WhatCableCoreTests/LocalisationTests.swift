import Testing
import Foundation
@testable import WhatCableCore

@Suite("Localisation")
struct LocalisationTests {

    @Test("String files have many keys")
    func stringFilesHaveManyKeys() throws {
        let bundle = Bundle.module
        let url = try #require(
            bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: "en.lproj"),
            "en.lproj/Localizable.strings not found in bundle"
        )
        let content = try String(contentsOf: url, encoding: .utf8)
        let keyLines = content.components(separatedBy: "\n").filter { $0.contains(" = ") && !$0.hasPrefix("//") }
        #expect(keyLines.count > 50, "en.lproj/Localizable.strings should have more than 50 entries")
    }

    @Test("English source strings resolve to themselves")
    func englishSourceStringsResolveToThemselves() {
        let bundle = Bundle.module
        let sample = String(localized: "Nothing connected", bundle: bundle)
        #expect(sample == "Nothing connected")
    }

    @Test("Interpolated strings resolve")
    func interpolatedStringsResolve() {
        let bundle = Bundle.module
        let result = String(localized: "Cable speed: \("USB 3.2 Gen 2 (10 Gbps)")", bundle: bundle)
        #expect(result == "Cable speed: USB 3.2 Gen 2 (10 Gbps)")
    }

    /// Every non-English Localizable.strings must define exactly the same keys
    /// as its en.lproj counterpart, with matching printf format specifiers.
    ///
    /// This guards the recurring failure mode where a key is added to en.lproj
    /// (or used in code) but a translation is never added, so the UI silently
    /// falls back to English in that language. It also catches a translation
    /// dropping or adding a `%@`/`%lld`, which crashes at format time.
    ///
    /// Files are read from the source tree (not the test bundle). Core holds
    /// the one catalogue; the localisation gate in CI fails on any `.lproj`
    /// anywhere else.
    @Test("Localisation key + format-specifier parity", arguments: [
        "Sources/WhatCableCore/Resources",
    ])
    func localisationParity(resourceDir: String) throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let base = repoRoot.appendingPathComponent(resourceDir)

        let enStrings = try loadStrings(base.appendingPathComponent("en.lproj/Localizable.strings"))
        let minimumKeyCount = 20
        #expect(enStrings.count > minimumKeyCount, "\(resourceDir)/en.lproj is unexpectedly small (\(enStrings.count) keys)")
        let enKeys = Set(enStrings.keys)

        let lprojs = try FileManager.default
            .contentsOfDirectory(atPath: base.path)
            .filter { $0.hasSuffix(".lproj") && $0 != "en.lproj" }
            .sorted()
        #expect(!lprojs.isEmpty, "\(resourceDir) has no non-English .lproj directories")

        for lproj in lprojs {
            let lang = String(lproj.dropLast(".lproj".count))
            let strings = try loadStrings(base.appendingPathComponent("\(lproj)/Localizable.strings"))

            let missing = enKeys.subtracting(strings.keys).sorted()
            let extra = Set(strings.keys).subtracting(enKeys).sorted()
            #expect(
                missing.isEmpty,
                "\(resourceDir) [\(lang)] is missing \(missing.count) key(s) present in en (falls back to English): \(missing.prefix(5))"
            )
            #expect(
                extra.isEmpty,
                "\(resourceDir) [\(lang)] has \(extra.count) key(s) not in en (stale/orphan): \(extra.prefix(5))"
            )

            for (key, _) in enStrings {
                guard let value = strings[key] else { continue }
                let keySpecs = formatSpecifiers(in: key)
                let valueSpecs = formatSpecifiers(in: value)
                #expect(
                    keySpecs == valueSpecs,
                    "\(resourceDir) [\(lang)] format specifiers differ for \"\(key)\": key \(keySpecs) vs value \(valueSpecs)"
                )
            }
        }
    }

    /// Parses a classic `"key" = "value";` strings file line by line, skipping
    /// comments and an empty-key placeholder. Deliberately not using
    /// `NSDictionary(contentsOf:)` so the check is independent of Foundation's
    /// strings-file quirks and matches what we verify manually.
    private func loadStrings(_ url: URL) throws -> [String: String] {
        let content = try String(contentsOf: url, encoding: .utf8)
        let line = try NSRegularExpression(
            pattern: #"^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;$"#
        )
        var result: [String: String] = [:]
        for raw in content.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            let ns = trimmed as NSString
            guard let m = line.firstMatch(in: trimmed, range: NSRange(location: 0, length: ns.length))
            else { continue }
            let key = ns.substring(with: m.range(at: 1))
            if key.isEmpty { continue }
            result[key] = ns.substring(with: m.range(at: 2))
        }
        return result
    }

    /// Sorted multiset of printf conversions (length modifier + type), ignoring
    /// the positional index, since grammatical reordering between languages
    /// legitimately changes `%1$@`/`%2$@` order while the conversions must match.
    private func formatSpecifiers(in s: String) -> [String] {
        let re = try! NSRegularExpression(pattern: #"%(?:[0-9]+\$)?(l*)([@a-zA-Z])"#)
        let ns = s as NSString
        var specs: [String] = []
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            specs.append(ns.substring(with: m.range(at: 1)) + ns.substring(with: m.range(at: 2)))
        }
        return specs.sorted()
    }
}
