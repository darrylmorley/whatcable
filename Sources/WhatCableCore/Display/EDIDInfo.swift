import Foundation

/// Parsed fields from a monitor's EDID (Extended Display Identification
/// Data): the descriptor block every display sends over DisplayPort / HDMI
/// describing what it is and which modes it supports.
///
/// Two different things live here, and they must not be confused:
///
/// - **Modes.** `modes` is every mode the panel declared, in every format the
///   EDID carries one in. `preferredMode` is the mode the EDID itself marks
///   preferred (the base block's first detailed timing, else a DisplayID
///   record carrying the preferred flag), nil when it marks none: held
///   separately here, and also present in `modes` under its own source
///   (established timings precede a base DTD in `modes`, so it is not
///   `modes[0]`). `topMode` is the highest of the list. Both are modes the
///   panel has.
/// - **The envelope.** `rangeLimits` comes from the 0xFD display range-limits
///   descriptor. It describes the range of signals the panel will *accept*,
///   not a mode it has. A 4K60 panel routinely declares a 75 Hz vertical
///   ceiling it has no 75 Hz mode for.
///
/// The diagnostic compares the link against the display's **top mode**, never
/// the preferred one: the feature's whole question is "why won't my monitor
/// run at its *full* refresh?", so checking against the preferred
/// (conservative) mode would hide exactly the bottleneck we are looking for,
/// a 100 Hz monitor capped to 60 Hz by a weak cable reading as "fine". The
/// top mode comes from `topMode` here; `DisplayDiagnostic.resolveTopMode`
/// weighs CoreGraphics' `maxMode` against this list and labels it from the
/// entry it matches. It never comes from the 0xFD envelope.
///
/// Pure value type, no platform imports, so it compiles on every target. The
/// 128-byte base block carries the preferred mode, the 0xFD envelope and four
/// timing slots; the CTA-861 extension block and the DisplayID extension
/// block (when present) are scanned too, so a top mode declared only there
/// still counts. Other extension data (DSC capability, audio, HDR) is not
/// yet parsed.
public struct EDIDInfo: Hashable, Sendable {
    /// Monitor name from the 0xFC descriptor, e.g. "LEN G34w-10". Not every
    /// EDID includes one, so optional.
    public let monitorName: String?

    /// EDID structure version / revision, e.g. 1 and 3 for EDID 1.3.
    public let versionMajor: Int
    public let versionMinor: Int

    /// EDID 1.4 byte 24 bit 0. nil below 1.4, where the bit means "supports default GTF" and is
    /// folded into `rangeLimits.timingSupport` instead.
    public let continuousFrequency: Bool?

    /// The mode the EDID declares preferred, or nil when it declares none. In order: the base
    /// block's first detailed timing descriptor when there is one; else the first DisplayID
    /// Type I / VII record whose preferred flag is set (byte 3 bit 7, data block revision
    /// below 2); else nil. Never "the first declared mode": the list has an order but the
    /// EDID has not said which entry it prefers, and a preference the EDID did not state is a
    /// guess. Apple's Pro Display XDR tile EDIDs and LG's UltraFine tile EDIDs carry no base
    /// DTD and no flagged record, so this is nil for them.
    public let preferredMode: EDIDMode?

    /// Every declared mode, in block order then descriptor order. Duplicates across formats are kept
    /// (a 1080p60 DTD and VIC 16 are two facts).
    public let modes: [EDIDMode]

    /// Standard timings the EDID declares without a formula the EDID licenses (EDID 1.4, range limits
    /// only, not in DMT). Facts without a timing; never guessed.
    public let undecodedStandardTimings: [StandardTimingID]

    /// The base block's 0xFD descriptor.
    public let rangeLimits: RangeLimits?

    /// DisplayID tag 0x09, when a DisplayID block carries one. A second fact, kept beside the first.
    public let displayIDRangeLimits: RangeLimits?

    /// DisplayID tag 0x25.
    public let dynamicRangeLimits: DynamicRangeLimits?

    public let blocks: [BlockInfo]
    public let declaredExtensionCount: Int
    public let tiledTopology: TiledTopology?

    /// CTA Video Format Preference entries that name a VIC, in preference order. A preference, not a mode source.
    public let ctaPreferredVICs: [Int]

    /// The entry with the highest pixel clock; ties broken by the larger picture (width * height),
    /// then the higher refresh, then the earlier entry in `modes`. Only entries with `width`,
    /// `height`, `hTotal` and `vTotal` all above zero are candidates: a descriptor with no
    /// picture or no total (a 128x0 CTA DTD is a real corpus shape, and edid-decode prints it
    /// with an `inf` refresh) is a declared fact that stays in `modes`, but it is not
    /// a mode the panel can run and cannot be the top. Nil when no entry qualifies, which for
    /// a parsed EDID means every declared entry has a zero dimension.
    public var topMode: EDIDMode? {
        var best: EDIDMode? = nil
        for candidate in modes {
            guard candidate.width > 0, candidate.height > 0, candidate.hTotal > 0, candidate.vTotal > 0 else { continue }
            guard let current = best else { best = candidate; continue }
            if Self.isHigherPriority(candidate, than: current) {
                best = candidate
            }
        }
        return best
    }

    /// `a` beats `b` on the `topMode` tie-break chain: pixel clock, then picture area, then
    /// refresh. A full tie returns false, which keeps whichever of the two `topMode`'s scan
    /// already holds, so the earlier entry in `modes` wins ties.
    /// Internal rather than private: `DisplayDiagnostic` ranks a filtered list with this same chain.
    static func isHigherPriority(_ a: EDIDMode, than b: EDIDMode) -> Bool {
        if a.pixelClockHz != b.pixelClockHz { return a.pixelClockHz > b.pixelClockHz }
        let aArea = a.width * a.height
        let bArea = b.width * b.height
        if aArea != bArea { return aArea > bArea }
        if a.refreshHz != b.refreshHz { return a.refreshHz > b.refreshHz }
        return false
    }

    /// Facets of `preferredMode`; nil exactly when it is nil.
    public var preferredWidth: Int? { preferredMode?.width }
    public var preferredHeight: Int? { preferredMode?.height }
    public var preferredRefreshHz: Int? { preferredMode.map { Int($0.refreshHz.rounded()) } }
    public var preferredPixelClockHz: Int? { preferredMode?.pixelClockHz }

    /// Memberwise init, mainly so tests (and the diagnostic's own tests) can
    /// fabricate an `EDIDInfo` without a raw byte blob.
    public init(
        monitorName: String?,
        versionMajor: Int,
        versionMinor: Int,
        continuousFrequency: Bool?,
        preferredMode: EDIDMode?,
        modes: [EDIDMode],
        undecodedStandardTimings: [StandardTimingID],
        rangeLimits: RangeLimits?,
        displayIDRangeLimits: RangeLimits?,
        dynamicRangeLimits: DynamicRangeLimits?,
        blocks: [BlockInfo],
        declaredExtensionCount: Int,
        tiledTopology: TiledTopology?,
        ctaPreferredVICs: [Int]
    ) {
        self.monitorName = monitorName
        self.versionMajor = versionMajor
        self.versionMinor = versionMinor
        self.continuousFrequency = continuousFrequency
        self.preferredMode = preferredMode
        self.modes = modes
        self.undecodedStandardTimings = undecodedStandardTimings
        self.rangeLimits = rangeLimits
        self.displayIDRangeLimits = displayIDRangeLimits
        self.dynamicRangeLimits = dynamicRangeLimits
        self.blocks = blocks
        self.declaredExtensionCount = declaredExtensionCount
        self.tiledTopology = tiledTopology
        self.ctaPreferredVICs = ctaPreferredVICs
    }

    /// Parse the whole EDID buffer: the 128-byte base block plus every extension block present.
    /// Returns `nil` when the blob is too short, the EDID header is wrong, or the walk finds no
    /// mode at all (`modes` would be empty). A base block with no detailed timing is not a
    /// reason to return nil: EDID 1.3 panels declare modes through established and standard
    /// timings alone, and Apple's and LG's tiled panels put every mode in DisplayID records
    /// behind four display descriptors; edid-decode parses all of them.
    ///
    /// `preferredMode` is the base block's first detailed timing when there is one
    /// (`EDIDBlockWalker.Result.base.preferred`), else the first DisplayID record flagged
    /// preferred (`displayIDPreferred`), else nil.
    public init?(_ data: Data) {
        // Copy to a 0-based array. `Data` can be a slice with a non-zero
        // start index, so never index it directly.
        let bytes = [UInt8](data)
        guard bytes.count >= 128 else { return nil }

        // Every EDID base block starts with this fixed 8-byte header.
        let header: [UInt8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
        guard Array(bytes[0..<8]) == header else { return nil }

        self.versionMajor = Int(bytes[18])
        self.versionMinor = Int(bytes[19])

        let walked = EDIDBlockWalker.walk(bytes)
        guard !walked.modes.isEmpty else { return nil }
        self.preferredMode = walked.base.preferred ?? walked.displayIDPreferred
        self.rangeLimits = walked.base.rangeLimits
        self.monitorName = walked.base.monitorName

        self.modes = walked.modes
        self.undecodedStandardTimings = walked.base.undecoded
        self.continuousFrequency = walked.base.continuousFrequency
        self.displayIDRangeLimits = walked.displayIDRangeLimits
        self.dynamicRangeLimits = walked.dynamicRangeLimits
        self.blocks = walked.blocks
        self.declaredExtensionCount = Int(bytes[126])
        self.tiledTopology = walked.tiledTopology
        self.ctaPreferredVICs = walked.ctaPreferredVICs
    }
}

extension EDIDInfo {
    public struct RangeLimits: Hashable, Sendable, Codable {
        /// Byte 10 of the 0xFD descriptor. `.secondaryGTF` is recorded only when byte 10 is
        /// 0x02 and the curve block (bytes 12 to 17) is not all zero; byte 10 = 0x02 over an
        /// empty curve block is `.defaultGTF`, because edid-decode's
        /// `supports_sec_gtf = !memchk(x + 12, 6)` says an empty block is no curve, so the
        /// default curve is what the EDID licenses.
        public enum TimingSupport: Hashable, Sendable, Codable {
            case defaultGTF
            case rangeLimitsOnly
            case secondaryGTF(startFrequencyKHz: Int, c: Double, m: Int, k: Int, j: Double)
            case cvt(version: String, maxActivePixelsPerLine: Int?, standardBlanking: Bool, reducedBlanking: Bool, preferredRefreshHz: Int?, realMaxPixelClockHz: Int?)
            case unknown(UInt8)
        }
        public let minVerticalHz: Int
        public let maxVerticalHz: Int
        public let minHorizontalKHz: Int
        public let maxHorizontalKHz: Int
        public let maxPixelClockHz: Int?      // byte 9 * 10 MHz; nil when byte 9 is 0
        public let timingSupport: TimingSupport

        public init(
            minVerticalHz: Int, maxVerticalHz: Int, minHorizontalKHz: Int, maxHorizontalKHz: Int,
            maxPixelClockHz: Int?, timingSupport: TimingSupport
        ) {
            self.minVerticalHz = minVerticalHz
            self.maxVerticalHz = maxVerticalHz
            self.minHorizontalKHz = minHorizontalKHz
            self.maxHorizontalKHz = maxHorizontalKHz
            self.maxPixelClockHz = maxPixelClockHz
            self.timingSupport = timingSupport
        }
    }

    public struct BlockInfo: Hashable, Sendable, Codable {
        public enum Kind: Hashable, Sendable, Codable {
            case base, cta861, displayID(version: UInt8), vtb, blockMap, padding, unknown(tag: UInt8)
        }
        public let index: Int
        public let kind: Kind
        public let checksumValid: Bool

        public init(index: Int, kind: Kind, checksumValid: Bool) {
            self.index = index
            self.kind = kind
            self.checksumValid = checksumValid
        }
    }

    public struct StandardTimingID: Hashable, Sendable, Codable {
        public let width: Int
        public let height: Int
        public let refreshHz: Int
        public let sourceIndex: Int

        public init(width: Int, height: Int, refreshHz: Int, sourceIndex: Int) {
            self.width = width
            self.height = height
            self.refreshHz = refreshHz
            self.sourceIndex = sourceIndex
        }
    }

    public struct TiledTopology: Hashable, Sendable, Codable {
        public let hTiles: Int
        public let vTiles: Int
        public let tileWidth: Int
        public let tileHeight: Int
        public let hLocation: Int
        public let vLocation: Int

        public init(hTiles: Int, vTiles: Int, tileWidth: Int, tileHeight: Int, hLocation: Int, vLocation: Int) {
            self.hTiles = hTiles
            self.vTiles = vTiles
            self.tileWidth = tileWidth
            self.tileHeight = tileHeight
            self.hLocation = hLocation
            self.vLocation = vLocation
        }
    }

    /// DisplayID 2.0 tag 0x25. Units as the block carries them.
    public struct DynamicRangeLimits: Hashable, Sendable, Codable {
        public let minPixelClockKHz: Int
        public let maxPixelClockKHz: Int
        public let minRefreshHz: Int
        public let maxRefreshHz: Int

        public init(minPixelClockKHz: Int, maxPixelClockKHz: Int, minRefreshHz: Int, maxRefreshHz: Int) {
            self.minPixelClockKHz = minPixelClockKHz
            self.maxPixelClockKHz = maxPixelClockKHz
            self.minRefreshHz = minRefreshHz
            self.maxRefreshHz = maxRefreshHz
        }
    }
}
