import Foundation
import IOKit
import WhatCableCore

/// Watches `IOPortFeaturePowerSource` services. These appear under each port's
/// `Power In` feature when something that advertises PD is connected.
@MainActor
public final class PowerSourceWatcher: ObservableObject {
    @Published public private(set) var sources: [PowerSource] = []

    private var notifyPort: IONotificationPortRef?
    private var addedIter: io_iterator_t = 0
    private var removedIter: io_iterator_t = 0

    public init() {}

    public func start() {
        guard notifyPort == nil else { return }
        let port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        notifyPort = port

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let added: IOServiceMatchingCallback = { refcon, iter in
            guard let refcon else { return }
            let w = Unmanaged<PowerSourceWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in w.handleAdded(iter) }
        }
        let removed: IOServiceMatchingCallback = { refcon, iter in
            guard let refcon else { return }
            let w = Unmanaged<PowerSourceWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in w.handleRemoved(iter) }
        }

        let matching = IOServiceMatching("IOPortFeaturePowerSource")
        if IOServiceAddMatchingNotification(port, kIOMatchedNotification, matching, added, selfPtr, &addedIter) == KERN_SUCCESS {
            handleAdded(addedIter)
        }

        let matching2 = IOServiceMatching("IOPortFeaturePowerSource")
        if IOServiceAddMatchingNotification(port, kIOTerminatedNotification, matching2, removed, selfPtr, &removedIter) == KERN_SUCCESS {
            handleRemoved(removedIter)
        }
    }

    public func stop() {
        if addedIter != 0 { IOObjectRelease(addedIter); addedIter = 0 }
        if removedIter != 0 { IOObjectRelease(removedIter); removedIter = 0 }
        if let p = notifyPort { IONotificationPortDestroy(p); notifyPort = nil }
        sources.removeAll()
    }

    public func refresh() {
        // Build the new list locally and assign once. Mutating the published
        // `sources` in place (removeAll then re-append) emits a transient empty
        // value that downstream subscribers see as "everything disconnected,"
        // which made NotificationManager fire a charger-connect/disconnect pair
        // on every poll tick. See issue #227.
        var rebuilt: [PowerSource] = []
        var iter: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOPortFeaturePowerSource"), &iter) == KERN_SUCCESS {
            while case let service = IOIteratorNext(iter), service != 0 {
                if let s = makeSource(from: service), !rebuilt.contains(where: { $0.id == s.id }) {
                    rebuilt.append(s)
                }
                IOObjectRelease(service)
            }
            IOObjectRelease(iter)
        }
        if rebuilt != sources { sources = rebuilt }
    }

    private func handleAdded(_ iter: io_iterator_t) {
        while case let service = IOIteratorNext(iter), service != 0 {
            if let s = makeSource(from: service), !sources.contains(where: { $0.id == s.id }) {
                sources.append(s)
            }
            IOObjectRelease(service)
        }
    }

    private func handleRemoved(_ iter: io_iterator_t) {
        while case let service = IOIteratorNext(iter), service != 0 {
            var entryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &entryID)
            sources.removeAll { $0.id == entryID }
            IOObjectRelease(service)
        }
    }

    private func makeSource(from service: io_service_t) -> PowerSource? {
        var entryID: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(service, &entryID)

        // Read keys individually rather than fetching the full property
        // dictionary. The bulk fetch (IORegistryEntryCreateCFProperties)
        // can abort the process from inside IOCFUnserializeBinary when
        // the kernel returns a malformed serialised properties blob,
        // typically when the service is being torn down mid-read. The
        // per-key call has no such failure path. See issue #181.
        func read(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }

        let name = (read("PowerSourceName") as? String) ?? "Unknown"
        let parent = Self.parentPortIdentity(read: read)

        let options: [PowerOption] = parseOptions(read("PowerSourceOptions"))
        let winning: PowerOption? = parseOption(read("WinningPowerSourceOption"))

        return PowerSource(
            id: entryID,
            name: name,
            parentPortType: parent.type,
            parentPortNumber: parent.number,
            options: options,
            winning: winning
        )
    }

    nonisolated static func parentPortIdentity(read: (String) -> Any?) -> (type: Int, number: Int) {
        let type = (read("ParentBuiltInPortType") as? NSNumber)?.intValue
            ?? (read("ParentPortType") as? NSNumber)?.intValue
            ?? 0
        let number = (read("ParentBuiltInPortNumber") as? NSNumber)?.intValue
            ?? (read("ParentPortNumber") as? NSNumber)?.intValue
            ?? Int(((read("Priority") as? NSNumber)?.uint64Value ?? 0) & 0xFF)
        return (type, number)
    }

    private func parseOptions(_ value: Any?) -> [PowerOption] {
        // IOKit publishes PowerSourceOptions as an __NSCFSet (CF set), not
        // an NSArray. ioreg renders it as "[{...}]" which looks like an
        // array, but the actual CF type is a set. Handle both.
        let items: [Any]
        if let set = value as? NSSet {
            items = set.allObjects
        } else if let arr = value as? NSArray {
            items = arr.compactMap { $0 }
        } else {
            return []
        }
        return items.compactMap { parseOption($0) }
            .sorted { $0.maxPowerMW > $1.maxPowerMW }
    }

    private func parseOption(_ value: Any?) -> PowerOption? {
        let dict: [String: Any]?
        if let d = value as? [String: Any] {
            dict = d
        } else if let nsd = value as? NSDictionary {
            var converted: [String: Any] = [:]
            for case let (key, val) as (String, Any) in nsd {
                converted[key] = val
            }
            dict = converted
        } else {
            dict = nil
        }
        guard let dict else { return nil }
        let v = (dict["Voltage (mV)"] as? NSNumber)?.intValue ?? 0
        let i = (dict["Max Current (mA)"] as? NSNumber)?.intValue ?? 0
        let p = (dict["Max Power (mW)"] as? NSNumber)?.intValue ?? (v * i / 1000)
        guard v > 0 else { return nil }
        return PowerOption(voltageMV: v, maxCurrentMA: i, maxPowerMW: p)
    }
}

extension PowerSourceWatcher {
    /// All power sources attached to a given port.
    public func sources(for port: AppleHPMInterface) -> [PowerSource] {
        guard let key = port.portKey else { return [] }
        return sources.filter { $0.portKey == key }
    }
}

