import Foundation

/// How a USB-C DisplayPort Alt Mode link splits its four high-speed lanes
/// between DisplayPort video and USB3 data.
///
/// A USB-C cable has four high-speed lanes. DisplayPort Alt Mode uses either:
/// - all four for DP (Pin Assignment C/E): 4 DP lanes, no USB3 alongside, or
/// - two for DP and two for USB3 (Pin Assignment D/F): 2 DP lanes + USB3.
///
/// We decide which from whether USB3 is active alongside DisplayPort, NOT from
/// IOKit's `DisplayPortPinAssignment` integer. That integer is not reliable for
/// this: the UGreen Revodok dock reports the same value (`1`) for both a
/// 2-lane link (USB3 active) and a 4-lane link (no USB3) on the same Mac, so it
/// cannot be encoding the lane split (issue #228). The physical constraint is
/// what makes USB3-coexistence definitive: if USB3 is running, at most two
/// lanes are left for DP.
public struct DisplayPortLaneConfig: Hashable {
    public enum Assignment: Hashable {
        case fourLane   // C/E: all four lanes carry DP; no USB3 alongside
        case twoLane    // D/F: two lanes DP, two lanes USB3
    }

    public let assignment: Assignment

    /// The raw `DisplayPortPinAssignment` integer, kept only for reference and
    /// diagnostics. It does not drive `assignment` (see the type doc / #228).
    public let rawPinAssignment: Int

    /// - Parameters:
    ///   - usb3Active: whether USB3 is active on the same link as DisplayPort.
    ///     `true` means the link can only be carrying two DP lanes.
    ///   - rawPinAssignment: the `DisplayPortPinAssignment` value, recorded for
    ///     reference only.
    public init(usb3Active: Bool, rawPinAssignment: Int = 0) {
        self.assignment = usb3Active ? .twoLane : .fourLane
        self.rawPinAssignment = rawPinAssignment
    }

    public var label: String {
        switch assignment {
        case .fourLane:
            return String(localized: "4 DP lanes (no USB3 alongside video)", bundle: _coreLocalizedBundle)
        case .twoLane:
            return String(localized: "2 DP lanes + USB3 data", bundle: _coreLocalizedBundle)
        }
    }
}
