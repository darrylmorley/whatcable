// Hand-written lookup helpers over the generated tables in
// EDIDTimingTables.generated.swift. Kept separate so the generator never has
// to know about them: regeneration only ever touches the .generated.swift file.

extension EDIDTimingTables {
    /// Look up a DMT timing by its EDID 2-byte standard timing code.
    public static func dmt(standardCode: UInt16) -> DMTTiming? {
        dmt.values.first { $0.standardCode == standardCode }
    }

    /// Look up a DMT timing by resolution, rounded refresh rate and the
    /// reduced-blanking flag. Refresh is rounded the same way the parser
    /// will compute it from a detailed timing:
    /// Int((pixelClockKHz * 1000) / (hTotal * vTotal)).rounded()
    ///
    /// Interlaced DMTs (only 0x0F, 1024x768@43i) match on field rate: the
    /// stored vTotal is the frame total, so the field rate is twice the
    /// frame rate computed from hTotal * vTotal.
    public static func dmt(width: Int, height: Int, refreshHz: Int, reducedBlanking: Bool) -> DMTTiming? {
        dmt.values.first { candidate in
            guard candidate.width == width,
                  candidate.height == height,
                  candidate.reducedBlanking == reducedBlanking
            else { return false }

            let denominator = candidate.hTotal * candidate.vTotal
            guard denominator > 0 else { return false }

            let frameHz = Double(candidate.pixelClockKHz * 1000) / Double(denominator)
            let computedHz = candidate.interlaced ? frameHz * 2 : frameHz
            return Int(computedHz.rounded()) == refreshHz
        }
    }
}
