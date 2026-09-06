import Foundation
import os.log

private let _usb3CorroborationLog = Logger(subsystem: "uk.whatcable.whatcable", category: "usb3-corroboration")

/// One choke point for two USB3 speed decisions every rendering surface
/// needs: which `USB3Transport` belongs to a port, and whether a live USB3
/// signal is corroborated by anything besides the transport itself
/// (issue #181).
///
/// Without this gate, the HPM port controller briefly publishes `USB3` in
/// `TransportsActive` during cable orientation / SuperSpeed handshake on a
/// charger-only cable (no SuperSpeed peer). PD negotiation then discovers
/// there is no data peer and withdraws it. The settled state (no USB3 line)
/// is correct; the flash is real system state but reads as the app losing
/// information it briefly had. See
/// `planning/dar-50-usb3-speed-corroboration.md` for the full design.
public enum USB3SpeedCorroboration {

    /// The ONE way every surface picks a port's direct (non-tunnelled) USB3
    /// transport: canonically matched (UUID-keyed, portKey fallback), with
    /// `tunnelled != true`. Returns nil when no such transport exists.
    /// `PortSummary`, `JSONFormatter`, `DataLinkDiagnostic`, and
    /// `CableDiagnosticView` all switch to this instead of each running
    /// their own slightly different selection.
    ///
    /// Tie policy. More than one canonically-matched non-tunnelled entry
    /// should never occur (one USB3 transport node per physical port), but
    /// the ordering below is total so a violation is deterministic rather
    /// than array-order-dependent:
    /// 1. Match STRENGTH first: an exact valid-UUID match always beats a
    ///    portKey-fallback match. `hpmControllerUUID` is optional and
    ///    `canonicallyMatches` admits both strengths, so strength has to be
    ///    an explicit tier, not an accident of sort keys.
    /// 2. Within a strength tier: ascending normalised UUID (nil/invalid
    ///    ordered last via a sentinel), then portKey, then the transport's
    ///    unique registry-entry `id`.
    /// A fired tie (two candidates sharing the same rank) logs a warning
    /// but still returns a deterministic winner.
    public static func selectedTransport(
        for port: AppleHPMInterface, in transports: [USB3Transport]
    ) -> USB3Transport? {
        let candidates = transports.filter {
            $0.tunnelled != true && $0.canonicallyMatches(port: port)
        }
        guard !candidates.isEmpty else { return nil }
        guard candidates.count > 1 else { return candidates[0] }

        let ranked = candidates.sorted { sortKey(for: $0, port: port) < sortKey(for: $1, port: port) }
        if sortKey(for: ranked[0], port: port).ranksIdentically(ignoringIDTo: sortKey(for: ranked[1], port: port)) {
            let portName = port.serviceName
            _usb3CorroborationLog.warning("USB3 transport selection tie on \(portName): entry ids \(ranked[0].id) and \(ranked[1].id)")
        }
        return ranked[0]
    }

    /// Whether a live USB3 transport reading is corroborated by anything
    /// other than the transport itself.
    ///
    /// True when ANY of:
    /// - `USBDevice.rootSuperSpeed(in:)` or `USBDevice.portMatchedSuperSpeed(in:)`
    ///   is non-nil (a real SuperSpeed device enumerated on this port), OR
    /// - `hasNativeSuperSpeedDevice(in:)`: a natively-attached SuperSpeed
    ///   device the two arms above miss because it sits behind a hub on a
    ///   Mac that publishes no port naming (see that method), OR
    /// - `selected?.transportRestricted == true`: exactly the predicate the
    ///   `.blockedBySecurity` verdict already keys on, no more.
    ///   `USB3Transport` only carries `transportRestricted`; a bare
    ///   `TRMTransport` restriction is documented to also occur on
    ///   accessories with no data to offer, so it is not on its own
    ///   evidence of a real link and is deliberately NOT consulted here.
    ///
    /// A restriction on any OTHER entry (USB2, CIO, tunnelled, wrong port,
    /// or a TRM record for a no-data accessory) corroborates nothing: it
    /// never reaches this function because `selected` is already the
    /// canonically-matched direct transport.
    public static func isCorroborated(
        selected: USB3Transport?,
        devices: [USBDevice]
    ) -> Bool {
        // Every arm runs against devices that reached this port NATIVELY.
        // A device that arrived over a Thunderbolt tunnel says nothing
        // about whether THIS port's own USB3 link is real.
        //
        // Filtering here rather than at each call site is deliberate.
        // `rootSuperSpeed` keys on `isRootDevice`, which counts locationID
        // hub nibbles, and a locationID is relative to whichever controller
        // enumerated the device. A drive plugged straight into a dock is
        // therefore a "root" device of the DOCK's controller and passes that
        // test unchanged. Measured on the corpus: 122 dock-attached
        // SuperSpeed devices across 84 machines have exactly one nibble and
        // would corroborate a native port this way. One caller
        // (`CableDiagnosticView`) passes the tunnel-inclusive union, so
        // without this filter a dock's own drive could light a phantom
        // speed label on the host port during the very handshake window
        // issue #181 exists to suppress. Adversarial review, PR #528.
        //
        // An internal-hub device is kept ONLY when it carries a port name.
        // An earlier revision of this filter excluded every
        // `isBehindInternalHub` device and that was a regression, caught by
        // both reviewers: on a desktop, a front USB-C port's device sits
        // behind the Mac's own board hub and carries the flag, yet
        // `matchingDevices` legitimately attributes it to the physical port
        // when `controllerPortName` is an EXACT match (issue #456,
        // `claimsInternalHubDevice`). Such a device is really on this port
        // and its link is really SuperSpeed. A real corpus machine loses
        // its label without this: `m1_macos26.5.2_f` `Port-USB-C@3`, an M1
        // desktop with a WD My Book behind a Satechi hub.
        //
        // The name is what makes it credible: the exact-name claim is the
        // ONLY route by which an internal-hub device reaches a port-scoped
        // list at all (the bus-index fallback excludes them outright). So a
        // nameless internal-hub device belongs to no port and must not
        // corroborate one, which also keeps this honest if a caller ever
        // passes a list it hasn't scoped. Codex + adversarial review, PR #528.
        let native = devices.filter { device in
            if device.isThunderboltTunnelled { return false }
            if device.isBehindInternalHub { return device.controllerPortName != nil }
            return true
        }

        if USBDevice.rootSuperSpeed(in: native) != nil { return true }
        if USBDevice.portMatchedSuperSpeed(in: native) != nil { return true }
        if hasNativeSuperSpeedDevice(in: native) { return true }
        return selected?.transportRestricted == true
    }

    /// Any natively-attached SuperSpeed device on this port, including one
    /// sitting behind a hub.
    ///
    /// The two arms above miss exactly one real shape: a SuperSpeed device
    /// behind a hub on a Mac where macOS publishes no `UsbIOPort` naming
    /// (macOS 15 and earlier). Such a device is not a root device (its
    /// locationID carries more than one hub nibble) and has no
    /// `controllerPortName`, so it corroborated nothing, and the port lost
    /// a speed line it had legitimately earned. Measured on the corpus:
    /// 10 machines of 269, all macOS 15, every one a fast drive behind a
    /// plain hub. `USB3CorroborationBusIndexSweepTests` replays it.
    ///
    /// Sound because SuperSpeed is end to end: a device that negotiated
    /// SuperSpeed behind a hub proves every link up to the port is
    /// SuperSpeed too. This answers only "is a real SuperSpeed link
    /// present" (corroboration); it deliberately does NOT feed the speed
    /// VALUE, which still comes from `portMatchedSuperSpeed`'s narrower
    /// rule, because a device several hops down can negotiate a rate that
    /// overstates the port's own link.
    ///
    /// Tunnelled devices are excluded (they reach the Mac by Thunderbolt
    /// topology and say nothing about this port's own link); the caller
    /// already filters them, and repeating it here keeps this method
    /// correct if it is ever called directly. Internal-hub devices are NOT
    /// excluded: on a desktop front port they are genuinely this port's
    /// devices, claimed by exact name (see the note in `isCorroborated`).
    ///
    /// Callers pass a PORT-SCOPED device list; every arm of this function
    /// already relies on that, and this one no more than the others.
    private static func hasNativeSuperSpeedDevice(in devices: [USBDevice]) -> Bool {
        devices.contains {
            ($0.speedRaw ?? 0) >= 3 && !$0.isThunderboltTunnelled
        }
    }

    // MARK: - Tie ordering

    /// `id` is part of both `<` and the synthesised, member-wise `==`, so
    /// the two stay consistent (Comparable requires that equal values never
    /// compare less than one another; leaving `id` out of `==` while
    /// keeping it in `<` broke that for two candidates that differ only by
    /// `id`, which is exactly the common case: `id` is a unique
    /// registry-entry id, so it differs on every real pair). The
    /// fired-tie warning below needs a DIFFERENT, narrower notion of
    /// "the same rank ignoring id", so that lives in its own method
    /// (`ranksIdentically(ignoringIDTo:)`), not in `==`.
    private struct SortKey: Comparable {
        let strength: Int
        let uuid: String
        let portKey: String
        let id: UInt64

        static func < (lhs: SortKey, rhs: SortKey) -> Bool {
            if lhs.strength != rhs.strength { return lhs.strength < rhs.strength }
            if lhs.uuid != rhs.uuid { return lhs.uuid < rhs.uuid }
            if lhs.portKey != rhs.portKey { return lhs.portKey < rhs.portKey }
            return lhs.id < rhs.id
        }

        /// True when two keys rank identically for selection purposes,
        /// ignoring `id` (a fired tie: same strength, same uuid, same
        /// portKey, distinguished only by which registry entry happens to
        /// carry the data). Used only to decide whether to log the
        /// tie-break warning.
        func ranksIdentically(ignoringIDTo other: SortKey) -> Bool {
            strength == other.strength && uuid == other.uuid && portKey == other.portKey
        }
    }

    private static func sortKey(for transport: USB3Transport, port: AppleHPMInterface) -> SortKey {
        SortKey(
            strength: matchStrength(transport, port: port),
            // Sentinel sorts last: normalised UUIDs are always exactly 32
            // lowercase hex characters, so this is never a real value.
            uuid: normalisedUUID(transport.hpmControllerUUID) ?? "\u{FFFF}",
            portKey: transport.portKey,
            id: transport.id
        )
    }

    /// 0 = exact valid-UUID match (strongest), 1 = portKey-fallback match.
    private static func matchStrength(_ transport: USB3Transport, port: AppleHPMInterface) -> Int {
        if let srcUUID = normalisedUUID(transport.hpmControllerUUID),
           let portUUID = normalisedUUID(port.hpmControllerUUID),
           srcUUID == portUUID {
            return 0
        }
        return 1
    }

    /// Normalises to 32 lowercase hex characters, or nil if the value isn't
    /// a valid UUID once dashes are stripped. Validating the characters
    /// (not just the length) matters here: a malformed 32-character value
    /// must sort as invalid/nil (last, via the sentinel in `sortKey`), the
    /// same way a genuinely absent UUID does, not be treated as a real,
    /// comparable UUID.
    private static func normalisedUUID(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let n = raw.replacingOccurrences(of: "-", with: "").lowercased()
        guard n.count == 32, n.allSatisfy({ $0.isHexDigit }) else { return nil }
        return n
    }
}
