import Foundation

public enum AppInfo {
    public static let name = "WhatCable"
    public static let version: String = {
        // Single source of truth lives in the .app's Info.plist (written by
        // scripts/build-app.sh). Falls back to "dev" when run via `swift run`,
        // which has no bundled Info.plist.
        if let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            return v
        }
        // The CLI binary at Contents/Helpers/whatcable lives one extra level
        // deep, so Bundle.main doesn't auto-resolve to the .app. Walk up from
        // the executable until we find a Contents/Info.plist sibling.
        // Resolve symlinks first: when invoked via Homebrew's /opt/homebrew/bin
        // symlink, the executable path points outside the .app and walking up
        // would never find the bundle.
        let exe = Bundle.main.executablePath ?? CommandLine.arguments.first ?? ""
        var dir = URL(fileURLWithPath: exe)
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        for _ in 0..<4 {
            let plist = dir.appendingPathComponent("Info.plist")
            if let data = try? Data(contentsOf: plist),
               let parsed = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let v = parsed["CFBundleShortVersionString"] as? String {
                return v
            }
            dir = dir.deletingLastPathComponent()
        }
        return "dev"
    }()
    public static let credit = "WhatCable"
    public static let tagline = String(localized: "What can this USB-C cable actually do?", bundle: .module)
    public static let copyright = "© \(Calendar.current.component(.year, from: Date())) \(credit)"
    public static let helpURL = URL(string: "https://github.com/darrylmorley/whatcable")!

    /// Compare dot-separated numeric versions. Non-numeric segments compare as 0.
    public static func isNewer(remote: String, current: String) -> Bool {
        let r = parts(remote)
        let c = parts(current)
        for i in 0..<max(r.count, c.count) {
            let rv = i < r.count ? r[i] : 0
            let cv = i < c.count ? c[i] : 0
            if rv != cv { return rv > cv }
        }
        return false
    }

    private static func parts(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }
}
