import Foundation
import Combine
import WhatCableDarwinBackend

@MainActor
final class WatcherHub {
    static let shared = WatcherHub()

    let portWatcher    = AppleHPMInterfaceWatcher()
    let deviceWatcher  = USBWatcher()
    let powerWatcher   = PowerSourceWatcher()
    let pdWatcher      = USBPDSOPWatcher()
    let tbWatcher      = IOIOThunderboltSwitchWatcher()
    let usb3Watcher    = USB3TransportWatcher()
    let trmWatcher     = TRMTransportWatcher()
    let displayWatcher = DisplayPortTransportWatcher()

    private var isStarted = false
    private var pollTask: Task<Void, Never>?
    private var burstTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var isRefreshing = false

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true

        portWatcher.start()
        deviceWatcher.start()
        powerWatcher.start()
        pdWatcher.start()
        tbWatcher.start()
        usb3Watcher.start()
        trmWatcher.start()
        displayWatcher.start()

        startPoll()
        setupBurstTriggers()
    }

    func refreshAll() {
        isRefreshing = true
        defer { isRefreshing = false }
        portWatcher.refresh()
        powerWatcher.refresh()
        pdWatcher.refresh()
        tbWatcher.refresh()
        usb3Watcher.refresh()
        trmWatcher.refresh()
        displayWatcher.refresh()
    }

    private func startPoll() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.refreshAll()
            }
        }
    }

    private func setupBurstTriggers() {
        deviceWatcher.$devices
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, !self.isRefreshing else { return }
                self.scheduleBurst()
            }
            .store(in: &cancellables)

        powerWatcher.$sources
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, !self.isRefreshing else { return }
                self.scheduleBurst()
            }
            .store(in: &cancellables)

        pdWatcher.$identities
            .dropFirst()
            .sink { [weak self] _ in
                guard let self, !self.isRefreshing else { return }
                self.scheduleBurst()
            }
            .store(in: &cancellables)
    }

    private func scheduleBurst() {
        burstTask?.cancel()
        burstTask = Task { @MainActor [weak self] in
            for delay in [150, 500, 1500, 3000, 6000] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled, let self else { return }
                self.refreshAll()
            }
        }
    }
}
