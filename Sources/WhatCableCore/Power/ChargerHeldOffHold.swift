import Foundation

/// The wait before a charger held off on battery is shown (public issue 672).
///
/// The held-off state needs the Mac to read as on battery while the SMC says
/// a charger is supplying it. Both sides move at slightly different times
/// around a plug or an unplug:
///
/// - Plugging in: `AC-W` and the DC-in voltage come up at once, while the
///   signals behind "on battery" (macOS's adapter details, and the SMC charge
///   keys `BatteryChargeState` reads, which settle within about 3 s) lag.
///   For that moment a normal, charging charger looks held off.
/// - Unplugging a charging Mac: "on battery" turns true while the SMC can
///   still report the charger for a moment.
///
/// So the state is published only once the machine-wide precondition (charger
/// supply present AND on battery) has held continuously for `holdSeconds`.
/// Until then the flag reads false and the card keeps today's wording.
///
/// Pure and clock-injected, so the rule is testable without sleeping. The
/// Darwin backend applies it per hardware read on the live surfaces (the app
/// and `--watch`). One-shot reads (CLI snapshot and JSON, the dashboard's
/// first paint, bench report, the widget's own read) have nothing to flash,
/// so they use the single read's raw candidate and never wait.
public enum ChargerHeldOffHold {
    /// 5 s: the ~3 s the SMC charge keys take to settle after a plug-in, plus
    /// two of the app's 1 s poll ticks of margin. Longer than the 2 s
    /// `runningOnBatteryHold`, which only rides out a CH0R pulse, because this
    /// one has to outlast the adapter-details and charge-state lag too. The
    /// state is steady once reached (the corpus Macs sat in it for the whole
    /// capture), so a few seconds' delay costs nothing.
    public static let holdSeconds: TimeInterval = 5

    /// This read's precondition: the SMC reports charger supply and the Mac
    /// reads as on battery. nil when the supply reading is unavailable.
    public static func candidate(chargerSupplyPresent: Bool?, onBattery: Bool) -> Bool? {
        chargerSupplyPresent.map { $0 && onBattery }
    }

    /// The same precondition with each costly read deferred until it can
    /// matter, for the per-tick hardware read (review of issue 672): the
    /// battery record and macOS's adapter details are read only when the SMC
    /// already says a charger is supplying the Mac AND this read's SMC charge
    /// state leaves "on battery" possible. Same answer as
    /// `BatteryChargeState.resolvedFlags` + `SystemPowerState.onBattery`.
    public static func candidate(
        chargerSupplyPresent supply: Bool?,
        chargeState: BatteryChargeState?,
        batteryIsCharging: () -> Bool?,
        adapterPresent: () -> Bool
    ) -> Bool? {
        guard supply == true else { return supply }
        // `resolvedFlags`' isCharging, reading the battery record only for the
        // states that keep it.
        let isCharging: Bool?
        switch chargeState {
        case .charging?:
            return false  // the SMC says charging: not on battery
        case .notPluggedIn?, .onHold?, .chargeLimitReached?, .runningOnBattery?:
            isCharging = false
        case .full?, nil:
            isCharging = batteryIsCharging()
        }
        guard isCharging == false else { return false }
        // `SystemPowerState.onBattery`: on battery only with no adapter.
        return !adapterPresent()
    }

    /// One read through the hold. `since` is the monotonic time the current
    /// unbroken run of `true` candidates started (nil when the last read was
    /// anything else). Returns what to publish and the new `since`.
    ///
    /// A false or nil candidate is published at once and ends the run: the
    /// state only ever waits on the way IN.
    public static func step(
        candidate: Bool?, now: TimeInterval, since: TimeInterval?
    ) -> (published: Bool?, since: TimeInterval?) {
        guard candidate == true else { return (candidate, nil) }
        let start = since ?? now
        return (now - start >= holdSeconds, start)
    }
}
