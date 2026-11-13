import AppKit
import WhatCableCore
import WhatCableDarwinBackend

/// A one-time "this Mac can't work" alert for Intel Macs.
///
/// Intel Macs don't publish the IOKit port-controller data every reading in
/// the app is built on. There's no partial or degraded mode to offer: there's
/// simply no data. Confirmed against all 7 Intel machines in
/// `research/customer-probes/intel_*`, where probe 01 reports every
/// port-controller iterator empty. So instead of leaving the user staring at
/// an empty window, say why.
///
/// The check is `DarwinSystemInfo.isIntelHardware()` (a runtime sysctl read),
/// deliberately NOT `#if arch(x86_64)`. See that method for why the compile
/// time version is wrong: it fires under Rosetta on Apple Silicon, where the
/// app works fine.
@MainActor
enum UnsupportedArchitectureNotice {
    /// Shown on every launch on Intel, deliberately not once-ever: the app has
    /// nothing to show on this hardware, so a user who reopens it is asking the
    /// same question again and deserves the same answer. The app keeps running
    /// afterwards: the user asked to be told, not blocked.
    ///
    /// `isIntel` is injectable so the alert can be exercised on an Apple
    /// Silicon dev machine, where the real check is (correctly) always false.
    static func showIfNeeded(isIntel: Bool = DarwinSystemInfo.isIntelHardware()) {
        guard isIntel else { return }

        // Same dance as UpdateChecker.showAlert: an LSUIElement app can't
        // reliably bring a modal to the front without briefly becoming a
        // regular app first.
        let originalPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()

        let alert = NSAlert()
        alert.messageText = String(
            localized: "WhatCable can't read cables on this Mac",
            bundle: _coreLocalizedBundle
        )
        alert.informativeText = String(
            localized: "This Mac has an Intel processor. WhatCable gets its cable and port data from Apple Silicon's port controller, and Intel Macs don't expose it, so the app will show nothing useful.\n\nIt'll stay open if you want to look around, but there's nothing behind it.",
            bundle: _coreLocalizedBundle
        )
        alert.window.level = .floating
        alert.addButton(withTitle: String(localized: "OK", bundle: _coreLocalizedBundle))
        alert.addButton(withTitle: String(localized: "Learn more", bundle: _coreLocalizedBundle))
        let response = alert.runModal()

        NSApp.setActivationPolicy(originalPolicy)

        if response == .alertSecondButtonReturn {
            NSWorkspace.shared.open(URL(string: "https://www.whatcable.uk/#faq")!)
        }
    }
}
