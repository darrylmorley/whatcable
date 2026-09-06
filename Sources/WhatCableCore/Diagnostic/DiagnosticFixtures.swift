import Foundation

#if DEBUG
/// Loads the diagnostic contract fixtures exported by the diagnostic engine.
/// These are the only inputs the internal diagnostic screen renders, there is
/// no live engine integration in the app.
///
/// DEBUG-only, and deliberately NOT bundled as an app resource. The fixtures
/// carry corpus-derived reasoning, so they live under the mirror-excluded
/// `research/` tree instead of `Resources/`: that keeps them out of the shipped
/// app bundle (a release build compiles this whole file out) and off the public
/// mirror. The trade-off is that they are read from the source checkout on disk
/// rather than a resource bundle, which is fine because nothing but dev tooling
/// and tests ever reads them.
///
/// Load failures are never swallowed, a malformed or wrong-version fixture is
/// reported, not silently omitted, so a drifted contract fails visibly. Three
/// cases are kept distinct on purpose: no `research/` tree at all (public clone /
/// fresh checkout) is an expected empty result, not a failure; a `research/` tree
/// with the fixtures folder missing (a rename on the private tree) IS a failure;
/// and a `#filePath` that can no longer locate its own package is a failure too.
public enum DiagnosticFixtures {
    public struct LoadResult: Sendable {
        public let contracts: [DiagnosticContract]
        /// One entry per fixture that could not be loaded: "<file>: <reason>".
        public let failures: [String]
    }

    /// The repository root, found by walking up from this source file until a
    /// directory containing `Package.swift` is reached, or nil if none is found.
    ///
    /// This is anchored on a landmark (`Package.swift`) rather than a fixed parent
    /// count, so moving this file within the package does not silently break the
    /// lookup. A nil result means the `#filePath` anchor has genuinely drifted out
    /// of the package, which `load()` treats as a hard failure (not "nothing to
    /// load"), so a relocation is caught instead of hidden.
    static var repositoryRoot: URL? {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        // Bounded walk: package depth is small; the cap only stops an unbounded
        // loop if this ever runs somewhere with no `Package.swift` ancestor.
        for _ in 0..<16 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
                return dir
            }
            let parent = dir.deletingLastPathComponent()
            if parent == dir { break }   // reached the filesystem root
            dir = parent
        }
        return nil
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// True on the private tree, where the mirror-excluded `research/` library
    /// exists; false on the public clone or a fresh checkout that has no such
    /// tree. This, not the fixtures subfolder, is what decides whether the
    /// fixture-backed tests run or skip. Keeping the two separate is deliberate:
    /// it means renaming or moving `research/diagnostic-fixtures/` on the private
    /// tree is a loud load failure, not a silent test skip.
    static var researchTreePresent: Bool {
        guard let root = repositoryRoot else { return false }
        return isDirectory(root.appendingPathComponent("research", isDirectory: true))
    }

    /// The on-disk fixtures directory if it exists, else nil.
    public static var directory: URL? {
        guard let root = repositoryRoot else { return nil }
        let dir = root
            .appendingPathComponent("research", isDirectory: true)
            .appendingPathComponent("diagnostic-fixtures", isDirectory: true)
        return isDirectory(dir) ? dir : nil
    }

    public static func load() -> LoadResult {
        // The `#filePath` anchor could not find its own package: the source moved
        // out from under this logic. A hard failure, never a silent empty, so it
        // cannot hide behind a test skip.
        guard let root = repositoryRoot else {
            return LoadResult(contracts: [], failures: ["repository root not found from #filePath; DiagnosticFixtures locator drifted"])
        }
        // No research tree at all: public mirror / fresh clone. Nothing to load,
        // and that is expected, not an error.
        guard isDirectory(root.appendingPathComponent("research", isDirectory: true)) else {
            return LoadResult(contracts: [], failures: [])
        }
        // Research tree present but the fixtures folder is missing: a rename or
        // deletion on the private tree. Loud failure, never a silent empty.
        guard let root = directory else {
            return LoadResult(contracts: [], failures: ["fixtures directory not found at expected path: research/diagnostic-fixtures"])
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let urls = try? FileManager.default.contentsOfDirectory(
                  at: root, includingPropertiesForKeys: nil) else {
            return LoadResult(contracts: [], failures: ["fixtures directory unreadable: \(root.path)"])
        }

        var contracts: [DiagnosticContract] = []
        var failures: [String] = []
        for url in urls.filter({ $0.pathExtension == "json" })
                       .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = url.lastPathComponent
            guard let data = try? Data(contentsOf: url) else {
                failures.append("\(name): unreadable"); continue
            }
            do {
                let contract = try decoder.decode(DiagnosticContract.self, from: data)
                guard contract.schemaVersion == DiagnosticContract.supportedSchemaVersion else {
                    failures.append("\(name): unsupported schema version \(contract.schemaVersion)")
                    continue
                }
                contracts.append(contract)
            } catch {
                failures.append("\(name): decode failed (\(error))")
            }
        }
        return LoadResult(contracts: contracts, failures: failures)
    }

    /// Convenience for callers that only want the successfully-loaded contracts.
    public static func all() -> [DiagnosticContract] { load().contracts }
}
#endif
