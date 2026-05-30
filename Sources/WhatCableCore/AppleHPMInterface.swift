import Foundation

public struct AppleHPMInterface: Identifiable, Hashable {
    public let id: UInt64
    public let serviceName: String          // e.g. "Port-USB-C@1"
    public let className: String            // e.g. "AppleHPMInterfaceType10"
    public let portDescription: String?     // "Port-USB-C@1"
    public let portTypeDescription: String? // "USB-C"
    public let portNumber: Int?
    public let connectionActive: Bool?
    public let activeCable: Bool?
    public let opticalCable: Bool?
    public let usbActive: Bool?
    public let superSpeedActive: Bool?
    public let usbModeType: Int?            // raw enum
    public let usbConnectString: String?    // "None" / human label
    public let transportsSupported: [String]
    public let transportsActive: [String]
    public let transportsProvisioned: [String]
    public let plugOrientation: Int?
    public let plugEventCount: Int?
    public let connectionCount: Int?
    public let overcurrentCount: Int?
    public let pinConfiguration: [String: String]
    public let displayPortPinAssignment: Int?
    public let powerCurrentLimits: [Int]
    public let firmwareVersion: String?
    public let bootFlagsHex: String?
    /// Liquid detection state from the HPM controller. "Idle" means clear.
    public let ldcmStateDescription: String?
    /// Active features reported by the HPM controller (e.g. ["TRM", "LDCM", "Power In"]).
    public let featuresEnabled: [String]
    /// Current power mode from IOAccessoryPowerMode.
    public let accessoryPowerMode: Int?
    /// Active power mode from IOAccessoryActivePowerMode.
    public let accessoryActivePowerMode: Int?
    /// Index of the XHCI controller serving this physical port, derived from
    /// the `hpmN@…` ancestor in the IOKit parent chain on M3+ machines.
    /// Pairs with `USBDevice.busIndex` for device-to-port matching. `nil`
    /// when the parent walk doesn't find an `hpm` node (e.g. M1/M2, MagSafe).
    public let busIndex: Int?
    public let rawProperties: [String: String]

    /// Build from a parsed IOKit property dictionary. Returns nil
    /// if the entry isn't a real physical Type-C / MagSafe port. Lives in
    /// `WhatCableCore` rather than the watcher so it can be exercised against
    /// fixture data without IOKit. The watcher feeds in real CFProperties;
    /// tests feed in hand-crafted dictionaries derived from `ioreg` dumps.
    public static func from(
        entryID: UInt64,
        serviceName: String,
        className: String,
        read: (String) -> Any?,
        readAll: (() -> [String: Any]?)? = nil,
        busIndex: Int? = nil
    ) -> AppleHPMInterface? {
        // Only return things that actually look like a physical Type-C or
        // MagSafe port. Real ports have a `PortTypeDescription` and a name
        // like `Port-USB-C@N` / `Port-MagSafe 3@N`.
        let portType = read("PortTypeDescription") as? String
        let isRealPort = (portType == "USB-C" || portType?.hasPrefix("MagSafe") == true)
            && serviceName.hasPrefix("Port-")
        guard isRealPort else { return nil }

        // Build rawProperties for CLI verbose output (`--raw` flag and
        // `whatcable` verbose mode). When the caller provides `readAll`,
        // use a bulk fetch to capture every key the service publishes --
        // this preserves the complete property dump that existed before
        // the per-key hardening work (DAR-41). Fall back to the known-key
        // list when no bulk-fetch path is available (e.g. unit tests).
        // HPM port-controller services are long-lived: they appear at boot
        // and disappear on dock removal, so the teardown window where the
        // bulk fetch can crash is narrow. All operational data fields
        // (connectionActive, transportsActive, etc.) always come from the
        // crash-safe per-key `read` calls above, regardless of this path.
        var raw: [String: String] = [:]
        if let allProps = readAll?() {
            for (key, value) in allProps {
                raw[key] = stringifyProperty(value)
            }
        } else {
            let knownKeys = [
                "PortType", "PortTypeDescription", "PortDescription", "PortNumber",
                "ConnectionActive", "ActiveCable", "OpticalCable",
                "IOAccessoryUSBActive", "IOAccessoryUSBSuperSpeedActive",
                "IOAccessoryUSBModeType", "IOAccessoryUSBConnectString",
                "TransportsSupported", "TransportsActive", "TransportsProvisioned",
                "PlugOrientation", "Plug Event Count", "ConnectionCount",
                "Overcurrent Count", "Pin Configuration", "DisplayPortPinAssignment",
                "IOAccessoryPowerCurrentLimits", "FW Version", "Boot Flags",
                "LDCM_StateDescription", "FeaturesEnabled",
                "IOAccessoryPowerMode", "IOAccessoryActivePowerMode",
            ]
            for key in knownKeys {
                if let v = read(key) { raw[key] = stringifyProperty(v) }
            }
        }

        return AppleHPMInterface(
            id: entryID,
            serviceName: serviceName,
            className: className,
            portDescription: read("PortDescription") as? String,
            portTypeDescription: portType,
            portNumber: (read("PortNumber") as? NSNumber)?.intValue,
            connectionActive: (read("ConnectionActive") as? NSNumber)?.boolValue,
            activeCable: (read("ActiveCable") as? NSNumber)?.boolValue,
            opticalCable: (read("OpticalCable") as? NSNumber)?.boolValue,
            usbActive: (read("IOAccessoryUSBActive") as? NSNumber)?.boolValue,
            superSpeedActive: (read("IOAccessoryUSBSuperSpeedActive") as? NSNumber)?.boolValue,
            usbModeType: (read("IOAccessoryUSBModeType") as? NSNumber)?.intValue,
            usbConnectString: read("IOAccessoryUSBConnectString") as? String,
            transportsSupported: stringArrayProperty(read("TransportsSupported")),
            transportsActive: stringArrayProperty(read("TransportsActive")),
            transportsProvisioned: stringArrayProperty(read("TransportsProvisioned")),
            plugOrientation: (read("PlugOrientation") as? NSNumber)?.intValue,
            plugEventCount: (read("Plug Event Count") as? NSNumber)?.intValue,
            connectionCount: (read("ConnectionCount") as? NSNumber)?.intValue,
            overcurrentCount: (read("Overcurrent Count") as? NSNumber)?.intValue,
            pinConfiguration: pinConfigProperty(read("Pin Configuration")),
            displayPortPinAssignment: (read("DisplayPortPinAssignment") as? NSNumber)?.intValue,
            powerCurrentLimits: intArrayProperty(read("IOAccessoryPowerCurrentLimits")),
            firmwareVersion: hexDataProperty(read("FW Version")),
            bootFlagsHex: hexDataProperty(read("Boot Flags")),
            ldcmStateDescription: read("LDCM_StateDescription") as? String,
            featuresEnabled: stringArrayProperty(read("FeaturesEnabled")),
            accessoryPowerMode: (read("IOAccessoryPowerMode") as? NSNumber)?.intValue,
            accessoryActivePowerMode: (read("IOAccessoryActivePowerMode") as? NSNumber)?.intValue,
            busIndex: busIndex,
            rawProperties: raw
        )
    }

    public init(
        id: UInt64,
        serviceName: String,
        className: String,
        portDescription: String?,
        portTypeDescription: String?,
        portNumber: Int?,
        connectionActive: Bool?,
        activeCable: Bool?,
        opticalCable: Bool?,
        usbActive: Bool?,
        superSpeedActive: Bool?,
        usbModeType: Int?,
        usbConnectString: String?,
        transportsSupported: [String],
        transportsActive: [String],
        transportsProvisioned: [String],
        plugOrientation: Int?,
        plugEventCount: Int?,
        connectionCount: Int?,
        overcurrentCount: Int?,
        pinConfiguration: [String: String],
        displayPortPinAssignment: Int? = nil,
        powerCurrentLimits: [Int],
        firmwareVersion: String?,
        bootFlagsHex: String?,
        ldcmStateDescription: String? = nil,
        featuresEnabled: [String] = [],
        accessoryPowerMode: Int? = nil,
        accessoryActivePowerMode: Int? = nil,
        busIndex: Int? = nil,
        rawProperties: [String: String]
    ) {
        self.id = id
        self.serviceName = serviceName
        self.className = className
        self.portDescription = portDescription
        self.portTypeDescription = portTypeDescription
        self.portNumber = portNumber
        self.connectionActive = connectionActive
        self.activeCable = activeCable
        self.opticalCable = opticalCable
        self.usbActive = usbActive
        self.superSpeedActive = superSpeedActive
        self.usbModeType = usbModeType
        self.usbConnectString = usbConnectString
        self.transportsSupported = transportsSupported
        self.transportsActive = transportsActive
        self.transportsProvisioned = transportsProvisioned
        self.plugOrientation = plugOrientation
        self.plugEventCount = plugEventCount
        self.connectionCount = connectionCount
        self.overcurrentCount = overcurrentCount
        self.pinConfiguration = pinConfiguration
        self.displayPortPinAssignment = displayPortPinAssignment
        self.powerCurrentLimits = powerCurrentLimits
        self.firmwareVersion = firmwareVersion
        self.bootFlagsHex = bootFlagsHex
        self.ldcmStateDescription = ldcmStateDescription
        self.featuresEnabled = featuresEnabled
        self.accessoryPowerMode = accessoryPowerMode
        self.accessoryActivePowerMode = accessoryActivePowerMode
        self.busIndex = busIndex
        self.rawProperties = rawProperties
    }

    /// Decoded DisplayPort alt mode lane configuration, if DP is active.
    public var dpLaneConfig: DisplayPortLaneConfig? {
        // DisplayPort must actually be carried on this link to report a lane
        // split. Decide 2-lane vs 4-lane from whether USB3 is active alongside
        // it, not from DisplayPortPinAssignment (unreliable, see issue #228).
        guard transportsActive.contains("DisplayPort") else { return nil }
        return DisplayPortLaneConfig(
            usb3Active: transportsActive.contains("USB3"),
            rawPinAssignment: displayPortPinAssignment ?? 0
        )
    }

    /// True when this port can host a data link (USB or Thunderbolt).
    /// MagSafe and any other power-only port returns false. Source of
    /// truth for "should we attempt to correlate this port to a TB
    /// switch lane". The `@N` socket suffix on a power-only port can
    /// collide with the first USB-C port on the same HPM controller
    /// (issue #195, universal across M-class chips); gating any
    /// topology lookup on this property is what keeps that collision
    /// from leaking USB-C lane state onto power-only ports.
    public var carriesData: Bool {
        let dataTransports: Set<String> = ["USB2", "USB3", "USB4", "CIO", "DisplayPort"]
        return transportsSupported.contains(where: dataTransports.contains)
    }

    public func matchingDevices(from devices: [USBDevice]) -> [USBDevice] {
        guard connectionActive == true else { return [] }

        let portNames = [serviceName, portDescription].compactMap(Self.cleanPortName)

        if !portNames.isEmpty {
            let directMatches = devices.filter { device in
                guard let name = device.controllerPortName else { return false }
                return portNames.contains { portName in
                    Self.portNameMatches(
                        portName,
                        deviceName: name,
                        portBusIndex: busIndex,
                        deviceBusIndex: device.busIndex
                    )
                }
            }
            if !directMatches.isEmpty {
                return directMatches
            }
        }

        guard carriesUSB, let busIndex else { return [] }
        return devices.filter { device in
            device.controllerPortName == nil && device.busIndex == busIndex
        }
    }

    private var carriesUSB: Bool {
        if usbActive == true || superSpeedActive == true {
            return true
        }
        return transportsActive.contains { transport in
            transport == "USB2" || transport == "USB3" || transport == "USB4" || transport == "CIO"
        }
    }

    private static func portNameMatches(
        _ portName: String,
        deviceName: String,
        portBusIndex: Int?,
        deviceBusIndex: Int?
    ) -> Bool {
        guard let portName = cleanPortName(portName),
              let deviceName = cleanPortName(deviceName) else {
            return false
        }
        if portName == deviceName {
            return true
        }
        guard busIndexesAreCompatible(portBusIndex, deviceBusIndex) else {
            return false
        }
        if basePortName(portName) == deviceName {
            return true
        }
        if basePortName(deviceName) == portName {
            return true
        }
        return false
    }

    private static func cleanPortName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func basePortName(_ value: String) -> String? {
        guard let at = value.firstIndex(of: "@") else { return nil }
        let base = String(value[..<at])
        return base.hasPrefix("Port-") ? base : nil
    }

    private static func busIndexesAreCompatible(_ lhs: Int?, _ rhs: Int?) -> Bool {
        guard let lhs, let rhs else { return true }
        return lhs == rhs
    }
}

// MARK: - Property-dictionary parsing helpers
//
// Used by `AppleHPMInterface.from(...)` and (transitively) by the watcher. Pulled out
// to file scope so the pure factory can run without an instance.

func stringArrayProperty(_ value: Any?) -> [String] {
    (value as? [Any])?.compactMap { $0 as? String } ?? []
}

func intArrayProperty(_ value: Any?) -> [Int] {
    (value as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue } ?? []
}

func pinConfigProperty(_ value: Any?) -> [String: String] {
    guard let dict = value as? [String: Any] else { return [:] }
    var result: [String: String] = [:]
    for (k, v) in dict { result[k] = stringifyProperty(v) }
    return result
}

func hexDataProperty(_ value: Any?) -> String? {
    guard let data = value as? Data else { return nil }
    return data.map { String(format: "%02X", $0) }.joined(separator: " ")
}

func stringifyProperty(_ value: Any) -> String {
    switch value {
    case let n as NSNumber: return n.stringValue
    case let s as String: return s
    case let d as Data: return d.map { String(format: "%02X", $0) }.joined(separator: " ")
    case let a as [Any]: return "[" + a.map { stringifyProperty($0) }.joined(separator: ", ") + "]"
    case let d as [String: Any]:
        return "{" + d.sorted { $0.key < $1.key }.map { "\($0.key): \(stringifyProperty($0.value))" }.joined(separator: ", ") + "}"
    default: return String(describing: value)
    }
}

@available(*, deprecated, renamed: "AppleHPMInterface")
public typealias USBCPort = AppleHPMInterface
