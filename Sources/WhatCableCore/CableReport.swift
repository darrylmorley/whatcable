import Foundation
import Darwin

/// Builds the data and pre-filled GitHub issue URL behind the "Report this
/// cable" feature. Pure data assembly. The app and the CLI both render this
/// payload; nothing in here touches the network.
public enum CableReport {
    /// The cable identity an issue is being filed for, plus optional system
    /// info. Renders to a stable markdown block so reports can later be
    /// parsed back into a curated rules file.
    public struct Payload {
        public let cable: CableFingerprint
        public let system: SystemInfo?
        public let appVersion: String

        public init(cable: CableFingerprint, system: SystemInfo?, appVersion: String) {
            self.cable = cable
            self.system = system
            self.appVersion = appVersion
        }
    }

    public struct CableFingerprint {
        public let vendorID: Int
        public let productID: Int
        public let vendorIDHex: String
        public let productIDHex: String
        public let vendorName: String
        public let speed: String?
        public let currentRating: String?
        public let maxVolts: Int?
        public let maxWatts: Int?
        public let type: String?
        public let hasEmarker: Bool
        /// Raw 32-bit VDOs as the cable returned them. Included in reports
        /// so we can later distinguish "macOS dropped the field" from "the
        /// cable genuinely sent zero" when calibrating heuristics like the
        /// zero-PID flag.
        public let vdos: [UInt32]

        public init(identity: PDIdentity) {
            self.vendorID = identity.vendorID
            self.productID = identity.productID
            self.vendorIDHex = String(format: "0x%04X", identity.vendorID)
            self.productIDHex = String(format: "0x%04X", identity.productID)
            self.vendorName = VendorDB.name(for: identity.vendorID) ?? "Unregistered / unknown"
            self.vdos = identity.vdos
            if let cv = identity.cableVDO {
                self.speed = cv.speed.label
                self.currentRating = cv.current.label
                self.maxVolts = cv.maxVolts
                self.maxWatts = cv.maxWatts
                self.type = cv.cableType == .active ? "active" : "passive"
                self.hasEmarker = true
            } else {
                self.speed = nil
                self.currentRating = nil
                self.maxVolts = nil
                self.maxWatts = nil
                self.type = nil
                self.hasEmarker = (identity.endpoint == .sopPrime || identity.endpoint == .sopDoublePrime)
            }
        }
    }

    public struct SystemInfo {
        public let macModel: String
        public let macOSVersion: String

        public init(macModel: String, macOSVersion: String) {
            self.macModel = macModel
            self.macOSVersion = macOSVersion
        }

        public static func current() -> SystemInfo {
            SystemInfo(macModel: fetchMacModel(), macOSVersion: fetchOSVersion())
        }

        private static func fetchMacModel() -> String {
            var size = 0
            sysctlbyname("hw.model", nil, &size, nil, 0)
            guard size > 0 else { return "unknown" }
            var buf = [CChar](repeating: 0, count: size)
            sysctlbyname("hw.model", &buf, &size, nil, 0)
            return String(cString: buf)
        }

        private static func fetchOSVersion() -> String {
            let v = ProcessInfo.processInfo.operatingSystemVersion
            return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        }
    }

    /// Build a payload from a cable e-marker identity. Returns nil if the
    /// identity isn't a cable endpoint (SOP' / SOP'').
    public static func payload(
        for identity: PDIdentity,
        includeSystemInfo: Bool = false,
        appVersion: String = AppInfo.version
    ) -> Payload? {
        let isCable = identity.endpoint == .sopPrime || identity.endpoint == .sopDoublePrime
        guard isCable else { return nil }
        return Payload(
            cable: CableFingerprint(identity: identity),
            system: includeSystemInfo ? SystemInfo.current() : nil,
            appVersion: appVersion
        )
    }

    /// Issue endpoint the report is filed against.
    public static let issueBaseURL = URL(string: "https://github.com/darrylmorley/whatcable/issues/new")!

    /// Map a VDO array index to its role per the USB-PD spec layout for a
    /// passive / active cable Discover Identity response. Anything past the
    /// known indices is "Other" so we still surface the raw value.
    static func vdoRoleLabel(at index: Int) -> String {
        switch index {
        case 0: return "ID Header"
        case 1: return "Cert Stat"
        case 2: return "Product"
        case 3: return "Cable"
        default: return "Other"
        }
    }
}

extension CableReport.Payload {
    /// Markdown body that gets dropped into the cable-report issue template.
    /// Format is intentionally stable so future tooling can parse reports
    /// back into a curated rules file.
    public var markdown: String {
        var lines: [String] = []
        lines.append("### Cable e-marker fingerprint")
        lines.append("")
        lines.append("| Field | Value |")
        lines.append("|---|---|")
        lines.append("| Vendor ID | `\(cable.vendorIDHex)` (\(cable.vendorName)) |")
        lines.append("| Product ID | `\(cable.productIDHex)` |")
        if let speed = cable.speed {
            lines.append("| Cable speed | \(speed) |")
        }
        if let cur = cable.currentRating, let v = cable.maxVolts, let w = cable.maxWatts {
            lines.append("| Current rating | \(cur) at up to \(v)V (~\(w)W) |")
        }
        if let t = cable.type {
            lines.append("| Type | \(t) |")
        }
        lines.append("| Has e-marker | \(cable.hasEmarker ? "Yes" : "No") |")
        lines.append("")
        if !cable.vdos.isEmpty {
            lines.append("### Raw VDOs")
            lines.append("")
            lines.append("| Index | Role | Value |")
            lines.append("|---|---|---|")
            for (i, vdo) in cable.vdos.enumerated() {
                let role = CableReport.vdoRoleLabel(at: i)
                let hex = String(format: "0x%08X", vdo)
                lines.append("| \(i) | \(role) | `\(hex)` |")
            }
            lines.append("")
        }
        lines.append("### Environment")
        lines.append("")
        lines.append("- WhatCable: `\(appVersion)`")
        if let s = system {
            lines.append("- Mac: `\(s.macModel)`")
            lines.append("- macOS: `\(s.macOSVersion)`")
        } else {
            lines.append("- Mac model and macOS version: not included by reporter")
        }
        return lines.joined(separator: "\n")
    }

    /// Short, descriptive issue title. Vendor name + speed is enough to scan
    /// the issue list at a glance.
    public var issueTitle: String {
        let speedPart = cable.speed ?? "cable"
        return "[Cable Report] \(cable.vendorName), \(speedPart)"
    }

    /// Pre-filled GitHub issue URL. Targets the cable-report template and
    /// drops the fingerprint markdown into the form's `fingerprint` field.
    public var githubURL: URL {
        var components = URLComponents(url: CableReport.issueBaseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "template", value: "cable-report.yml"),
            URLQueryItem(name: "labels", value: "cable-report"),
            URLQueryItem(name: "title", value: issueTitle),
            URLQueryItem(name: "fingerprint", value: markdown)
        ]
        return components.url ?? CableReport.issueBaseURL
    }
}
