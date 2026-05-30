import Foundation
import IOKit
import WhatCableCore

@MainActor
public final class DisplayPortTransportWatcher: ObservableObject {
    public struct DisplayPortUpdate: Codable, Sendable, Equatable {
        public let portIndex: Int
        public let portType: String
        public let status: IOPortTransportStateDisplayPort
    }

    @Published public private(set) var statuses: [DisplayPortUpdate] = []

    public let updates: AsyncStream<DisplayPortUpdate>

    private var continuation: AsyncStream<DisplayPortUpdate>.Continuation?
    private var notifyPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0

    public init() {
        var continuation: AsyncStream<DisplayPortUpdate>.Continuation?
        updates = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    public func start() {
        guard notifyPort == nil else { return }
        let port = IONotificationPortCreate(kIOMainPortDefault)
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        notifyPort = port

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let added: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            let watcher = Unmanaged<DisplayPortTransportWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in watcher.handleAdded(iterator) }
        }
        let removed: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            let watcher = Unmanaged<DisplayPortTransportWatcher>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in watcher.handleRemoved(iterator) }
        }

        if IOServiceAddMatchingNotification(
            port,
            kIOMatchedNotification,
            IOServiceMatching("IOPortTransportStateDisplayPort"),
            added,
            selfPtr,
            &addedIterator
        ) == KERN_SUCCESS {
            handleAdded(addedIterator)
        }

        if IOServiceAddMatchingNotification(
            port,
            kIOTerminatedNotification,
            IOServiceMatching("IOPortTransportStateDisplayPort"),
            removed,
            selfPtr,
            &removedIterator
        ) == KERN_SUCCESS {
            handleRemoved(removedIterator)
        }
    }

    public func stop() {
        if addedIterator != 0 { IOObjectRelease(addedIterator); addedIterator = 0 }
        if removedIterator != 0 { IOObjectRelease(removedIterator); removedIterator = 0 }
        if let port = notifyPort {
            IONotificationPortDestroy(port)
            notifyPort = nil
        }
        statuses.removeAll()
    }

    public func refresh() {
        // Build locally and assign once so subscribers never see a transient
        // empty list mid-refresh. The per-update continuation yield is kept so
        // the `updates` stream contract is unchanged. See issue #227.
        var rebuilt: [DisplayPortUpdate] = []
        var iter: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOPortTransportStateDisplayPort"), &iter) == KERN_SUCCESS {
            while case let service = IOIteratorNext(iter), service != 0 {
                if let update = makeUpdate(from: service) {
                    rebuilt.removeAll {
                        $0.portIndex == update.portIndex && $0.portType == update.portType
                    }
                    rebuilt.append(update)
                    continuation?.yield(update)
                }
                IOObjectRelease(service)
            }
            IOObjectRelease(iter)
        }
        if rebuilt != statuses { statuses = rebuilt }
    }

    private func handleAdded(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            if let update = makeUpdate(from: service) {
                statuses.removeAll {
                    $0.portIndex == update.portIndex && $0.portType == update.portType
                }
                statuses.append(update)
                continuation?.yield(update)
            }
            IOObjectRelease(service)
        }
    }

    private func handleRemoved(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            // Use per-key reads so portIndex and portType match what makeUpdate
            // stored, not the registry location fallback that wcPortIndex(from:[:])
            // falls through to when the dict is empty (W1 fix).
            func read(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            let portIndex = wcPortIndex(read: read, service: service)
            let portType = wcPortType(read: read, service: service)
            statuses.removeAll {
                $0.portIndex == portIndex && $0.portType == portType
            }
        }
    }

    private func makeUpdate(from service: io_service_t) -> DisplayPortUpdate? {
        // Read keys individually rather than fetching the full property
        // dictionary. The bulk fetch (IORegistryEntryCreateCFProperties)
        // can abort the process from inside IOCFUnserializeBinary when
        // the kernel returns a malformed serialised properties blob,
        // typically when the service is being torn down mid-read. The
        // per-key call has no such failure path. See issue #181.
        func read(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }

        let link = DisplayPortLink(
            active: wcBool(read("Active")),
            laneCount: wcInt(read("LaneCount")),
            maxLaneCount: wcInt(read("MaxLaneCount")),
            linkRate: wcInt(read("LinkRate")),
            linkRateDescription: read("LinkRateDescription") as? String,
            tunneled: wcBool(read("Tunneled")),
            hpdState: wcInt(read("HPD_State")),
            hpdStateDescription: read("HPD_StateDescription") as? String
        )

        let metadata = read("Metadata") as? [String: Any]
        let monitor = MonitorInfo(
            manufacturerName: (read("ManufacturerName") as? String)
                ?? (metadata?["ManufacturerName"] as? String),
            productName: (read("ProductName") as? String)
                ?? (metadata?["ProductName"] as? String),
            productId: read("ProductID").map(wcInt)
                ?? metadata?["ProductID"].map(wcInt),
            serialNumber: read("SerialNumber").map(wcInt)
                ?? metadata?["SerialNumber"].map(wcInt),
            yearOfManufacture: read("YearOfManufacture").map(wcInt)
                ?? metadata?["Year of Manufacture"].map(wcInt),
            weekOfManufacture: metadata?["Week of Manufacture"].map(wcInt),
            edid: wcData(read("EDID")) ?? wcData(metadata?["EDID"])
        )

        let freqs: [Int]
        if let arr = read("NominalSignalingFrequenciesHz") as? [Any] {
            freqs = arr.map { wcInt($0) }
        } else {
            freqs = []
        }

        let status = IOPortTransportStateDisplayPort(
            link: link,
            monitor: monitor,
            dfpType: (read("DFP Type Description") as? String)
                ?? (metadata?["DFP Type Description"] as? String)
                ?? read("DFP Type").map { String(wcInt($0)) },
            branchDeviceId: (read("BranchDeviceID") as? String)
                ?? (metadata?["BranchDeviceID"] as? String),
            branchDeviceOUI: wcData(read("BranchDeviceOUI"))
                ?? wcData(metadata?["BranchDeviceOUI"]),
            sinkCount: wcInt(read("SinkCount")),
            role: wcInt(read("Role")),
            roleDescription: read("RoleDescription") as? String,
            driverStatus: wcInt(read("DriverStatus")),
            driverStatusDescription: read("DriverStatusDescription") as? String,
            transportType: wcInt(read("TransportType")),
            transportTypeDescription: read("TransportTypeDescription") as? String,
            transportDescription: read("TransportDescription") as? String,
            authorizationRequired: wcBool(read("AuthorizationRequired")),
            authorizationStatus: wcInt(read("AuthorizationStatus")),
            authorizationStatusDescription: read("AuthorizationStatusDescription") as? String,
            authenticationRequired: wcBool(read("AuthenticationRequired")),
            authenticationStatus: wcInt(read("AuthenticationStatus")),
            authenticationStatusDescription: read("AuthenticationStatusDescription") as? String,
            hashStatus: wcInt(read("HashStatus")),
            hashStatusDescription: read("HashStatusDescription") as? String,
            trmTransportSupervised: wcBool(read("TRM_TransportSupervised")),
            parentPortType: wcInt(read("ParentPortType")),
            parentPortTypeDescription: read("ParentPortTypeDescription") as? String,
            parentPortNumber: wcInt(read("ParentPortNumber")),
            parentPortBuiltIn: wcBool(read("ParentPortBuiltIn")),
            parentBuiltInPortType: wcInt(read("ParentBuiltInPortType")),
            parentBuiltInPortTypeDescription: read("ParentBuiltInPortTypeDescription") as? String,
            parentBuiltInPortNumber: wcInt(read("ParentBuiltInPortNumber")),
            edidChanged: wcBool(read("EDIDChanged")),
            nominalSignalingFrequenciesHz: freqs,
            index: wcInt(read("Index"))
        )
        return DisplayPortUpdate(
            portIndex: wcPortIndex(read: read, service: service),
            portType: wcPortType(read: read, service: service),
            status: status
        )
    }
}
