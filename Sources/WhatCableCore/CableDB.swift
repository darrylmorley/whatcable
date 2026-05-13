import Foundation
import SQLite3

/// Read-only SQLite-backed lookup for vendors and known cables.
///
/// Loaded lazily on first use from the bundled `whatcable.db`. All rows
/// are read into in-memory dictionaries on init, then the database handle
/// is closed. For ~14k vendors and a handful of cables this is a few
/// hundred KB of resident memory, same as the old TSV loader.
///
/// Uses the system SQLite3 C API (a macOS system framework), so there's
/// no SPM dependency to add.
public enum CableDB {
    /// Vendor entry with provenance tracking.
    struct VendorEntry {
        let name: String
        /// "usbif", "usbids", or "manual".
        let source: String
    }

    private static let store: Store = Store.load()

    /// Look up a vendor name by VID. Returns names from any source
    /// (USB-IF, usb.ids, manual). Returns nil for unknown VIDs and
    /// for VID 0 (which is filtered at the presentation layer by
    /// `VendorDB`, not here).
    public static func vendorName(vid: Int) -> String? {
        store.vendors[vid]?.name
    }

    /// True only if the VID is in USB-IF's official published list.
    /// Used by `CableTrustReport` to decide whether to fire the
    /// `vidNotInUSBIFList` flag. A VID present via usb.ids or manual
    /// override returns false here, preserving the trust signal
    /// semantics.
    public static func isUSBIFRegistered(_ vid: Int) -> Bool {
        store.vendors[vid]?.source == "usbif"
    }

    /// Look up a known cable by its e-marker fingerprint. Returns
    /// nil when the cable isn't in our curated database.
    public static func curatedCable(
        vid: Int,
        pid: Int,
        cableVDO: UInt32
    ) -> CuratedCable? {
        store.cables[CableKey(vid: vid, pid: pid, cableVDO: cableVDO)]
    }

    /// Number of vendor entries loaded. Exposed for tests.
    public static var vendorCount: Int { store.vendors.count }

    /// Number of cable entries loaded. Exposed for tests.
    public static var cableCount: Int { store.cables.count }
}

/// A cable identified by user reports and curated into the database.
public struct CuratedCable {
    public let brand: String
    public let speed: String
    public let power: String
    public let type: String
    public let issueURL: String
}

// MARK: - Internal types

private struct CableKey: Hashable {
    let vid: Int
    let pid: Int
    let cableVDO: UInt32
}

private struct Store {
    let vendors: [Int: CableDB.VendorEntry]
    let cables: [CableKey: CuratedCable]

    static func load() -> Store {
        guard let url = Bundle.module.url(forResource: "whatcable", withExtension: "db")
                ?? findResourceURL(name: "whatcable", ext: "db") else {
            return Store(vendors: [:], cables: [:])
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(
            url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil
        ) == SQLITE_OK else {
            return Store(vendors: [:], cables: [:])
        }
        defer { sqlite3_close(db) }

        let vendors = loadVendors(db: db!)
        let cables = loadCables(db: db!)

        return Store(vendors: vendors, cables: cables)
    }

    private static func loadVendors(db: OpaquePointer) -> [Int: CableDB.VendorEntry] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(
            db, "SELECT vid, name, source FROM vendors", -1, &stmt, nil
        ) == SQLITE_OK else {
            return [:]
        }
        defer { sqlite3_finalize(stmt) }

        var map: [Int: CableDB.VendorEntry] = [:]
        map.reserveCapacity(15000)

        while sqlite3_step(stmt) == SQLITE_ROW {
            let vid = Int(sqlite3_column_int(stmt, 0))
            guard let namePtr = sqlite3_column_text(stmt, 1),
                  let sourcePtr = sqlite3_column_text(stmt, 2) else { continue }
            let name = String(cString: namePtr)
            let source = String(cString: sourcePtr)
            map[vid] = CableDB.VendorEntry(name: name, source: source)
        }
        return map
    }

    private static func loadCables(db: OpaquePointer) -> [CableKey: CuratedCable] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(
            db, "SELECT vid, pid, cable_vdo, brand, speed, power, type, issue_url FROM cables",
            -1, &stmt, nil
        ) == SQLITE_OK else {
            return [:]
        }
        defer { sqlite3_finalize(stmt) }

        var map: [CableKey: CuratedCable] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let vid = Int(sqlite3_column_int(stmt, 0))
            let pid = Int(sqlite3_column_int(stmt, 1))
            let cableVDO = UInt32(bitPattern: sqlite3_column_int(stmt, 2))
            guard let brandPtr = sqlite3_column_text(stmt, 3) else { continue }

            let key = CableKey(vid: vid, pid: pid, cableVDO: cableVDO)
            map[key] = CuratedCable(
                brand: String(cString: brandPtr),
                speed: sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? "",
                power: sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? "",
                type: sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? "",
                issueURL: sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? ""
            )
        }
        return map
    }
}

// MARK: - Resource resolution

/// Find a bundled resource across the contexts WhatCableCore runs in:
/// SwiftPM tests / `swift run`, the .app's GUI binary in Contents/MacOS/,
/// and the CLI binary in Contents/Helpers/. This is the same search
/// strategy the old TSV loader used, extracted so both the vendor TSV
/// (if ever needed) and the SQLite DB can share it.
func findResourceURL(name: String, ext: String) -> URL? {
    let bundleName = "WhatCable_WhatCableCore"
    let fm = FileManager.default

    var roots: [URL] = []

    let env = ProcessInfo.processInfo.environment
    if let override = env["PACKAGE_RESOURCE_BUNDLE_PATH"] ?? env["PACKAGE_RESOURCE_BUNDLE_URL"] {
        roots.append(URL(fileURLWithPath: override))
    }

    if let r = Bundle.main.resourceURL { roots.append(r) }
    if let r = Bundle(for: BundleFinder.self).resourceURL { roots.append(r) }
    roots.append(Bundle.main.bundleURL)
    roots.append(Bundle.main.bundleURL.deletingLastPathComponent())
    roots.append(Bundle(for: BundleFinder.self).bundleURL.deletingLastPathComponent())

    if let exe = Bundle.main.executableURL {
        let parent = exe.deletingLastPathComponent()
        let contents = parent.deletingLastPathComponent()
        roots.append(contents.appendingPathComponent("Resources"))
    }

    for root in roots {
        let viaBundle = root
            .appendingPathComponent("\(bundleName).bundle")
            .appendingPathComponent("\(name).\(ext)")
        if fm.fileExists(atPath: viaBundle.path) { return viaBundle }

        let loose = root.appendingPathComponent("\(name).\(ext)")
        if fm.fileExists(atPath: loose.path) { return loose }
    }
    return nil
}

private final class BundleFinder {}
