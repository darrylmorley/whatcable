import Foundation

/// Vendor IDs belonging to the companies that make e-marker chips, as opposed
/// to the companies that make cables.
///
/// A cable whose e-marker was never reprogrammed answers Discover Identity
/// with its chip maker's default vendor ID, so the port card ends up naming
/// the silicon supplier as if it were the cable brand. 72 of 764 SOP'
/// readings in the corpus (9.4%, across 65 machines) carry one of these five
/// IDs, and 56 of those 72 also report product ID 0, the factory-default
/// shape.
///
/// All five resolve in the bundled `vendors` table with source `usbif`, so
/// this is a hint about where a name came from, not a fallback for a name
/// that is missing. It is a presentation hint only: it must never become a
/// trust signal or change a verdict, because a factory-default vendor ID is
/// ordinary on genuine hardware.
public enum EmarkerSilicon {
    /// Short vendor name when `vid` is an e-marker silicon maker's own VID,
    /// nil otherwise. The names are short because they read inside a sentence.
    public static func shortName(for vid: Int) -> String? {
        switch vid {
        case 0x315C: return "CPS"       // Chengdu Convenientpower Semiconductor
        case 0x2109: return "VIA"       // VIA Labs
        case 0x2E87: return "Injoinic"
        case 0x2E99: return "Hynetek"
        case 0x04B4: return "Cypress"
        default: return nil
        }
    }
}
