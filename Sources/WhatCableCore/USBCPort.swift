import Foundation

public struct USBCPort: Identifiable, Hashable {
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
    public let powerCurrentLimits: [Int]
    public let firmwareVersion: String?
    public let bootFlagsHex: String?
    /// Index of the XHCI controller serving this physical port, derived from
    /// the `hpmN@…` ancestor in the IOKit parent chain on M3+ machines.
    /// Pairs with `USBDevice.busIndex` for device-to-port matching. `nil`
    /// when the parent walk doesn't find an `hpm` node (e.g. M1/M2, MagSafe).
    public let busIndex: Int?
    public let rawProperties: [String: String]

    /// Build a `USBCPort` from a parsed IOKit property dictionary. Returns nil
    /// if the entry isn't a real physical Type-C / MagSafe port. Lives in
    /// `WhatCableCore` rather than the watcher so it can be exercised against
    /// fixture data without IOKit. The watcher feeds in real CFProperties;
    /// tests feed in hand-crafted dictionaries derived from `ioreg` dumps.
    public static func from(
        entryID: UInt64,
        serviceName: String,
        className: String,
        properties: [String: Any],
        busIndex: Int? = nil
    ) -> USBCPort? {
        // Only return things that actually look like a physical Type-C or
        // MagSafe port. Real ports have a `PortTypeDescription` and a name
        // like `Port-USB-C@N` / `Port-MagSafe 3@N`.
        let portType = properties["PortTypeDescription"] as? String
        let isRealPort = (portType == "USB-C" || portType?.hasPrefix("MagSafe") == true)
            && serviceName.hasPrefix("Port-")
        guard isRealPort else { return nil }

        var raw: [String: String] = [:]
        for (k, v) in properties { raw[k] = stringifyProperty(v) }

        return USBCPort(
            id: entryID,
            serviceName: serviceName,
            className: className,
            portDescription: properties["PortDescription"] as? String,
            portTypeDescription: properties["PortTypeDescription"] as? String,
            portNumber: (properties["PortNumber"] as? NSNumber)?.intValue,
            connectionActive: (properties["ConnectionActive"] as? NSNumber)?.boolValue,
            activeCable: (properties["ActiveCable"] as? NSNumber)?.boolValue,
            opticalCable: (properties["OpticalCable"] as? NSNumber)?.boolValue,
            usbActive: (properties["IOAccessoryUSBActive"] as? NSNumber)?.boolValue,
            superSpeedActive: (properties["IOAccessoryUSBSuperSpeedActive"] as? NSNumber)?.boolValue,
            usbModeType: (properties["IOAccessoryUSBModeType"] as? NSNumber)?.intValue,
            usbConnectString: properties["IOAccessoryUSBConnectString"] as? String,
            transportsSupported: stringArrayProperty(properties["TransportsSupported"]),
            transportsActive: stringArrayProperty(properties["TransportsActive"]),
            transportsProvisioned: stringArrayProperty(properties["TransportsProvisioned"]),
            plugOrientation: (properties["PlugOrientation"] as? NSNumber)?.intValue,
            plugEventCount: (properties["Plug Event Count"] as? NSNumber)?.intValue,
            connectionCount: (properties["ConnectionCount"] as? NSNumber)?.intValue,
            overcurrentCount: (properties["Overcurrent Count"] as? NSNumber)?.intValue,
            pinConfiguration: pinConfigProperty(properties["Pin Configuration"]),
            powerCurrentLimits: intArrayProperty(properties["IOAccessoryPowerCurrentLimits"]),
            firmwareVersion: hexDataProperty(properties["FW Version"]),
            bootFlagsHex: hexDataProperty(properties["Boot Flags"]),
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
        powerCurrentLimits: [Int],
        firmwareVersion: String?,
        bootFlagsHex: String?,
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
        self.powerCurrentLimits = powerCurrentLimits
        self.firmwareVersion = firmwareVersion
        self.bootFlagsHex = bootFlagsHex
        self.busIndex = busIndex
        self.rawProperties = rawProperties
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
// Used by `USBCPort.from(...)` and (transitively) by the watcher. Pulled out
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
        return "{" + d.map { "\($0.key): \(stringifyProperty($0.value))" }.joined(separator: ", ") + "}"
    default: return String(describing: value)
    }
}
