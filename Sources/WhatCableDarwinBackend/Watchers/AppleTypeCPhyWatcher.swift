import Foundation
import IOKit
import WhatCableCore
import os.log

/// Watches `AppleT8132TypeCPhy` services for per-lane physical layer state.
/// One instance per physical USB-C port. Provides the only way to see which
/// transport protocol (CIO, DisplayPort, or idle) is assigned to each lane.
///
/// The IOKit class name varies by chip generation:
/// - M3/M4: AppleT8132TypeCPhy
/// - Future chips may use different suffixes.
///
/// Updates instantly on mode change (notification-driven).
@MainActor
public final class AppleTypeCPhyWatcher: ObservableObject {
    @Published public private(set) var phys: [AppleTypeCPhy] = []

    nonisolated static let candidateClasses = [
        "AppleT8132TypeCPhy",
        "AppleT8122TypeCPhy",
        "AppleT8112TypeCPhy",
        "AppleT6042TypeCPhy",
        "AppleT6022TypeCPhy",
        "AppleT6002TypeCPhy",
        "AppleT6000TypeCPhy",
    ]

    private var notifyPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var interestNotifications: [UInt64: io_object_t] = [:]

    nonisolated private static let log = Logger(subsystem: "uk.whatcable.whatcable", category: "typec-phy")

    public init() {}

    public func start() {
        guard notifyPort == nil else { return }
        let port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        notifyPort = port

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let cb: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            let watcher = Unmanaged<AppleTypeCPhyWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor [weak watcher] in
                // `wcDrainIterator` returning `false` means this
                // notification iterator was still invalidated (registry
                // changed mid-walk) after every retry, so this particular
                // match notification may not be fully re-armed. There is no
                // stronger recovery here: the caller (`DarwinSnapshotProvider`
                // / `CableTimelineProvider`) already polls `refresh()` on a
                // 1s timer independently of notifications, and that poll is
                // the backstop that converges state even if this one
                // notification stays deaf.
                if !wcDrainIterator(iterator) {
                    AppleTypeCPhyWatcher.log.error("AppleTypeCPhyWatcher: match-notification iterator stayed invalid after retries; relying on the 1s poll to converge")
                }
                watcher?.refresh()
            }
        }

        for cls in Self.candidateClasses {
            var iter: io_iterator_t = 0
            if IOServiceAddMatchingNotification(port, kIOMatchedNotification,
                                                 IOServiceMatching(cls), cb, selfPtr, &iter) == KERN_SUCCESS {
                iterators.append(iter)
                if !wcDrainIterator(iter) {
                    Self.log.error("AppleTypeCPhyWatcher: initial drain for \(cls, privacy: .public) stayed invalid after retries; relying on the 1s poll to converge")
                }
            }
        }
        refresh()
    }

    public func stop() {
        for iter in iterators { IOObjectRelease(iter) }
        iterators.removeAll()
        for (_, n) in interestNotifications { IOObjectRelease(n) }
        interestNotifications.removeAll()
        if let port = notifyPort {
            IONotificationPortDestroy(port)
            notifyPort = nil
        }
        phys.removeAll()
    }

    public func refresh() {
        var rebuilt: [AppleTypeCPhy] = []
        var liveEntryIDs: Set<UInt64> = []

        for cls in Self.candidateClasses {
            var iter: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(cls), &iter) == KERN_SUCCESS else {
                continue
            }
            defer { IOObjectRelease(iter) }

            // `registerInterest` inside the transform is idempotent, so it is
            // safe to run again on a discarded, retried pass; only the
            // `rebuilt`/`liveEntryIDs` merge needs to happen after the walk.
            let results = wcDrainAllRetrying(iter) { service -> (phy: AppleTypeCPhy, entryID: UInt64?)? in
                guard let phy = makePhy(from: service) else { return nil }
                var entryID: UInt64 = 0
                guard IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS else {
                    return (phy, nil)
                }
                registerInterest(for: service, entryID: entryID)
                return (phy, entryID)
            }
            for result in results {
                guard let result else { continue }
                if !rebuilt.contains(where: { $0.id == result.phy.id }) {
                    rebuilt.append(result.phy)
                }
                if let entryID = result.entryID {
                    liveEntryIDs.insert(entryID)
                }
            }
        }

        // Release interest notifications for PHY services that are no longer
        // present. The watcher only subscribes to kIOMatchedNotification (no
        // kIOTerminatedNotification), so pruning happens here on each refresh
        // to prevent io_object_t handles accumulating across kext reloads or
        // power-state transitions that recycle PHY services (W2 fix).
        for entryID in interestNotifications.keys where !liveEntryIDs.contains(entryID) {
            if let n = interestNotifications.removeValue(forKey: entryID) {
                IOObjectRelease(n)
            }
        }

        rebuilt.sort { $0.id < $1.id }
        if rebuilt != phys { phys = rebuilt }
    }

    private func makePhy(from service: io_service_t) -> AppleTypeCPhy? {
        // Read keys individually rather than fetching the full property
        // dictionary. The bulk fetch (IORegistryEntryCreateCFProperties)
        // can abort the process from inside IOCFUnserializeBinary when
        // the kernel returns a malformed serialised properties blob,
        // typically when the service is being torn down mid-read. The
        // per-key call has no such failure path. See issue #181.
        func read(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }

        // The PHY's own device-tree node index (`atc-phyN`, 55 of 55), never a
        // port index: PHY count differs from USB-C port count on 735 of 1254
        // folders, and M1/M2 Ultra repeat PhyIDs across their two dies.
        let phyID = (read("AppleTypeCPhyID") as? NSNumber)?.intValue ?? -1
        guard phyID >= 0 else { return nil }

        var lanes: [PhyLane] = []
        if let laneDict = read("AppleTypeCPhyLane") as? [String: Any] {
            for i in 0..<4 {
                let key = "Lane \(i)"
                guard let laneProps = laneDict[key] as? [String: Any] else { continue }
                let lane = PhyLane(
                    index: i,
                    transport: (laneProps["Transport"] as? String) ?? "",
                    powerLevel: (laneProps["Power Level"] as? String) ?? "",
                    client: (laneProps["Client"] as? String) ?? ""
                )
                lanes.append(lane)
            }
        }

        let usb2: PhyUSB2?
        if let usb2Dict = read("AppleTypeCPhyUSB2") as? [String: Any] {
            usb2 = PhyUSB2(
                transport: (usb2Dict["Transport"] as? String) ?? "",
                client: (usb2Dict["Client"] as? String) ?? ""
            )
        } else {
            usb2 = nil
        }

        let dpPclk: PhyDisplayPortPclk?
        if let pclkDict = read("AppleTypeCPhyDisplayPortPclk") as? [String: Any] {
            dpPclk = PhyDisplayPortPclk(
                linkRate: (pclkDict["Link Rate"] as? String) ?? ""
            )
        } else {
            dpPclk = nil
        }

        let dpTunnel = read("AppleTypeCPhyDisplayPortTunnel") as? String

        return AppleTypeCPhy(
            id: phyID,
            lanes: lanes,
            usb2: usb2,
            displayPortPclk: dpPclk,
            displayPortTunnel: dpTunnel
        )
    }

    private func registerInterest(for service: io_service_t, entryID: UInt64) {
        guard let notifyPort, interestNotifications[entryID] == nil else { return }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let cb: IOServiceInterestCallback = { refcon, _, _, _ in
            guard let refcon else { return }
            let watcher = Unmanaged<AppleTypeCPhyWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor [weak watcher] in watcher?.refresh() }
        }
        var notification: io_object_t = 0
        let result = IOServiceAddInterestNotification(
            notifyPort,
            service,
            kIOGeneralInterest,
            cb,
            selfPtr,
            &notification
        )
        if result == KERN_SUCCESS {
            interestNotifications[entryID] = notification
        }
    }
}
