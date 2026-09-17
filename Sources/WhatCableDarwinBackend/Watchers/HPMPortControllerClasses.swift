import Foundation

/// The IOKit classes Apple publishes USB-C and MagSafe port controllers under.
///
/// These six names used to be written out in full in two files
/// (`AppleHPMInterfaceWatcher` and `PowerService`), which meant a Mac
/// with a class neither list knew about would be half-supported: seen by one
/// reader and invisible to the other, with nothing to say so.
///
/// **The `IOPort` catch-all is deliberately NOT in here.** That is the one real
/// difference between the two old lists, and it is a behaviour question rather
/// than a copy-paste slip, so it stays visible at the one site that has always
/// used it. See ``AppleHPMInterfaceWatcher/candidateClasses``.
enum HPMPortControllerClasses {

    /// Every named class, without the catch-all. Ordering is not meaningful:
    /// callers search by content, and anything that needs a stable order sorts
    /// by the controller's `RID`.
    static let named = [
        "AppleHPMInterfaceType10",
        "AppleHPMInterfaceType11",
        // Never observed. Zero mentions across 771 machines in the probe-04
        // corpus, where every other name here appears. Kept because the cost of
        // a name that matches nothing is zero and the cost of missing a real
        // controller is a port that vanishes from the app.
        "AppleHPMInterfaceType12",
        // Rare but real: 13 corpus folders, all A18 Pro (2026-09-17).
        "AppleHPMInterfaceType18",
        "AppleTCControllerType10",
        "AppleTCControllerType11",
    ]
}
