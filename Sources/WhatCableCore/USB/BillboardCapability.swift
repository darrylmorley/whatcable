import Foundation

/// What a USB-C device's Billboard Capability Descriptor advertises: the list
/// of Alternate Modes it declares support for (DisplayPort, Thunderbolt, ...)
/// and, per mode, whether that mode actually came up.
///
/// This is read from the device's BOS descriptor (Binary Object Store, device
/// capability type `0x0d`). It is *platform-free*: the Darwin backend reads the
/// raw bytes from IOKit and hands a parsed value in here; Core never touches
/// IOKit.
///
/// Plain-English framing: a device advertising DisplayPort Alt Mode is normal,
/// not a fault. Only a per-mode *failed* state (`unsuccessful` / `error`)
/// suggests something didn't come up. `notAttempted` stays benign: the 2-bit
/// field can't tell "never tried" apart from "was up, then exited".
public struct BillboardCapability: Codable, Hashable, Sendable {
    /// The per-mode "Alternate Mode State" from the descriptor's `bmConfigured`
    /// field (2 bits per mode). Raw values match the USB Billboard Device Class
    /// spec encoding so the backend can build them straight from the bits and
    /// the JSON stays stable.
    public enum AltModeState: Int, Codable, Hashable, Sendable {
        case error = 0          // unspecified error
        case notAttempted = 1   // not attempted, or entered then exited
        case unsuccessful = 2   // attempted but did not come up
        case configured = 3     // came up successfully

        /// True only for states that indicate a mode tried and did not come up.
        /// `notAttempted` is deliberately excluded (it is benign).
        public var isFailure: Bool {
            self == .error || self == .unsuccessful
        }
    }

    /// One advertised Alternate Mode.
    public struct AltMode: Codable, Hashable, Sendable {
        /// Standard or Vendor ID identifying the Alt Mode (e.g. `0xFF01` for
        /// DisplayPort, `0x8087` for Thunderbolt).
        public let svid: UInt16
        public let state: AltModeState

        public init(svid: UInt16, state: AltModeState) {
            self.svid = svid
            self.state = state
        }

        /// Plain-English name for well-known SVIDs, else `nil`.
        public var protocolName: String? {
            switch svid {
            case 0xFF01: return "DisplayPort"
            case 0x8087: return "Thunderbolt"
            case 0xFF00: return "USB"
            default: return nil
            }
        }
    }

    public let altModes: [AltMode]
    /// Index into `altModes` of the device's preferred mode, if the descriptor
    /// names one and it is in range. `nil` otherwise.
    public let preferredIndex: Int?

    public init(altModes: [AltMode], preferredIndex: Int? = nil) {
        self.altModes = altModes
        if let preferredIndex, altModes.indices.contains(preferredIndex) {
            self.preferredIndex = preferredIndex
        } else {
            self.preferredIndex = nil
        }
    }

    /// True when the device advertises DisplayPort Alt Mode at all (any state).
    public var advertisesDisplayPort: Bool {
        altModes.contains { $0.svid == 0xFF01 }
    }

    /// Advertised modes that named a protocol we recognise, in order. Used for
    /// the informational "advertises DisplayPort, Thunderbolt" line.
    public var namedProtocols: [String] {
        altModes.compactMap { $0.protocolName }
    }

    /// Any advertised mode in a failed state (`unsuccessful` / `error`). This is
    /// the only signal that should drive a (hedged) "this Alt Mode didn't come
    /// up" note.
    public var hasFailedAltMode: Bool {
        altModes.contains { $0.state.isFailure }
    }

    // MARK: - Parsing

    /// Parses a raw BOS (Binary Object Store) descriptor and returns the first
    /// Billboard capability (`0x0d`) it contains, or `nil` if there is none.
    ///
    /// Pure function over bytes (no IOKit), so the Darwin backend reads the raw
    /// descriptor and hands it here, and tests can feed corpus samples directly.
    public static func parse(bos: [UInt8]) -> BillboardCapability? {
        let total = bos.count
        // 5-byte BOS header; byte 1 is bDescriptorType (0x0F = BOS).
        guard total >= 5, bos[1] == 0x0F else { return nil }

        var offset = 5
        while offset + 3 <= total {
            let capLen = Int(bos[offset])
            guard capLen >= 3, offset + capLen <= total else { break }
            // bDescriptorType 0x10 = DEVICE CAPABILITY; bDevCapabilityType 0x0d = Billboard.
            if bos[offset + 1] == 0x10, bos[offset + 2] == 0x0d {
                return parseCapability(Array(bos[offset..<offset + capLen]))
            }
            offset += capLen
        }
        return nil
    }

    /// Decodes one Billboard Capability Descriptor (USB Billboard Device Class
    /// 1.2.2). Fixed header is 44 bytes, then 4 bytes per Alt Mode:
    /// `{ wSVID(2), bAlternateMode(1), iAlternateModeString(1) }`. The per-mode
    /// state lives in the 32-byte `bmConfigured` field at offset 8, two bits
    /// per mode.
    private static func parseCapability(_ cap: [UInt8]) -> BillboardCapability? {
        // Need the full 44-byte header before reading any of its fields.
        guard cap.count >= 44 else { return nil }
        let count = Int(cap[4])                   // bNumberOfAlternateModes
        // Reject truncated descriptors up front: the full alt-mode array must
        // be present, or we'd return a partial result built from whatever
        // prefix happened to fit.
        guard count > 0, cap.count >= 44 + count * 4 else { return nil }
        let preferred = Int(cap[5])              // bPreferredAlternateMode (index)
        let bmConfigured = Array(cap[8..<40])    // 2 bits per mode

        var modes: [AltMode] = []
        modes.reserveCapacity(count)
        for index in 0..<count {
            let entry = 44 + index * 4
            let svid = UInt16(cap[entry]) | (UInt16(cap[entry + 1]) << 8)
            let bits = (Int(bmConfigured[index / 4]) >> ((index % 4) * 2)) & 0x3
            let state = AltModeState(rawValue: bits) ?? .error
            modes.append(AltMode(svid: svid, state: state))
        }
        return BillboardCapability(altModes: modes, preferredIndex: preferred)
    }

    // MARK: - Registry keys (macOS's own decode)

    /// Builds the capability from the `UsbBillboard*` registry keys macOS
    /// publishes on an `AppleUSBHostBillboardDevice` node.
    ///
    /// Why this exists alongside `parse(bos:)`: on all 400 standalone Billboard
    /// nodes in the customer-probe corpus the BOS control transfer is refused
    /// (`kIOReturnUnsupported`), while 362 of them carry these keys. The kernel
    /// has already decoded the descriptor; reading its answer back is a
    /// registry property read, not bus traffic.
    ///
    /// Mode strings come in two shapes: a protocol name macOS resolved
    /// ("DisplayPort", "Thunderbolt", "USB") or `"SVID 0x<hex> VDO 0x<hex>"`.
    /// Entries that parse as neither are dropped; the order of the rest is
    /// kept. Current and preferred modes are matched by SVID, not by string,
    /// so "DisplayPort" still matches "SVID 0xff01 VDO ...".
    ///
    /// Per-mode state: `altModeFailed` (present only as true, and only on nodes
    /// with no current mode: 29 of 29 in the corpus) marks every mode `.error`.
    /// Otherwise the current mode is `.configured` and the rest `.notAttempted`;
    /// the registry says nothing finer than that.
    ///
    /// `version` (`UsbBillboardVersion`, e.g. "1.22") is accepted and ignored:
    /// the struct has no field for it yet, and the value is informational.
    ///
    /// Returns nil when no supported-mode string parses. Three corpus nodes
    /// carry Current/Preferred/Version but no SupportedModes; they get no table.
    public static func fromRegistry(
        supportedModes: [String],
        currentMode: String?,
        preferredMode: String?,
        altModeFailed: Bool,
        version: String?
    ) -> BillboardCapability? {
        let svids = supportedModes.compactMap(registryModeSVID)
        guard !svids.isEmpty else { return nil }

        let current = currentMode.flatMap(registryModeSVID)
        let preferred = preferredMode.flatMap(registryModeSVID)

        // Only the first entry sharing the current SVID is marked configured.
        let currentIndex = current.flatMap { svids.firstIndex(of: $0) }
        let modes = svids.enumerated().map { index, svid -> AltMode in
            if altModeFailed { return AltMode(svid: svid, state: .error) }
            let state: AltModeState = index == currentIndex ? .configured : .notAttempted
            return AltMode(svid: svid, state: state)
        }
        let preferredIndex = preferred.flatMap { svids.firstIndex(of: $0) }
        return BillboardCapability(altModes: modes, preferredIndex: preferredIndex)
    }

    /// Parses one registry mode string to its SVID: a resolved protocol name
    /// ("DisplayPort" 0xFF01, "Thunderbolt" 0x8087, "USB" 0xFF00) or
    /// `"SVID 0x<hex> VDO 0x<hex>"`, where only the SVID matters. Returns nil
    /// for anything else so the caller drops the mode rather than crashing.
    /// Case-insensitive on both the names and the hex digits.
    static func registryModeSVID(_ string: String) -> UInt16? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "displayport": return 0xFF01
        case "thunderbolt": return 0x8087
        case "usb": return 0xFF00
        default: break
        }

        // "SVID 0xff00 VDO 0x2687e000": take the token after "SVID", strip
        // the 0x prefix, and read it as hex. Anything else is not a mode.
        let tokens = trimmed.split(whereSeparator: { $0.isWhitespace })
        guard tokens.count >= 2, tokens[0].lowercased() == "svid" else { return nil }
        var hex = tokens[1].lowercased()
        if hex.hasPrefix("0x") { hex = hex.dropFirst(2).description }
        guard !hex.isEmpty else { return nil }
        return UInt16(hex, radix: 16)
    }
}
