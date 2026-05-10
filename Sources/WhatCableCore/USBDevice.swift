import Foundation

public struct USBDevice: Identifiable, Hashable {
    public let id: UInt64
    public let locationID: UInt32
    public let vendorID: UInt16
    public let productID: UInt16
    public let vendorName: String?
    public let productName: String?
    public let serialNumber: String?
    public let usbVersion: String?
    public let speedRaw: UInt8?
    public let busPowerMA: Int?
    public let currentMA: Int?
    /// Index of the XHCI controller this device is attached to, derived from
    /// the upper byte of `locationID` (and confirmed by walking the IOKit
    /// parent chain to the `AppleT*USBXHCI` ancestor). Used to associate the
    /// device with its physical USB-C port. `nil` if the parent walk failed.
    public let busIndex: Int?
    /// Service name of the physical port this device's XHCI controller is
    /// wired to (e.g. "Port-USB-C@1"), parsed from the controller's
    /// `UsbIOPort` property. This is a direct mapping and is preferred over
    /// `busIndex` when available. `nil` on machines that don't expose
    /// `UsbIOPort` on the XHCI controller.
    public let controllerPortName: String?
    public let rawProperties: [String: String]

    public init(
        id: UInt64,
        locationID: UInt32,
        vendorID: UInt16,
        productID: UInt16,
        vendorName: String?,
        productName: String?,
        serialNumber: String?,
        usbVersion: String?,
        speedRaw: UInt8?,
        busPowerMA: Int?,
        currentMA: Int?,
        busIndex: Int? = nil,
        controllerPortName: String? = nil,
        rawProperties: [String: String]
    ) {
        self.id = id
        self.locationID = locationID
        self.vendorID = vendorID
        self.productID = productID
        self.vendorName = vendorName
        self.productName = productName
        self.serialNumber = serialNumber
        self.usbVersion = usbVersion
        self.speedRaw = speedRaw
        self.busPowerMA = busPowerMA
        self.currentMA = currentMA
        self.busIndex = busIndex
        self.controllerPortName = controllerPortName
        self.rawProperties = rawProperties
    }

    public var speedLabel: String {
        speedLabel(language: .default)
    }

    public func speedLabel(language: WhatCableLanguage = .default) -> String {
        // IOUSBHostDevice "Device Speed" enum values
        switch speedRaw {
        case 0: return LocalizedCopy.string("Low Speed (1.5 Mbps)", language: language)
        case 1: return LocalizedCopy.string("Full Speed (12 Mbps)", language: language)
        case 2: return LocalizedCopy.string("High Speed (480 Mbps)", language: language)
        case 3: return LocalizedCopy.string("Super Speed (5 Gbps)", language: language)
        case 4: return LocalizedCopy.string("Super Speed+ (10 Gbps)", language: language)
        case 5: return LocalizedCopy.string("Super Speed+ Gen 2x2 (20 Gbps)", language: language)
        default: return LocalizedCopy.string("Unknown speed", language: language)
        }
    }
}
