import Foundation
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

    /// issue #181: a USB3 transport that corroborates on its own,
    /// via TRM restriction, independent of any enumerated device. Used by
    /// tests that assert USB3-derived headline/status/badge behaviour but
    /// don't otherwise care about corroboration (that is covered by the
    /// dedicated issue #181 tests). Matches `makePort()`'s fixed
    /// "Port-USB-C@1" / portNumber 1 port via portKey "2/1".
    private func corroboratingUSB3Transport(signaling: Int = 1) -> USB3Transport {
        USB3Transport(
            id: 9000, portKey: "2/1", signaling: signaling,
            signalingDescription: nil, dataRole: "host",
            transportRestricted: true
        )
    }

    /// issue #181: a root SuperSpeed device that corroborates without also
    /// setting the TRM-restricted ("data blocked") wording, unlike
    /// `corroboratingUSB3Transport()`. Used by tests that need a genuinely
    /// UNBLOCKED "USB device" headline.
    private func corroboratingDevice() -> USBDevice {
        USBDevice(
            id: 9002, locationID: 0x0020_0000,
            vendorID: 0x1234, productID: 0x5678,
            vendorName: nil, productName: "Test SSD", serialNumber: nil,
            usbVersion: nil, speedRaw: 3,
            busPowerMA: nil, currentMA: nil,
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
        // issue #181: corroborate with a TRM-restricted transport so the
        // headline reaches the "USB device" branch this test pins.
        let port = makePort(active: ["USB3"], supported: ["USB2", "USB3"], superSpeed: true)
        let summary = PortSummary(port: port, usb3Transports: [corroboratingUSB3Transport()], batteryFullyCharged: true)
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
        // issue #181: corroborate with a TRM-restricted transport so the
        // headline reaches the "USB device" branch this test pins.
        let port = makePort(active: ["USB3"], supported: ["USB2", "USB3"], superSpeed: true)
        let summary = PortSummary(port: port, usb3Transports: [corroboratingUSB3Transport()])
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
        // issue #181: corroborate with a TRM-restricted transport so the
        // headline reaches the "with video" branch this test pins.
        let port = makePort(active: ["USB3", "DisplayPort"], superSpeed: true)
        let summary = PortSummary(port: port, usb3Transports: [corroboratingUSB3Transport()])
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

    @Test("E-marker cable produces a read e-marker group")
    func emarkerCableProducesEmarkerBullet() {
        let port = makePort(active: ["USB3"], superSpeed: true)
        let cable = USBPDSOP(
            id: 99, endpoint: .sopPrime,
            parentPortType: 0, parentPortNumber: 0,
            vendorID: 0, productID: 0, bcdDevice: 0,
            vdos: [(3 << 27), 0, 0, (0b10 << 5) | 0b011 | (1 << 13)], specRevision: 0
        )
        let summary = PortSummary(port: port, identities: [cable])
        // A read e-marker is a group with the cable's own claims in it and no
        // "we couldn't read it" subtitle.
        let group = summary.group(.emarker)
        #expect(group != nil, "expected an e-marker group, got: \(summary.groups)")
        #expect(group?.subtitle == nil, "a read e-marker must carry no not-read subtitle")
        #expect(group?.lines.contains { $0.contains("Cable speed") } == true)
    }

    @Test("E-marker present but not read shows the not-read subtitle, not claims")
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
        let group = summary.group(.emarker)
        #expect(
            group?.subtitle?.contains("not read on this connection") == true,
            "expected a not-read subtitle, got: \(String(describing: group))"
        )
        #expect(group?.lines.isEmpty == true, "an unread e-marker has nothing to list")
        // Bug A: the advice must not contradict the port it is printed on.
        // This port negotiates nothing above 3 A and has no Thunderbolt, so
        // naming those conditions is correct here.
        #expect(group?.subtitle?.contains("above 3A or over Thunderbolt") == true)
    }

    /// Issue #573 part 2 (Codex design review, "the visible-delta
    /// recommendation currently produces misleading UI"): once
    /// `USBPDSOPWatcher` starts producing a MagSafe cable identity (real
    /// VID/PID, always empty `vdos`, since MagSafe never has a VDO array to
    /// answer with), the plain `hasEmarker && !emarkerRead` rule above would
    /// show "Present, but not read on this connection" -- exactly the wrong
    /// message: the IDs WERE read, there was simply never anything else to
    /// read. This is what `!isMagSafe` in that condition exists to suppress.
    @Test("MagSafe cable identity never shows the unread-e-marker subtitle")
    func magSafeCableIdentityNeverShowsUnreadSubtitle() {
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
        let magSafeCable = USBPDSOP(
            id: 99, endpoint: .sopPrime,
            parentPortType: 17, parentPortNumber: 1,
            vendorID: 0x05AC, productID: 0x7800, bcdDevice: 0,
            vdos: [], specRevision: 0
        )
        let summary = PortSummary(
            port: magSafePort,
            sources: [usbPD(maxW: 100, winningW: 100)],
            identities: [magSafeCable]
        )
        // hasEmarker is true (the endpoint responded), but no group carries
        // the "not read" subtitle: no new UI, no new string, just silence
        // where a USB-C port would have shown the wrong claim.
        let group = summary.group(.emarker)
        #expect(
            group?.subtitle?.contains("not read on this connection") != true,
            "MagSafe must never show the unread-e-marker subtitle, got: \(String(describing: group))"
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
        let group = summary.group(.emarker)
        #expect(
            group?.lines.contains { $0.contains("Cable speed") } == true,
            "expected the populated endpoint to win, got: \(String(describing: group))"
        )
        #expect(
            group?.subtitle == nil,
            "should not say 'not read' when one endpoint carries VDOs"
        )
    }

    @Test("No e-marker cable produces a no-e-marker subtitle")
    func noEmarkerCableProducesNoEmarkerBullet() {
        // PD-capable port (CC present) with no SOP'/SOP'' identity. The
        // wording deliberately doesn't claim "basic cable" - macOS may
        // simply not have run Discover Identity SOP' yet (typically only
        // happens when the link needs to negotiate above 3A).
        let port = makePort(active: ["USB2"], supported: ["CC", "USB2"], emarker: false)
        let summary = PortSummary(port: port)
        #expect(
            summary.group(.emarker)?.subtitle?.contains("No e-marker") == true,
            "expected a no-e-marker subtitle, got: \(summary.groups)"
        )
    }

    @Test("No PD port does not claim basic cable")
    func noPDPortDoesNotClaimBasicCable() {
        // USB-only port (no CC = no PD = no SOP' query possible). Don't blame
        // the cable for a missing e-marker the OS could never have read. This
        // is the M4 Mac Mini front-port case from issue #50.
        let port = makePort(active: ["USB3"], supported: ["USB2", "USB3"], superSpeed: true)
        let summary = PortSummary(port: port)
        let subtitle = summary.group(.emarker)?.subtitle
        #expect(
            subtitle?.contains("No e-marker") != true,
            "no-PD port should not claim a missing e-marker, got: \(String(describing: subtitle))"
        )
        #expect(
            subtitle?.contains("can't read cable details") == true,
            "expected the 'port can't read cable details' subtitle, got: \(summary.groups)"
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
            summary.group(.emarker)?.lines.contains { $0.contains("Cable speed") } == true,
            "expected e-marker claims on a PD-capable port, got: \(summary.groups)"
        )
    }

    // MARK: - E-marker read window (age-gated wording)
    //
    // macOS reads the cable e-marker 5.0-5.6s after CC attach on a fixed
    // schedule (research/emarker-read-timing.md). Before that, "no SOP' node"
    // means "not read yet", not "no e-marker". `connectionAge` carries that
    // fact in; these tests pin the branch that decides "Reading cable
    // details..." vs. the post-window wording.
    //
    // Ages used throughout: 2.0 (young, well inside the window), 5.99
    // (boundary, still reading: 5.99 < 6.0 is true), 6.0 (boundary, post-
    // window: 6.0 < 6.0 is false, the window is a half-open interval
    // [0, 6.0)), 7.0 (comfortably post-window), and nil (unknown age, which
    // must always render post-window wording, never "Reading").

    @Test("Reading window: above-3A readConditionsMet, age-gated wording")
    func readingWindowAbove3A() {
        // No SOP'/SOP'' identity at all. Charging above 3A makes
        // readConditionsMet true, which is exactly the state that used to
        // print the disproven "capped at 3A" claim.
        let port = makePort(active: ["USB2"], supported: ["CC", "USB2"], emarker: false)
        let sources = [usbPD(maxW: 96, winningW: 96)]

        for age in [2.0, 5.99] {
            let summary = PortSummary(port: port, sources: sources, connectionAge: age)
            #expect(
                summary.group(.emarker)?.subtitle == "Reading cable details…",
                "age \(age): expected the reading subtitle, got: \(String(describing: summary.group(.emarker)))"
            )
        }
        for age: TimeInterval? in [6.0, 7.0, nil] {
            let summary = PortSummary(port: port, sources: sources, connectionAge: age)
            let subtitle = summary.group(.emarker)?.subtitle
            #expect(
                subtitle == "The 4.8A contract shows the charger treated this as an e-marked, 5A-capable cable, so charging isn't limited by the cable. This Mac couldn't get its own read here. Connect the cable to another device to see its details.",
                "age \(String(describing: age)): expected the negotiated-above-3A subtitle, got: \(String(describing: subtitle))"
            )
            #expect(subtitle?.contains("3A") != true, "age \(String(describing: age)): must not claim a 3A cap, got: \(String(describing: subtitle))")
        }
    }

    @Test("Reading window: live-TB readConditionsMet, age-gated wording")
    func readingWindowLiveTB() {
        // Same as above but readConditionsMet is satisfied by a live
        // Thunderbolt link (hasTB), not a negotiated contract. No charging
        // source at all, so this also proves readConditionsMet doesn't
        // require chargingSource, and that it falls to the TB-only wording
        // rather than the negotiatedAbove3A branch.
        let port = makePort(active: ["CIO"], supported: ["CC", "CIO"], emarker: false)

        for age in [2.0, 5.99] {
            let summary = PortSummary(port: port, connectionAge: age)
            #expect(
                summary.group(.emarker)?.subtitle == "Reading cable details…",
                "age \(age): expected the reading subtitle, got: \(String(describing: summary.group(.emarker)))"
            )
        }
        for age: TimeInterval? in [6.0, 7.0, nil] {
            let summary = PortSummary(port: port, connectionAge: age)
            let subtitle = summary.group(.emarker)?.subtitle
            #expect(
                subtitle == "No e-marker response. Cable details aren't available on this connection. Try another device to read it.",
                "age \(String(describing: age)): expected the TB-only subtitle, got: \(String(describing: subtitle))"
            )
            #expect(subtitle?.contains("3A") != true, "age \(String(describing: age)): must not claim a 3A cap, got: \(String(describing: subtitle))")
        }
    }

    @Test("Reading window: readConditionsMet false keeps the cautious wording post-window")
    func readingWindowConditionsNotMet() {
        // Below 3A, no Thunderbolt: readConditionsMet is false. Young age
        // still reads "Reading"; post-window/nil falls to the EXISTING
        // cautious wording, unchanged by this PR (only the readConditionsMet
        // == true string was replaced).
        let port = makePort(active: ["USB2"], supported: ["CC", "USB2"], emarker: false)

        for age in [2.0, 5.99] {
            let summary = PortSummary(port: port, connectionAge: age)
            #expect(
                summary.group(.emarker)?.subtitle == "Reading cable details…",
                "age \(age): expected the reading subtitle, got: \(String(describing: summary.group(.emarker)))"
            )
        }
        for age: TimeInterval? in [6.0, 7.0, nil] {
            let summary = PortSummary(port: port, connectionAge: age)
            let subtitle = summary.group(.emarker)?.subtitle
            #expect(
                subtitle == "No e-marker read. The cable may have one; macOS usually reads it above 3A or over Thunderbolt.",
                "age \(String(describing: age)): expected the unchanged cautious subtitle, got: \(String(describing: subtitle))"
            )
        }
    }

    @Test("Reading window: populated SOP' wins over 'Reading' at every age")
    func readingWindowPopulatedEmarkerWinsAtEveryAge() {
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
        for age: TimeInterval? in [2.0, 5.99, 6.0, 7.0, nil] {
            let summary = PortSummary(port: port, identities: [cable], connectionAge: age)
            let group = summary.group(.emarker)
            #expect(
                group?.lines.contains { $0.contains("Cable speed") } == true,
                "age \(String(describing: age)): expected cable details, got: \(String(describing: group))"
            )
            #expect(group?.subtitle == nil, "age \(String(describing: age)): a read e-marker carries no subtitle, got: \(String(describing: group))")
        }
    }

    @Test("Reading window: SOP' present with empty VDOs keeps 'not read' wording at every age")
    func readingWindowEmptyEmarkerKeepsNotReadAtEveryAge() {
        // Regression pin: `hasEmarker` (endpoint present) takes priority over
        // the age gate entirely, per spec (this branch is unchanged code).
        let port = makePort(active: ["USB2"], supported: ["CC", "USB2"])
        let cable = USBPDSOP(
            id: 99, endpoint: .sopPrime,
            parentPortType: 0, parentPortNumber: 0,
            vendorID: 0, productID: 0, bcdDevice: 0,
            vdos: [], specRevision: 0
        )
        for age: TimeInterval? in [2.0, 5.99, 6.0, 7.0, nil] {
            let summary = PortSummary(port: port, identities: [cable], connectionAge: age)
            let subtitle = summary.group(.emarker)?.subtitle
            #expect(
                subtitle?.contains("not read on this connection") == true,
                "age \(String(describing: age)): expected the not-read subtitle, got: \(String(describing: subtitle))"
            )
            #expect(subtitle != "Reading cable details…", "age \(String(describing: age)): must not show the reading subtitle here")
        }
    }

    @Test("Reading window: non-PD port keeps USB-only wording at every age")
    func readingWindowNonPDPortAtEveryAge() {
        let port = makePort(active: ["USB3"], supported: ["USB2", "USB3"], superSpeed: true)
        for age: TimeInterval? in [2.0, 5.99, 6.0, 7.0, nil] {
            let summary = PortSummary(port: port, connectionAge: age)
            let subtitle = summary.group(.emarker)?.subtitle
            #expect(
                subtitle?.contains("can't read cable details") == true,
                "age \(String(describing: age)): expected the USB-only subtitle, got: \(String(describing: subtitle))"
            )
        }
    }

    @Test("Reading window: MagSafe never shows an e-marker subtitle at any age")
    func readingWindowMagSafeAtEveryAge() {
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
        for age: TimeInterval? in [2.0, 5.99, 6.0, 7.0, nil] {
            let summary = PortSummary(
                port: magSafePort,
                sources: [usbPD(maxW: 100, winningW: 100)],
                connectionAge: age
            )
            #expect(
                summary.group(.emarker) == nil,
                "age \(String(describing: age)): MagSafe must not carry an e-marker group, got: \(String(describing: summary.group(.emarker)))"
            )
        }
    }

    @Test("Reading window: no payload / disconnected never enters the reading state")
    func readingWindowNoPayloadNeverReads() {
        // Disconnected port: no e-marker group at all, at any age.
        let disconnected = makePort(connected: false)
        for age: TimeInterval? in [2.0, 5.99, 6.0, 7.0, nil] {
            let summary = PortSummary(port: disconnected, connectionAge: age)
            #expect(
                summary.group(.emarker) == nil,
                "age \(String(describing: age)): disconnected port must not carry an e-marker group"
            )
            #expect(summary.subtitle != "Reading cable details…")
        }

        // Connected but nothing plugged in (no active transports, no
        // partner): hasPayload is false, so no e-marker group either.
        let empty = makePort(connected: true)
        for age: TimeInterval? in [2.0, 5.99, 6.0, 7.0, nil] {
            let summary = PortSummary(port: empty, connectionAge: age)
            #expect(
                summary.group(.emarker) == nil,
                "age \(String(describing: age)): empty port must not carry an e-marker group"
            )
        }
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
        // issue #181: corroborate with a TRM-restricted transport so the
        // headline reaches the "USB device" branch this test pins.
        let port = makePort(active: ["USB3"], superSpeed: true)
        let summary = PortSummary(
            port: port,
            sources: [usbPD(maxW: 96, winningW: 60)],
            identities: [cableIdentity(currentBits: 1)],
            devices: [corroboratingDevice()]
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
        // issue #181: corroborate with a TRM-restricted transport so the
        // headline reaches the "USB device" branch this test pins.
        let port = makePort(active: ["USB3"], superSpeed: true)
        let summary = PortSummary(
            port: port, identities: [cableIdentity(currentBits: 1)],
            devices: [corroboratingDevice()]
        )
        #expect(summary.headline == "USB device")
    }

    @Test("Cable limit suffix absent when no cable")
    func cableLimitSuffixAbsentWhenNoCable() {
        // No e-marker: no cable wattage to surface.
        // issue #181: corroborate with a TRM-restricted transport so the
        // headline reaches the "USB device" branch this test pins.
        let port = makePort(active: ["USB3"], superSpeed: true)
        let summary = PortSummary(
            port: port, sources: [usbPD(maxW: 96, winningW: 60)],
            devices: [corroboratingDevice()]
        )
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
    @Test("Bullets are attributed to the source they came from")
    func bulletsAreAttributedToTheirSource() {
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
        // issue #181: corroborate with a TRM-restricted, no-precise-signaling
        // transport so the "SuperSpeed USB" GENERIC fallback line this test
        // pins actually appears (a transport with real signaling data would
        // show a precise "USB 3.2 Gen N" line instead).
        let corroboratingTransport = USB3Transport(
            id: 9001, portKey: "2/1", signaling: nil,
            signalingDescription: nil, dataRole: "host",
            transportRestricted: true
        )
        let summary = PortSummary(
            port: port,
            sources: [usbPD(maxW: 96, winningW: 60)],
            identities: [cable, partner],
            usb3Transports: [corroboratingTransport]
        )

        // Every line lands in the group matching where it came from.
        func kind(of needle: String) -> BulletGroup.Kind? {
            summary.groups.first { $0.lines.contains { $0.contains(needle) } }?.kind
        }

        #expect(kind(of: "SuperSpeed USB") == .measured)
        #expect(kind(of: "Connected device") == .measured)
        #expect(kind(of: "Currently negotiated") == .measured)
        #expect(kind(of: "Cable speed") == .emarker)
        #expect(kind(of: "Passive (no signal-conditioning electronics)") == .emarker)
        #expect(kind(of: "Charger advertises") == .charger)
        #expect(kind(of: "Made by Apple (0x05AC)") == .database)
        // The raw vendor ID gets no line of its own: it would be new free
        // content, and the Pro diagnostics screen already shows it.
        #expect(kind(of: "Vendor ID 0x05AC") == nil)

        // Groups appear in the agreed order: the cable's own claims first
        // (this is a cable app, and it is the question the card exists to
        // answer), then what the Mac measured, then what our records add
        // about that cable. The charger is last: it is the one group that is
        // not about the cable at all.
        #expect(summary.groups.map(\.kind) == [.emarker, .measured, .database, .charger])

        // `bullets` is the flattened groups, so the two can never disagree.
        #expect(summary.bullets == summary.groups.flatMap(\.lines))
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
            summary.group(.emarker)?.subtitle?.contains("No e-marker") == true,
            "Expected an e-marker read-state subtitle in .unknown with SOP partner, got: \(summary.groups)"
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

    @Test("A read e-marker drops the charger nag: the cable is already identified")
    func readEmarkerDropsTheChargerNag() {
        // Reported 2026-07-30. A Thunderbolt 5 cable with an accessory on the
        // far end that macOS never authorised for data: CC active only, no
        // charger. The card listed the cable's maker, speed, 240W rating and
        // certification ID, then advised finding a higher-wattage charger "to
        // identify the cable". It was already identified. A charger is how you
        // make macOS run Discover Identity when it hasn't; here it had.
        let port = makePort(connected: true, active: ["CC"], supported: ["CC", "USB2", "USB3", "CIO"])
        let cable = USBPDSOP(
            id: 42, endpoint: .sopPrime,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0x01B6, productID: 0x4003, bcdDevice: 0,
            vdos: [(3 << 27), 0, 0, (0b10 << 5) | 0b011 | (1 << 13)], specRevision: 3
        )
        let summary = PortSummary(port: port, identities: [cable])
        #expect(summary.headline == "Connected")
        #expect(
            !summary.subtitle.contains("higher-wattage"),
            "a cable whose e-marker was read is already identified, got: \(summary.subtitle)"
        )
        #expect(summary.subtitle == "No data link or charger detected on this port.")
        // Status stays .unknown on purpose. We still cannot say WHY the port is
        // quiet, and a display cable whose link failed to establish reaches this
        // same branch, so the card keeps its caution icon rather than implying
        // all is well.
        #expect(summary.status == .unknown)
    }

    @Test("An unread e-marker keeps the charger nag, which is what it is for")
    func unreadEmarkerKeepsTheChargerNag() {
        // The guard on the test above. SOP' responded but carries no VDOs, so
        // macOS never ran Discover Identity on this connection. That is exactly
        // the case a higher-wattage charger can fix, so the advice must survive.
        let port = makePort(connected: true, active: ["CC"], supported: ["CC", "USB2", "USB3", "CIO"])
        let unread = USBPDSOP(
            id: 43, endpoint: .sopPrime,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0, productID: 0, bcdDevice: 0,
            vdos: [], specRevision: 3
        )
        let summary = PortSummary(port: port, identities: [unread])
        #expect(summary.status == .unknown)
        #expect(summary.headline == "Connected")
        #expect(
            summary.subtitle == "Try a higher-wattage charger to identify the cable.",
            "an unread e-marker is the one case the nag is for, got: \(summary.subtitle)"
        )
    }

    @Test("The e-marker branch does not steal a port that has a charger")
    func readEmarkerDoesNotStealTheChargingCase() {
        // Branch-ordering guard. The new e-marker branch sits at the bottom of
        // the chain, so a port with a read e-marker AND a charger must still
        // come out as charging, not as the new "nothing running" wording.
        let port = makePort(connected: true, active: ["CC"], supported: ["CC", "USB2"])
        let cable = USBPDSOP(
            id: 44, endpoint: .sopPrime,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0x05AC, productID: 0x1234, bcdDevice: 0,
            vdos: [(3 << 27), 0, 0, (0b10 << 5) | 0b011 | (1 << 13)], specRevision: 3
        )
        let summary = PortSummary(port: port, sources: [usbPD(maxW: 96, winningW: 96)], identities: [cable])
        #expect(summary.status == .charging)
        #expect(!summary.subtitle.contains("No data link or charger detected"))
    }

    @Test("#459: source-less USB-C port with a FedDetails charger reads 'Plugged in', not the cable nag")
    func fedChargerReplacesGenericConnected() {
        // M1 Pro/Max/Ultra: no PowerSource node, no resolvable wattage, but
        // FedDetails says a charger is attached to this live USB-C port. The card
        // must say a charger is plugged in, not fall to the generic "Connected /
        // try a higher-wattage charger", which read as a contradiction next to
        // the "Charger on standby" banner (issue #459). vid 0 on purpose: a
        // generic charger that doesn't answer Discover Identity still counts.
        let port = makePort(connected: true, active: ["CC"], supported: ["CC"])
        let summary = PortSummary(port: port, federatedIdentities: [fed(portIndex: 1, vid: 0)])
        #expect(summary.headline == "Plugged in")
        #expect(summary.subtitle == "")
        #expect(!summary.subtitle.contains("higher-wattage"))
    }

    @Test("#459: FedDetails on a different port does not change this port's generic text")
    func fedChargerOnOtherPortLeavesGenericConnected() {
        // The charger entry is for port 2; this port (1) has no evidence, so it
        // must keep the generic wording rather than borrow port 2's entry.
        let port = makePort(connected: true, active: ["CC"], supported: ["CC"])
        let summary = PortSummary(port: port, federatedIdentities: [fed(portIndex: 2, vid: 0)])
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

    // MARK: - dataWithheld reads the SAME selected transport as the speed label

    @Test("dataWithheld agrees with the selected transport, not a contains scan over every match (review finding 2)")
    func dataWithheldAgreesWithSelectedTransport() {
        // Review finding 2: the exact-UUID transport is UNRESTRICTED (this
        // is the one USB3SpeedCorroboration.selectedTransport picks, since
        // exact-UUID beats portKey-fallback). A WEAKER same-portKey record
        // (no UUID, so a fallback match only) IS restricted. A device also
        // corroborates the link. Before the fix, dataWithheld scanned ALL
        // canonically-matching transports with `contains`, so it would
        // find the weaker restricted record and call the port blocked,
        // even though the selected transport (and therefore the speed
        // label) says the link is fine. That is a direct contradiction:
        // "SuperSpeed data link is active" next to "data blocked".
        let validUUID = "12345678-1234-1234-1234-123456789ABC"
        let port = AppleHPMInterface(
            id: 1,
            serviceName: "Port-USB-C@1",
            className: "AppleHPMInterfaceType10",
            portDescription: nil,
            portTypeDescription: "USB-C",
            portNumber: 1,
            connectionActive: true,
            activeCable: nil,
            opticalCable: nil,
            usbActive: nil,
            superSpeedActive: nil,
            usbModeType: nil,
            usbConnectString: nil,
            transportsSupported: ["CC", "USB2", "USB3"],
            transportsActive: ["USB3"],
            transportsProvisioned: [],
            plugOrientation: nil,
            plugEventCount: nil,
            connectionCount: nil,
            overcurrentCount: nil,
            pinConfiguration: [:],
            powerCurrentLimits: [],
            firmwareVersion: nil,
            bootFlagsHex: nil,
            hpmControllerUUID: validUUID,
            rawProperties: [:]
        )
        let exactUnrestricted = USB3Transport(
            id: 700, portKey: "2/1", signaling: 2,
            signalingDescription: "Gen 2", dataRole: "host",
            hpmControllerUUID: validUUID, transportRestricted: false
        )
        let weakerRestricted = USB3Transport(
            id: 701, portKey: "2/1", signaling: 1,
            signalingDescription: "Gen 1", dataRole: "host",
            hpmControllerUUID: nil, transportRestricted: true
        )
        let device = USBDevice(
            id: 20, locationID: 0x0020_0000,
            vendorID: 0x1234, productID: 0x5678,
            vendorName: nil, productName: "Test SSD", serialNumber: nil,
            usbVersion: nil, speedRaw: 4,
            busPowerMA: nil, currentMA: nil,
            rawProperties: [:]
        )
        let summary = PortSummary(
            port: port, devices: [device],
            usb3Transports: [exactUnrestricted, weakerRestricted]
        )
        #expect(summary.headline == "USB device", "got: \(summary.headline)")
        #expect(summary.subtitle == "SuperSpeed data link is active.", "got: \(summary.subtitle)")
        #expect(summary.headline.contains("blocked") == false, "must not contradict the fine speed label, got: \(summary.headline)")
    }

    // MARK: - USB3 Transport integration

    @Test("USB3 Gen 1 shows precise speed")
    func usb3Gen1ShowsPreciseSpeed() {
        let port = makePort(connected: true, active: ["USB3"], supported: ["CC", "USB3"])
        // issue #181: `transportRestricted: true` corroborates independently
        // (via TRM), isolating the speed-formatting behaviour this test
        // pins from the separate corroboration question.
        let transport = USB3Transport(
            id: 100, portKey: "2/1", signaling: 1,
            signalingDescription: "Gen 1", dataRole: "host",
            transportRestricted: true
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
        // issue #181: corroborate via TRM restriction, isolating the
        // speed-formatting behaviour this test pins.
        let transport = USB3Transport(
            id: 101, portKey: "2/1", signaling: 2,
            signalingDescription: "Gen 2", dataRole: "host",
            transportRestricted: true
        )
        let summary = PortSummary(port: port, usb3Transports: [transport])
        #expect(
            summary.bullets.contains(where: { $0.contains("USB 3.2 Gen 2 (10 Gbps)") }),
            "Gen 2 transport should produce precise label, got: \(summary.bullets)"
        )
    }

    @Test("USB3 with no transport data and nothing else is uncorroborated (issue #181)")
    func usb3FallbackWhenNoTransportData() {
        // When the USB3 transport service hasn't appeared yet (no device
        // connected or watcher hasn't caught up) and nothing else
        // corroborates the reading, issue #181 suppresses the generic
        // "SuperSpeed USB" label rather than showing it: this is exactly
        // the transient-handshake shape the gate exists to catch (issue
        // #181). Pre-issue #181 this asserted the OPPOSITE (that the generic
        // label DID appear); that was the bug.
        let port = makePort(connected: true, active: ["USB3"], supported: ["CC", "USB3"])
        let summary = PortSummary(port: port, usb3Transports: [])
        #expect(
            summary.bullets.contains(where: { $0.contains("SuperSpeed USB") }) == false,
            "Uncorroborated USB3 must not show the generic label, got: \(summary.bullets)"
        )
    }

    @Test("USB3 fallback when signaling nil")
    func usb3FallbackWhenSignalingNil() {
        // Transport exists but signaling field is nil (IOKit property absent).
        let port = makePort(connected: true, active: ["USB3"], supported: ["CC", "USB3"])
        // issue #181: corroborate via TRM restriction so the fallback-label
        // behaviour this test pins is reachable at all.
        let transport = USB3Transport(
            id: 102, portKey: "2/1", signaling: nil,
            signalingDescription: nil, dataRole: nil,
            transportRestricted: true
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

    @Test("Link badge: uncorroborated USB3 with no transport data shows no badge (issue #181)")
    func linkBadgeUSB3Floor() {
        // Pre-issue #181 this asserted a 5G floor badge; that is exactly the
        // transient flash the gate exists to suppress when nothing
        // corroborates the reading (issue #181).
        let port = makePort(connected: true, active: ["USB3"], supported: ["CC", "USB3"])
        let summary = PortSummary(port: port, usb3Transports: [])
        #expect(summary.linkSpeed == nil, "got: \(String(describing: summary.linkSpeed))")
    }

    @Test("Link badge: USB3 Gen 2 transport reads 10G")
    func linkBadgeUSB3Gen2() {
        let port = makePort(connected: true, active: ["USB3"], supported: ["CC", "USB3"])
        // issue #181: corroborate via TRM restriction, isolating the badge-tier
        // formatting this test pins.
        let transport = USB3Transport(
            id: 1, portKey: "2/1", signaling: 2,
            signalingDescription: "Gen 2", dataRole: "host",
            transportRestricted: true
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
        // issue #181: corroborate via TRM restriction, isolating the
        // unknown-generation label formatting this test pins.
        let transport = USB3Transport(
            id: 104, portKey: "2/1", signaling: 3,
            signalingDescription: "Gen 3", dataRole: "host",
            transportRestricted: true
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
        // issue #181: with the wrong-port transport correctly excluded, nothing
        // corroborates this port's USB3 reading at all, so no USB3 bullet
        // appears -- not even the generic "SuperSpeed USB" fallback (which,
        // pre-issue #181, is exactly the kind of unsupported transient reading
        // this gate exists to suppress).
        let port = makePort(connected: true, active: ["USB3"], supported: ["CC", "USB3"])
        let transport = USB3Transport(
            id: 103, portKey: "2/99", signaling: 2,
            signalingDescription: "Gen 2", dataRole: "host"
        )
        let summary = PortSummary(port: port, usb3Transports: [transport])
        #expect(
            summary.bullets.contains(where: { $0.contains("USB 3.2") || $0.contains("SuperSpeed") }) == false,
            "Transport for wrong port should be ignored and not corroborate, got: \(summary.bullets)"
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
        // issue #181: corroborate via TRM restriction (no device is matched,
        // by design of this test).
        let transport = USB3Transport(
            id: 201, portKey: "2/1", signaling: 2,
            signalingDescription: "Gen 2", dataRole: "host",
            transportRestricted: true
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
        // issue #181: the only device present is USB2, which does not
        // corroborate (only a real SuperSpeed device or a TRM restriction
        // does). `transportRestricted: true` corroborates independently so
        // this test keeps proving its original point (the USB2 device must
        // not win the SPEED label) without also asserting anything about
        // corroboration, which is covered elsewhere.
        let transport = USB3Transport(
            id: 202, portKey: "2/1", signaling: 1,
            signalingDescription: "Gen 1", dataRole: "host",
            transportRestricted: true
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

    // MARK: - The #459 FedDetails branch must not claim "Plugged in" on battery

    /// Reproduced on an M5 on 2026-08-10: `pmset` reported battery power and
    /// discharging while the card showed a charging bolt and "Plugged in".
    ///
    /// The #459 branch recovers a charger from FedDetails when this port has no
    /// PowerSource node (the M1 Pro/Max/Ultra case). It was the only one of the
    /// three charger branches without the `!systemPowerUnavailable` guard, and
    /// it rests on `FedExternalConnected`, which is stale roughly 40% of the
    /// time, so it needs the cross-check more than its siblings, not less.
    @Test("FedDetails charger does not claim 'Plugged in' when the system is on battery")
    func fedDetailsChargerSuppressedOnBattery() {
        // No PowerSource node, no adapter, battery discharging: the system
        // says there is no external power, whatever FedDetails still holds.
        let port = makePort(connected: true, active: [], supported: ["CC"])
        let summary = PortSummary(
            port: port,
            federatedIdentities: [fed(portIndex: 1, vid: 0x05AC)],
            batteryIsCharging: false,
            adapter: nil
        )
        #expect(summary.status != .charging,
                "must not report charging on battery, got \(summary.status)")
        #expect(!summary.headline.contains("Plugged in"),
                "must not claim plugged in on battery, got: \(summary.headline)")
        // Pin the whole message, not just what it must NOT say. Suppressing
        // the wrong claim is only half the job: the catch-all this now falls
        // to used to advise a HIGHER-WATTAGE charger, which assumes one is
        // already attached and reads as nonsense on battery.
        #expect(summary.subtitle == "Connect a charger to identify the cable.",
                "got: \(summary.subtitle)")
        #expect(!summary.subtitle.contains("higher-wattage"),
                "must not imply a charger is already attached, got: \(summary.subtitle)")
    }

    /// The other half, so the fix cannot be "delete the branch": with real
    /// external power the branch must still fire. This is the case #459 was
    /// opened for, and losing it would put the card back to advising a bigger
    /// charger next to a "Charger on standby" banner.
    @Test("FedDetails charger still reports 'Plugged in' when the Mac has external power")
    func fedDetailsChargerStillFiresOnPower() {
        let port = makePort(connected: true, active: [], supported: ["CC"])
        let summary = PortSummary(
            port: port,
            federatedIdentities: [fed(portIndex: 1, vid: 0x05AC)],
            batteryIsCharging: false,
            // An adapter present means the system IS on external power, so
            // `onBattery` is false even with the battery not charging (a
            // charge hold at 100%, say).
            adapter: adapter(watts: 96)
        )
        #expect(summary.status == .charging)
        #expect(summary.headline.contains("Plugged in"),
                "expected the #459 branch to still fire, got: \(summary.headline)")
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

    // Battery-full must not exempt the stale-PDO gate: unplugging at 100% with
    // a lingering PDO (charging false, full true, adapter nil) must still read
    // "Connected", not a charging claim.
    @Test("Stale PDO: no charging claim when full and unplugged with no adapter")
    func stalePDOFullBatteryNoAdapterIsConnected() {
        let port = makePort(connected: true, active: [], supported: ["USB2"])
        let summary = PortSummary(
            port: port,
            sources: [usbPD(maxW: 96, winningW: 96)],
            batteryFullyCharged: true,
            batteryIsCharging: false,
            adapter: nil
        )
        #expect(summary.status == .unknown)
        #expect(summary.headline == "Connected")
        #expect(summary.subtitle.contains("Power is flowing") == false)
        #expect(summary.bullets.contains { $0.contains("Currently negotiated") } == false)
    }

    // Desktop Macs report batteryIsCharging as nil (no battery). The gate must
    // NOT suppress in that state: a winning PDO still means power is flowing.
    @Test("Desktop (nil battery state) is not suppressed by the stale-PDO gate")
    func desktopNilBatteryNotSuppressed() {
        let port = makePort(connected: true, active: [], supported: ["USB2"])
        let summary = PortSummary(
            port: port,
            sources: [usbPD(maxW: 96, winningW: 96)],
            batteryFullyCharged: nil,
            batteryIsCharging: nil,
            adapter: nil
        )
        #expect(summary.status == .charging)
        #expect(summary.headline.contains("96W"))
    }

    // A genuine 100% charge hold has an adapter present, so the gate does not
    // fire and the normal "battery full" display is preserved (regression guard
    // that the stale-PDO gating didn't break legitimate charge-hold copy).
    @Test("Charge hold at 100% with adapter shows battery full")
    func chargeHoldFullWithAdapterShowsBatteryFull() {
        let port = makePort(connected: true, active: [], supported: ["USB2"])
        let summary = PortSummary(
            port: port,
            sources: [usbPD(maxW: 96, winningW: 96)],
            batteryFullyCharged: true,
            batteryIsCharging: false,
            adapter: adapter()
        )
        #expect(summary.status == .batteryFull)
        #expect(summary.headline == "Plugged in · battery full")
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

    // MARK: - Data withheld by macOS accessory security

    /// TRM fixture for one transport on port 1.
    private func trm(_ type: String, restricted: Bool, tunnelled: Bool? = false) -> TRMTransport {
        TRMTransport(
            id: 900, portKey: "2/1", transportType: type,
            state: 2, stateDescription: "Restricted",
            transportRestricted: restricted, transportSupervised: true,
            identificationRestricted: false, deviceLocked: false,
            relaxedPeriod: true, gracePeriodReason: 4,
            gracePeriodReasonDescription: "Device Unlocked",
            profile: 1, profileDescription: "Ask Every Time",
            cacheMiss: false, tunnelled: tunnelled
        )
    }

    @Test("Denied USB3 accessory: the card stops claiming an active link")
    func deniedUSB3DoesNotClaimAnActiveLink() {
        // Measured 2026-07-30 by denying a Pixel 8 at the macOS prompt. macOS
        // keeps USB3 in TransportsActive and the node Active=Yes while
        // withholding authorisation, so the card read "USB device /
        // SuperSpeed data link is active" directly above a diagnostic saying
        // data was blocked. No data was flowing.
        let port = makePort(active: ["CC", "USB3"], supported: ["CC", "USB2", "USB3"], superSpeed: true)
        let transport = USB3Transport(
            id: 100, portKey: "2/1", signaling: 2,
            signalingDescription: "Gen 2", dataRole: "host",
            transportRestricted: true
        )
        let summary = PortSummary(port: port, usb3Transports: [transport])
        #expect(summary.headline == "USB device, data blocked")
        #expect(
            !summary.subtitle.contains("is active"),
            "must not claim a live link while macOS withholds it, got: \(summary.subtitle)"
        )
        #expect(summary.subtitle == "macOS is holding data back until you approve the accessory.")
    }

    @Test("Keyboard shape: restricted but not active keeps its normal wording")
    func restrictedButInactiveTransportIsNotTreatedAsBlocked() {
        // The trap. An iPad keyboard carries transportRestricted=true with a
        // valid Gen 2 signalling rate, exactly like the denied phone, and is
        // NOT blocked: it never asked for data. The only field separating the
        // two is whether the transport is in TransportsActive. Measured on
        // hardware 2026-07-30: identical on every other field.
        //
        // Honest note on what this test does and does not prove. It is a
        // STRUCTURAL guard: a port whose transports are all idle has no active
        // data transport, so `dataWithheld` is false by construction and no
        // branch can reach the blocked wording. It does not exercise any
        // single condition in isolation. What it pins is that moving the
        // blocked check earlier in the chain, or computing the verdict from
        // the restricted flag alone, fails here.
        let port = makePort(active: ["CC"], supported: ["CC", "USB2", "USB3"])
        let transport = USB3Transport(
            id: 101, portKey: "2/1", signaling: 2,
            signalingDescription: "Gen 2", dataRole: "host",
            transportRestricted: true
        )
        let summary = PortSummary(port: port, usb3Transports: [transport])
        #expect(summary.headline == "Connected")
        #expect(summary.subtitle == "Try a higher-wattage charger to identify the cable.")
    }

    @Test("An unrestricted USB3 port still reports its active link")
    func unrestrictedUSB3StillReportsActiveLink() {
        // issue #181: an unrestricted transport with no enumerated device does
        // NOT corroborate (that is precisely the transient-handshake shape
        // the gate exists to suppress), so this test now supplies a real
        // root SuperSpeed device to keep testing what it always meant to
        // test: that an UNRESTRICTED (not blocked) port reports its link
        // normally, as opposed to the blocked-by-security wording.
        let port = makePort(active: ["CC", "USB3"], supported: ["CC", "USB2", "USB3"], superSpeed: true)
        let transport = USB3Transport(
            id: 102, portKey: "2/1", signaling: 2,
            signalingDescription: "Gen 2", dataRole: "host",
            transportRestricted: false
        )
        let device = USBDevice(
            id: 20, locationID: 0x0020_0000,
            vendorID: 0x1234, productID: 0x5678,
            vendorName: nil, productName: "Test SSD", serialNumber: nil,
            usbVersion: nil, speedRaw: 4,
            busPowerMA: nil, currentMA: nil,
            rawProperties: [:]
        )
        let summary = PortSummary(port: port, devices: [device], usb3Transports: [transport])
        #expect(summary.headline == "USB device")
        #expect(summary.subtitle == "SuperSpeed data link is active.")
    }

    @Test("USB3 + DisplayPort blocked: data wording changes, video claim does not")
    func blockedDataWithVideoDoesNotBlameTheDisplay() {
        // Only the data half is withheld. The picture is genuinely working, so
        // the wording must not imply the display is affected.
        let port = makePort(active: ["CC", "USB3", "DisplayPort"], supported: ["CC", "USB3", "DisplayPort"], superSpeed: true)
        let transport = USB3Transport(
            id: 103, portKey: "2/1", signaling: 2,
            signalingDescription: "Gen 2", dataRole: "host",
            transportRestricted: true
        )
        let summary = PortSummary(port: port, usb3Transports: [transport])
        #expect(summary.headline == "USB-C with video")
        #expect(summary.subtitle == "Video is working. macOS is holding data back until you approve the accessory.")
    }

    @Test("Denied USB2 accessory: read from TRM, since USB2 has no transport model")
    func deniedUSB2IsDetectedViaTRM() {
        // Every corpus machine with a withheld transport lists USB2, not USB3.
        // Those ports used to read "Slow USB device or charge-only cable /
        // Only USB 2.0 is active" while macOS withheld the data.
        let port = makePort(active: ["CC", "USB2"], supported: ["CC", "USB2", "USB3"])
        let summary = PortSummary(port: port, trmTransports: [trm("USB2", restricted: true)])
        #expect(summary.headline == "USB device, data blocked")
        #expect(summary.subtitle == "macOS is holding data back until you approve the accessory.")
    }

    @Test("An unrestricted USB2 port keeps the slow-device wording")
    func unrestrictedUSB2KeepsSlowDeviceWording() {
        let port = makePort(active: ["CC", "USB2"], supported: ["CC", "USB2", "USB3"])
        let summary = PortSummary(port: port, trmTransports: [trm("USB2", restricted: false)])
        #expect(summary.headline == "Slow USB device or charge-only cable")
    }

    @Test("Thunderbolt port ignores the withheld verdict (deliberate, documented gap)")
    func thunderboltPortIgnoresTheWithheldVerdict() {
        // Raised in review as a critical gap, and it is a real one: the hasTB
        // branch is checked first and never consumes `dataWithheld`, so a
        // Thunderbolt port with a withheld CIO transport keeps its ordinary
        // wording. Scoped out rather than fixed: no CIO transport is
        // restricted anywhere in the corpus (0 of 739 machines) or on any
        // hardware seen, so there is no evidence to write wording against.
        //
        // This test exists to make that a decision rather than an accident.
        // If Thunderbolt coverage is added later, this test SHOULD fail, and
        // whoever changes it should have a real sample in hand.
        let port = makePort(active: ["CC", "CIO"], supported: ["CC", "CIO", "USB3"])
        let summary = PortSummary(port: port, trmTransports: [trm("CIO", restricted: true)])
        #expect(summary.status == .thunderboltCable)
        #expect(
            !summary.headline.contains("data blocked"),
            "Thunderbolt coverage is deliberately out of scope; if this now fails, see the note above"
        )
    }

    @Test("USB3 withheld while USB2 runs: the port still has data, so not blocked")
    func partiallyWithheldPortIsNotCalledBlocked() {
        // Raised in review. A port can run USB2 and USB3 at once with only one
        // held back. The corpus has the mirror case (m5pro_macos27.0 port 1:
        // USB2 withheld, USB3 running) and this is the other direction. Either
        // way the port carries data, so "data blocked" would be a new false
        // claim in place of the old one.
        let port = makePort(active: ["CC", "USB2", "USB3"], supported: ["CC", "USB2", "USB3"], superSpeed: true)
        let blockedUSB3 = USB3Transport(
            id: 104, portKey: "2/1", signaling: 2,
            signalingDescription: "Gen 2", dataRole: "host",
            transportRestricted: true
        )
        let summary = PortSummary(
            port: port,
            usb3Transports: [blockedUSB3],
            trmTransports: [trm("USB2", restricted: false)]
        )
        #expect(
            !summary.headline.contains("data blocked"),
            "USB2 is still carrying data, got: \(summary.headline)"
        )
    }

    @Test("A dock's tunnelled USB3 transport cannot make the port look blocked")
    func tunnelledUSB3EntryIsIgnored() {
        // Raised in review. USB3Transport gained `tunnelled` for this: portKey
        // is parentPortType/parentPortNumber, so a dock's tunnelled
        // Port-USB-C@N/CIO/USB3@0 node shares the physical port's key and
        // would otherwise be selected as the port's own link.
        let port = makePort(active: ["CC", "USB3"], supported: ["CC", "USB3"], superSpeed: true)
        let tunnelledTransport = USB3Transport(
            id: 105, portKey: "2/1", signaling: 2,
            signalingDescription: "Gen 2", dataRole: "host",
            transportRestricted: true, tunnelled: true
        )
        let summary = PortSummary(port: port, usb3Transports: [tunnelledTransport])
        #expect(
            !summary.headline.contains("data blocked"),
            "a tunnelled entry belongs to the dock, not this port, got: \(summary.headline)"
        )
    }

    @Test("A dock's tunnelled transport does not mark the physical port blocked")
    func tunnelledTRMEntryIsIgnored() {
        // portKey is parentPortType/parentPortNumber, and a dock's tunnelled
        // Port-USB-C@N/CIO/USB3@0 node carries the SAME parent port number as
        // the port's own transports. Without the tunnelled flag the dock's
        // internal plumbing would be read as a property of the physical port.
        let port = makePort(active: ["CC", "USB2"], supported: ["CC", "USB2"])
        let summary = PortSummary(port: port, trmTransports: [trm("USB2", restricted: true, tunnelled: true)])
        #expect(
            !summary.headline.contains("data blocked"),
            "a tunnelled entry belongs to the dock, not this port, got: \(summary.headline)"
        )
    }

    // MARK: - Cable identity: single vs multi-brand wording (#505)

    /// Builds a cable identity (SOP') with a given VID/PID/Cable VDO, so a
    /// specific curated-DB row can be matched. Cable VDO defaults to a
    /// harmless passive/USB4 encoding when not overridden by the caller.
    private func cableIdentity(vendorID: Int, productID: Int, cableVDO: UInt32) -> USBPDSOP {
        USBPDSOP(
            id: 99, endpoint: .sopPrime,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: vendorID, productID: productID, bcdDevice: 0,
            vdos: [
                (3 << 27) | UInt32(vendorID), // ID Header VDO: passive cable
                0,
                0,
                cableVDO,
            ],
            specRevision: 3
        )
    }

    @Test("Single curated brand: shows the plain 'Cable identified as' line")
    func singleCuratedBrandShowsPlainLine() {
        // CalDigit's Thunderbolt 5 cable (VID 0x01B6, PID 0x4003, Cable VDO
        // 0x110A2644) curates to exactly one row. This must keep today's
        // single-brand wording so existing translations still apply.
        let cable = cableIdentity(vendorID: 0x01B6, productID: 0x4003, cableVDO: 0x110A2644)
        let port = makePort(active: ["USB3"], superSpeed: true)
        let summary = PortSummary(port: port, identities: [cable])

        #expect(summary.bullets.contains { $0.contains("Cable identified as") && $0.contains("CalDigit") })
        #expect(!summary.bullets.contains { $0.contains("This e-marker is used in:") })
    }

    @Test("Multi-brand fingerprint: shows the shared-fingerprint line naming both brands")
    func multiBrandFingerprintShowsSharedLine() {
        // ACON's Thunderbolt 5 cable (VID 0x0522, PID 0x0A33, Cable VDO
        // 0x110A2644) curates to two rows: Anker Prime and UGREEN (#505).
        // Neither brand can be picked as "the" answer, so this must use the
        // honest multi-brand wording, not the single-brand line.
        let cable = cableIdentity(vendorID: 0x0522, productID: 0x0A33, cableVDO: 0x110A2644)
        let port = makePort(active: ["USB3"], superSpeed: true)
        let summary = PortSummary(port: port, identities: [cable])

        let multiBrandLine = summary.bullets.first { $0.contains("This e-marker is used in:") }
        #expect(multiBrandLine != nil, "expected the multi-brand line, got bullets: \(summary.bullets)")
        // The localised prefix stays a substring check (repo convention: the
        // catalogue owns exact wording), but the joined-brands payload after
        // it is pinned exactly, including the "; " separator and the order
        // (Anker before UGREEN, matching the DB's own
        // ORDER BY vid, pid, cable_vdo, brand).
        let expectedBrands = "Anker Prime Thunderbolt 5 cable, bundled with Anker Prime TB5 Dock, Amazon; UGREEN Thunderbolt 5 cable 80Gbps 240W, Amazon"
        #expect(multiBrandLine?.hasSuffix(expectedBrands) == true, "expected brand list '\(expectedBrands)', got: \(multiBrandLine ?? "nil")")
        #expect(!summary.bullets.contains { $0.contains("Cable identified as") })
    }

    @Test("No curated match: shows neither the single-brand nor multi-brand line")
    func noCuratedMatchShowsNeitherLine() {
        // An unknown VID/PID pair resolves no curated rows at all, so
        // neither the single-brand nor the multi-brand bullet should appear.
        let cable = cableIdentity(vendorID: 0xDEAD, productID: 0xBEEF, cableVDO: 0x110A2644)
        let port = makePort(active: ["USB3"], superSpeed: true)
        let summary = PortSummary(port: port, identities: [cable])

        #expect(!summary.bullets.contains { $0.contains("Cable identified as") })
        #expect(!summary.bullets.contains { $0.contains("This e-marker is used in:") })
    }

    // MARK: - Cable classification wiring

    /// The CalDigit 2M Thunderbolt 4 cable from issue #111, second capture:
    /// passive ID Header, VDO[3] bit 3 CLEAR, so nothing structural to infer
    /// from. Only the port controller can promote this one.
    private func caldigitBitThreeClear() -> USBPDSOP {
        USBPDSOP(
            id: 99, endpoint: .sopPrime,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0x2B1D, productID: 0x1901, bcdDevice: 0x97,
            vdos: [0x1C002B1D, 0x00000000, 0x19010097, 0x32084842],
            specRevision: 3
        )
    }

    /// The same cable's other capture, VDO[3] bit 3 SET, which is the layout
    /// contradiction on its own.
    private func caldigitBitThreeSet() -> USBPDSOP {
        USBPDSOP(
            id: 99, endpoint: .sopPrime,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0x2B1D, productID: 0x1901, bcdDevice: 0x97,
            vdos: [0x1C002B1D, 0x00000000, 0x19010097, 0x3208485A],
            specRevision: 3
        )
    }

    private static let portControllerLine =
        "E-marker reports passive, but the port controller detects an active cable"
    private static let contradictionLine = "carries active-cable structure"
    private static let passiveLine = "Passive (no signal-conditioning electronics)"

    private func emarkerLines(_ summary: PortSummary) -> [String] {
        summary.groups.first { $0.kind == .emarker }?.lines ?? []
    }

    @Test("Port controller promotion gets its own hedged wording")
    func portControllerPromotionGetsItsOwnWording() {
        let port = makePort(active: ["CIO", "USB3"], supported: ["CC", "CIO", "USB3"], emarker: true)
        let summary = PortSummary(port: port, identities: [caldigitBitThreeClear()])
        let lines = emarkerLines(summary)
        #expect(lines.contains { $0.contains(Self.portControllerLine) },
                "expected the port-controller line, got: \(lines)")
        #expect(!lines.contains { $0.contains(Self.passiveLine) },
                "a promoted cable must not also read as passive, got: \(lines)")
    }

    @Test("Port controller saying not active leaves the passive wording alone")
    func portControllerFalseKeepsPassiveWording() {
        let port = makePort(active: ["CIO", "USB3"], supported: ["CC", "CIO", "USB3"], emarker: false)
        let summary = PortSummary(port: port, identities: [caldigitBitThreeClear()])
        let lines = emarkerLines(summary)
        #expect(lines.contains { $0.contains(Self.passiveLine) },
                "expected the passive line, got: \(lines)")
        #expect(!lines.contains { $0.contains(Self.portControllerLine) })
        #expect(!lines.contains { $0.contains(Self.contradictionLine) })
    }

    @Test("Port controller takes precedence over the layout contradiction")
    func portControllerBeatsLayoutContradiction() {
        // A controller measurement beats a structural inference, so the four
        // corpus ports that set both move to the port-controller wording.
        let port = makePort(active: ["CIO", "USB3"], supported: ["CC", "CIO", "USB3"], emarker: true)
        let summary = PortSummary(port: port, identities: [caldigitBitThreeSet()])
        let lines = emarkerLines(summary)
        #expect(lines.contains { $0.contains(Self.portControllerLine) },
                "expected the port-controller line, got: \(lines)")
        #expect(!lines.contains { $0.contains(Self.contradictionLine) },
                "the contradiction wording must not fire as well, got: \(lines)")
    }

    @Test("A port-promoted cable carrying VDO[4] renders its medium and element")
    func portPromotedCableRendersMediumAndElement() {
        // Synthetic, and it has to be: all 12 corpus ports the controller
        // promotes carry exactly 4 VDOs, so no capture can exercise VDO[4]
        // on this path.
        let passiveIDHeader: UInt32 = (3 << 27) | UInt32(0x2B1D)
        let passiveVDO3: UInt32 = 0b011 | UInt32(2 << 5) | UInt32(1 << 13)
        let identity = USBPDSOP(
            id: 99, endpoint: .sopPrime,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0x2B1D, productID: 0x1901, bcdDevice: 0x97,
            vdos: [passiveIDHeader, 0, 0x19010097, passiveVDO3, 0x11082041],
            specRevision: 3
        )
        let port = makePort(active: ["CIO", "USB3"], supported: ["CC", "CIO", "USB3"], emarker: true)
        let lines = emarkerLines(PortSummary(port: port, identities: [identity]))
        #expect(lines.contains { $0.hasPrefix("Active ") && $0.contains(" cable, ") },
                "expected the medium/element line, got: \(lines)")
    }

    // MARK: - Captive plug line

    private func plugTypeCable(bits: UInt32) -> USBPDSOP {
        // Cable VDO: USB4 Gen3, 5A, ~1m latency, plug type in bits 19:18.
        let vdo3: UInt32 = 0b011 | UInt32(2 << 5) | UInt32(1 << 13) | (bits << 18)
        return USBPDSOP(
            id: 99, endpoint: .sopPrime,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0x05AC, productID: 0x1234, bcdDevice: 0,
            vdos: [(3 << 27) | UInt32(0x05AC), 0, 0, vdo3],
            specRevision: 3
        )
    }

    @Test("Captive plug adds a line, a Type-C plug adds none")
    func captivePlugLineOnlyWhenCaptive() {
        let port = makePort()
        let captive = emarkerLines(PortSummary(port: port, identities: [plugTypeCable(bits: 0b11)]))
        #expect(captive.contains { $0.contains("Captive cable") },
                "expected the captive line, got: \(captive)")
        let typeC = emarkerLines(PortSummary(port: port, identities: [plugTypeCable(bits: 0b10)]))
        #expect(!typeC.contains { $0.contains("plug") || $0.contains("Captive") },
                "a Type-C plug on a USB-C cable is not information, got: \(typeC)")
    }

    // MARK: - Chip-vendor hint

    private func vendorCable(vendorID: Int, productID: Int) -> USBPDSOP {
        USBPDSOP(
            id: 99, endpoint: .sopPrime,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: vendorID, productID: productID, bcdDevice: 0,
            vdos: [(3 << 27) | UInt32(vendorID), 0, 0, 0b011 | UInt32(2 << 5) | UInt32(1 << 13)],
            specRevision: 3
        )
    }

    private func databaseLines(_ summary: PortSummary) -> [String] {
        summary.groups.first { $0.kind == .database }?.lines ?? []
    }

    @Test("Chip-vendor hint appears only for e-marker silicon vendor IDs")
    func chipVendorHintOnlyForSiliconVendorIDs() {
        let port = makePort()
        let cps = databaseLines(PortSummary(port: port, identities: [vendorCable(vendorID: 0x315C, productID: 0)]))
        #expect(cps.contains { $0.contains("chip maker's default vendor ID (CPS)") },
                "expected the chip-vendor hint, got: \(cps)")
        #expect(cps.contains { $0.contains("Made by") },
                "the vendor name is honest and stays, got: \(cps)")

        let apple = databaseLines(PortSummary(port: port, identities: [vendorCable(vendorID: 0x05AC, productID: 0x1234)]))
        #expect(!apple.contains { $0.contains("chip maker's default vendor ID") },
                "a cable brand's own VID gets no hint, got: \(apple)")
        #expect(apple.contains { $0.contains("Made by") },
                "expected the vendor line, got: \(apple)")
    }
}
