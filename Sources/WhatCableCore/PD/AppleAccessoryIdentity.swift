import Foundation

/// Identity of an Apple accessory read from the port's PD SOP node, published
/// via Apple's private UVDM (vendor-defined USB-PD) channel as
/// `IOPortTransportProtocolAppleUVDM`. Carries the accessory's own
/// human-readable name ("96W USB-C Power Adapter", "Studio Display",
/// "iPhone", "iPad", "Vision Pro Battery"). The IOKit watcher that reads the
/// live node is a separate task; this is the pure Core model.
public struct AppleAccessoryIdentity: Identifiable, Hashable, Sendable {
    public let id: UInt64
    /// Port correlation key matching `PowerSource.portKey`.
    public let portKey: String

    // Raw fields, stored exactly as read from IOKit, never cleaned. Hardware
    // identifiers (serialNumber above all) are never dropped or redacted:
    // they are the product's join keys.
    public let manufacturer: String?
    public let vendor: String?
    public let product: String?
    public let userString: String?
    public let model: String?
    public let serialNumber: String?
    public let hardwareVersion: String?
    public let vendorID: Int?
    public let productID: Int?

    /// HPM controller UUID captured by walking the IOKit parent chain.
    /// Internal join key only. Never serialised to JSON or text output.
    public let hpmControllerUUID: String?

    public init(
        id: UInt64,
        portKey: String,
        manufacturer: String?,
        vendor: String?,
        product: String?,
        userString: String?,
        model: String?,
        serialNumber: String?,
        hardwareVersion: String?,
        vendorID: Int?,
        productID: Int?,
        hpmControllerUUID: String? = nil
    ) {
        self.id = id
        self.portKey = portKey
        self.manufacturer = manufacturer
        self.vendor = vendor
        self.product = product
        self.userString = userString
        self.model = model
        self.serialNumber = serialNumber
        self.hardwareVersion = hardwareVersion
        self.vendorID = vendorID
        self.productID = productID
        self.hpmControllerUUID = hpmControllerUUID
    }

    /// Canonical in-session join key: normalised UUID when captured, else portKey.
    /// Internal only; never expose in JSON or text output.
    public var canonicalJoinKey: String {
        if let uuid = hpmControllerUUID {
            let n = uuid.replacingOccurrences(of: "-", with: "").lowercased()
            if n.count == 32 { return n }
        }
        return portKey
    }

    /// True when this identity record belongs to the same physical port as `port`.
    /// UUID-keyed when both sides have a UUID, portKey fallback otherwise.
    public func canonicallyMatches(port: AppleHPMInterface) -> Bool {
        guard let portKey = port.portKey else { return false }
        if let srcUUID = hpmControllerUUID, let portUUID = port.hpmControllerUUID {
            let sn = srcUUID.replacingOccurrences(of: "-", with: "").lowercased()
            let pn = portUUID.replacingOccurrences(of: "-", with: "").lowercased()
            if sn.count == 32 && pn.count == 32 { return sn == pn }
        }
        return self.portKey == portKey
    }

    /// A single Apple engineering-validation accessory (VID 0x05AC, PID
    /// 0x1657, serial "1234567890") that publishes placeholder identity
    /// strings ("EV" as its Product). Excluded from displayName so it never
    /// surfaces as a named accessory.
    private static let engineeringValidationProductID = 0x1657

    /// The one displayable name, or nil when nothing trustworthy was read.
    ///
    /// Preference order, re-derived from the corpus this task (1380 folders
    /// carrying probe 17, 126 UVDM nodes across 118 folders, two parsers
    /// agreeing):
    ///
    /// 1. `userString`, trimmed of whitespace and newlines, when non-empty.
    ///    33 of 126 nodes carry one (9 distinct values, all "<N>W USB-C
    ///    Power Adapter"); 7 of those 33 have a trailing space inside the
    ///    quotes, hence the trim rather than a direct comparison.
    /// 2. Otherwise `product`, trimmed, except: `"0"`, `"EV"` (11 nodes, all
    ///    the same 0x05AC/0x1657 engineering-validation accessory), empty
    ///    (7 nodes), or `productID == 0x1657`. Those are placeholder values,
    ///    not names, so they give nil rather than surfacing as an accessory
    ///    name.
    ///
    ///    The `"0"` guard is a FORWARD guard and no corpus node reaches it
    ///    today: all 29 nodes with `Product == "0"` also carry a `User
    ///    String`, so step 1 has already returned by then. It stays because
    ///    nothing guarantees the next node pairs the two fields the same way,
    ///    but it is not currently load-bearing and no test can make it so
    ///    without invented data.
    /// 3. The candidate must then pass `isDisplayable` or the whole thing is
    ///    nil: nine corpus nodes carry control bytes inside `Serial Number`
    ///    (two of those embed a raw newline), which is why validation, not
    ///    just trimming, gates this path. `serialNumber` itself is never
    ///    touched by any of this: it is stored exactly as read, for joins.
    ///
    /// 104 of the 126 corpus UVDM nodes produce a non-nil name under this rule.
    public var displayName: String? {
        if let userString {
            let trimmed = userString.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return Self.isDisplayable(trimmed) ? trimmed : nil
            }
        }

        guard let product else { return nil }
        let trimmedProduct = product.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProduct.isEmpty,
              trimmedProduct != "0",
              trimmedProduct != "EV",
              productID != Self.engineeringValidationProductID else {
            return nil
        }
        return Self.isDisplayable(trimmedProduct) ? trimmedProduct : nil
    }

    /// 1 to 64 graphemes AND 1 to 64 Unicode scalars, no control characters,
    /// no line or paragraph separators, no unassigned scalars. Gates both the
    /// `userString` and `product` paths so a corrupt read (control bytes, an
    /// embedded newline) never reaches the UI as a name.
    ///
    /// Both counts are bounded on purpose. Graphemes are what a reader sees,
    /// but combining marks fold into one grapheme without limit, so a
    /// grapheme-only bound passes a "one character" string that is kilobytes
    /// of stacked diacritics. The scalar count is what bounds the payload.
    private static func isDisplayable(_ candidate: String) -> Bool {
        guard (1...64).contains(candidate.count),
              (1...64).contains(candidate.unicodeScalars.count) else { return false }
        for scalar in candidate.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar) { return false }
            // U+2028 and U+2029 are Zl / Zp, not Cc, so the control-character
            // test above never sees them. They are still line breaks and would
            // split a card line in two.
            if scalar.properties.generalCategory == .lineSeparator
                || scalar.properties.generalCategory == .paragraphSeparator { return false }
            if scalar.properties.generalCategory == .unassigned { return false }
        }
        return true
    }
}
