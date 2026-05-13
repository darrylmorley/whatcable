import Foundation

/// Interprets the USB-C alt mode pin assignment from IOKit's
/// `DisplayPortPinAssignment` property and the `Pin Configuration` dictionary.
///
/// USB-C DisplayPort Alt Mode defines several pin assignments that determine
/// how many lanes carry DP vs USB3 signals:
/// - Assignment C/E: 4 DP lanes, no USB3 alongside video
/// - Assignment D/F: 2 DP lanes + USB3 data
///
/// Apple's IOKit exposes `DisplayPortPinAssignment` as an integer on the
/// HPM port service. When DP alt mode is not active the value is 0 or absent.
public struct DisplayPortLaneConfig: Hashable {
    public enum Assignment: Hashable {
        case fourLane   // C or E: all lanes used for DP
        case twoLane    // D or F: 2 DP lanes, USB3 on remaining lanes
        case unknown(Int)
    }

    public let assignment: Assignment
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
        // Apple encodes the active pin assignment as a small integer.
        // Empirically observed on Apple Silicon Macs:
        //   0 = no DP alt mode active
        //   1 = Pin Assignment C (4-lane DP)
        //   2 = Pin Assignment D (2-lane DP + USB3)
        //   3 = Pin Assignment E (4-lane DP, flipped orientation)
        //   4 = Pin Assignment F (2-lane DP + USB3, flipped)
        switch rawValue {
        case 1, 3: self.assignment = .fourLane
        case 2, 4: self.assignment = .twoLane
        default: self.assignment = .unknown(rawValue)
        }
    }

    public var isActive: Bool {
        switch assignment {
        case .fourLane, .twoLane: return true
        case .unknown(let v): return v != 0
        }
    }

    public var label: String {
        switch assignment {
        case .fourLane:
            return String(localized: "4 DP lanes (no USB3 alongside video)", bundle: .module)
        case .twoLane:
            return String(localized: "2 DP lanes + USB3 data", bundle: .module)
        case .unknown:
            return String(localized: "DisplayPort alt mode", bundle: .module)
        }
    }
}

extension DisplayPortLaneConfig {
    /// Try to infer lane assignment from the pin configuration dictionary
    /// when `DisplayPortPinAssignment` is missing or zero. Returns nil if
    /// the pin configuration doesn't clearly indicate a DP alt mode layout.
    public static func fromPinConfiguration(_ pins: [String: String]) -> DisplayPortLaneConfig? {
        // Each pin (tx1, tx2, rx1, rx2) has a numeric value indicating its
        // current protocol assignment. When DP alt mode is active, the values
        // shift from their idle state. Without a definitive mapping table from
        // Apple, we can't reliably decode this, so we only use the explicit
        // DisplayPortPinAssignment property.
        nil
    }
}
