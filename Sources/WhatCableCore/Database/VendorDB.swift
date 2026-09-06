import Foundation

/// USB vendor name lookup, backed by the bundled SQLite database
/// (`whatcable.db`). The database merges the USB-IF published list,
/// the community usb.ids list, and manual overrides.
///
/// A `curatedOverrides` escape hatch is kept available for the rare
/// cases where USB-IF's published name is genuinely wrong, mojibake'd,
/// or unintelligible. The default policy is **don't add overrides**.
/// Trust upstream; if you're tempted to shorten "Anker Innovations
/// Limited" to "Anker", don't, the longer form is accurate. Past
/// curated entries drifted out of date (e.g. `0x103C` was labelled
/// "HP" in the curated map but is registered to AMX Corp. per
/// USB-IF, and we shipped that wrong label for months).
public enum VendorDB {
    /// Override map. Empty by default. Add an entry only when the
    /// upstream USB-IF name is materially wrong or unusable, not
    /// merely verbose.
    private static let curatedOverrides: [Int: String] = [:]

    public static func name(for vendorID: Int) -> String? {
        if let override = curatedOverrides[vendorID] { return override }
        if vendorID == 0 {
            return "No vendor reported"
        }
        // 0xFFFF is the USB-PD spec-defined "no vendor ID assigned"
        // sentinel (PID forced to 0). Surface that neutrally rather
        // than letting it look unregistered.
        if vendorID == 0xFFFF {
            return "No vendor ID assigned (USB-PD spec sentinel)"
        }
        return CableDB.vendorName(vid: vendorID)
    }

    /// True if the VID is present in USB-IF's official published list
    /// (or the curated override map). Distinct from `name(for:) != nil`
    /// because usb.ids community entries and VID 0 return a name for
    /// display but are not USB-IF registrations. Used by
    /// `CableTrustReport` to gate the `vidNotInUSBIFList` flag.
    public static func isRegistered(_ vendorID: Int) -> Bool {
        if curatedOverrides[vendorID] != nil { return true }
        if vendorID == 0 { return false }
        if vendorID == 0xFFFF { return false }
        return CableDB.isUSBIFRegistered(vendorID)
    }

    /// Returns "Apple (0x05AC)" if known, else "0x05AC".
    public static func label(for vendorID: Int) -> String {
        if vendorID == 0 { return "No vendor reported" }
        if let n = name(for: vendorID) {
            return "\(n) (0x\(String(format: "%04X", vendorID)))"
        }
        return "0x\(String(format: "%04X", vendorID))"
    }
}
