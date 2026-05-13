import Foundation

/// Decide whether a port is physically live based on the union of IOKit
/// watcher state (devices, power sources, PD identities) and the port-level
/// `ConnectionActive` flag.
///
/// Why this helper exists:
///
/// - `USBCPort.connectionActive` lingers `true` for several seconds after
///   unplug on MagSafe (`AppleHPMInterfaceType11`), so we can't trust it
///   alone there.
/// - The power source watcher caches the last negotiated PDO, so a port
///   with nothing plugged in can still expose a USB-PD source long after
///   the cable was removed (issue #47).
///
/// So we treat each signal differently. Devices and PD identities are
/// strong: their watchers terminate on real IOKit notifications, no
/// caching. The port-level `connectionActive` flag is trusted on
/// non-MagSafe. Power sources need corroboration before they count.
public func isPortLive(
    port: USBCPort,
    powerSources: [PowerSource],
    identities: [PDIdentity],
    matchingDevices: [USBDevice]
) -> Bool {
    if !matchingDevices.isEmpty { return true }
    if !identities.isEmpty { return true }

    let isMagSafe = port.portTypeDescription?.hasPrefix("MagSafe") == true
    if !isMagSafe && port.connectionActive == true { return true }

    // Power sources alone aren't enough: the watcher's cached PDO can
    // outlive the physical connection. Only count them when the port
    // itself agrees something is connected.
    if !powerSources.isEmpty && port.connectionActive == true { return true }

    return false
}
