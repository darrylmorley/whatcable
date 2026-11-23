import Foundation

/// A hedged "the cable may be limiting charging" hint for when macOS has not
/// read the cable's e-marker (issue #672).
///
/// The existing cable check (`ChargingDiagnostic.Bottleneck.cableLimit`)
/// needs the cable's own rating, so it can never fire when the e-marker went
/// unread. This hint works from the charger's side instead. Under USB-PD a
/// charger only offers more than 3 A after it has read a 5 A e-marker itself,
/// so a charger rated well above 60 W that offers nothing over 3 A has most
/// likely not found a 5 A cable. "Most likely": a bad contact or a cable whose
/// e-marker did not answer looks the same, which is why the wording is "may".
///
/// Apple chargers only, for now: their name carries their rating ("96W USB-C
/// Power Adapter"). Nothing reliable rates a non-Apple charger. `AdapterInfo.watts`
/// is the current offer, not a rating, and `AdapterPowerTier` is too coarse.
public struct ChargerCableHint: Hashable, Sendable {
    /// The charger's rating, the first wattage in its Apple name.
    public let chargerRatedW: Int
    /// The highest offer on this connection, rounded to whole watts.
    public let offeredW: Int

    public init(chargerRatedW: Int, offeredW: Int) {
        self.chargerRatedW = chargerRatedW
        self.offeredW = offeredW
    }

    /// Below this rating a 3 A cable is not the limit (20 V x 3 A = 60 W), so
    /// a 61 W or 60 W charger is never a candidate.
    public static let minimumRatedW = 65
    /// The rating must beat the highest offer by MORE than this. Apple chargers
    /// in normal use sit 1 to 4 W under their name (96 W offers 94 W, 87 W
    /// offers 86.x W), so they never qualify.
    public static let marginW = 5
    /// No offer may be above this. A charger that offers more than 3 A has
    /// already found a 5 A cable.
    public static let threeAmpCeilingMA = 3000

    /// The rating in an Apple USB-C charger's name, e.g. 96 for
    /// "96W USB-C Power Adapter". Nil for anything else.
    ///
    /// The name must be exactly Apple's shape, `<N>W USB-C Power Adapter`
    /// with 1 to 3 digits and nothing before or after (surrounding whitespace
    /// is trimmed: some corpus names end in a space). Every Apple USB-C
    /// charger name in the corpus (probe 32 AdapterDetails, probe 17 UVDM)
    /// has it. It leaves out "143W Power Adapter" (an iMac supply with no
    /// USB-C offers), "40W Pwr Adapter 60W Max", and any other maker's name
    /// that merely contains the phrase, such as "96W USB-C Power Adapter
    /// (Anker)", which matters because AdapterDetails can lack a Manufacturer.
    public static func ratedWatts(appleChargerName name: String?) -> Int? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        let digits = trimmed.prefix { $0.isASCII && $0.isNumber }
        guard (1...3).contains(digits.count),
              trimmed.dropFirst(digits.count) == "W USB-C Power Adapter",
              let watts = Int(digits), watts > 0 else { return nil }
        return watts
    }

    /// The charger name to rate, for a port.
    ///
    /// The port's own UVDM name comes first: it belongs to whatever is on
    /// this port. `AdapterDetails` is system-wide, so it only names this
    /// port's charger when this is the one port holding a live charging
    /// contract. With two contracts it could be either charger. A
    /// manufacturer other than Apple rules the AdapterDetails name out; a
    /// missing one does not, because 20 Apple-named corpus captures carry no
    /// Manufacturer at all.
    public static func chargerName(
        accessory: AppleAccessoryIdentity?,
        adapter: AdapterInfo?,
        portHasLiveContract: Bool,
        anotherPortActivelyCharging: Bool
    ) -> String? {
        guard portHasLiveContract else { return nil }
        // A readable UVDM name says what is on THIS port. If it is not a
        // charger ("Studio Display"), the system-wide AdapterDetails name
        // belongs to something else and must not be borrowed.
        if let name = accessory?.displayName {
            return ratedWatts(appleChargerName: name) != nil ? name : nil
        }
        guard !anotherPortActivelyCharging,
              let adapter, let name = adapter.name else { return nil }
        if let maker = adapter.manufacturer, maker != "Apple Inc." { return nil }
        return name
    }

    /// The hint, or nil when any gate fails.
    ///
    /// `source.options` is everything the charger offers on this port, EPR
    /// (over 20 V) included. The cable-rating gate (no e-marker rating read)
    /// is applied by `ChargingDiagnostic`, which owns that read.
    ///
    /// - Only a USB-PD source. A winning TypeC or Brick ID source means PD
    ///   failed or has not finished, which is not a cable-rating matter.
    /// - Only a real offer list. An SMC-synthesised source carries the
    ///   contract alone (`options == [winning]`), which says nothing about
    ///   what else the charger would offer. A synthesised source with the
    ///   full PortControllerInfo list (M1 Pro/Max) is a real list.
    /// - Every offer must have a known current of 3 A or less: an option
    ///   reading 0 mA is unknown, not "3 A or less".
    public static func evaluate(chargerName: String?, source: PowerSource) -> ChargerCableHint? {
        let offers = source.options
        guard source.name == "USB-PD",
              !source.isSynthesized || offers.count > 1,
              let rated = ratedWatts(appleChargerName: chargerName),
              rated >= minimumRatedW,
              !offers.isEmpty,
              offers.allSatisfy({ $0.maxCurrentMA > 0 && $0.maxCurrentMA <= threeAmpCeilingMA }),
              let topMW = offers.map(\.maxPowerMW).max(), topMW > 0,
              rated * 1000 - topMW > marginW * 1000
        else { return nil }
        return ChargerCableHint(chargerRatedW: rated, offeredW: Int((Double(topMW) / 1000).rounded()))
    }
}
