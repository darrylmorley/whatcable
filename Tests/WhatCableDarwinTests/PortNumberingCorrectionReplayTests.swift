import Foundation
import Testing
@testable import WhatCableDarwinBackend
@testable import WhatCableCore

// Public issue #627, plan §4 T3: end-to-end replay of the two
// Mac17,14 format-1 runs through the production seams.
//
// - Ports: every IOPort-family entry through `AppleHPMInterfaceWatcher.portFrom`,
//   with `readAll` set to macOS's uncorrected dictionary, and again with
//   `readAll: nil` (the `readAllPorts` / `PowerService` path).
// - Transports: every `IOPortTransportStateUSB3` entry through
//   `USB3TransportWatcher.makeTransport`.
// - Devices: each USB device's ancestor chain is rebuilt from the IOService
//   links the way `USBWatcher.collectAncestors` gathers it, then classified
//   by `USBWatcher.classifyAncestry`.
// - Then the shared groupings (`matchingDevices`, `TunnelledDeviceGrouping`,
//   `BuiltInPortGrouping`) decide where each device renders.
//
// Run 397cf7be's owner confirmed the sockets by hand: the Sabrent SSD
// (10 Gb/s) is in the front USB-C next to the card reader, which macOS calls
// Port-USB-A@2; the WD My Book (5 Gb/s) is in the rear USB-A next to the
// power cable, which macOS calls Port-USB-C@6. Run 305e3a4f has the same map
// and nothing plugged into these two sockets.
//
// Skips when research-data is not linked (public and fresh clones), like
// every other corpus test. When it is linked, a missing run or a model other
// than Mac17,14 fails.

private let confirmedRun = "397cf7be-d888-4b06-b64d-d5adac29f7ba"
private let unconfirmedRun = "305e3a4f-8992-487e-8d8e-2124b87c2b89"

/// One run, replayed.
private struct Replay {
    let run: FormatOneRun
    let cards: [AppleHPMInterface]
    let cardsWithoutBulkFetch: [AppleHPMInterface]
    let transports: [USB3Transport]
    let devices: [USBDevice]

    init(_ run: FormatOneRun, model: String?) {
        self.run = run
        var cards: [AppleHPMInterface] = []
        var cardsWithoutBulkFetch: [AppleHPMInterface] = []
        for (id, entry) in run.entries.sorted(by: { $0.key < $1.key }) where run.conforms(id, to: "IOPort") {
            guard let name = run.serviceName(of: id), let cls = entry.className else { continue }
            let props = entry.properties
            if let card = AppleHPMInterfaceWatcher.portFrom(
                serviceName: name, className: cls, read: { props[$0] }, readAll: { props },
                entryID: id, busIndex: nil, hpmControllerUUID: nil, model: model
            ) { cards.append(card) }
            if let card = AppleHPMInterfaceWatcher.portFrom(
                serviceName: name, className: cls, read: { props[$0] }, readAll: nil,
                entryID: id, busIndex: nil, hpmControllerUUID: nil, model: model
            ) { cardsWithoutBulkFetch.append(card) }
        }
        self.cards = cards
        self.cardsWithoutBulkFetch = cardsWithoutBulkFetch

        transports = run.entries.values
            .filter { $0.className == "IOPortTransportStateUSB3" }
            .sorted { $0.id < $1.id }
            .compactMap { entry in
                let props = entry.properties
                return USB3TransportWatcher.makeTransport(
                    entryID: entry.id, read: { props[$0] }, hpmControllerUUID: nil, model: model
                )
            }

        devices = run.entries.keys.sorted()
            .filter { run.conforms($0, to: "IOUSBHostDevice") }
            .map { Self.device(run: run, id: $0, model: model) }
    }

    /// The ancestor chain `USBWatcher.collectAncestors` would gather: first
    /// IOService parent each hop, stopping at a terminating controller (or,
    /// past a tunnel controller, at the `apciecN` root).
    static func ancestors(run: FormatOneRun, of id: UInt64) -> [USBWatcher.USBAncestor] {
        var result: [USBWatcher.USBAncestor] = []
        var current = id
        var pastTunnelController = false
        for _ in 0..<40 {
            guard let parent = run.parent(of: current), let entry = run.entries[parent] else { break }
            current = parent
            let className = entry.className ?? ""
            let props = entry.properties
            let conforms = run.conforms(parent, to: "IOUSBHostDevice")
            let continues = USBWatcher.isWalkTerminator(className)
                && USBWatcher.walkContinuation(after: className) == .continueToPCIeRoot
            result.append(USBWatcher.USBAncestor(
                className: className,
                locationID: (props["locationID"] as? NSNumber)?.uint32Value,
                usbIOPortPath: props["UsbIOPort"].flatMap { USBWatcher.usbIOPortPath(from: $0) },
                usbPortType: conforms ? (props["USBPortType"] as? NSNumber)?.intValue : nil,
                conformsToUSBHostDevice: conforms,
                serviceName: run.plainName(of: parent),
                entryID: parent
            ))
            if continues { pastTunnelController = true; continue }
            if pastTunnelController {
                if let name = run.plainName(of: parent), RegistryRootNaming.isRootName(name, prefix: "apciec") { break }
                continue
            }
            if USBWatcher.isWalkTerminator(className) { break }
        }
        return result
    }

    static func classification(run: FormatOneRun, id: UInt64, model: String?) -> USBWatcher.AncestryClassification {
        let props = run.entries[id]?.properties ?? [:]
        return USBWatcher.classifyAncestry(
            ancestors(run: run, of: id),
            ownUSBPortType: (props["USBPortType"] as? NSNumber)?.intValue,
            deviceClass: (props["bDeviceClass"] as? NSNumber)?.uint8Value,
            model: model
        )
    }

    static func device(run: FormatOneRun, id: UInt64, model: String?) -> USBDevice {
        let props = run.entries[id]?.properties ?? [:]
        let c = classification(run: run, id: id, model: model)
        let locationID = (props["locationID"] as? NSNumber)?.uint32Value ?? 0
        return USBDevice(
            id: id,
            locationID: locationID,
            vendorID: (props["idVendor"] as? NSNumber)?.uint16Value ?? 0,
            productID: (props["idProduct"] as? NSNumber)?.uint16Value ?? 0,
            vendorName: props["USB Vendor Name"] as? String,
            productName: props["USB Product Name"] as? String,
            serialNumber: props["USB Serial Number"] as? String,
            usbVersion: nil,
            speedRaw: (props["Device Speed"] as? NSNumber)?.uint8Value,
            busPowerMA: nil,
            currentMA: nil,
            busIndex: c.busIndex ?? USBWatcher.busIndex(fromLocationID: locationID),
            controllerPortName: c.portName,
            isThunderboltTunnelled: c.tunnelled,
            isBehindInternalHub: c.behindInternalHub,
            deviceClass: (props["bDeviceClass"] as? NSNumber)?.uint8Value,
            ioClassName: run.entries[id]?.className,
            rawProperties: [:]
        )
    }
}

@Suite("Mac17,14 swapped sockets: end-to-end replay (issue #627)")
struct PortNumberingCorrectionReplayTests {

    /// Loads a run, or nil to skip when research-data is not linked. A
    /// missing run or the wrong model is a failure when it is linked.
    private static func load(_ runID: String) throws -> FormatOneRun? {
        guard FormatOneRun.corpusPresent else { return nil }
        let run = try FormatOneRun(runID: runID)
        try #require(run.model == "Mac17,14", "run \(runID) has model \(run.model ?? "nil")")
        return run
    }

    @Test("Both Mac17,14 runs: exactly one corrected Port-USB-C@6 card, raw data kept, keyed 2/6 on both read paths",
          arguments: [confirmedRun, unconfirmedRun])
    func correctedCard(runID: String) throws {
        guard let run = try Self.load(runID) else { return }
        let replay = Replay(run, model: run.model)

        for (label, cards) in [("readAll", replay.cards), ("readAll nil", replay.cardsWithoutBulkFetch)] {
            let c6 = cards.filter { $0.serviceName == "Port-USB-C@6" }
            try #require(c6.count == 1, "\(label): \(cards.map(\.serviceName))")
            let card = c6[0]
            #expect(card.className == "IOPort", "\(label)")
            #expect(card.registryPortName == "Port-USB-A@2", "\(label)")
            #expect(card.portDescription == "Port-USB-C@6", "\(label)")
            #expect(card.portTypeDescription == "USB-C", "\(label)")
            #expect(card.rawProperties["PortType"] == "3", "\(label)")
            #expect(card.rawProperties["PortDescription"] == "Port-USB-A@2", "\(label)")
            #expect(card.portKey == "2/6", "\(label)")
            // The physical USB-A (macOS's Port-USB-C@6) is not a card.
            #expect(!cards.contains { $0.serviceName == "Port-USB-A@2" || $0.registryPortName == "Port-USB-C@6" }, "\(label)")
            // Every other card is untouched.
            #expect(cards.filter { $0.registryPortName != nil }.count == 1, "\(label)")
        }
    }

    @Test("Before correcting, the walk reads macOS's names: Sabrent on Port-USB-A@2, WD on Port-USB-C@6")
    func uncorrectedWalk() throws {
        guard let run = try Self.load(confirmedRun) else { return }
        let sabrent = try #require(Self.deviceID(run, product: "Sabrent"))
        let wd = try #require(Self.deviceID(run, product: "My Book 25EE"))
        let s = Replay.classification(run: run, id: sabrent, model: nil)
        let w = Replay.classification(run: run, id: wd, model: nil)
        #expect(s.behindInternalHub && w.behindInternalHub)
        #expect(s.portName == "Port-USB-A@2")
        #expect(w.portName == "Port-USB-C@6")
    }

    @Test("Run 397cf7be: the Sabrent lands on the Port-USB-C@6 card at 10 Gb/s, the WD under Built-in USB-A port 2, nothing twice")
    func devicesLandOnTheirSockets() throws {
        guard let run = try Self.load(confirmedRun) else { return }
        let replay = Replay(run, model: run.model)
        let sabrent = try #require(Self.deviceID(run, product: "Sabrent"))
        let wd = try #require(Self.deviceID(run, product: "My Book 25EE"))

        let card = try #require(replay.cards.first { $0.serviceName == "Port-USB-C@6" })
        let onCard = card.matchingDevices(from: replay.devices)
        #expect(onCard.map(\.id).contains(sabrent), "\(onCard.map { $0.productName ?? "?" })")
        #expect(!onCard.map(\.id).contains(wd))

        // Its own USB3 transport (the child of macOS's Port-USB-A@2 node) is
        // the one selected, and the speed line comes from the Sabrent's
        // 10 Gb/s link.
        let ioPortA2 = try #require(run.entries.values.first {
            $0.className == "IOPort" && $0.properties["PortDescription"] as? String == "Port-USB-A@2"
        })
        let usb3Child = try #require(run.serviceLinks.first {
            $0.parent == ioPortA2.id && run.entries[$0.id]?.className == "IOPortTransportStateUSB3"
        })
        #expect(USB3SpeedCorroboration.selectedTransport(for: card, in: replay.transports)?.id == usb3Child.id)
        #expect(USB3SpeedCorroboration.hasLiveSuperSpeed(port: card, usb3Transports: replay.transports, devices: onCard))
        let speedDevice = try #require(USBDevice.portMatchedSuperSpeed(in: onCard))
        #expect(speedDevice.id == sabrent)
        #expect(speedDevice.speedRaw == 4) // SuperSpeedPlus, 10 Gb/s

        let grouping = TunnelledDeviceGrouping.group(
            devices: replay.devices, ports: replay.cards, thunderboltSwitches: [], isDesktopMac: true
        )
        let builtIn = grouping.internalHubDevices
        #expect(!builtIn.map(\.id).contains(sabrent))
        let groups = BuiltInPortGrouping.groups(from: builtIn)
        let a2 = try #require(groups.first { $0.portNodeName == "Port-USB-A@2" })
        #expect(a2.connector == "USB-A" && a2.portNumber == 2)
        #expect(a2.devices.map(\.id) == [wd])
        #expect(groups.filter { $0.devices.contains { $0.id == wd } }.count == 1)

        // Every device renders once: on one card or in the built-in list.
        var seen: [UInt64: Int] = [:]
        for port in replay.cards {
            for device in port.matchingDevices(from: replay.devices) { seen[device.id, default: 0] += 1 }
        }
        for device in builtIn { seen[device.id, default: 0] += 1 }
        let twice = seen.filter { $0.value > 1 }.keys.sorted()
        #expect(twice.isEmpty, "shown more than once: \(twice.map { String($0, radix: 16) })")
        #expect(seen[sabrent] == 1 && seen[wd] == 1)
    }

    private static func deviceID(_ run: FormatOneRun, product: String) -> UInt64? {
        let matches = run.entries.values.filter {
            run.conforms($0.id, to: "IOUSBHostDevice") && $0.properties["USB Product Name"] as? String == product
        }
        return matches.count == 1 ? matches[0].id : nil
    }
}
