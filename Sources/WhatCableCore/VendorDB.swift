import Foundation

/// Tiny in-memory USB-IF vendor name lookup. We only carry vendors likely to
/// appear in cables, chargers, hubs, docks, and storage devices — i.e. the
/// stuff that ends up in the popover. Add more as needed.
///
/// Source: usb.org public VID assignments. Names trimmed to common form.
public enum VendorDB {
    private static let names: [Int: String] = [
        0x05AC: "Apple",
        0x004C: "Apple (legacy)",
        // Cable e-marker silicon vendors. Cable e-markers carry the chip
        // vendor's VID, not the cable brand's, so these come up far more
        // often than the consumer-device VIDs further down. Verified
        // against USB-IF's March 2026 vendor ID list.
        0x20C2: "Sumitomo Electric Optical Comm",
        0x315C: "Chengdu Convenientpower Semiconductor",
        0x2095: "CE LINK",
        0x2E99: "Hynetek Semiconductor",
        0x201C: "Hongkong Freeport Electronics",
        0x2B1D: "Lintes Technology",
        0x05E3: "Genesys Logic",
        0x0BDA: "Realtek",
        0x174C: "ASMedia",
        0x2109: "VIA Labs",
        0x152D: "JMicron",
        0x067B: "Prolific",
        0x0451: "Texas Instruments",
        0x8087: "Intel",
        0x046D: "Logitech",
        0x0BB4: "HTC",
        0x18D1: "Google",
        0x12D1: "Huawei",
        0x04E8: "Samsung",
        0x2717: "Xiaomi",
        0x22D9: "OPPO",
        0x2A70: "OnePlus",
        0x05C6: "Qualcomm",
        0x0BC2: "Seagate",
        0x1058: "Western Digital",
        0x0781: "SanDisk",
        0x0930: "Toshiba",
        0x0951: "Kingston",
        0x125F: "ADATA",
        0x1B1C: "Corsair",
        0x154B: "PNY",
        0x0080: "Crucial",
        0x174F: "Syntek",
        0x046E: "Behavior Tech",
        0x05DC: "Lexar",
        0x0E8D: "MediaTek",
        0x148F: "Ralink",
        0x0B95: "ASIX",
        0x0CF3: "Qualcomm Atheros",
        0x06CB: "Synaptics",
        0x056A: "Wacom",
        0x040A: "Kodak",
        0x056D: "EIZO",
        0x0AF8: "Belkin",
        0x050D: "Belkin (older)",
        0x291A: "Anker",
        0x0BB8: "Plantronics / Poly",
        0x0763: "M-Audio",
        0x0FCE: "Sony Mobile",
        0x054C: "Sony",
        0x04F2: "Chicony",
        0x046A: "Cherry",
        0x04D9: "Holtek",
        0x1532: "Razer",
        0x1B7E: "Holosonics",
        0x07AA: "Corega",
        0x2188: "SmartAction",
        0x0E0F: "VMware",
        0x0FFE: "OWC",
        0x152E: "Lenovo",
        0x17EF: "Lenovo (older)",
        0x0BAF: "U.S. Robotics",
        0x0DCD: "Diconix",
        0x0FCA: "Research In Motion",
        0x05E0: "Symbol",
        0x05DD: "Delorme",
        0x0764: "CyberPower",
        0x051D: "American Power Conversion (APC)",
        0x2C7C: "Quectel",
        0x2341: "Arduino",
        0x1A40: "Terminus (hub chips)",
        0x1D6B: "Linux Foundation",
        0x0CF8: "Targus",
        0x0B05: "ASUS",
        0x103C: "HP",
        0x413C: "Dell",
        0x0CCD: "TerraTec",
        0x0E58: "Aopen",
        0x14AD: "Microvision"
    ]

    public static func name(for vendorID: Int) -> String? {
        names[vendorID]
    }

    /// Returns "Realtek (0x0BDA)" if known, else "0x0BDA".
    public static func label(for vendorID: Int) -> String {
        if let n = name(for: vendorID) {
            return "\(n) (0x\(String(format: "%04X", vendorID)))"
        }
        return "0x\(String(format: "%04X", vendorID))"
    }
}
