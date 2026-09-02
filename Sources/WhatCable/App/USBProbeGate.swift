import Foundation

/// Whether WhatCable may read Billboard/BOS descriptors from attached USB
/// devices.
///
/// That read is a real USB control transfer, not a registry lookup, and a few
/// hubs and KVM switches lock up when it reaches them (issues #429 and #571).
/// Until issue #571 the only condition was the user's compatibility switch,
/// which meant a first run put traffic on the bus before the app had drawn
/// anything: a user whose hardware it broke never got a UI to fix it with.
///
/// `hasCompletedOnboarding` is the second condition, and it is deliberately a
/// value the app already stores rather than a new preference. It means "this
/// person has been through the welcome screen", which is the moment the app is
/// known to have loaded.
///
/// This only protects a FIRST run. Once onboarding is complete the probe runs
/// at launch as before, because subsystem startup still precedes UI creation
/// (`App.swift`). The escape hatch for anyone it breaks is the Settings switch,
/// reachable from the CLI via `whatcable --desktop|--popover --no-usb-probe`.
enum USBProbeGate {
    static func shouldProbe(hasCompletedOnboarding: Bool, skipDeepUSBProbing: Bool) -> Bool {
        hasCompletedOnboarding && !skipDeepUSBProbing
    }
}
