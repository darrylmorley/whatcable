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
/// (active plus blanking), its refresh as a 16.16 fixed-point sync rate, the
/// colour modes it allows (`ColorModes`, each with `PixelEncoding`, `Depth`,
/// `SupportsDSC`, `IsVirtual` and, behind a converter, a `DownstreamFormat`),
/// the `ValidPixelEncodings` bitmask, and two lists of colour-mode IDs:
/// `DSCRequiredColorElementIDs` (the modes that need DSC on this link, the
/// producer's own decision, dump Finding 5 and A1) and `UnsafeColorElementIDs`
/// (the modes over a converter's TMDS cap, A1). Totals times refresh is the
/// pixel clock the wire carries. Everything read here is carried into Core as
/// a `DisplayTimingStatement`; the parse names nothing and decides nothing.
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
        public let colourModes: [DisplayColourMode]
        /// True only when `ColorModes` is present and an array (an absent
        /// key or a scalar is not an empty table, ruling 43; an empty array
        /// is) and every entry parsed: a dictionary with a numeric `ID`,
        /// `PixelEncoding` and `SupportsDSC`, a `Depth` above 0, an
        /// `IsVirtual` that is a genuine boolean, and, when a
        /// `DownstreamFormat` is present, a dictionary with a numeric
        /// `PixelEncoding` and a `Depth` above 0. A table missing an entry
        /// cannot say what depths or encodings the timing admits.
        public let colourModesComplete: Bool
        /// The timing's own `IsVirtual` (a synthetic HDR twin the node adds
        /// beside the panel's entries; 0xffffffff in `ValidPixelEncodings`).
        /// nil when not a genuine boolean. The driven lookup does not need
        /// it; the statement's `allTimings` keeps only `false`.
        public let isVirtual: Bool?
        /// `DSCRequiredColorElementIDs` as read. nil when the key is absent,
        /// is not an array, or holds an entry that is not a number.
        public let dscRequiredList: [Int]?
        /// `UnsafeColorElementIDs`, same contract.
        public let unsafeList: [Int]?
        /// `ValidPixelEncodings`. nil when absent or outside 0...0xffffffff.
        public let validPixelEncodings: UInt32?

        public init(id: Int, width: Int, height: Int, hTotal: Int, vTotal: Int, refreshHz: Double, interlaced: Bool,
                    colourModes: [DisplayColourMode], colourModesComplete: Bool, isVirtual: Bool? = nil,
                    dscRequiredList: [Int]? = nil, unsafeList: [Int]? = nil, validPixelEncodings: UInt32? = nil) {
            self.id = id
            self.width = width
            self.height = height
            self.hTotal = hTotal
            self.vTotal = vTotal
            self.refreshHz = refreshHz
            self.interlaced = interlaced
            self.colourModes = colourModes
            self.colourModesComplete = colourModesComplete
            self.isVirtual = isVirtual
            self.dscRequiredList = dscRequiredList
            self.unsafeList = unsafeList
            self.validPixelEncodings = validPixelEncodings
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
        /// nothing. Nothing else fills it in: the port's NSScreen depth is
        /// the framebuffer's, not the link's, and it used to decide the DSC
        /// reading on every several-depth timing (PR #665 gate, Claude F1).
        public var bitsPerComponent: Int? {
            guard colourModesComplete else { return nil }
            let depths = Set(colourModes.filter { !$0.isVirtual }.map(\.depth))
            return depths.count == 1 ? depths.first : nil
        }

        /// The link encoding, when the timing admits exactly one across its
        /// non-virtual modes, on the same terms as `bitsPerComponent`. RGB
        /// beside YCbCr 4:4:4 (the common case) is nil: no key names the live one.
        public var pixelEncoding: DisplayPixelEncoding? {
            guard colourModesComplete else { return nil }
            let encodings = Set(colourModes.filter { !$0.isVirtual }.map(\.encoding))
            return encodings.count == 1 ? encodings.first : nil
        }

        /// The converter's output format, when every non-virtual mode carries
        /// the same one; nil when any carries none or they differ.
        public var downstreamFormat: DisplayDownstreamFormat? {
            guard colourModesComplete else { return nil }
            let nonVirtual = colourModes.filter { !$0.isVirtual }
            guard !nonVirtual.isEmpty else { return nil }
            let formats = Set(nonVirtual.map(\.downstreamFormat))
            guard formats.count == 1, let format = formats.first else { return nil }
            return format
        }

        /// This timing's lists as Core reads them, resolved against its
        /// non-virtual colour modes, each list carrying whether it was
        /// complete (ruling 42).
        public var lists: DisplayTimingLists {
            DisplayTimingLists(
                colourModes: colourModes,
                dscRequiredList: dscRequiredList ?? [],
                unsafeList: unsafeList ?? [],
                validPixelEncodings: validPixelEncodings,
                colourModesComplete: colourModesComplete,
                dscListComplete: dscRequiredList != nil,
                unsafeListComplete: unsafeList != nil
            )
        }

        /// This timing as one entry of the statement's `allTimings`: its
        /// picture, refresh, clock (nil when interlaced) and lists.
        public var nodeTiming: DisplayNodeTiming {
            DisplayNodeTiming(id: id, width: width, height: height, refreshHz: refreshHz, pixelClockHz: pixelClockHz, lists: lists, interlaced: interlaced)
        }
    }

    /// One external display node with a display attached.
    public struct Node: Equatable, Sendable {
        /// `EDID UUID`, else `IOMFBUUID`, uppercased.
        public let edidKey: String
        /// `DisplayAttributes.ProductAttributes.SerialNumber`: the EDID's
        /// 32-bit serial, the same value `MonitorInfo.serialNumber` carries.
        public let serialNumber: Int?
        /// `DPTimingModeId`. nil when it is not a number, and when the read
        /// was torn (the ID or the UUID changed while the arrays were read,
        /// see `parseNode`).
        public let currentTimingID: Int?
        /// The entry of either list whose `ID` is `currentTimingID`. nil when
        /// the ID is absent or no entry carries it (a probe capture that
        /// sampled the list; never seen on a live node).
        public let currentTiming: Timing?
        /// Every `ID` the two lists carried as read, for the replay sweep to
        /// name what it could not compare.
        public let capturedTimingIDs: [Int]
        /// Every entry of both lists that parsed, in the node's order
        /// (`TimingElements` then `PreferredTimingElements`), virtual ones
        /// included; the statement keeps the non-virtual ones. On external
        /// panels the real timings are almost all in `PreferredTimingElements`
        /// (1 to 7 per node in the corpus); `TimingElements` holds the virtual
        /// HDR twins, and it is the list the probe samples. Empty when the
        /// read was torn (see `parseNode`).
        public let timings: [Timing]

        public init(edidKey: String, serialNumber: Int?, currentTimingID: Int?, currentTiming: Timing?, capturedTimingIDs: [Int], timings: [Timing] = []) {
            self.edidKey = edidKey
            self.serialNumber = serialNumber
            self.currentTimingID = currentTimingID
            self.currentTiming = currentTiming
            self.capturedTimingIDs = capturedTimingIDs
            self.timings = timings
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

    /// An array of numbers the node published under a list key, else nil. An
    /// absent key, a scalar, or a single entry that is not a number all read
    /// as nil: `wcArray` would read the first two as an empty list, and an
    /// empty DSC-required list is a statement ("nothing here needs DSC") that
    /// an unreadable one must never make.
    private static func idList(_ value: Any?) -> [Int]? {
        guard let items = array(value) else { return nil }
        var ids: [Int] = []
        for item in items {
            guard let id = number(item) else { return nil }
            ids.append(id)
        }
        return ids
    }

    /// An array the node published under a key, else nil: an absent key or a
    /// scalar is nil, an empty array is `[]`. `wcArray` folds the first two
    /// into `[]`, which is the wrong answer for both ID lists and for
    /// `ColorModes` (ruling 43).
    private static func array(_ value: Any?) -> [Any]? {
        if let array = value as? [Any] { return array }
        if let nsArray = value as? NSArray { return nsArray.map { $0 } }
        return nil
    }

    /// A `DownstreamFormat` sub-dictionary as the Core value, or nil when the
    /// entry carries none. `.some(nil)`-style ambiguity is avoided by the
    /// caller: it checks for the key first, then calls this, and treats a nil
    /// return for a present key as a malformed entry.
    private static func downstreamFormat(_ value: Any) -> DisplayDownstreamFormat? {
        let dict = wcDictionary(value)
        guard !dict.isEmpty,
              let encoding = number(dict["PixelEncoding"]),
              let depth = number(dict["Depth"]), depth > 0
        else { return nil }
        return DisplayDownstreamFormat(encoding: DisplayPixelEncoding(rawValue: encoding), depth: depth)
    }

    /// One `TimingElements` / `PreferredTimingElements` entry. nil unless it
    /// carries a numeric `ID`, a readable `IsInterlaced`, both actives and
    /// both totals above zero with each total at least its active, and a
    /// precise sync rate above zero: a timing without those cannot name a
    /// clock, and nothing is filled in. `ColorModes` absent or not an array
    /// is an incomplete table with no entries (ruling 43); an empty array is
    /// a complete one. A colour mode whose `ID`, `PixelEncoding`, `Depth` or
    /// `SupportsDSC` is not a number, whose `Depth` is not above 0, whose
    /// `SupportsDSC` is outside the two-bit field the dump names (0 to 3:
    /// bit 0 the sink, bit 1 a branch device; PR #665 gate, Codex 2), whose
    /// `IsVirtual` is not a genuine boolean, or whose `DownstreamFormat` is
    /// present but unreadable, is dropped, and the timing records that its
    /// table was incomplete. The two ID lists and
    /// `ValidPixelEncodings` are read as they are (an ID no colour mode
    /// carries is `DisplayTimingLists`'s to reject); an unreadable list is
    /// nil, and the timing's own `IsVirtual` is nil unless a genuine boolean.
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
        var colourModes: [DisplayColourMode] = []
        // Ruling 43: the table must be present and an array. An absent key
        // read as an empty table would, with an empty DSC list, state
        // "uncompressed" about a timing whose modes were never published.
        let colourModeEntries = array(dict["ColorModes"])
        var complete = colourModeEntries != nil
        for entry in (colourModeEntries ?? []).map(wcDictionary) {
            guard let modeID = number(entry["ID"]),
                  let encoding = number(entry["PixelEncoding"]),
                  let depth = number(entry["Depth"]), depth > 0,
                  let supportsDSC = number(entry["SupportsDSC"]), (0...3).contains(supportsDSC),
                  let isVirtual = flag(entry["IsVirtual"])
            else {
                complete = false
                continue
            }
            var downstream: DisplayDownstreamFormat? = nil
            if let rawDownstream = entry["DownstreamFormat"] {
                guard let parsed = downstreamFormat(rawDownstream) else {
                    complete = false
                    continue
                }
                downstream = parsed
            }
            colourModes.append(DisplayColourMode(
                id: modeID, encoding: DisplayPixelEncoding(rawValue: encoding), depth: depth,
                supportsDSC: supportsDSC, isVirtual: isVirtual, downstreamFormat: downstream
            ))
        }
        let validPixelEncodings = number(dict["ValidPixelEncodings"]).flatMap { UInt32(exactly: $0) }
        return Timing(
            id: id, width: width, height: height, hTotal: hTotal, vTotal: vTotal,
            refreshHz: Double(syncRate) / 65536, interlaced: interlaced,
            colourModes: colourModes, colourModesComplete: complete,
            isVirtual: flag(dict["IsVirtual"]),
            dscRequiredList: idList(dict["DSCRequiredColorElementIDs"]),
            unsafeList: idList(dict["UnsafeColorElementIDs"]),
            validPixelEncodings: validPixelEncodings
        )
    }

    /// One display node from a property-read closure, the same per-key shape
    /// `DisplayPortTransportWatcher.makeUpdate` uses. nil for the internal
    /// panel (`external` absent or false), an empty external slot, or a node
    /// with no UUID key. The current timing is looked up in `TimingElements`
    /// first, then `PreferredTimingElements`; the two share one ID space. A
    /// `DPTimingModeId` that is not a number names no current timing.
    ///
    /// Per-key reads can straddle a mode change or a hot-plug (PR #665 gate,
    /// Codex 4): the arrays from one generation of the node and the ID from
    /// another would attach a timing that was never driven in this snapshot,
    /// with a confident verdict. So the UUID and `DPTimingModeId` are read
    /// before the arrays and again after, and unless both pairs agree the
    /// node yields no current timing (`currentTimingID` and `currentTiming`
    /// both nil, so `match` attaches nothing). The identity pair does not
    /// catch a table that changed under a stable identity (a same-panel link
    /// retrain between `TimingElements` and `PreferredTimingElements`; gate
    /// rerun, Codex R2), so inside that bracket both arrays are read twice
    /// and parsed twice, and the node carries timings only when the two
    /// parses are equal; otherwise it carries none, so nothing attaches and
    /// no top-mode match runs on a mixed-generation list. Four array reads
    /// per node per watcher tick instead of two. A dictionary-backed read
    /// (the probe-26 replay) never tears.
    public static func parseNode(read: (String) -> Any?) -> Node? {
        guard wcBool(read("external")) else { return nil }
        func uuid() -> String? {
            let value = (read("EDID UUID") as? String) ?? (read("IOMFBUUID") as? String)
            return value.flatMap { $0.isEmpty ? nil : $0 }
        }
        func tables() -> [[String: Any]] {
            (wcArray(read("TimingElements")) + wcArray(read("PreferredTimingElements"))).map(wcDictionary)
        }
        guard let uuidBefore = uuid() else { return nil }
        let idBefore = number(read("DPTimingModeId"))
        let dictionaries = tables()
        let firstParse = dictionaries.compactMap(Self.parseTiming)
        let secondParse = tables().compactMap(Self.parseTiming)
        let stable = uuid() == uuidBefore && number(read("DPTimingModeId")) == idBefore && firstParse == secondParse
        let timings = stable ? firstParse : []
        let currentID = stable ? idBefore : nil
        let current = currentID.flatMap { id in timings.first { $0.id == id } }
        let product = wcDictionary(wcDictionary(read("DisplayAttributes"))["ProductAttributes"])
        return Node(
            edidKey: uuidBefore.uppercased(),
            serialNumber: number(product["SerialNumber"]),
            currentTimingID: currentID,
            currentTiming: current,
            capturedTimingIDs: dictionaries.compactMap { number($0["ID"]) },
            timings: timings
        )
    }

    // MARK: - The match (pure)

    /// Attach each node's driven timing to the one DisplayPort node whose
    /// EDID gives the same key. The timing replaces the CoreGraphics width,
    /// height and refresh (it is macOS's own driven timing) and supplies the
    /// pixel clock; bits per component is the timing's single depth when it
    /// has one, else nil. The port's NSScreen depth never stands in: the
    /// node does not carry the live depth, and a depth the node did not
    /// publish must not narrow `candidateModes` (PR #665 gate, Claude F1;
    /// 12 of 231 corpus nodes changed verdict on it). Once the node speaks,
    /// the driven mode carries only what the node said.
    /// The statement (`DisplayTimingStatement`: the driven timing's lists and
    /// every non-virtual timing the node lists) is attached as `drivenTiming`
    /// in the same step and nowhere else; which of those timings is the
    /// panel's top mode is Core's question, not this reader's;
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
                bitsPerComponent: timing.bitsPerComponent,
                pixelClockHz: pixelClockHz,
                pixelEncoding: timing.pixelEncoding,
                downstreamFormat: timing.downstreamFormat
            )
            let statement = DisplayTimingStatement(
                driven: timing.lists,
                allTimings: withTiming[index].timings.filter { $0.isVirtual == false }.map(\.nodeTiming)
            )
            return port.with(currentMode: mode, maxMode: port.maxMode, drivenTiming: statement)
        }
    }

    // MARK: - The read (IOKit)

    /// Public entry point: read every display node and attach the driven
    /// timing where exactly one matches. Returns the ports unchanged when no
    /// port carries an EDID or no node is readable. Runs after
    /// `DisplayModeReader.enrich`, which supplies `maxMode`; the NSScreen
    /// depth on the CoreGraphics mode survives only where no node matches.
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
