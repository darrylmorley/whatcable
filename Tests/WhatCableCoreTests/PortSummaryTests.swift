import Testing
@testable import WhatCableCore

/// Pins the user-facing headline strings produced by PortSummary so refactors
/// of the state machine can't silently change what users see in the popover.
@Suite("Port Summary")
struct PortSummaryTests {

    // MARK: - Fixtures

    private func makePort(
        connected: Bool = true,
        active: [String] = [],
        supported: [String] = [],
        superSpeed: Bool? = nil,
        emarker: Bool? = nil
    ) -> USBCPort {
        USBCPort(
            id: 1,
            serviceName: "Port-USB-C@1",
            className: "AppleHPMInterfaceType10",
            portDescription: "Port-USB-C@1",
            portTypeDescription: "USB-C",
            portNumber: 1,
            connectionActive: connected,
            activeCable: emarker,
            opticalCable: nil,
            usbActive: nil,
            superSpeedActive: superSpeed,
            usbModeType: nil,
            usbConnectString: nil,
            transportsSupported: supported,
            transportsActive: active,
            transportsProvisioned: [],
            plugOrientation: nil,
            plugEventCount: nil,
            connectionCount: nil,
            overcurrentCount: nil,
            pinConfiguration: [:],
            powerCurrentLimits: [],
            firmwareVersion: nil,
            bootFlagsHex: nil,
            rawProperties: [:]
        )
    }

    private func usbPD(maxW: Int, winningW: Int) -> PowerSource {
        let winning = PowerOption(
            voltageMV: 20_000,
            maxCurrentMA: winningW * 50,
            maxPowerMW: winningW * 1000
        )
        let max = PowerOption(
            voltageMV: 20_000,
            maxCurrentMA: maxW * 50,
            maxPowerMW: maxW * 1000
        )
        return PowerSource(
            id: 1, name: "USB-PD", parentPortType: 2, parentPortNumber: 1,
            options: [max], winning: winning
        )
    }

    private func brickID(maxW: Int, winningW: Int) -> PowerSource {
        let winning = PowerOption(
            voltageMV: 20_000,
            maxCurrentMA: winningW * 50,
            maxPowerMW: winningW * 1000
        )
        let max = PowerOption(
            voltageMV: 20_000,
            maxCurrentMA: maxW * 50,
            maxPowerMW: maxW * 1000
        )
        return PowerSource(
            id: 2, name: "Brick ID", parentPortType: 0x11, parentPortNumber: 1,
            options: [max], winning: winning
        )
    }

    // MARK: - Disconnected

    @Test("Nothing connected headline")
    func nothingConnectedHeadline() {
        let summary = PortSummary(port: makePort(connected: false))
        #expect(summary.status == .empty)
        #expect(summary.headline == "Nothing connected")
        #expect(summary.bullets.isEmpty)
    }

    // MARK: - Charging

    @Test("Charging only without data has wattage suffix")
    func chargingOnlyWithoutDataHasWattageSuffix() {
        let port = makePort(connected: true, active: [], supported: ["USB2"])
        let summary = PortSummary(port: port, sources: [usbPD(maxW: 96, winningW: 60)])
        #expect(summary.status == .charging)
        #expect(summary.headline == "Charging · 96W charger")
    }

    @Test("Charging only without PDO options omits wattage")
    func chargingOnlyWithoutPDOOptionsOmitsWattage() {
        // No options means no wattage suffix; the headline just says "Charging only".
        let port = makePort(connected: true, active: [], supported: ["USB2"])
        let summary = PortSummary(port: port)
        #expect(summary.status == .charging)
        #expect(summary.headline == "Charging only")
    }

    @Test("MagSafe Brick ID source counts as charging power")
    func magSafeBrickIDSourceCountsAsChargingPower() {
        let port = makePort(connected: true, active: [], supported: [])
        let summary = PortSummary(port: port, sources: [brickID(maxW: 140, winningW: 140)])
        #expect(summary.status == .charging)
        #expect(summary.headline == "Charging · 140W charger")
    }

    // MARK: - Battery full (issue #154)

    @Test("Battery full overrides the charging headline")
    func batteryFullOverridesChargingHeadline() {
        let port = makePort(connected: true, active: [], supported: [])
        let summary = PortSummary(
            port: port,
            sources: [brickID(maxW: 140, winningW: 140)],
            batteryFullyCharged: true
        )
        #expect(summary.status == .batteryFull)
        #expect(summary.headline == "Plugged in · battery full")
        // Subtitle is now empty: the battery-full explanation lives in the
        // charging banner instead, so the two don't repeat each other.
        #expect(summary.subtitle.isEmpty)
    }

    @Test("Battery full overrides the 'Charging only' state")
    func batteryFullOverridesChargingOnly() {
        // No PD source, USB2 only: the "Charging only" branch.
        let port = makePort(connected: true, active: [], supported: ["USB2"])
        let summary = PortSummary(port: port, batteryFullyCharged: true)
        #expect(summary.status == .batteryFull)
        #expect(summary.headline == "Plugged in · battery full")
    }

    @Test("Battery not full still shows charging wattage")
    func batteryNotFullStillShowsCharging() {
        // Regression guard: false / nil must not trigger the battery-full path.
        let port = makePort(connected: true, active: [], supported: ["USB2"])
        let chargingFalse = PortSummary(
            port: port,
            sources: [usbPD(maxW: 96, winningW: 60)],
            batteryFullyCharged: false
        )
        #expect(chargingFalse.status == .charging)
        #expect(chargingFalse.headline == "Charging · 96W charger")

        let chargingNil = PortSummary(port: port, sources: [usbPD(maxW: 96, winningW: 60)])
        #expect(chargingNil.status == .charging)
        #expect(chargingNil.headline == "Charging · 96W charger")
    }

    @Test("Battery full does not relabel a data connection")
    func batteryFullDoesNotRelabelData() {
        // A USB3 data device with the battery full is still a data device;
        // the override only applies to the pure-power headlines.
        let port = makePort(active: ["USB3"], supported: ["USB2", "USB3"], superSpeed: true)
        let summary = PortSummary(port: port, batteryFullyCharged: true)
        #expect(summary.status == .dataDevice)
        #expect(summary.headline.hasPrefix("USB device"), "got: \(summary.headline)")
    }

    // MARK: - USB

    @Test("USB2 only is slow device")
    func usb2OnlyIsSlowDevice() {
        let port = makePort(active: ["USB2"], supported: ["USB2"])
        let summary = PortSummary(port: port)
        #expect(summary.status == .dataDevice)
        #expect(
            summary.headline.hasPrefix("Slow USB device or charge-only cable"),
            "got: \(summary.headline)"
        )
    }

    @Test("USB3 is USB device")
    func usb3IsUSBDevice() {
        let port = makePort(active: ["USB3"], supported: ["USB2", "USB3"], superSpeed: true)
        let summary = PortSummary(port: port)
        #expect(summary.status == .dataDevice)
        #expect(summary.headline.hasPrefix("USB device"), "got: \(summary.headline)")
    }

    // MARK: - Thunderbolt and Display

    @Test("Thunderbolt link")
    func thunderboltLink() {
        let port = makePort(active: ["CIO", "USB3"], supported: ["CIO", "USB3"])
        let summary = PortSummary(port: port, sources: [usbPD(maxW: 96, winningW: 60)])
        #expect(summary.status == .thunderboltCable)
        #expect(summary.headline == "Thunderbolt / USB4 · 96W charger")
    }

    @Test("USB-C with video")
    func usbCWithVideo() {
        let port = makePort(active: ["USB3", "DisplayPort"], superSpeed: true)
        let summary = PortSummary(port: port)
        #expect(summary.status == .displayCable)
        #expect(summary.headline == "USB-C with video")
    }

    @Test("Display only")
    func displayOnly() {
        let port = makePort(active: ["DisplayPort"])
        let summary = PortSummary(port: port)
        #expect(summary.status == .displayCable)
        #expect(summary.headline == "Display connected")
    }

    // MARK: - Bullets

    @Test("E-marker cable produces e-marker bullet")
    func emarkerCableProducesEmarkerBullet() {
        let port = makePort(active: ["USB3"], superSpeed: true)
        let cable = USBPDSOP(
            id: 99, endpoint: .sopPrime,
            parentPortType: 0, parentPortNumber: 0,
            vendorID: 0, productID: 0, bcdDevice: 0,
            vdos: [(3 << 27), 0, 0, (0b10 << 5) | 0b011 | (1 << 13)], specRevision: 0
        )
        let summary = PortSummary(port: port, identities: [cable])
        #expect(
            summary.bullets.contains(where: { $0.contains("e-marker") && $0.contains("advertises") }),
            "expected an e-marker bullet, got bullets: \(summary.bullets)"
        )
    }

    @Test("E-marker present but not read shows the not-read bullet, not advertises")
    func unreadEmarkerShowsNotReadBullet() {
        // Endpoint present but no identity VDOs: a connection at 3A or below,
        // no Thunderbolt, never wakes the e-marker. We should say "not read",
        // not claim the cable advertises capabilities it never sent.
        let port = makePort(active: ["USB2"], supported: ["CC", "USB2"])
        let cable = USBPDSOP(
            id: 99, endpoint: .sopPrime,
            parentPortType: 0, parentPortNumber: 0,
            vendorID: 0, productID: 0, bcdDevice: 0,
            vdos: [], specRevision: 0
        )
        let summary = PortSummary(port: port, identities: [cable])
        #expect(
            summary.bullets.contains(where: { $0.contains("e-marker") && $0.contains("not read") }),
            "expected a not-read e-marker bullet, got: \(summary.bullets)"
        )
        #expect(
            summary.bullets.contains(where: { $0.contains("advertises") }) == false,
            "should not claim the cable advertises capabilities when its e-marker was not read"
        )
    }

    @Test("Populated SOP'' wins over an empty SOP' (reads, not 'not read')")
    func populatedEndpointWinsOverEmptyOne() {
        // Both cable endpoints present: SOP' empty, SOP'' populated. We should
        // read the populated one and say "advertises", not "not read".
        let port = makePort(active: ["USB3"], supported: ["CC", "USB2", "USB3"], superSpeed: true)
        let emptySOP = USBPDSOP(
            id: 98, endpoint: .sopPrime,
            parentPortType: 0, parentPortNumber: 0,
            vendorID: 0, productID: 0, bcdDevice: 0,
            vdos: [], specRevision: 0
        )
        let populatedSOPp = USBPDSOP(
            id: 99, endpoint: .sopDoublePrime,
            parentPortType: 0, parentPortNumber: 0,
            vendorID: 0, productID: 0, bcdDevice: 0,
            vdos: [(3 << 27), 0, 0, (0b10 << 5) | 0b011 | (1 << 13)], specRevision: 0
        )
        let summary = PortSummary(port: port, identities: [emptySOP, populatedSOPp])
        #expect(
            summary.bullets.contains(where: { $0.contains("e-marker") && $0.contains("advertises") }),
            "expected the populated endpoint to win, got: \(summary.bullets)"
        )
        #expect(
            summary.bullets.contains(where: { $0.contains("not read") }) == false,
            "should not say 'not read' when one endpoint carries VDOs"
        )
    }

    @Test("No e-marker cable produces no e-marker bullet")
    func noEmarkerCableProducesNoEmarkerBullet() {
        // PD-capable port (CC present) with no SOP'/SOP'' identity. The
        // wording deliberately doesn't claim "basic cable" - macOS may
        // simply not have run Discover Identity SOP' yet (typically only
        // happens when the link needs to negotiate above 3A).
        let port = makePort(active: ["USB2"], supported: ["CC", "USB2"], emarker: false)
        let summary = PortSummary(port: port)
        #expect(
            summary.bullets.contains(where: { $0.contains("No e-marker detected") }),
            "expected a no-e-marker bullet, got: \(summary.bullets)"
        )
    }

    @Test("No PD port does not claim basic cable")
    func noPDPortDoesNotClaimBasicCable() {
        // USB-only port (no CC = no PD = no SOP' query possible). Don't blame
        // the cable for a missing e-marker the OS could never have read. This
        // is the M4 Mac Mini front-port case from issue #50.
        let port = makePort(active: ["USB3"], supported: ["USB2", "USB3"], superSpeed: true)
        let summary = PortSummary(port: port)
        #expect(
            summary.bullets.contains(where: { $0.contains("No e-marker detected") }) == false,
            "no-PD port should not claim a missing e-marker, got: \(summary.bullets)"
        )
        #expect(
            summary.bullets.contains(where: { $0.contains("can't read cable details") }),
            "expected the 'port can't read cable details' bullet, got: \(summary.bullets)"
        )
    }

    @Test("MagSafe port does not claim no power delivery")
    func magSafePortDoesNotClaimNoPowerDelivery() {
        // Regression: a charging MagSafe port reports an empty
        // TransportsSupported (MagSafe negotiates PD over its own pins,
        // not the CC line). The previous logic tripped the "no Power
        // Delivery" branch because `pdCapable` is gated on CC. MagSafe
        // ports must not get any "can't read cable details" bullet at
        // all, since the cable is built into the brick.
        let magSafePort = USBCPort(
            id: 1,
            serviceName: "Port-MagSafe 3@1",
            className: "AppleHPMInterfaceType11",
            portDescription: "Port-MagSafe 3@1",
            portTypeDescription: "MagSafe 3",
            portNumber: 1,
            connectionActive: true,
            activeCable: nil, opticalCable: nil, usbActive: nil, superSpeedActive: nil,
            usbModeType: nil, usbConnectString: nil,
            transportsSupported: [],
            transportsActive: ["CC"],
            transportsProvisioned: ["CC"],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:], powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil, rawProperties: [:]
        )
        let summary = PortSummary(
            port: magSafePort,
            sources: [usbPD(maxW: 100, winningW: 100)]
        )
        #expect(
            summary.bullets.contains(where: { $0.contains("no Power Delivery") }) == false,
            "MagSafe must not claim 'no Power Delivery', got: \(summary.bullets)"
        )
        #expect(
            summary.bullets.contains(where: { $0.contains("can't read cable details") }) == false,
            "MagSafe must not show the 'can't read cable details' bullet, got: \(summary.bullets)"
        )
        #expect(
            summary.bullets.contains(where: { $0.contains("No e-marker detected") }) == false,
            "MagSafe must not show the missing-e-marker bullet, got: \(summary.bullets)"
        )
    }

    @Test("PD port with e-marker still shows e-marker")
    func pdPortWithEmarkerStillShowsEmarker() {
        // Sanity: presence of an e-marker means PD must have fired, regardless
        // of whether the test fixture happens to set CC explicitly. We don't
        // want the new gate to suppress legitimate e-marker bullets.
        let port = makePort(
            active: ["USB3"],
            supported: ["CC", "USB2", "USB3"],
            superSpeed: true
        )
        let cable = USBPDSOP(
            id: 99, endpoint: .sopPrime,
            parentPortType: 0, parentPortNumber: 0,
            vendorID: 0, productID: 0, bcdDevice: 0,
            vdos: [(3 << 27), 0, 0, (0b10 << 5) | 0b011 | (1 << 13)], specRevision: 0
        )
        let summary = PortSummary(port: port, identities: [cable])
        #expect(
            summary.bullets.contains(where: { $0.contains("e-marker") && $0.contains("advertises") }),
            "expected e-marker bullet on PD-capable port, got: \(summary.bullets)"
        )
    }

    @Test("Negotiated PDO appears in bullets")
    func negotiatedPDOAppearsInBullets() {
        let port = makePort(active: ["USB3"], superSpeed: true)
        let summary = PortSummary(port: port, sources: [usbPD(maxW: 96, winningW: 60)])
        #expect(
            summary.bullets.contains(where: { $0.contains("Currently negotiated") }),
            "expected a negotiated PDO bullet, got: \(summary.bullets)"
        )
    }

    // MARK: - Cable wattage limit suffix

    /// Helper: build an SOP' cable identity with the given current bits.
    /// Uses USB4 Gen 3 (3) as the speed baseline and a valid latency.
    /// `currentBits = 1` => 3A (60W); `currentBits = 2` => 5A (100W).
    private func cableIdentity(currentBits: Int) -> USBPDSOP {
        let vdo: UInt32 = UInt32(0b011) | UInt32(currentBits << 5) | UInt32(1 << 13)
        return USBPDSOP(
            id: 99, endpoint: .sopPrime,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0x05AC, productID: 0, bcdDevice: 0,
            vdos: [(3 << 27) | UInt32(0x05AC), 0, 0, vdo],
            specRevision: 3
        )
    }

    @Test("Cable limit suffix appears when cable under-advertised")
    func cableLimitSuffixAppearsWhenCableUnderAdvertised() {
        // Charger says 96W; cable rated 60W (3A * 20V).
        let port = makePort(active: ["USB3"], superSpeed: true)
        let summary = PortSummary(
            port: port,
            sources: [usbPD(maxW: 96, winningW: 60)],
            identities: [cableIdentity(currentBits: 1)]
        )
        #expect(summary.headline == "USB device · 96W charger · 60W cable")
    }

    @Test("Cable limit suffix absent when cable matches charger")
    func cableLimitSuffixAbsentWhenCableMatchesCharger() {
        // Charger 96W, cable 100W (5A * 20V): cable can carry full power.
        let port = makePort(active: ["CIO"], superSpeed: true)
        let summary = PortSummary(
            port: port,
            sources: [usbPD(maxW: 96, winningW: 60)],
            identities: [cableIdentity(currentBits: 2)]
        )
        #expect(summary.headline == "Thunderbolt / USB4 · 96W charger")
    }

    @Test("Cable limit suffix absent when no charger")
    func cableLimitSuffixAbsentWhenNoCharger() {
        // No charger: nothing to compare against, so no cable suffix.
        let port = makePort(active: ["USB3"], superSpeed: true)
        let summary = PortSummary(port: port, identities: [cableIdentity(currentBits: 1)])
        #expect(summary.headline == "USB device")
    }

    @Test("Cable limit suffix absent when no cable")
    func cableLimitSuffixAbsentWhenNoCable() {
        // No e-marker: no cable wattage to surface.
        let port = makePort(active: ["USB3"], superSpeed: true)
        let summary = PortSummary(port: port, sources: [usbPD(maxW: 96, winningW: 60)])
        #expect(summary.headline == "USB device · 96W charger")
    }

    @Test("Cable limit suffix on charging only headline")
    func cableLimitSuffixOnChargingOnlyHeadline() {
        // The charging-only state path also gets the suffix when relevant.
        let port = makePort(connected: true, active: [], supported: ["USB2"])
        let summary = PortSummary(
            port: port,
            sources: [usbPD(maxW: 96, winningW: 60)],
            identities: [cableIdentity(currentBits: 1)]
        )
        #expect(summary.headline == "Charging · 96W charger · 60W cable")
    }

    // MARK: - Bullet ordering / grouping

    /// Pins the three-block grouping in the bullet list. Concrete
    /// expectation: link state and connected device come before any
    /// cable-specific lines, and cable-specific lines come before the
    /// charger-power numbers. Refactors that move bullets between these
    /// blocks should fail this test.
    @Test("Bullets are grouped link then cable then power")
    func bulletsAreGroupedLinkThenCableThenPower() {
        let port = makePort(active: ["USB3"], superSpeed: true)
        let cable = USBPDSOP(
            id: 99, endpoint: .sopPrime,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0x05AC, productID: 0, bcdDevice: 0,
            vdos: [
                (3 << 27) | UInt32(0x05AC),
                0,
                0,
                UInt32(0b011) | UInt32(2 << 5) | UInt32(1 << 13) // USB4 Gen3, 5A, ~1m
            ],
            specRevision: 3
        )
        let partner = USBPDSOP(
            id: 100, endpoint: .sop,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0x05AC, productID: 0, bcdDevice: 0,
            vdos: [(2 << 27) | UInt32(0x05AC)], // USB Peripheral
            specRevision: 3
        )
        let summary = PortSummary(
            port: port,
            sources: [usbPD(maxW: 96, winningW: 60)],
            identities: [cable, partner]
        )

        func index(_ predicate: (String) -> Bool) -> Int? {
            summary.bullets.firstIndex(where: predicate)
        }

        let speedIdx = index { $0.contains("SuperSpeed USB") }
        let deviceIdx = index { $0.contains("Connected device") }
        let cableSpeedIdx = index { $0.contains("Cable speed") }
        let cableMakerIdx = index { $0.contains("Cable made by") }
        let chargerIdx = index { $0.contains("Charger advertises") }
        let negotiatedIdx = index { $0.contains("Currently negotiated") }

        #expect(speedIdx != nil)
        #expect(deviceIdx != nil)
        #expect(cableSpeedIdx != nil)
        #expect(cableMakerIdx != nil)
        #expect(chargerIdx != nil)
        #expect(negotiatedIdx != nil)

        // A: link + connected device come first
        #expect(speedIdx! < deviceIdx!, "Speed should come before connected device")
        #expect(deviceIdx! < cableSpeedIdx!, "Connected device should come before cable details")

        // B: cable details (speed -> maker) come before power numbers
        #expect(cableSpeedIdx! < cableMakerIdx!, "Cable speed should come before cable maker")
        #expect(cableMakerIdx! < chargerIdx!, "Cable maker should come before charger numbers")

        // C: power negotiation tail
        #expect(chargerIdx! < negotiatedIdx!, "Charger max should come before currently negotiated")
    }

    // MARK: - DisplayPort lane config

    @Test("DP bullet shows 4 lanes when USB3 is not active alongside")
    func dpBulletShowsFourLaneWhenNoUSB3() {
        // DisplayPort active, no USB3 on the link: all four lanes carry DP.
        let port = USBCPort(
            id: 1, serviceName: "Port-USB-C@1", className: "AppleHPMInterfaceType10",
            portDescription: "Port-USB-C@1", portTypeDescription: "USB-C",
            portNumber: 1, connectionActive: true, activeCable: nil, opticalCable: nil,
            usbActive: nil, superSpeedActive: nil, usbModeType: nil, usbConnectString: nil,
            transportsSupported: ["CC", "USB2", "DisplayPort"],
            transportsActive: ["DisplayPort"],
            transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:],
            displayPortPinAssignment: 1,
            powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil, rawProperties: [:]
        )
        let summary = PortSummary(port: port)
        let dpBullet = summary.bullets.first { $0.contains("DisplayPort") }
        #expect(dpBullet != nil)
        #expect(dpBullet!.contains("4 DP lanes"), "Expected 4-lane info, got: \(dpBullet!)")
    }

    // Regression for issue #228 (UGreen Revodok): the same
    // DisplayPortPinAssignment value (1) appears for both a 4-lane link (no
    // USB3) and a 2-lane link (USB3 active). Lane count must come from whether
    // USB3 is active, not from the pin assignment integer. This port uses
    // pin assignment 1 *and* has USB3 active, so it must read as 2 lanes.
    @Test("DP bullet shows 2 lanes when USB3 is active alongside (ignores pin assignment)")
    func dpBulletShowsTwoLaneWhenUSB3Active() {
        let port = USBCPort(
            id: 1, serviceName: "Port-USB-C@1", className: "AppleHPMInterfaceType10",
            portDescription: "Port-USB-C@1", portTypeDescription: "USB-C",
            portNumber: 1, connectionActive: true, activeCable: nil, opticalCable: nil,
            usbActive: nil, superSpeedActive: true, usbModeType: nil, usbConnectString: nil,
            transportsSupported: ["CC", "USB2", "USB3", "DisplayPort"],
            transportsActive: ["CC", "USB3", "USB2", "DisplayPort"],
            transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:],
            displayPortPinAssignment: 1,
            powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil, rawProperties: [:]
        )
        let summary = PortSummary(port: port)
        let dpBullet = summary.bullets.first { $0.contains("DisplayPort") }
        #expect(dpBullet != nil)
        #expect(dpBullet!.contains("2 DP lanes"), "Expected 2-lane info, got: \(dpBullet!)")
        #expect(!dpBullet!.contains("no USB3"), "2-lane link must not claim 'no USB3': \(dpBullet!)")
    }

    @Test("DP lane count is determined without relying on a pin assignment")
    func dpBulletClassifiesWithoutPinAssignment() {
        // DisplayPort active, no USB3, no pin assignment reported: still
        // classifiable as 4-lane from the absence of USB3.
        let port = makePort(active: ["DisplayPort"])
        let summary = PortSummary(port: port)
        let dpBullet = summary.bullets.first { $0.contains("DisplayPort") }
        #expect(dpBullet != nil)
        #expect(dpBullet!.contains("4 DP lanes"), "Expected 4-lane info, got: \(dpBullet!)")
    }

    // MARK: - Partner PD revision

    @Test("Partner bullet includes PD revision")
    func partnerBulletIncludesPDRevision() {
        let port = makePort(active: ["USB3"], supported: ["CC"], superSpeed: true)
        let partner = USBPDSOP(
            id: 50, endpoint: .sop,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0x05AC, productID: 0x1234, bcdDevice: 0,
            vdos: [0x6C00_05AC], specRevision: 3
        )
        let summary = PortSummary(port: port, identities: [partner])
        let deviceBullet = summary.bullets.first { $0.contains("Connected device") }
        #expect(deviceBullet != nil)
        #expect(deviceBullet!.contains("PD 3.0"), "Expected PD revision, got: \(deviceBullet!)")
    }

    @Test("Partner bullet omits PD revision when zero")
    func partnerBulletOmitsPDRevisionWhenZero() {
        let port = makePort(active: ["USB3"], supported: ["CC"], superSpeed: true)
        let partner = USBPDSOP(
            id: 50, endpoint: .sop,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0x05AC, productID: 0x1234, bcdDevice: 0,
            vdos: [0x6C00_05AC], specRevision: 0
        )
        let summary = PortSummary(port: port, identities: [partner])
        let deviceBullet = summary.bullets.first { $0.contains("Connected device") }
        #expect(deviceBullet != nil)
        #expect(deviceBullet!.contains("PD") == false, "Should not show PD revision when unknown")
    }

    // MARK: - Charger answering Discover Identity as a cable (issue #268)

    /// A charging SOP partner that declares a cable product type must be shown
    /// as the charger, never echoed back as a passive cable / connected device,
    /// with its PD revision preserved.
    @Test("SOP partner claiming to be a cable while charging is shown as the charger")
    func sopCablePartnerWhileChargingIsRelabelledAsCharger() {
        // Issue #268: an Anker Prime 165W charger answered Discover Identity at
        // SOP with product-type 3 (passive cable). On a charger-only port the
        // card showed "Connected device: Passive cable, Anker ..." under the
        // "Cable details" heading, which read as if the cable were an Anker
        // passive cable. A device sourcing power can't be a passive cable, so
        // we relabel it as the charger. No adapter manufacturer here, so the
        // relabel path (not the suppress path) fires.
        let port = makePort(connected: true, active: [], supported: ["CC"])
        let partner = USBPDSOP(
            id: 50, endpoint: .sop,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0x291A, productID: 0, bcdDevice: 0,
            vdos: [(3 << 27) | UInt32(0x291A)],  // product type 3 = passive cable
            specRevision: 3
        )
        let summary = PortSummary(
            port: port,
            sources: [usbPD(maxW: 100, winningW: 100)],
            identities: [partner]
        )
        let chargerLine = summary.bullets.first { $0.contains("Charger identified as") }
        #expect(chargerLine != nil, "Expected a 'Charger identified as' line, got: \(summary.bullets)")
        #expect(chargerLine!.contains("0x291A"), "Expected the partner VID, got: \(chargerLine!)")
        #expect(chargerLine!.contains("PD 3.0"), "PD revision should be preserved, got: \(chargerLine!)")
        #expect(
            !summary.bullets.contains(where: { $0.contains("Passive cable") }),
            "A charger must not be labelled a passive cable, got: \(summary.bullets)"
        )
        #expect(
            !summary.bullets.contains(where: { $0.contains("Connected device") }),
            "The charger must not appear as a connected device, got: \(summary.bullets)"
        )
    }

    /// When AdapterDetails already gives a richer "Charger: <mfr> <name>" line,
    /// the relabelled cable-partner line is suppressed so only one charger line
    /// appears.
    @Test("SOP cable-partner while charging is suppressed when a richer Charger line fires")
    func sopCablePartnerSuppressedWhenAdapterPresent() {
        // Same self-contradicting partner, but AdapterDetails gives a richer
        // "Charger: <mfr> <name>" line. The partner line must be suppressed so
        // we don't print two charger lines (mirrors the federated branch).
        let port = makePort(connected: true, active: [], supported: ["CC"])
        let partner = USBPDSOP(
            id: 50, endpoint: .sop,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0x05AC, productID: 0, bcdDevice: 0,
            vdos: [(3 << 27) | UInt32(0x05AC)],  // product type 3 = passive cable
            specRevision: 3
        )
        let summary = PortSummary(
            port: port,
            sources: [usbPD(maxW: 140, winningW: 140)],
            identities: [partner],
            adapter: adapter(manufacturer: "Apple Inc.", name: "140W USB-C Power Adapter")
        )
        let chargerLines = summary.bullets.filter {
            $0.starts(with: "Charger:") || $0.contains("Charger identified as")
        }
        #expect(chargerLines.count == 1,
            "Expected exactly one charger line (the richer one), got: \(chargerLines)")
        #expect(chargerLines.first == "Charger: Apple Inc. 140W USB-C Power Adapter")
        #expect(
            !summary.bullets.contains(where: { $0.contains("Passive cable") || $0.contains("Connected device") }),
            "No passive-cable / connected-device line expected, got: \(summary.bullets)"
        )
    }

    // MARK: - Unknown state enrichment

    @Test("Unknown with SOP partner shows e-marker bullet")
    func unknownWithSOPPartnerShowsEmarkerBullet() {
        // Connected, PD-capable, no transports active, no charger,
        // but a partner SOP identity exists. The e-marker explanation
        // bullet should appear because we know something is on the
        // other end.
        let port = makePort(connected: true, active: [], supported: ["CC"])
        let partner = USBPDSOP(
            id: 50, endpoint: .sop,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0x05AC, productID: 0x1234, bcdDevice: 0,
            vdos: [0x6C00_05AC], specRevision: 3
        )
        let summary = PortSummary(port: port, identities: [partner])
        #expect(summary.status == .unknown)
        #expect(
            summary.bullets.contains(where: { $0.contains("No e-marker detected") }),
            "Expected e-marker explanation bullet in .unknown with SOP partner, got: \(summary.bullets)"
        )
    }

    @Test("Unknown with charger hits charging not unknown")
    func unknownWithChargerHitsChargingNotUnknown() {
        // A charger on the port should hit .charging, not .unknown,
        // even when no transports are active. Pin this so a future
        // refactor doesn't accidentally drop charger-only connections
        // into .unknown.
        let port = makePort(connected: true, active: [], supported: ["CC"])
        let source = usbPD(maxW: 20, winningW: 20)
        let summary = PortSummary(port: port, sources: [source])
        #expect(summary.status == .charging,
            "Charger present with no active transports should be .charging, not .unknown")
    }

    @Test("Battery full with adapter wattage but no live contract (issue #278)")
    func batteryFullAdapterWattageNoContract() {
        // Reporter's case: charger plugged in, battery full so macOS tore the
        // PD contract down (no PowerSource), but the CC comms line is still
        // active. The system adapter resolves to 100W. Must surface that as
        // "battery full", not the misleading "try a higher-wattage charger".
        let port = makePort(
            connected: true,
            active: ["CC"],
            supported: ["CC", "USB2", "USB3", "CIO", "DisplayPort"]
        )
        let summary = PortSummary(
            port: port,
            chargerWattageSource: .systemAdapterFallback(watts: 100),
            batteryFullyCharged: true
        )
        #expect(summary.status == .batteryFull)
        #expect(summary.headline == "Plugged in · battery full")
        #expect(
            !summary.subtitle.contains("higher-wattage"),
            "Should not nag for a higher-wattage charger when one is known, got: \(summary.subtitle)"
        )
        // The reporter's actual complaint: show the wattage. The battery-full
        // headline carries no number, so it must surface as a bullet even with
        // no live PD contract.
        #expect(
            summary.bullets.contains("System reports charger at 100W"),
            "Battery-full charger wattage should appear as a bullet, got: \(summary.bullets)"
        )
    }

    @Test("Adapter wattage, no live contract, battery charging (issue #278)")
    func adapterWattageNoContractWhileCharging() {
        // Same shape but the battery is not full: show the resolved wattage
        // as an active charge rather than dropping into .unknown.
        let port = makePort(
            connected: true,
            active: ["CC"],
            supported: ["CC", "USB2", "USB3", "CIO", "DisplayPort"]
        )
        let summary = PortSummary(
            port: port,
            chargerWattageSource: .systemAdapterFallback(watts: 100),
            batteryFullyCharged: false
        )
        #expect(summary.status == .charging)
        #expect(summary.headline == "Charging · 100W charger")
    }

    @Test("Empty active + USB2 + resolved wattage shows charger, not 'Charging only' (issue #278)")
    func emptyActiveResolvedWattageBeatsChargingOnly() {
        // Branch-ordering guard (CodeRabbit): a charge-only cable with no
        // active transports but a resolved fallback wattage must surface the
        // charger, not the generic "Charging only" that sits in the same
        // active.isEmpty + USB2 region.
        let port = makePort(connected: true, active: [], supported: ["USB2"])
        let charging = PortSummary(
            port: port,
            chargerWattageSource: .systemAdapterFallback(watts: 60),
            batteryFullyCharged: false
        )
        #expect(charging.status == .charging)
        #expect(charging.headline == "Charging · 60W charger")
        #expect(charging.bullets.contains("System reports charger at 60W"))

        let full = PortSummary(
            port: port,
            chargerWattageSource: .systemAdapterFallback(watts: 60),
            batteryFullyCharged: true
        )
        #expect(full.status == .batteryFull)
        #expect(full.headline == "Plugged in · battery full")
        #expect(full.bullets.contains("System reports charger at 60W"))
    }

    @Test("Empty active + USB2 + no wattage still shows 'Charging only' (issue #278 guard)")
    func emptyActiveNoWattageStillChargingOnly() {
        // The reorder must not steal the genuine no-charger case: with no
        // resolved wattage, the generic "Charging only" branch still owns it.
        let port = makePort(connected: true, active: [], supported: ["USB2"])
        let summary = PortSummary(port: port)
        #expect(summary.status == .charging)
        #expect(summary.headline == "Charging only")
    }

    @Test("CC active with no resolved wattage stays unknown (issue #278 guard)")
    func ccActiveNoWattageStaysUnknown() {
        // Regression guard: the new branch must only fire when a wattage is
        // actually resolved. With no charger reading, a bare CC-active port
        // is genuinely unknown and should still nudge for a better charger.
        let port = makePort(connected: true, active: ["CC"], supported: ["CC"])
        let summary = PortSummary(port: port)
        #expect(summary.status == .unknown)
        #expect(summary.headline == "Connected")
    }

    @Test("Pure unknown has no bullets")
    func pureUnknownHasNoBullets() {
        // Connected but truly zero data: no transports, no charger,
        // no identities, no USB2 in supported. Should be .unknown
        // with empty bullets (no false "basic cable" claim).
        let port = makePort(connected: true, active: [], supported: [])
        let summary = PortSummary(port: port)
        #expect(summary.status == .unknown)
        #expect(summary.bullets.isEmpty,
            "Pure .unknown with no data should have empty bullets, got: \(summary.bullets)")
    }

    // MARK: - USB3 Transport integration

    @Test("USB3 Gen 1 shows precise speed")
    func usb3Gen1ShowsPreciseSpeed() {
        let port = makePort(connected: true, active: ["USB3"], supported: ["CC", "USB3"])
        let transport = USB3Transport(
            id: 100, portKey: "2/1", signaling: 1,
            signalingDescription: "Gen 1", dataRole: "host"
        )
        let summary = PortSummary(port: port, usb3Transports: [transport])
        #expect(
            summary.bullets.contains(where: { $0.contains("USB 3.2 Gen 1 (5 Gbps)") }),
            "Gen 1 transport should produce precise label, got: \(summary.bullets)"
        )
        #expect(
            summary.bullets.contains(where: { $0.contains("SuperSpeed USB") }) == false,
            "Generic SuperSpeed label should not appear when precise data is available"
        )
    }

    @Test("USB3 Gen 2 shows precise speed")
    func usb3Gen2ShowsPreciseSpeed() {
        let port = makePort(connected: true, active: ["USB3"], supported: ["CC", "USB3"])
        let transport = USB3Transport(
            id: 101, portKey: "2/1", signaling: 2,
            signalingDescription: "Gen 2", dataRole: "host"
        )
        let summary = PortSummary(port: port, usb3Transports: [transport])
        #expect(
            summary.bullets.contains(where: { $0.contains("USB 3.2 Gen 2 (10 Gbps)") }),
            "Gen 2 transport should produce precise label, got: \(summary.bullets)"
        )
    }

    @Test("USB3 fallback when no transport data")
    func usb3FallbackWhenNoTransportData() {
        // When the USB3 transport service hasn't appeared yet (no device
        // connected or watcher hasn't caught up), fall back to the
        // generic "SuperSpeed USB" label.
        let port = makePort(connected: true, active: ["USB3"], supported: ["CC", "USB3"])
        let summary = PortSummary(port: port, usb3Transports: [])
        #expect(
            summary.bullets.contains(where: { $0.contains("SuperSpeed USB") }),
            "Should fall back to generic label without transport data, got: \(summary.bullets)"
        )
    }

    @Test("USB3 fallback when signaling nil")
    func usb3FallbackWhenSignalingNil() {
        // Transport exists but signaling field is nil (IOKit property absent).
        let port = makePort(connected: true, active: ["USB3"], supported: ["CC", "USB3"])
        let transport = USB3Transport(
            id: 102, portKey: "2/1", signaling: nil,
            signalingDescription: nil, dataRole: nil
        )
        let summary = PortSummary(port: port, usb3Transports: [transport])
        #expect(
            summary.bullets.contains(where: { $0.contains("SuperSpeed USB") }),
            "Should fall back to generic label when signaling is nil, got: \(summary.bullets)"
        )
    }

    // MARK: - Structured link-speed badge

    @Test("Link badge: USB 2.0 reads 480M")
    func linkBadgeUSB2() {
        let port = makePort(connected: true, active: ["USB2"], supported: ["CC", "USB2"])
        let summary = PortSummary(port: port)
        #expect(summary.linkSpeed?.tier == .usb2)
        #expect(summary.linkSpeed?.badge == "480M")
    }

    @Test("Link badge: USB3 with no precise data floors at 5G")
    func linkBadgeUSB3Floor() {
        let port = makePort(connected: true, active: ["USB3"], supported: ["CC", "USB3"])
        let summary = PortSummary(port: port, usb3Transports: [])
        #expect(summary.linkSpeed?.tier == .usb5g)
        #expect(summary.linkSpeed?.badge == "5G")
    }

    @Test("Link badge: USB3 Gen 2 transport reads 10G")
    func linkBadgeUSB3Gen2() {
        let port = makePort(connected: true, active: ["USB3"], supported: ["CC", "USB3"])
        let transport = USB3Transport(
            id: 1, portKey: "2/1", signaling: 2,
            signalingDescription: "Gen 2", dataRole: "host"
        )
        let summary = PortSummary(port: port, usb3Transports: [transport])
        #expect(summary.linkSpeed?.tier == .usb10g)
        #expect(summary.linkSpeed?.badge == "10G")
    }

    @Test("Link badge: absent when nothing connected")
    func linkBadgeNoneWhenEmpty() {
        let summary = PortSummary(port: makePort(connected: false))
        #expect(summary.linkSpeed == nil)
    }

    @Test("Link badge: absent on charge-only (no active data link)")
    func linkBadgeNoneOnChargeOnly() {
        let port = makePort(connected: true, active: [], supported: ["CC", "USB2"])
        let summary = PortSummary(port: port, sources: [usbPD(maxW: 60, winningW: 60)])
        #expect(summary.linkSpeed == nil)
    }

    @Test("Link badge: signaling 0 falls through to port-matched device, not 5G")
    func linkBadgeSignalingZeroUsesPortMatchedDevice() {
        // `signaling == 0` is IOKit's "no info" sentinel (common on Apple
        // Silicon front ports). The bullet skips the transport and uses the
        // port-matched device's speed; the badge must agree, not floor at 5G.
        let port = makePort(connected: true, active: ["USB3"], supported: ["CC", "USB3"])
        let transport = USB3Transport(
            id: 1, portKey: "2/1", signaling: 0,
            signalingDescription: nil, dataRole: "host"
        )
        // Non-root (two non-zero locationID nibbles) so rootSuperSpeed is nil
        // and the port-matched path is what resolves the speed.
        let device = USBDevice(
            id: 2, locationID: 0x0121_0000,
            vendorID: 0x04E8, productID: 0x4001,
            vendorName: "Samsung", productName: "PSSD T7",
            serialNumber: nil, usbVersion: "3.2",
            speedRaw: 4, busPowerMA: 900, currentMA: 896,
            controllerPortName: "Port-USB-C@1",
            rawProperties: [:]
        )
        let summary = PortSummary(port: port, devices: [device], usb3Transports: [transport])
        #expect(summary.linkSpeed?.tier == .usb10g)
        #expect(summary.linkSpeed?.badge == "10G")
        // And the badge agrees with the prose bullet.
        #expect(summary.bullets.contains { $0.contains("10 Gbps") })
    }

    @Test("USB3 unknown signaling shows generic gen")
    func usb3UnknownSignalingShowsGenericGen() {
        // A signaling value we haven't seen before should still produce
        // a reasonable label rather than crashing or falling back to
        // the generic "SuperSpeed USB" text.
        let port = makePort(connected: true, active: ["USB3"], supported: ["CC", "USB3"])
        let transport = USB3Transport(
            id: 104, portKey: "2/1", signaling: 3,
            signalingDescription: "Gen 3", dataRole: "host"
        )
        let summary = PortSummary(port: port, usb3Transports: [transport])
        #expect(
            summary.bullets.contains(where: { $0.contains("USB 3.2 Gen 3") }),
            "Unknown gen should still produce a label, got: \(summary.bullets)"
        )
    }

    @Test("Thunderbolt active ignores USB3 transport data")
    func thunderboltActiveIgnoresUSB3TransportData() {
        // When Thunderbolt (CIO) is active, the USB3 bullet should not
        // appear at all. The TB label takes priority. USB3 transport
        // data should have no effect.
        let port = makePort(connected: true, active: ["CIO", "USB3"], supported: ["CIO", "USB3"])
        let transport = USB3Transport(
            id: 105, portKey: "2/1", signaling: 2,
            signalingDescription: "Gen 2", dataRole: "host"
        )
        let summary = PortSummary(
            port: port,
            sources: [usbPD(maxW: 96, winningW: 60)],
            usb3Transports: [transport]
        )
        #expect(summary.status == .thunderboltCable)
        #expect(
            summary.bullets.contains(where: { $0.contains("USB 3.2") }) == false,
            "USB3 transport label should not appear when Thunderbolt is active, got: \(summary.bullets)"
        )
        #expect(
            summary.bullets.contains(where: { $0.contains("Thunderbolt") || $0.contains("USB4") }),
            "Thunderbolt bullet should be present, got: \(summary.bullets)"
        )
    }

    @Test("USB3 transport alone does not activate USB3 bullet")
    func usb3TransportAloneDoesNotActivateUSB3Bullet() {
        // The port controller's transportsActive is the authority for
        // whether USB3 is active. Transport watcher data is supplementary
        // (refines the speed label). If transportsActive doesn't include
        // "USB3", the transport data should not cause a USB3 bullet to
        // appear. This prevents a split-brain state where the speed
        // bullet says "USB 3.2 Gen 2" but the headline says "Nothing
        // connected."
        let port = makePort(connected: true, active: [], supported: ["CC", "USB3"])
        let transport = USB3Transport(
            id: 106, portKey: "2/1", signaling: 2,
            signalingDescription: "Gen 2", dataRole: "host"
        )
        let summary = PortSummary(port: port, usb3Transports: [transport])
        #expect(
            summary.bullets.contains(where: { $0.contains("USB 3.2") || $0.contains("SuperSpeed") }) == false,
            "USB3 bullet should not appear when transportsActive has no USB3, got: \(summary.bullets)"
        )
    }

    @Test("USB2-only link ignores superSpeedActive and lingering USB3 transport")
    func usb2OnlyLinkIgnoresSuperSpeedFlagAndLingeringTransport() {
        // Issue #187: a USB-C to Micro-USB cable (physically USB 2.0 only)
        // is reported as USB 3.2 Gen 2 (10 Gbps). The HPM port controller
        // can leave IOAccessoryUSBSuperSpeedActive=1 set and keep a
        // lingering IOPortTransportStateUSB3 service registered even when
        // TransportsActive carries only USB2. The transport label must
        // never override the authoritative TransportsActive list.
        let port = makePort(
            connected: true,
            active: ["CC", "USB2"],
            supported: ["CC", "USB2", "USB3", "CIO", "DisplayPort"],
            superSpeed: true
        )
        let transport = USB3Transport(
            id: 187, portKey: "2/1", signaling: 2,
            signalingDescription: "Gen 2", dataRole: "host"
        )
        let summary = PortSummary(port: port, usb3Transports: [transport])
        #expect(
            summary.bullets.contains(where: { $0.contains("USB 3.2") || $0.contains("SuperSpeed") }) == false,
            "USB3 bullet must not appear for a USB2-only link, got: \(summary.bullets)"
        )
        #expect(
            summary.bullets.contains(where: { $0.contains("USB 2.0") }),
            "USB 2.0 bullet should appear, got: \(summary.bullets)"
        )
    }

    @Test("USB3 transport wrong port key ignored")
    func usb3TransportWrongPortKeyIgnored() {
        // Transport data for a different port should not affect this port.
        let port = makePort(connected: true, active: ["USB3"], supported: ["CC", "USB3"])
        let transport = USB3Transport(
            id: 103, portKey: "2/99", signaling: 2,
            signalingDescription: "Gen 2", dataRole: "host"
        )
        let summary = PortSummary(port: port, usb3Transports: [transport])
        #expect(
            summary.bullets.contains(where: { $0.contains("SuperSpeed USB") }),
            "Transport for wrong port should be ignored, got: \(summary.bullets)"
        )
    }

    // MARK: - USB device speed preferred over HPM transport

    @Test("USB3 device speed preferred over transport")
    func usb3DeviceSpeedPreferredOverTransport() {
        // Issue #140: IOUSBHostDevice reports Gen 2 (10 Gbps) but HPM
        // SuperSpeedSignaling reports Gen 1 (5 Gbps). The device speed
        // should win because it comes from the host controller negotiation.
        let port = makePort(connected: true, active: ["USB3"], supported: ["CC", "USB3"])
        let transport = USB3Transport(
            id: 200, portKey: "2/1", signaling: 1,
            signalingDescription: "Gen 1", dataRole: "host"
        )
        let device = USBDevice(
            id: 300, locationID: 0x0120_0000,
            vendorID: 0x04E8, productID: 0x4001,
            vendorName: "Samsung", productName: "PSSD T7",
            serialNumber: nil, usbVersion: "3.2",
            speedRaw: 4, busPowerMA: 900, currentMA: 896,
            controllerPortName: "Port-USB-C@1",
            rawProperties: [:]
        )
        let summary = PortSummary(
            port: port, devices: [device], usb3Transports: [transport]
        )
        #expect(
            summary.bullets.contains(where: { $0.contains("USB 3.2 Gen 2 (10 Gbps)") }),
            "Device speed (Gen 2) should win over HPM transport (Gen 1), got: \(summary.bullets)"
        )
        #expect(
            summary.bullets.contains(where: { $0.contains("5 Gbps") }) == false,
            "Gen 1 label should not appear when device reports Gen 2, got: \(summary.bullets)"
        )
    }

    @Test("USB3 falls back to transport when no device")
    func usb3FallsBackToTransportWhenNoDevice() {
        // When no USB device is matched, the transport label should
        // still be used (existing behaviour).
        let port = makePort(connected: true, active: ["USB3"], supported: ["CC", "USB3"])
        let transport = USB3Transport(
            id: 201, portKey: "2/1", signaling: 2,
            signalingDescription: "Gen 2", dataRole: "host"
        )
        let summary = PortSummary(port: port, usb3Transports: [transport])
        #expect(
            summary.bullets.contains(where: { $0.contains("USB 3.2 Gen 2 (10 Gbps)") }),
            "Should fall back to transport label when no device matched, got: \(summary.bullets)"
        )
    }

    @Test("USB3 device speed ignores USB2 devices")
    func usb3DeviceSpeedIgnoresUSB2Devices() {
        // A USB 2.0 device (speedRaw=2) behind a hub should not produce
        // a USB3 speed label. Only SuperSpeed and above count.
        let port = makePort(connected: true, active: ["USB3"], supported: ["CC", "USB3"])
        let transport = USB3Transport(
            id: 202, portKey: "2/1", signaling: 1,
            signalingDescription: "Gen 1", dataRole: "host"
        )
        let usb2Device = USBDevice(
            id: 301, locationID: 0x0120_0000,
            vendorID: 0x1234, productID: 0x0001,
            vendorName: "Test", productName: "USB2 Device",
            serialNumber: nil, usbVersion: "2.0",
            speedRaw: 2, busPowerMA: 500, currentMA: 100,
            controllerPortName: "Port-USB-C@1",
            rawProperties: [:]
        )
        let summary = PortSummary(
            port: port, devices: [usb2Device], usb3Transports: [transport]
        )
        #expect(
            summary.bullets.contains(where: { $0.contains("USB 3.2 Gen 1 (5 Gbps)") }),
            "USB 2.0 device speed should be ignored, transport label should win, got: \(summary.bullets)"
        )
    }

    @Test("USB3 hub with faster downstream device")
    func usb3HubWithFasterDownstreamDevice() {
        // A Gen 1 hub (5 Gbps upstream) with a Gen 2 device (10 Gbps)
        // behind it. The bullet should reflect the upstream link (Gen 1),
        // not the downstream device's faster negotiation with the hub.
        let port = makePort(connected: true, active: ["USB3"], supported: ["CC", "USB3"])
        let transport = USB3Transport(
            id: 203, portKey: "2/1", signaling: 1,
            signalingDescription: "Gen 1", dataRole: "host"
        )
        // Hub is root device: locationID 0x0120_0000 (one path nibble)
        let hub = USBDevice(
            id: 400, locationID: 0x0120_0000,
            vendorID: 0x2109, productID: 0x2822,
            vendorName: "VIA Labs", productName: "USB3.0 Hub",
            serialNumber: nil, usbVersion: "3.2",
            speedRaw: 3, busPowerMA: 900, currentMA: 0,
            controllerPortName: "Port-USB-C@1",
            rawProperties: [:]
        )
        // Downstream device: locationID 0x0121_0000 (two path nibbles)
        let downstream = USBDevice(
            id: 401, locationID: 0x0121_0000,
            vendorID: 0x04E8, productID: 0x4001,
            vendorName: "Samsung", productName: "PSSD T7",
            serialNumber: nil, usbVersion: "3.2",
            speedRaw: 4, busPowerMA: 900, currentMA: 896,
            controllerPortName: "Port-USB-C@1",
            rawProperties: [:]
        )
        let summary = PortSummary(
            port: port, devices: [hub, downstream], usb3Transports: [transport]
        )
        #expect(
            summary.bullets.contains(where: { $0.contains("USB 3.2 Gen 1 (5 Gbps)") }),
            "Hub upstream speed (Gen 1) should be used, not downstream device (Gen 2), got: \(summary.bullets)"
        )
        #expect(
            summary.bullets.contains(where: { $0.contains("10 Gbps") }) == false,
            "Downstream Gen 2 speed should not appear, got: \(summary.bullets)"
        )
    }

    @Test("USB3 falls back to transport when no root device")
    func usb3FallsBackToTransportWhenNoRootDevice() {
        // If only downstream (non-root) devices are matched and none are
        // root devices, fall back to the HPM transport label.
        let port = makePort(connected: true, active: ["USB3"], supported: ["CC", "USB3"])
        let transport = USB3Transport(
            id: 204, portKey: "2/1", signaling: 1,
            signalingDescription: "Gen 1", dataRole: "host"
        )
        // Only a downstream device (two path nibbles), no root
        let downstream = USBDevice(
            id: 402, locationID: 0x0121_0000,
            vendorID: 0x04E8, productID: 0x4001,
            vendorName: "Samsung", productName: "PSSD T7",
            serialNumber: nil, usbVersion: "3.2",
            speedRaw: 4, busPowerMA: 900, currentMA: 896,
            controllerPortName: "Port-USB-C@1",
            rawProperties: [:]
        )
        let summary = PortSummary(
            port: port, devices: [downstream], usb3Transports: [transport]
        )
        #expect(
            summary.bullets.contains(where: { $0.contains("USB 3.2 Gen 1 (5 Gbps)") }),
            "Should fall back to HPM transport when no root device, got: \(summary.bullets)"
        )
    }

    /// Issue #190 follow-up: iPhone 17 Pro on a Mac Studio front USB-C port
    /// shows "5 Gbps or faster" instead of "USB 3.2 Gen 2 (10 Gbps)" even
    /// though the device section correctly reports 10 Gbps. Apple Silicon
    /// front USB-C ports route through an internal virtual root that
    /// inflates the locationID by an extra nibble, so directly-attached
    /// devices fail `isRootDevice`. With no HPM transport reading
    /// (SuperSpeedSignaling==0 on these ports) the bullet falls through to
    /// the generic "SuperSpeed USB" string. The port-matched fallback,
    /// driven by `controllerPortName`, recovers the real speed.
    @Test("Issue #190: virtual-root port reports device speed via controllerPortName")
    func issue190VirtualRootPortReportsViaControllerPortName() {
        let port = makePort(connected: true, active: ["USB3"], supported: ["CC", "USB3"])
        // Transport service exists but signaling is 0 (USB3Transport.speedLabel
        // returns nil for this case after commit 90fce0b).
        let transport = USB3Transport(
            id: 210, portKey: "2/1", signaling: 0,
            signalingDescription: "None", dataRole: "host"
        )
        // Directly-attached device, but locationID has two non-zero nibbles
        // because of Apple's internal virtual root in front of the port.
        let device = USBDevice(
            id: 410, locationID: 0x0021_0000,
            vendorID: 0x05AC, productID: 0x12A8,
            vendorName: "Apple", productName: "iPhone",
            serialNumber: nil, usbVersion: "3.2",
            speedRaw: 4, busPowerMA: 500, currentMA: 500,
            controllerPortName: "Port-USB-C@1",
            rawProperties: [:]
        )
        let summary = PortSummary(
            port: port, devices: [device], usb3Transports: [transport]
        )
        #expect(
            summary.bullets.contains(where: { $0.contains("USB 3.2 Gen 2 (10 Gbps)") }),
            "Should report device speed via controllerPortName fallback, got: \(summary.bullets)"
        )
        #expect(
            summary.bullets.contains(where: { $0.contains("5 Gbps or faster") }) == false,
            "Generic fallback should not fire when device speed is available, got: \(summary.bullets)"
        )
    }

    // MARK: - Real cable reproductions (from issue reports)

    /// Issue #131: Apple Thunderbolt 5 data cable (A3189) on M4 MBA.
    /// Reporter expected "Thunderbolt 5" label but saw "Thunderbolt / USB4".
    /// Pins the exact output so we can verify any future labelling changes.
    @Test("Issue #131: Apple TB5 cable on CIO port")
    func issue131AppleTB5CableOnCIOPort() {
        let vdos: [UInt32] = [0x1C60_05AC, 0x0000_0000, 0x720A_0100, 0x110A_2644]
        let cable = USBPDSOP(
            id: 99, endpoint: .sopPrime,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0x05AC, productID: 0x720A, bcdDevice: 0x0100,
            vdos: vdos, specRevision: 0
        )

        // Verify the cable VDO decodes to Gen 4 / 80 Gbps / 50V-rated passive.
        let cv = cable.cableVDO!
        #expect(cv.speed == .usb4Gen4)
        #expect(cv.current == .fiveAmp)
        #expect(cv.maxVolts == 50)
        // Deliverable power is clamped to USB-PD's 48V ceiling: 48 * 5 = 240W,
        // not the 50 * 5 = 250W the raw rating field would imply.
        #expect(cv.maxWatts == 240)
        #expect(cv.cableType == .passive)
        #expect(cv.decodeWarnings.isEmpty)

        // CIO active (Thunderbolt link up on the port).
        let port = makePort(
            connected: true,
            active: ["CIO", "USB3"],
            supported: ["CC", "USB2", "USB3", "CIO"]
        )
        let summary = PortSummary(port: port, identities: [cable])

        #expect(summary.status == .thunderboltCable)
        #expect(summary.headline == "Thunderbolt / USB4")
        #expect(
            summary.bullets.contains(where: { $0.contains("USB4 Gen 4 (80 Gbps, Thunderbolt 5 class)") }),
            "Cable speed bullet should show Gen 4, got: \(summary.bullets)"
        )
        #expect(
            summary.bullets.contains(where: { $0.contains("Apple") }),
            "Cable maker bullet should show Apple, got: \(summary.bullets)"
        )
        #expect(
            summary.bullets.contains(where: { $0.contains("240W") && $0.contains("USB-PD caps at 48V") }),
            "Cable power bullet should show the 240W deliverable with the 48V cap note, got: \(summary.bullets)"
        )
    }

    // MARK: - Charger identification (AdapterDetails + FedDetails fallback)

    private func adapter(
        manufacturer: String? = nil,
        name: String? = nil,
        model: String? = nil,
        watts: Int? = 100
    ) -> AdapterInfo {
        AdapterInfo(
            watts: watts,
            isCharging: nil,
            source: "AC",
            manufacturer: manufacturer,
            name: name,
            model: model
        )
    }

    private func fed(portIndex: Int = 1, vid: Int) -> FederatedIdentity {
        FederatedIdentity(
            portIndex: portIndex,
            vendorID: vid,
            productID: 0,
            pdSpecRevision: 0,
            powerRole: 0,
            dualRolePower: false,
            externalConnected: true
        )
    }

    @Test("Charger bullet shows manufacturer and name when AdapterDetails populated")
    func chargerBulletShowsManufacturerAndName() {
        // Apple 140W brick: AdapterDetails has both fields. Expect the
        // richer "Charger: Apple Inc. 140W USB-C Power Adapter" line.
        let port = makePort(connected: true, active: [], supported: ["CC"])
        let summary = PortSummary(
            port: port,
            sources: [usbPD(maxW: 140, winningW: 140)],
            adapter: adapter(manufacturer: "Apple Inc.", name: "140W USB-C Power Adapter")
        )
        let bullet = summary.bullets.first { $0.starts(with: "Charger:") }
        #expect(bullet == "Charger: Apple Inc. 140W USB-C Power Adapter")
    }

    @Test("Charger bullet shows manufacturer only when Name is missing")
    func chargerBulletShowsManufacturerOnly() {
        let port = makePort(connected: true, active: [], supported: ["CC"])
        let summary = PortSummary(
            port: port,
            sources: [usbPD(maxW: 60, winningW: 60)],
            adapter: adapter(manufacturer: "Apple Inc.", name: nil)
        )
        let bullet = summary.bullets.first { $0.starts(with: "Charger:") }
        #expect(bullet == "Charger: Apple Inc.")
    }

    @Test("FedDetails fallback emits Charger identified line when no AdapterDetails")
    func fedDetailsFallbackEmitsCharger() {
        // CUKTECH-style case: AdapterDetails is empty / not present, but
        // FedDetails gives us the VID (11009 = Zimi). Expect the hedged
        // "Charger identified as Zimi Corporation (0x2B01)" line.
        let port = makePort(connected: true, active: [], supported: ["CC"])
        let summary = PortSummary(
            port: port,
            sources: [usbPD(maxW: 45, winningW: 45)],
            federatedIdentities: [fed(portIndex: 1, vid: 11009)]
        )
        let bullet = summary.bullets.first { $0.contains("Charger identified as") }
        #expect(bullet != nil, "Expected hedged 'Charger identified as' bullet, got: \(summary.bullets)")
        #expect(bullet!.contains("Zimi") && bullet!.contains("0x2B01"),
            "Expected Zimi Corporation (0x2B01), got: \(bullet ?? "<nil>")")
    }

    @Test("FedDetails fallback suppressed when AdapterDetails has richer identity")
    func fedDetailsSuppressedWhenAdapterPresent() {
        // Hypothetical: both AdapterDetails and FedDetails populated.
        // The richer "Charger: <Manufacturer> <Name>" line should fire;
        // the FedDetails-derived "Charger identified as" line should NOT
        // also fire (avoids double-prefix repetition on the same line).
        let port = makePort(connected: true, active: [], supported: ["CC"])
        let summary = PortSummary(
            port: port,
            sources: [usbPD(maxW: 140, winningW: 140)],
            federatedIdentities: [fed(portIndex: 1, vid: 0x05AC)],
            adapter: adapter(manufacturer: "Apple Inc.", name: "140W USB-C Power Adapter")
        )
        let chargerLines = summary.bullets.filter { $0.starts(with: "Charger:") || $0.contains("Charger identified as") }
        #expect(chargerLines.count == 1,
            "Expected exactly one charger-identity line, got: \(chargerLines)")
        #expect(chargerLines.first == "Charger: Apple Inc. 140W USB-C Power Adapter")
    }

    @Test("Apple brick on MagSafe: AdapterDetails catches the silent FedDetails failure")
    func appleBrickOnMagSafeUsesAdapterDetails() {
        // The Apple-brick-on-MagSafe silent-failure case: FedDetails
        // returns FedVendorID = 0, but AdapterDetails has the rich
        // identity. The primary path should catch it.
        let port = makePort(connected: true, active: [], supported: ["CC"])
        let summary = PortSummary(
            port: port,
            sources: [usbPD(maxW: 96, winningW: 96)],
            federatedIdentities: [fed(portIndex: 1, vid: 0)],  // silent failure
            adapter: adapter(manufacturer: "Apple Inc.", name: "96W USB-C Power Adapter")
        )
        let bullet = summary.bullets.first { $0.starts(with: "Charger:") }
        #expect(bullet == "Charger: Apple Inc. 96W USB-C Power Adapter")
        #expect(
            !summary.bullets.contains(where: { $0.contains("identified as") }),
            "No 'identified as' bullet expected when FedVendorID is 0"
        )
    }

    @Test("Unknown VendorDB lookup does not emit anything for FedDetails")
    func unknownVendorIDNoBullet() {
        // FedVendorID is non-zero but neither USB-IF nor the community
        // usb.ids list knows it. The old code would emit "Connected
        // device: 0xCAFE" (just the hex); the safe fallback drops the
        // bullet rather than mislead. 0xCAFE is verified not in
        // whatcable.db at the time of writing; if a real vendor takes
        // it later, swap to another truly-unknown VID.
        let port = makePort(connected: true, active: [], supported: ["CC"])
        let summary = PortSummary(
            port: port,
            sources: [usbPD(maxW: 65, winningW: 65)],
            federatedIdentities: [fed(portIndex: 1, vid: 0xCAFE)]  // not in either DB
        )
        #expect(
            !summary.bullets.contains(where: { $0.contains("Charger identified as") || $0.contains("Connected device") }),
            "No identity bullet expected for unknown VID, got: \(summary.bullets)"
        )
    }

    @Test("FedDetails wording is 'Connected device' when no charging source on port")
    func fedDetailsConnectedDeviceWhenNotCharging() {
        // A port with a known FedDetails VID but NO charging source on
        // the port (it's a peripheral, dock, drive). Keep the generic
        // "Connected device" wording rather than relabel as Charger.
        let port = makePort(connected: true, active: ["USB3"], supported: ["CC"], superSpeed: true)
        let summary = PortSummary(
            port: port,
            sources: [],  // no charging source
            federatedIdentities: [fed(portIndex: 1, vid: 11009)]
        )
        let bullet = summary.bullets.first { $0.contains("Connected device") }
        #expect(bullet != nil, "Expected 'Connected device' line for peripheral, got: \(summary.bullets)")
    }

    @Test("Adapter with nil manufacturer does not emit Charger bullet")
    func adapterWithNilManufacturerNoBullet() {
        // Adapter present but no identity fields (e.g. Mac Studio idle,
        // where AdapterDetails is {"FamilyCode"=0}). No bullet.
        let port = makePort(connected: true, active: [], supported: ["CC"])
        let summary = PortSummary(
            port: port,
            sources: [usbPD(maxW: 60, winningW: 60)],
            adapter: adapter(manufacturer: nil, name: nil)
        )
        #expect(
            !summary.bullets.contains(where: { $0.starts(with: "Charger:") }),
            "No Charger: bullet expected for empty AdapterDetails, got: \(summary.bullets)"
        )
    }

    @Test("Adapter with empty-string manufacturer does not emit Charger bullet")
    func adapterWithEmptyStringManufacturerNoBullet() {
        // Defensive case: the trim helper in the reader should already
        // map empty to nil, but if a caller hands us an empty string
        // directly we still want to suppress the bullet rather than
        // emit a trailing-whitespace "Charger: " line.
        let port = makePort(connected: true, active: [], supported: ["CC"])
        let summary = PortSummary(
            port: port,
            sources: [usbPD(maxW: 60, winningW: 60)],
            adapter: adapter(manufacturer: "", name: "Some Adapter")
        )
        #expect(
            !summary.bullets.contains(where: { $0.starts(with: "Charger:") }),
            "Empty manufacturer should suppress the Charger bullet, got: \(summary.bullets)"
        )
    }

    @Test("Charger bullet does not fire when no charging source on port")
    func chargerBulletRequiresChargingSourceOnPort() {
        // AdapterInfo is system-wide; it describes the brick that's
        // sourcing power somewhere on the system. The "Charger:" bullet
        // should only appear on the port that's actively charging, not
        // on every port the user has connected.
        let port = makePort(connected: true, active: ["USB3"], supported: ["CC"], superSpeed: true)
        let summary = PortSummary(
            port: port,
            sources: [],  // no charging source on THIS port
            adapter: adapter(manufacturer: "Apple Inc.", name: "140W USB-C Power Adapter")
        )
        #expect(
            !summary.bullets.contains(where: { $0.starts(with: "Charger:") }),
            "Charger: bullet should not appear on a non-charging port even when AdapterDetails is populated, got: \(summary.bullets)"
        )
    }

    // MARK: - Active-layout contradiction (DAR-30)

    /// Builds the CalDigit-style fixture: passive ID Header (Product Type 3)
    /// but VDO[3] has bit 3 set (SOP'' Controller Present, active-cable layout).
    /// VDO[4] encodes an optical re-timer so activeCableVDO2 can decode.
    private func contradictionCable() -> USBPDSOP {
        // VDO[3]: CalDigit 2M TB4 cable from issue #111.
        let caldigitVDO3: UInt32 = 0x3208485A
        // VDO[4]: optical (bit 10) + re-timer (bit 9).
        let vdo4: UInt32 = (1 << 10) | (1 << 9)
        return USBPDSOP(
            id: 99, endpoint: .sopPrime,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0x2B1D, productID: 0x1901, bcdDevice: 0x97,
            vdos: [
                (3 << 27) | UInt32(0x2B1D), // passive ID Header, VID Lintes
                0,
                0x19010097,
                caldigitVDO3,
                vdo4
            ],
            specRevision: 3
        )
    }

    @Test("Contradiction cable: surfaces the hedged note in bullets")
    func contradictionCableSurfacesNote() {
        // The CalDigit 2M TB4 cable reports passive in its ID Header but has
        // the SOP'' Controller Present bit set in VDO[3]. PortSummary should
        // emit a hedged bullet describing the structural contradiction.
        let port = makePort(active: ["CIO", "USB3"], supported: ["CC", "CIO", "USB3"])
        let summary = PortSummary(port: port, identities: [contradictionCable()])
        #expect(
            summary.bullets.contains(where: {
                $0.contains("passive") && $0.contains("active-cable structure")
            }),
            "expected a contradiction bullet, got: \(summary.bullets)"
        )
    }

    @Test("Contradiction cable: does not surface note for normal passive (regression guard)")
    func normalPassiveCableDoesNotSurfaceContradictionNote() {
        // 154 out of 157 passive cables in the corpus have bit 3 clear.
        // This guard ensures we don't flag them.
        let port = makePort(active: ["USB3"], superSpeed: true)
        let cable = USBPDSOP(
            id: 99, endpoint: .sopPrime,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0x05AC, productID: 0, bcdDevice: 0,
            vdos: [
                (3 << 27) | UInt32(0x05AC),
                0,
                0,
                UInt32(0b011) | UInt32(2 << 5) | UInt32(1 << 13) // bit 3 clear
            ],
            specRevision: 3
        )
        let summary = PortSummary(port: port, identities: [cable])
        #expect(
            summary.bullets.contains(where: {
                $0.contains("passive") && $0.contains("active-cable structure")
            }) == false,
            "normal passive cable must not trigger contradiction note, got: \(summary.bullets)"
        )
    }

    // MARK: - Charge hold (issue #319)

    @Test("Charge hold: headline shows 'Plugged in' with wattage, status is .charging")
    func chargeHoldHeadlineWithWattage() {
        // With a live USB-PD contract but batteryIsCharging=false, the port is
        // still drawing power (the Mac runs from the charger), so status stays
        // .charging. Headline changes from "Charging" to "Plugged in" to be
        // accurate: the battery itself is not gaining charge.
        let port = makePort(connected: true, active: [], supported: ["USB2"])
        let summary = PortSummary(
            port: port,
            sources: [usbPD(maxW: 96, winningW: 96)],
            batteryIsCharging: false,
            adapter: adapter()
        )
        #expect(summary.status == .charging)
        #expect(summary.headline.hasPrefix("Plugged in"))
        #expect(summary.headline.contains("96W"))
    }

    @Test("Stale PDO: no charging claim when the system has no adapter")
    func stalePDOWithNoSystemAdapterIsConnected() {
        let port = makePort(connected: true, active: [], supported: ["USB2"])
        let summary = PortSummary(
            port: port,
            sources: [usbPD(maxW: 96, winningW: 96)],
            batteryFullyCharged: false,
            batteryIsCharging: false,
            adapter: nil
        )
        #expect(summary.status == .unknown)
        #expect(summary.headline == "Connected")
        #expect(summary.subtitle.contains("Power is flowing") == false)
        #expect(summary.bullets.contains { $0.contains("Currently negotiated") } == false)
    }

    @Test("Charge hold: headline shows 'Plugged in' without wattage when no chargerW")
    func chargeHoldHeadlineWithoutWattage() {
        let port = makePort(connected: true, active: [], supported: ["USB2"])
        let summary = PortSummary(port: port, sources: [], batteryIsCharging: false)
        // No power source, so no headline override from charge-hold path.
        // The port just shows as empty/connected without a charger.
        #expect(summary.headline != "Charging")
    }

    @Test("Charger identity bullet appears before the wattage advertisement")
    func chargerIdentityBulletOrdering() {
        // Bullet ordering: "Charger: Apple Inc. 140W USB-C Power Adapter"
        // should appear immediately before "Charger advertises up to NW"
        // so the identity reads as the headline of the charger block.
        let port = makePort(connected: true, active: [], supported: ["CC"])
        let summary = PortSummary(
            port: port,
            sources: [usbPD(maxW: 140, winningW: 140)],
            adapter: adapter(manufacturer: "Apple Inc.", name: "140W USB-C Power Adapter")
        )
        let identityIdx = summary.bullets.firstIndex { $0.starts(with: "Charger:") }
        let wattageIdx = summary.bullets.firstIndex { $0.contains("advertises up to") }
        #expect(identityIdx != nil, "Identity bullet should appear")
        #expect(wattageIdx != nil, "Wattage bullet should appear")
        if let i = identityIdx, let w = wattageIdx {
            #expect(i < w, "Identity (\(i)) should come before wattage (\(w)) in bullets: \(summary.bullets)")
        }
    }
}
