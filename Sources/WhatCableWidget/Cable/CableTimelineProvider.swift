import Foundation
import WidgetKit
import AppIntents
import os.log
import WhatCableCore
import WhatCableDarwinBackend

/// Builds a timeline by reading IOKit directly on every provider run, with
/// a fallback to the App Group snapshot written by the main app.
///
/// Widgets are never live: the OS alone decides when to call the provider.
/// Every snapshot shown is "correct as of the last OS-triggered refresh."
/// The main app also pushes reloads via WidgetCenter on cable state changes,
/// which brings the widget up to date sooner when the app is running.
///
/// Data source priority:
///   1. Direct IOKit read (one-shot per provider run, no persistent watcher).
///      Works even when the main app is not running. The widget extension
///      sandbox permits IOKit registry reads (proven by the App Store
///      feasibility study).
///   2. App Group snapshot written by the main app. Used as fallback when
///      the IOKit read returns nothing (empty port list) or fails.
///
/// Staleness blanking has been removed. An old snapshot is still useful;
/// the "as of HH:MM" caption tells the user when it was captured.
struct CableTimelineProvider: AppIntentTimelineProvider {
    private let log = Logger(
        subsystem: "uk.whatcable.whatcable",
        category: "widget-timeline"
    )
    typealias Entry = CableWidgetEntry
    typealias Intent = CableWidgetIntent

    func placeholder(in context: Context) -> CableWidgetEntry {
        CableWidgetEntry.placeholder
    }

    func snapshot(for configuration: CableWidgetIntent, in context: Context) async -> CableWidgetEntry {
        if context.isPreview {
            return .placeholder
        }
        return await currentEntry(for: configuration)
    }

    func timeline(for configuration: CableWidgetIntent, in context: Context) async -> Timeline<CableWidgetEntry> {
        let entry = await currentEntry(for: configuration)
        // Always request a refresh in ~60s. The OS may honour this later or
        // earlier depending on budget; this is a hint, not a guarantee.
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60)))
    }

    // MARK: - Live IOKit read (one-shot)

    /// Reads the current cable state directly from IOKit in this extension
    /// process. One-shot: starts each watcher, refreshes once, reads, and
    /// discards the objects. This is simpler and more robust than keeping a
    /// singleton alive across provider calls (the OS can suspend and resume
    /// the extension process between runs, and a static singleton just means
    /// stale cached state in those cases). The overhead is minimal: IOKit
    /// match notifications are not needed here, only a single synchronous
    /// property scan.
    @MainActor
    private func liveSnapshot() -> WidgetSnapshot? {
        let portWatcher = AppleHPMInterfaceWatcher()
        let powerWatcher = PowerSourceWatcher()
        let pdWatcher = USBPDSOPWatcher()
        let usbWatcher = USBWatcher()
        let tbWatcher = IOIOThunderboltSwitchWatcher()
        let usb3Watcher = USB3TransportWatcher()
        let trmWatcher = TRMTransportWatcher()
        let phyWatcher = AppleTypeCPhyWatcher()
        let displayWatcher = DisplayPortTransportWatcher()
        let uvdmWatcher = AppleUVDMWatcher()

        // Each watcher's start() registers a persistent IOKit notification
        // wired to the main dispatch queue, holding an UNRETAINED pointer back
        // to the watcher (Unmanaged.passUnretained). Once this function returns
        // the local watcher objects are freed, but the notification ports would
        // outlive them, so the next device add/remove event would fire a
        // callback into freed memory and crash the widget (issue #341).
        //
        // stop() destroys each notification port. Tearing every watcher down
        // before we return closes that window. Safe here because this method is
        // @MainActor and fully synchronous (no await), so no callback can
        // interleave during the body, and the data we need is copied into
        // value-type arrays before the defer fires.
        //
        // It is also safe against an event that lands mid-snapshot: every
        // watcher delivers via IONotificationPortSetDispatchQueue(port, .main),
        // and IONotificationPortDestroy cancels that dispatch source. Because
        // we run on the main queue and destroy on the main queue, any callout
        // queued for an in-flight kernel message is ordered after us; by the
        // time it would run, the source is already cancelled, so libdispatch
        // suppresses it and the freed watcher is never touched.
        defer {
            portWatcher.stop()
            powerWatcher.stop()
            pdWatcher.stop()
            usbWatcher.stop()
            tbWatcher.stop()
            usb3Watcher.stop()
            trmWatcher.stop()
            phyWatcher.stop()
            displayWatcher.stop()
            uvdmWatcher.stop()
        }

        // The widget is a separate process, so the app's "Skip deep USB
        // probing" setting (issue #429) cannot reach it. The widget never
        // renders Billboard / alt-mode data, so it has no reason to issue the
        // BOS control transfer that upsets some KVMs and hubs. Disable it here
        // unconditionally: a background snapshot should never poke the bus.
        USBWatcher.probeBillboardDescriptors = false

        portWatcher.start()
        powerWatcher.start()
        pdWatcher.start()
        usbWatcher.start()
        tbWatcher.start()
        usb3Watcher.start()
        trmWatcher.start()
        phyWatcher.start()
        displayWatcher.start()
        uvdmWatcher.start()

        // Lets powerWatcher.refresh() synthesize a per-port source when macOS
        // never publishes a real IOPortFeaturePowerSource node (M1 Pro/Max/Ultra
        // USB-C, issue #401). This is a one-shot local build (see the teardown
        // comment above), so a plain closure over the local watchers is safe:
        // no retain cycle, and both are gone by the time the function returns.
        powerWatcher.synthesisContext = {
            PowerSourceSynthesisContext(
                ports: portWatcher.ports,
                identities: pdWatcher.identities,
                // hpmPortKeys() walks six IOKit service classes; wrapped in a
                // closure for API consistency with the other owners, though
                // this one-shot build only ever calls it once anyway.
                positionalPortKeys: { PowerService.hpmPortKeysRIDOrdered() }
            )
        }

        portWatcher.refresh()
        // pdWatcher before powerWatcher: PowerSourceSynthesis's partner-kind
        // attribution rung (issue #401) needs this tick's identities, not
        // last tick's.
        pdWatcher.refresh()
        powerWatcher.refresh()
        tbWatcher.refresh()
        usb3Watcher.refresh()
        trmWatcher.refresh()
        phyWatcher.refresh()
        displayWatcher.refresh()
        uvdmWatcher.refresh()

        let ports = portWatcher.ports
        guard !ports.isEmpty else {
            log.debug("Live IOKit read returned no ports; will fall back to cached snapshot")
            return nil
        }

        let battery = AppleSmartBatteryReader.read()
        let cable = CableSnapshot(
            ports: ports,
            powerSources: powerWatcher.sources,
            identities: pdWatcher.identities,
            usbDevices: usbWatcher.devices,
            adapter: SystemPower.currentAdapter(),
            thunderboltSwitches: tbWatcher.switches,
            isDesktopMac: battery.isDesktopMac,
            federatedIdentities: battery.federatedIdentities,
            usb3Transports: usb3Watcher.transports,
            trmTransports: trmWatcher.transports,
            cioCapabilities: trmWatcher.cioCapabilities,
            accessoryIdentities: uvdmWatcher.identities,
            typeCPhys: phyWatcher.phys,
            displayPorts: displayWatcher.statuses.map(\.status),
            batteryFullyCharged: battery.battery?.fullyCharged,
            batteryIsCharging: battery.battery?.isCharging
        )

        log.debug("Live IOKit read: \(ports.count) ports")
        return WidgetSnapshot(from: cable)
    }

    // MARK: - App Group fallback

    private func cachedSnapshot() -> WidgetSnapshot? {
        guard let url = WidgetSnapshot.sharedFileURL else {
            log.error("Failed to resolve App Group container URL for \(WidgetSnapshot.appGroupID, privacy: .public)")
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        if snapshot != nil {
            log.debug("Using cached App Group snapshot as fallback")
        }
        return snapshot
    }

    // MARK: - Entry builder

    /// Live IOKit read first; fall back to the App Group cache.
    /// Never blanks: an old snapshot is shown as-is with the timestamp caption.
    private func currentEntry(for configuration: CableWidgetIntent) async -> CableWidgetEntry {
        if let live = await liveSnapshot() {
            return CableWidgetEntry(date: live.timestamp, snapshot: live, configuration: configuration)
        }
        if let cached = cachedSnapshot() {
            return CableWidgetEntry(date: cached.timestamp, snapshot: cached, configuration: configuration)
        }
        return CableWidgetEntry(date: Date(), snapshot: nil, configuration: configuration)
    }
}

struct CableWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let configuration: CableWidgetIntent

    static let placeholder = CableWidgetEntry(
        date: Date(),
        snapshot: WidgetSnapshot(ports: [
            .init(
                id: 1,
                portName: "USB-C Port 1",
                status: .thunderboltCable,
                headline: "Thunderbolt / USB4",
                subtitle: "Supports high-speed data, video, smart cable.",
                topBullet: "Linked at up to 40 Gb/s x 2",
                iconName: "bolt.horizontal.fill",
                deviceCount: 2
            ),
            .init(
                id: 2,
                portName: "USB-C Port 2",
                status: .charging,
                headline: "Charging - 96W charger",
                subtitle: "Power is flowing. No data connection.",
                topBullet: "Charger advertises up to 96W",
                iconName: "bolt.fill",
                deviceCount: 0
            ),
            .init(
                id: 3,
                portName: "USB-C Port 3",
                status: .empty,
                headline: "Nothing connected",
                subtitle: "Plug a cable in to see what it can do.",
                topBullet: nil,
                iconName: "powerplug",
                deviceCount: 0
            ),
        ]),
        configuration: CableWidgetIntent()
    )
}
