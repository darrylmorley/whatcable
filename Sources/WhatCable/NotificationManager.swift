#if os(macOS)
import Foundation
import Combine
import UserNotifications
import os.log
import WhatCableCore
import WhatCableDarwinBackend

/// Posts user notifications when USB-C cables / power sources connect or
/// disconnect, gated by the user's `AppSettings.notifyOnChanges` preference.
///
/// Runs its own watchers so events are observed even when the popover is
/// closed — the UI's watchers only run while the popover is on screen.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private nonisolated static let log = Logger(subsystem: "com.bitmoor.whatcable", category: "notifications")

    private let usbWatcher = USBWatcher()
    private let powerWatcher = PowerSourceWatcher()
    private var cancellables = Set<AnyCancellable>()

    private var knownDeviceIDs: Set<UInt64> = []
    private var knownSourceIDs: Set<UInt64> = []
    private var didPrimeBaseline = false

    private init() {}

    func start() {
        usbWatcher.start()
        powerWatcher.start()

        // Prime baseline on the next runloop tick so we don't fire a flurry
        // of "connected" notifications for things already plugged in at launch.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.knownDeviceIDs = Set(self.usbWatcher.devices.map(\.id))
            self.knownSourceIDs = Set(self.powerWatcher.sources.map(\.id))
            self.didPrimeBaseline = true
        }

        usbWatcher.$devices
            .sink { [weak self] devices in self?.diffDevices(devices) }
            .store(in: &cancellables)

        powerWatcher.$sources
            .sink { [weak self] sources in self?.diffSources(sources) }
            .store(in: &cancellables)
    }

    /// Request notification permission. Call when the user enables the toggle.
    func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error {
                        Self.log.error("Notification auth failed: \(error.localizedDescription, privacy: .public)")
                    } else {
                        Self.log.info("Notification auth granted: \(granted)")
                    }
                }
            default:
                break
            }
        }
    }

    private func diffDevices(_ current: [USBDevice]) {
        guard didPrimeBaseline else { return }
        let currentIDs = Set(current.map(\.id))
        let added = current.filter { !knownDeviceIDs.contains($0.id) }
        let removedCount = knownDeviceIDs.subtracting(currentIDs).count
        knownDeviceIDs = currentIDs

        guard AppSettings.shared.notifyOnChanges else { return }

        for device in added {
            let name = device.productName ?? "USB device"
            postNotification(
                title: "Connected: \(name)",
                body: "\(device.speedLabel)\(device.vendorName.map { " · \($0)" } ?? "")"
            )
        }
        if removedCount > 0 {
            postNotification(
                title: "USB device disconnected",
                body: removedCount == 1 ? "1 device removed" : "\(removedCount) devices removed"
            )
        }
    }

    private func diffSources(_ current: [PowerSource]) {
        guard didPrimeBaseline else { return }
        let currentIDs = Set(current.map(\.id))
        let added = current.filter { !knownSourceIDs.contains($0.id) }
        let removedCount = knownSourceIDs.subtracting(currentIDs).count
        knownSourceIDs = currentIDs

        guard AppSettings.shared.notifyOnChanges else { return }

        for source in added {
            let watts = source.winning.map { "\($0.wattsLabel) negotiated" } ?? "PD source"
            postNotification(title: "Charger connected", body: "\(source.name) · \(watts)")
        }
        if removedCount > 0 {
            postNotification(title: "Charger disconnected", body: "")
        }
    }

    private func postNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        if !body.isEmpty { content.body = body }
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Self.log.error("Post failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

#endif
