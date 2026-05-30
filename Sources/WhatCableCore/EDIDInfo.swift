import Foundation

/// Parsed fields from a monitor's EDID (Extended Display Identification
/// Data): the descriptor block every display sends over DisplayPort / HDMI
/// describing what it is and which modes it supports.
///
/// We read two things that matter for the display weakest-link diagnostic:
///
/// - the monitor's **preferred** mode (its out-of-the-box default, taken from
///   the first detailed timing descriptor), and
/// - the monitor's **maximum** capability (max refresh and max pixel clock,
///   from the 0xFD display range-limits descriptor).
///
/// The maximum is the one the diagnostic compares the link against. The
/// feature's whole question is "why won't my monitor run at its *full*
/// refresh?", so checking the link against the preferred (conservative) mode
/// would hide exactly the bottleneck we are looking for: a 100 Hz monitor
/// capped to 60 Hz by a weak cable would read as "fine".
///
/// Pure value type, no platform imports, so it compiles on every target.
/// Only the 128-byte base block is parsed; CTA-861 extension blocks (which
/// can advertise additional high-refresh modes) are deferred to a later
/// version.
public struct EDIDInfo: Hashable, Sendable {
    /// Monitor name from the 0xFC descriptor, e.g. "LEN G34w-10". Not every
    /// EDID includes one, so optional.
    public let monitorName: String?

    /// EDID structure version / revision, e.g. 1 and 3 for EDID 1.3.
    public let versionMajor: Int
    public let versionMinor: Int

    /// Preferred mode, from the first detailed timing descriptor.
    public let preferredWidth: Int
    public let preferredHeight: Int
    public let preferredRefreshHz: Int
    /// Pixel clock of the preferred mode, in Hz.
    public let preferredPixelClockHz: Int

    /// Maximum vertical refresh the monitor accepts, in Hz, from byte 6 of the
    /// 0xFD range-limits descriptor. Optional: a monitor EDID is not required
    /// to carry a range-limits descriptor.
    public let maxRefreshHz: Int?
    /// Maximum pixel clock the monitor accepts, in Hz, from byte 9 of the
    /// 0xFD descriptor (stored there in units of 10 MHz). This is the ceiling
    /// the display diagnostic uses for its bandwidth comparison: it is not
    /// subject to the EDID 1.4 rate-offset flags, so it stays correct even for
    /// very high refresh monitors.
    public let maxPixelClockHz: Int?

    /// Memberwise init, mainly so tests (and the diagnostic's own tests) can
    /// fabricate an `EDIDInfo` without a raw byte blob.
    public init(
        monitorName: String?,
        versionMajor: Int,
        versionMinor: Int,
        preferredWidth: Int,
        preferredHeight: Int,
        preferredRefreshHz: Int,
        preferredPixelClockHz: Int,
        maxRefreshHz: Int?,
        maxPixelClockHz: Int?
    ) {
        self.monitorName = monitorName
        self.versionMajor = versionMajor
        self.versionMinor = versionMinor
        self.preferredWidth = preferredWidth
        self.preferredHeight = preferredHeight
        self.preferredRefreshHz = preferredRefreshHz
        self.preferredPixelClockHz = preferredPixelClockHz
        self.maxRefreshHz = maxRefreshHz
        self.maxPixelClockHz = maxPixelClockHz
    }

    /// Parse the 128-byte EDID base block. Returns `nil` when the blob is too
    /// short, the EDID header is wrong, or no usable timing is present.
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

        // The four 18-byte descriptor slots in the base block.
        let descriptorOffsets = [54, 72, 90, 108]

        // Preferred timing = the first detailed timing descriptor. A slot is a
        // detailed timing when its pixel-clock word (bytes 0-1) is non-zero; a
        // zero there marks a display (text) descriptor instead.
        var width = 0, height = 0, refreshHz = 0, pixelClockHz = 0
        for off in descriptorOffsets {
            let pixelClock10kHz = Int(bytes[off]) | (Int(bytes[off + 1]) << 8)
            guard pixelClock10kHz != 0 else { continue }
            let clockHz = pixelClock10kHz * 10_000
            // Active / blanking are split across a low byte and a high nibble.
            let hActive = Int(bytes[off + 2]) | ((Int(bytes[off + 4]) >> 4) << 8)
            let hBlank  = Int(bytes[off + 3]) | ((Int(bytes[off + 4]) & 0x0F) << 8)
            let vActive = Int(bytes[off + 5]) | ((Int(bytes[off + 7]) >> 4) << 8)
            let vBlank  = Int(bytes[off + 6]) | ((Int(bytes[off + 7]) & 0x0F) << 8)
            let hTotal = hActive + hBlank
            let vTotal = vActive + vBlank
            width = hActive
            height = vActive
            pixelClockHz = clockHz
            if hTotal > 0 && vTotal > 0 {
                refreshHz = Int((Double(clockHz) / Double(hTotal * vTotal)).rounded())
            }
            break // first detailed timing is the preferred one
        }
        guard width > 0, height > 0 else { return nil }
        self.preferredWidth = width
        self.preferredHeight = height
        self.preferredRefreshHz = refreshHz
        self.preferredPixelClockHz = pixelClockHz

        // Walk the display descriptors (bytes 0-2 all zero) for the range
        // limits (0xFD) and the monitor name (0xFC).
        var maxRefresh: Int? = nil
        var maxPixelClock: Int? = nil
        var name: String? = nil
        let isEDID14 = bytes[18] == 1 && bytes[19] >= 4
        for off in descriptorOffsets {
            guard bytes[off] == 0, bytes[off + 1] == 0, bytes[off + 2] == 0 else { continue }
            switch bytes[off + 3] {
            case 0xFD: // display range limits
                // EDID 1.4 can add 255 to the max vertical rate via an offset
                // flag (byte off+4, bit 1). 1.3 has no offsets. The pixel
                // clock ceiling below is unaffected by these flags.
                var maxV = Int(bytes[off + 6])
                if isEDID14 && (Int(bytes[off + 4]) & 0x02) != 0 {
                    maxV += 255
                }
                maxRefresh = maxV
                let pclk10MHz = Int(bytes[off + 9])
                if pclk10MHz != 0 {
                    maxPixelClock = pclk10MHz * 10_000_000
                }
            case 0xFC: // monitor name
                name = Self.decodeDescriptorString(Array(bytes[(off + 5)..<(off + 18)]))
            default:
                break
            }
        }
        self.maxRefreshHz = maxRefresh
        self.maxPixelClockHz = maxPixelClock
        self.monitorName = name
    }

    /// Decode a 13-byte EDID text payload (monitor name / serial). The string
    /// is ASCII, terminated by a line feed (0x0A) and padded with spaces.
    private static func decodeDescriptorString(_ raw: [UInt8]) -> String? {
        var out = ""
        for b in raw {
            if b == 0x0A { break }
            out.append(Character(UnicodeScalar(b)))
        }
        let trimmed = out.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
