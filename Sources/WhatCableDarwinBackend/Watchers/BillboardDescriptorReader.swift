import Foundation
import IOKit
import IOKit.usb
import IOKit.usb.IOUSBLib
import WhatCableCore

/// Reads a USB device's Billboard Capability Descriptor (BOS device-capability
/// type `0x0d`) and parses out the advertised Alt Modes and their per-mode
/// state.
///
/// How it gets the bytes: IOKit does not publish the parsed capability as a
/// property, so we fetch the BOS descriptor ourselves with a standard
/// `GET_DESCRIPTOR(BOS)` control transfer over the legacy
/// `IOUSBDeviceInterface` (the same path the Test Kit C probe
/// `25_usb_bos_descriptor.c` uses). This works from the app's userspace
/// context without USB entitlements and *without opening the device*, as long
/// as no kernel driver has exclusive-opened it. The app is not sandboxed, so
/// nothing extra is required. Confirmed on live hardware.
///
/// We never open the device. A no-open `DeviceRequest` is harmless on any
/// device: it either returns the descriptor (a Billboard device, or a dock that
/// carries a Billboard capability in its BOS) or returns a non-fatal error (no
/// BOS, a pipe stall, etc). It does *not* disturb a device a kernel driver is
/// holding, so it is safe to call on every USB device. The fix for issue #370
/// is exactly this no-open contract: an earlier version fell back to
/// `USBDeviceOpen` on a failed read, and force-opening a device its kernel HID
/// driver owns seizes it and freezes input devices (a 2.4 GHz mouse receiver in
/// that report). That fallback is gone.
///
/// Not every Billboard is read here. The Billboard nub
/// (`AppleUSBHostBillboardDevice`, the node macOS creates under a device's
/// Billboard interface) refuses the IOUSBLib plug-in:
/// `IOCreatePlugInInterfaceForService` fails with kIOReturnUnsupported on all
/// 400 such nubs in the customer-probe corpus (probe 25). The nub is not an
/// `IOUSBHostDevice`, so it never reaches this reader anyway; its
/// `UsbBillboard*` registry keys (macOS's own decode of the descriptor) are
/// read off the nub by `USBWatcher.billboardNubPropertyDictionaries` and
/// parsed by `USBWatcher.registryBillboard`. This reader still serves the 492
/// host-device BOS blocks in that corpus (docks and devices that carry a
/// Billboard capability inside their own BOS), which decode cleanly here.
///
/// All of this is one-shot and synchronous: call it once when a device appears,
/// never on a poll. It is a free function (no actor state) so the watcher can
/// call it off whatever context it likes.
enum BillboardDescriptorReader {

    // CFUUIDs for the IOUSBLib plug-in dance. The C headers expose these as
    // macros that Swift can't import, so we rebuild them from their byte values.
    private static let plugInTypeID = CFUUIDGetConstantUUIDWithBytes(nil,
        0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4,
        0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F) // kIOCFPlugInInterfaceID
    private static let userClientTypeID = CFUUIDGetConstantUUIDWithBytes(nil,
        0x9D, 0xC7, 0xB7, 0x80, 0x9E, 0xC0, 0x11, 0xD4,
        0xA5, 0x4F, 0x00, 0x0A, 0x27, 0x05, 0x28, 0x61) // kIOUSBDeviceUserClientTypeID
    private static let deviceInterfaceID = CFUUIDGetConstantUUIDWithBytes(nil,
        0x5C, 0x81, 0x87, 0xD0, 0x9E, 0xF3, 0x11, 0xD4,
        0x8B, 0x45, 0x00, 0x0A, 0x27, 0x05, 0x28, 0x61) // kIOUSBDeviceInterfaceID

    /// Returns the parsed Billboard capability, or `nil` if the device has no
    /// Billboard cap or the read failed at any step. Never throws. Byte parsing
    /// is `BillboardCapability.parse` in Core; this only fetches the raw bytes.
    static func read(from service: io_service_t) -> BillboardCapability? {
        guard let bos = fetchBOSDescriptor(service) else { return nil }
        return BillboardCapability.parse(bos: bos)
    }

    // MARK: - IOKit control transfer

    private static func fetchBOSDescriptor(_ service: io_service_t) -> [UInt8]? {
        var plugIn: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0
        guard IOCreatePlugInInterfaceForService(service, userClientTypeID, plugInTypeID,
                                                &plugIn, &score) == KERN_SUCCESS,
              let plugIn, let plugInIface = plugIn.pointee else {
            return nil
        }

        var devRaw: UnsafeMutableRawPointer?
        let hr = plugInIface.pointee.QueryInterface(
            UnsafeMutableRawPointer(plugIn),
            CFUUIDGetUUIDBytes(deviceInterfaceID),
            &devRaw)
        IODestroyPlugInInterface(plugIn)
        guard hr == 0, let devRaw else { return nil }

        let dev = devRaw.assumingMemoryBound(to: UnsafeMutablePointer<IOUSBDeviceInterface>?.self)
        defer { _ = dev.pointee?.pointee.Release(dev) }

        // GET_DESCRIPTOR(BOS): IN | standard | device, descriptor type 0x0F.
        func request(into buffer: inout [UInt8], length: UInt16) -> Int32 {
            var req = IOUSBDevRequest()
            req.bmRequestType = 0x80
            req.bRequest = 0x06
            req.wValue = UInt16(0x0F) << 8
            req.wIndex = 0
            req.wLength = length
            return buffer.withUnsafeMutableBytes { ptr in
                req.pData = ptr.baseAddress
                return dev.pointee?.pointee.DeviceRequest(dev, &req) ?? -1
            }
        }

        // Stage 1: 5-byte header to learn the total length. We deliberately do
        // NOT open the device. This no-open request is safe on any device: it
        // returns the descriptor on a Billboard device and a non-fatal error
        // otherwise, without disturbing a driver-held device. A failed read is
        // final: we return nil rather than force-opening, because the old
        // USBDeviceOpen fallback seized HID devices from their kernel driver and
        // froze them (issue #370).
        var header = [UInt8](repeating: 0, count: 5)
        let rc = request(into: &header, length: 5)
        guard rc == kIOReturnSuccess, header[1] == 0x0F else { return nil }
        let total = Int(header[2]) | (Int(header[3]) << 8)
        guard total >= 5, total <= 4096 else { return nil }

        // Stage 2: the full descriptor.
        var buffer = [UInt8](repeating: 0, count: total)
        guard request(into: &buffer, length: UInt16(total)) == kIOReturnSuccess else { return nil }
        return buffer
    }
}
