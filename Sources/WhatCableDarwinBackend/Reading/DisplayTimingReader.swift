import Foundation
import IOKit
import WhatCableCore

/// Reads the timing macOS is actually driving each external display at, from
/// macOS's own display node, and attaches it to the DisplayPort node it
/// belongs to.
///
/// Why this exists, in plain terms: CoreGraphics tells us the on-screen
/// resolution and refresh (`DisplayModeReader`), but not the timing behind
/// it, so the bandwidth the link carries had to be estimated from active
/// pixels and a bits-per-pixel assumption. The display node knows the real
/// timing: `DPTimingModeId` names the entry macOS is driving, and
/// `TimingElements` / `PreferredTimingElements` carry that entry's totals
/// (active plus blanking), its refresh as a 16.16 fixed-point sync rate, and
/// the colour modes it allows (`ColorModes`, each with `PixelEncoding` and
/// `Depth`). Totals times refresh is the pixel clock the wire carries.
///
/// Two class names publish the node, split by chip and not by macOS version
/// (measured across the corpus): `AppleCLCD2` on the M1 family, M2 and M3;
/// `IOMobileFramebufferShim` on M2 Pro/Max/Ultra, M3 Pro/Max and every M4
/// and M5. Both are read. Every machine also publishes empty external slots
/// (`external = true` and nothing else) and its internal panel; neither
/// parses to a `Node`.
///
/// Matching: the node's `EDID UUID` (or `IOMFBUUID`, equal wherever both
/// exist) is EDID bytes 8-23 formatted as a UUID with the serial bytes 12-15
/// zeroed, so the DisplayPort node's own EDID bytes give the same key.
/// Exactly one node per key attaches, to exactly one port; two identical
/// panels are told apart by `ProductAttributes.SerialNumber` against
/// `MonitorInfo.serialNumber`; anything else attaches nothing. Fail-closed
/// like `DisplayModeReader`, and at the parse as well as the match: a timing
/// with a value that is not a number, a zero or inconsistent dimension, or no
/// readable `IsInterlaced` is not a timing, and a timing without a pixel
/// clock never replaces a CoreGraphics mode.
///
/// The only platform-specific step is the IOKit read in `enrich`. The parse
/// and the match are pure functions so the probe-26 corpus can replay them.
public enum DisplayTimingReader {

    /// The IOKit classes that publish a display node. See the type comment.
    public static let nodeClassNames = ["AppleCLCD2", "IOMobileFramebufferShim"]

    /// One entry of a timing's `ColorModes`. `encoding` and `depth` are the
    /// node's raw integers: 0 RGB, 3 YCbCr 4:4:4, 2 YCbCr 4:2:2 by corpus
    /// correlation; 6 and 7 undecoded. Nothing here names them.
    public struct ColourMode: Equatable, Sendable {
        public let id: Int
        public let encoding: Int
        public let depth: Int
        /// Synthetic HDR entries macOS adds beside the panel's own; never a
        /// depth the link runs at.
        public let isVirtual: Bool

        public init(id: Int, encoding: Int, depth: Int, isVirtual: Bool) {
            self.id = id
            self.encoding = encoding
            self.depth = depth
            self.isVirtual = isVirtual
        }
    }

    /// One entry of `TimingElements` or `PreferredTimingElements`.
    public struct Timing: Equatable, Sendable {
        public let id: Int
        public let width: Int
        public let height: Int
        public let hTotal: Int
        public let vTotal: Int
        /// `VerticalAttributes.PreciseSyncRate / 65536`.
        public let refreshHz: Double
        public let interlaced: Bool
        /// The `ColorModes` entries that parsed. Facts, whether or not the
        /// table was complete.
        public let colourModes: [ColourMode]
        /// True only when every `ColorModes` entry parsed: a dictionary with
        /// a numeric `ID` and `PixelEncoding`, a `Depth` above 0, and an
        /// `IsVirtual` that is a genuine boolean. A table missing an entry
        /// cannot say what depths the timing admits.
        public let colourModesComplete: Bool

        public init(id: Int, width: Int, height: Int, hTotal: Int, vTotal: Int, refreshHz: Double, interlaced: Bool, colourModes: [ColourMode], colourModesComplete: Bool) {
            self.id = id
            self.width = width
            self.height = height
            self.hTotal = hTotal
            self.vTotal = vTotal
            self.refreshHz = refreshHz
            self.interlaced = interlaced
            self.colourModes = colourModes
            self.colourModesComplete = colourModesComplete
        }

        /// Totals times refresh: the clock the wire carries. nil for an
        /// interlaced timing (no corpus node is driven interlaced, so how
        /// the node expresses field totals is unmeasured) or a zero factor,
        /// which `parseTiming` never produces but the initialiser admits.
        /// A product that does not fit an Int is not a clock either: the
        /// conversion is exact rather than trapping, so a nonsense node
        /// cannot crash the app, the CLI or the widget. A timing without a
        /// clock never attaches (see `match`).
        public var pixelClockHz: Int? {
            guard !interlaced, hTotal > 0, vTotal > 0, refreshHz > 0 else { return nil }
            let clock = (Double(hTotal) * Double(vTotal) * refreshHz).rounded()
            guard clock.isFinite, let exact = Int(exactly: clock) else { return nil }
            return exact
        }

        /// The depth the link runs at, when the timing admits exactly one:
        /// every non-virtual colour mode shares it. A timing offering 8 and
        /// 10 bit cannot say which is live (no node carries a current
        /// colour-mode key), so that is nil. So is a table with a malformed
        /// entry: the entries that parsed cannot say what depths the timing
        /// admits (the missing one may be the 10-bit), so the table says
        /// nothing and the port keeps the NSScreen value.
        public var bitsPerComponent: Int? {
            guard colourModesComplete else { return nil }
            let depths = Set(colourModes.filter { !$0.isVirtual }.map(\.depth))
            return depths.count == 1 ? depths.first : nil
        }
    }

    /// One external display node with a display attached.
    public struct Node: Equatable, Sendable {
        /// `EDID UUID`, else `IOMFBUUID`, uppercased.
        public let edidKey: String
        /// `DisplayAttributes.ProductAttributes.SerialNumber`: the EDID's
        /// 32-bit serial, the same value `MonitorInfo.serialNumber` carries.
        public let serialNumber: Int?
        /// `DPTimingModeId`.
        public let currentTimingID: Int?
        /// The entry of either list whose `ID` is `currentTimingID`. nil when
        /// the ID is absent or no entry carries it (a probe capture that
        /// sampled the list; never seen on a live node).
        public let currentTiming: Timing?
        /// Every `ID` the two lists carried as read, for the replay sweep to
        /// name what it could not compare.
        public let capturedTimingIDs: [Int]

        public init(edidKey: String, serialNumber: Int?, currentTimingID: Int?, currentTiming: Timing?, capturedTimingIDs: [Int]) {
            self.edidKey = edidKey
            self.serialNumber = serialNumber
            self.currentTimingID = currentTimingID
            self.currentTiming = currentTiming
            self.capturedTimingIDs = capturedTimingIDs
        }
    }

    // MARK: - The key

    /// EDID bytes 8-23 as macOS formats its `EDID UUID`: manufacturer,
    /// product, serial, week and year, then bytes 18-23, as 8-4-4-4-12 hex.
    /// Bytes 12-15 (the serial) are zeroed because macOS zeroes them in the
    /// UUID (433 of 433 corpus nodes); the serial itself stays on
    /// `MonitorInfo.serialNumber`. nil when the blob cannot hold byte 23.
    public static func edidKey(from edid: Data) -> String? {
        let bytes = [UInt8](edid)
        guard bytes.count >= 24 else { return nil }
        var field = Array(bytes[8..<24])
        for i in 4..<8 { field[i] = 0 }
        let hex = field.map { String(format: "%02X", $0) }.joined()
        let h = Array(hex)
        return String(h[0..<8]) + "-" + String(h[8..<12]) + "-" + String(h[12..<16]) + "-" + String(h[16..<20]) + "-" + String(h[20..<32])
    }

    // MARK: - The parse (pure)

    /// A value the node published as a number, else nil. `wcInt` reads a
    /// missing, string or otherwise non-numeric value as 0, which a timing
    /// must never do: 0 here would become a dimension, an ID or a rate and
    /// pass for one. A boolean is not a number either, nor is a fractional
    /// or non-finite value: the conversion is exact, never a coercion. The
    /// NSNumber check comes first because a CFBoolean bridges to `Int` as
    /// 0 or 1, so an `as? Int` taken first would coerce it.
    private static func number(_ value: Any?) -> Int? {
        if let n = value as? NSNumber {
            guard CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
            let d = n.doubleValue
            guard d.isFinite, d == d.rounded(), let exact = Int(exactly: d) else { return nil }
            return exact
        }
        return value as? Int
    }

    /// A value the node published as a boolean, else nil. `wcBool` reads an
    /// absent key as false, which would make an unreadable `IsInterlaced`
    /// a progressive timing with a clock. Only a genuine boolean (a
    /// CFBoolean) is a flag; an integer is not.
    private static func flag(_ value: Any?) -> Bool? {
        guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        return n.boolValue
    }

    /// One `TimingElements` / `PreferredTimingElements` entry. nil unless it
    /// carries a numeric `ID`, a readable `IsInterlaced`, both actives and
    /// both totals above zero with each total at least its active, and a
    /// precise sync rate above zero: a timing without those cannot name a
    /// clock, and nothing is filled in. A colour mode whose `ID`,
    /// `PixelEncoding` or `Depth` is not a number, whose `Depth` is not
    /// above 0, or whose `IsVirtual` is not a genuine boolean is dropped,
    /// and the timing records that its table was incomplete.
    public static func parseTiming(_ dict: [String: Any]) -> Timing? {
        guard let id = number(dict["ID"]), let interlaced = flag(dict["IsInterlaced"]) else { return nil }
        let horizontal = wcDictionary(dict["HorizontalAttributes"])
        let vertical = wcDictionary(dict["VerticalAttributes"])
        guard let width = number(horizontal["Active"]), width > 0,
              let height = number(vertical["Active"]), height > 0,
              let hTotal = number(horizontal["Total"]), hTotal >= width,
              let vTotal = number(vertical["Total"]), vTotal >= height,
              let syncRate = number(vertical["PreciseSyncRate"]), syncRate > 0
        else { return nil }
        var colourModes: [ColourMode] = []
        var complete = true
        for entry in wcArray(dict["ColorModes"]).map(wcDictionary) {
            guard let modeID = number(entry["ID"]),
                  let encoding = number(entry["PixelEncoding"]),
                  let depth = number(entry["Depth"]), depth > 0,
                  let isVirtual = flag(entry["IsVirtual"])
            else {
                complete = false
                continue
            }
            colourModes.append(ColourMode(id: modeID, encoding: encoding, depth: depth, isVirtual: isVirtual))
        }
        return Timing(
            id: id, width: width, height: height, hTotal: hTotal, vTotal: vTotal,
            refreshHz: Double(syncRate) / 65536, interlaced: interlaced,
            colourModes: colourModes, colourModesComplete: complete
        )
    }

    /// One display node from a property-read closure, the same per-key shape
    /// `DisplayPortTransportWatcher.makeUpdate` uses. nil for the internal
    /// panel (`external` absent or false), an empty external slot, or a node
    /// with no UUID key. The current timing is looked up in `TimingElements`
    /// first, then `PreferredTimingElements`; the two share one ID space. A
    /// `DPTimingModeId` that is not a number names no current timing.
    public static func parseNode(read: (String) -> Any?) -> Node? {
        guard wcBool(read("external")) else { return nil }
        let uuid = (read("EDID UUID") as? String) ?? (read("IOMFBUUID") as? String)
        guard let uuid, !uuid.isEmpty else { return nil }
        let timings = (wcArray(read("TimingElements")) + wcArray(read("PreferredTimingElements"))).map(wcDictionary)
        let currentID = number(read("DPTimingModeId"))
        let current = currentID.flatMap { id in
            timings.lazy.compactMap(Self.parseTiming).first { $0.id == id }
        }
        let product = wcDictionary(wcDictionary(read("DisplayAttributes"))["ProductAttributes"])
        return Node(
            edidKey: uuid.uppercased(),
            serialNumber: number(product["SerialNumber"]),
            currentTimingID: currentID,
            currentTiming: current,
            capturedTimingIDs: timings.compactMap { number($0["ID"]) }
        )
    }

    // MARK: - The match (pure)

    /// Attach each node's driven timing to the one DisplayPort node whose
    /// EDID gives the same key. The timing replaces the CoreGraphics width,
    /// height and refresh (it is macOS's own driven timing) and supplies the
    /// pixel clock; bits per component is the timing's single depth when it
    /// has one, else whatever the port already carried (NSScreen's value).
    /// A port with no EDID, a port whose key and serial another port shares,
    /// a key matching zero or several nodes after the serial tiebreak, a
    /// single node whose real serial disagrees with the port's, a node
    /// without a captured timing or whose timing has no pixel clock
    /// (interlaced), or a node that two ports both chose: all returned
    /// untouched. One node attaches to at most one port. `maxMode` is never
    /// changed here.
    public static func match(ports: [IOPortTransportStateDisplayPort], nodes: [Node]) -> [IOPortTransportStateDisplayPort] {
        let withTiming = nodes.filter { $0.currentTiming != nil }
        // A port's identity: its key plus its EDID serial. Two ports sharing
        // one identity are panels nothing here can tell apart, so neither
        // attaches, whatever the node side looks like.
        let identities = ports.map { port -> String? in
            guard let edid = port.monitor?.edid, let key = edidKey(from: edid) else { return nil }
            return "\(key)/\(port.monitor?.serialNumber ?? 0)"
        }
        var identityCounts: [String: Int] = [:]
        for identity in identities.compactMap({ $0 }) { identityCounts[identity, default: 0] += 1 }
        // Each port's chosen node (an index into `withTiming`), decided before
        // anything attaches so a node two ports both chose can be seen.
        let chosen = zip(ports, identities).map { port, identity -> Int? in
            guard let identity, identityCounts[identity] == 1,
                  let edid = port.monitor?.edid, let key = edidKey(from: edid)
            else { return nil }
            var candidates = withTiming.indices.filter { withTiming[$0].edidKey == key }
            let portSerial = port.monitor?.serialNumber ?? 0
            if candidates.count > 1 {
                // Two identical panels: the EDID serial tells them apart, when
                // both sides have a real one. A placeholder shared by both
                // (0x01010101 is a corpus case) leaves it ambiguous.
                guard portSerial != 0 else { return nil }
                candidates = candidates.filter { withTiming[$0].serialNumber == portSerial }
            }
            guard candidates.count == 1 else { return nil }
            // One candidate, but a real serial on both sides that disagrees
            // is the other panel's node.
            if portSerial != 0, let nodeSerial = withTiming[candidates[0]].serialNumber, nodeSerial != 0, nodeSerial != portSerial {
                return nil
            }
            return candidates[0]
        }
        // A node two ports both chose (two panels sharing a key with only
        // one node readable, say) belongs to one of them and nothing here
        // can say which, so it attaches to neither. A chosen timing without
        // a clock (interlaced) has less to say than the CoreGraphics mode it
        // would replace, so it attaches nothing either.
        var chosenCounts: [Int: Int] = [:]
        for index in chosen.compactMap({ $0 }) { chosenCounts[index, default: 0] += 1 }
        return zip(ports, chosen).map { port, index in
            guard let index, chosenCounts[index] == 1,
                  let timing = withTiming[index].currentTiming, let pixelClockHz = timing.pixelClockHz
            else { return port }
            let mode = DisplayCurrentMode(
                width: timing.width, height: timing.height, refreshHz: timing.refreshHz,
                bitsPerComponent: timing.bitsPerComponent ?? port.currentMode?.bitsPerComponent,
                pixelClockHz: pixelClockHz
            )
            return port.with(currentMode: mode, maxMode: port.maxMode)
        }
    }

    // MARK: - The read (IOKit)

    /// Public entry point: read every display node and attach the driven
    /// timing where exactly one matches. Returns the ports unchanged when no
    /// port carries an EDID or no node is readable. Runs after
    /// `DisplayModeReader.enrich`, which supplies `maxMode` and the NSScreen
    /// depth this read keeps when the timing cannot name one.
    public static func enrich(_ ports: [IOPortTransportStateDisplayPort]) -> [IOPortTransportStateDisplayPort] {
        guard ports.contains(where: { $0.monitor?.edid != nil }) else { return ports }
        let nodes = readNodes()
        guard !nodes.isEmpty else { return ports }
        return match(ports: ports, nodes: nodes)
    }

    /// Every parsed display node under both class names. Keys are read one
    /// at a time rather than through `IORegistryEntryCreateCFProperties`,
    /// for the reason `DisplayPortTransportWatcher.makeUpdate` gives: the
    /// bulk fetch can abort the process on a node being torn down mid-read.
    static func readNodes() -> [Node] {
        var nodes: [Node] = []
        for className in nodeClassNames {
            var iterator: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else {
                continue
            }
            defer { IOObjectRelease(iterator) }
            let parsed = wcDrainAllRetrying(iterator) { service -> Node? in
                parseNode { key in
                    IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
                }
            }
            nodes += parsed.compactMap { $0 }
        }
        return nodes
    }
}
