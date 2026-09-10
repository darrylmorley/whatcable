import Testing
import Foundation
@testable import WhatCableCore

@Suite("Cable Report")
struct CableReportTests {

    private func cableIdentity(
        vendorID: Int = 0x05AC,
        productID: Int = 0x1234,
        endpoint: USBPDSOP.Endpoint = .sopPrime,
        vdos: [UInt32] = [
            // ID Header VDO: passive cable from VID 0x05AC
            (3 << 27) | UInt32(0x05AC),
            0,
            0,
            // Cable VDO: USB4 Gen 3 (0b011), 5A (0b10), passive,
            // latency 0001 (~1 m). A bare-zero VDO would trip the
            // reservedCableLatencyEncoding warning even though these
            // tests aren't about trust signals.
            (0b10 << 5) | 0b011 | (1 << 13)
        ]
    ) -> USBPDSOP {
        USBPDSOP(
            id: 1,
            endpoint: endpoint,
            parentPortType: 0,
            parentPortNumber: 0,
            vendorID: vendorID,
            productID: productID,
            bcdDevice: 0,
            vdos: vdos,
            specRevision: 3
        )
    }

    @Test("Payload only built for cable endpoints")
    func payloadOnlyBuiltForCableEndpoints() {
        #expect(CableReport.payload(for: cableIdentity(endpoint: .sopPrime)) != nil)
        #expect(CableReport.payload(for: cableIdentity(endpoint: .sopDoublePrime)) != nil)
        #expect(CableReport.payload(for: cableIdentity(endpoint: .sop)) == nil)
        #expect(CableReport.payload(for: cableIdentity(endpoint: .unknown)) == nil)
    }

    @Test("Fingerprint formats hex as uppercase four digits")
    func fingerprintFormatsHexAsUppercaseFourDigits() {
        let payload = CableReport.payload(for: cableIdentity(vendorID: 0x05AC, productID: 0x004C))!
        #expect(payload.cable.vendorIDHex == "0x05AC")
        #expect(payload.cable.productIDHex == "0x004C")
    }

    @Test("Fingerprint labels unregistered vendor")
    func fingerprintLabelsUnregisteredVendor() {
        let payload = CableReport.payload(for: cableIdentity(vendorID: 0xDEAD))!
        #expect(payload.cable.vendorName == "Unregistered / unknown")
    }

    @Test("Curated VID+PID match prefers the brand over the silicon vendor")
    func curatedMatchPrefersBrand() {
        // CalDigit Thunderbolt 5 cable (VID 0x01B6, PID 0x4003, Cable VDO
        // 0x110A2644) is in the curated DB. On a confident VID+PID+VDO match
        // the report surfaces the curated brand/model rather than only the
        // silicon vendor name. See #239.
        let curated = CableDB.curatedCables(vid: 0x01B6, pid: 0x4003, cableVDO: 0x110A2644)
        #expect(!curated.isEmpty)
        let vdos: [UInt32] = [
            (3 << 27) | UInt32(0x01B6), // ID Header VDO: passive cable
            0,
            0,
            0x110A2644, // Cable VDO matching the curated row
        ]
        let payload = CableReport.payload(for: cableIdentity(vendorID: 0x01B6, productID: 0x4003, vdos: vdos))!
        #expect(payload.cable.vendorName == curated.first?.brand)
        #expect(payload.cable.vendorName.contains("CalDigit"))
    }

    @Test("Multi-brand fingerprint joins the brands with ' / '")
    func multiBrandFingerprintJoinsBrandsWithSlash() {
        // ACON's Thunderbolt 5 cable (VID 0x0522, PID 0x0A33, Cable VDO
        // 0x110A2644) curates to two rows: Anker Prime and UGREEN (#505).
        // The machine-consumed report can't pick a winner, so it joins both
        // distinct brands with " / ". sync-cable-reports.swift only regexes
        // the hex VID out of this cell (extractHex matches the first
        // "0x..." anywhere in the string), so this join doesn't break it.
        let curated = CableDB.curatedCables(vid: 0x0522, pid: 0x0A33, cableVDO: 0x110A2644)
        #expect(curated.count == 2)
        let vdos: [UInt32] = [
            (3 << 27) | UInt32(0x0522), // ID Header VDO: passive cable
            0,
            0,
            0x110A2644, // Cable VDO matching both curated rows
        ]
        let payload = CableReport.payload(for: cableIdentity(vendorID: 0x0522, productID: 0x0A33, vdos: vdos))!
        // Pinned exactly: order and separator both matter here, not just
        // "both brands appear somewhere". Order matches the DB's own
        // ORDER BY vid, pid, cable_vdo, brand.
        let expected = "Anker Prime Thunderbolt 5 cable, bundled with Anker Prime TB5 Dock, Amazon / UGREEN Thunderbolt 5 cable 80Gbps 240W, Amazon"
        #expect(payload.cable.vendorName == expected)
    }

    @Test("Markdown includes fingerprint and environment")
    func markdownIncludesFingerprintAndEnvironment() {
        let payload = CableReport.payload(for: cableIdentity(), appVersion: "1.2.3")!
        let md = payload.markdown
        #expect(md.contains("### Cable e-marker fingerprint"))
        #expect(md.contains("`0x05AC`"))
        #expect(md.contains("Apple"))
        #expect(md.contains("### Environment"))
        #expect(md.contains("WhatCable: `1.2.3`"))
        // No system info opt-in: should be flagged as not included.
        #expect(md.contains("not included by reporter"))
    }

    @Test("Payload carries the injected Mac model, not a sysctl lookup")
    func payloadCarriesInjectedMacModel() {
        // CableReport doesn't call sysctl itself anymore (that's a
        // Darwin-only API, out of bounds for Core). Callers fetch the model
        // via WhatCableDarwinBackend and pass it in; this checks it flows
        // through untouched.
        let payload = CableReport.payload(
            for: cableIdentity(),
            includeSystemInfo: true,
            macModel: "Mac16,1"
        )!
        #expect(payload.system?.macModel == "Mac16,1")
    }

    @Test("Payload defaults Mac model to unknown when the caller doesn't provide one")
    func payloadDefaultsMacModelToUnknown() {
        let payload = CableReport.payload(for: cableIdentity(), includeSystemInfo: true)!
        #expect(payload.system?.macModel == "unknown")
    }

    @Test("Markdown includes system info when provided")
    func markdownIncludesSystemInfoWhenProvided() {
        let payload = CableReport.Payload(
            cable: CableReport.CableFingerprint(identity: cableIdentity()),
            system: CableReport.SystemInfo(macModel: "Mac15,3", macOSVersion: "14.5.0"),
            appVersion: "1.2.3"
        )
        let md = payload.markdown
        #expect(md.contains("Mac: `Mac15,3`"))
        #expect(md.contains("macOS: `14.5.0`"))
        #expect(md.contains("not included by reporter") == false)
    }

    @Test("GitHub URL targets template and carries fingerprint")
    func gitHubURLTargetsTemplateAndCarriesFingerprint() throws {
        let payload = CableReport.payload(for: cableIdentity())!
        let url = payload.githubURL
        let comps = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(comps.host == "github.com")
        #expect(comps.path == "/darrylmorley/whatcable/issues/new")
        let items = Dictionary(uniqueKeysWithValues:
            (comps.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )
        #expect(items["template"] == "cable-report.yml")
        #expect(items["labels"] == "cable-report")
        #expect(items["title"]?.hasPrefix("[Cable Report]") == true)
        #expect(items["fingerprint"]?.contains("0x05AC") == true)
    }

    @Test("Issue title and Markdown use the canonical report speed")
    func issueTitleAndMarkdownUseCanonicalSpeed() {
        let payload = CableReport.payload(for: cableIdentity())!
        let canonical = PDVDO.CableSpeed.usb4Gen3.reportLabel
        #expect(payload.cable.speed == canonical)
        #expect(payload.issueTitle == "[Cable Report] Apple, \(canonical)")
        #expect(payload.markdown.contains("| Cable speed | \(canonical) |"))
    }

    @Test("Reports preserve reserved cable speed encodings")
    func reportsPreserveReservedCableSpeedEncoding() {
        let reservedIdentity = cableIdentity(
            vdos: [
                (3 << 27) | UInt32(0x05AC),
                0,
                0,
                (1 << 5) | 5 | (1 << 13),
            ]
        )
        let payload = CableReport.payload(for: reservedIdentity)!
        let reservedLabel = "Reserved cable speed encoding (5)"

        #expect(payload.cable.speed == reservedLabel)
        #expect(payload.cable.speed != PDVDO.CableSpeed.usb20.reportLabel)
        #expect(payload.issueTitle == "[Cable Report] Apple, \(reservedLabel)")
        #expect(payload.markdown.contains("| Cable speed | \(reservedLabel) |"))
    }

    @Test("Fingerprint carries raw VDOs")
    func fingerprintCarriesRawVDOs() {
        let payload = CableReport.payload(for: cableIdentity())!
        // Fixture has 4 VDOs: ID Header, Cert Stat, Product, Cable.
        #expect(payload.cable.vdos.count == 4)
        // VDO[0] = passive cable header (3 << 27) | 0x05AC.
        #expect(payload.cable.vdos[0] == (3 << 27) | UInt32(0x05AC))
    }

    @Test("Markdown includes raw VDO section")
    func markdownIncludesRawVDOSection() {
        let payload = CableReport.payload(for: cableIdentity())!
        let md = payload.markdown
        #expect(md.contains("### Raw VDOs"))
        // ID Header VDO from the fixture: (3 << 27) | 0x05AC = 0x180005AC.
        #expect(md.contains("`0x180005AC`"))
        // Role labels appear so future readers can tell which is which
        // without having to know the spec layout.
        #expect(md.contains("ID Header"))
        #expect(md.contains("Cable"))
        #expect(md.contains("Product"))
    }

    @Test("Markdown omits raw VDO section when absent")
    func markdownOmitsRawVDOSectionWhenAbsent() {
        // Identity with no VDOs (e.g. a cable that didn't respond to
        // Discover Identity at all) shouldn't render an empty Raw VDOs table.
        let id = USBPDSOP(
            id: 1,
            endpoint: .sopPrime,
            parentPortType: 0,
            parentPortNumber: 0,
            vendorID: 0x05AC,
            productID: 0,
            bcdDevice: 0,
            vdos: [],
            specRevision: 3
        )
        let payload = CableReport.payload(for: id)!
        let md = payload.markdown
        #expect(md.contains("### Raw VDOs") == false)
    }

    @Test("Markdown notes when the e-marker was not read")
    func markdownNotesUnreadEmarker() {
        // Endpoint present but no VDOs: the e-marker was not woken on this
        // connection. The report should say so, so a blank vendor ID is not
        // mistaken for a faulty or counterfeit cable.
        let id = USBPDSOP(
            id: 1,
            endpoint: .sopPrime,
            parentPortType: 0,
            parentPortNumber: 0,
            vendorID: 0,
            productID: 0,
            bcdDevice: 0,
            vdos: [],
            specRevision: 3
        )
        let md = CableReport.payload(for: id)!.markdown
        #expect(md.contains("e-marker was not read on this connection"))
        // The fingerprint rows must not show a bogus 0x0000: the identity was
        // not read, so they read "not read on this connection" too.
        #expect(md.contains("| Vendor ID | not read on this connection |"))
        #expect(md.contains("0x0000") == false)
    }

    // MARK: - USB-IF certification ID (from Cert Stat VDO)

    @Test("USB-IF cert ID present when non-zero")
    func usbIFCertIDPresentWhenNonZero() {
        let id = USBPDSOP(
            id: 1,
            endpoint: .sopPrime,
            parentPortType: 0,
            parentPortNumber: 0,
            vendorID: 0x05AC,
            productID: 0x1234,
            bcdDevice: 0,
            vdos: [
                (3 << 27) | UInt32(0x05AC),
                0x00012345,             // Cert Stat with XID
                0,
                (0b10 << 5) | 0b011 | (1 << 13)
            ],
            specRevision: 3
        )
        let payload = CableReport.payload(for: id)!
        #expect(payload.cable.usbifCertID == 0x00012345)
        let md = payload.markdown
        #expect(md.contains("USB-IF certification ID"))
        #expect(md.contains("0x00012345"))
    }

    @Test("USB-IF cert ID absent when zero")
    func usbIFCertIDAbsentWhenZero() {
        // Calibration: Anker #60 and Caldigit #62 both ship with XID = 0.
        // We surface that as "none" rather than a trust signal.
        let payload = CableReport.payload(for: cableIdentity())!
        #expect(payload.cable.usbifCertID == nil)
        let md = payload.markdown
        #expect(md.contains("USB-IF certification ID"))
        #expect(md.contains("none (XID = 0)"))
    }

    @Test("USB-IF cert ID distinguishes absent VDO from zero value")
    func usbIFCertIDDistinguishesAbsentVDOFromZeroValue() {
        // Identity with only an ID Header VDO -- macOS didn't surface a
        // Cert Stat. The fingerprint should record that explicitly,
        // not flatten it to "XID = 0", so calibration data stays
        // faithful to what the cable actually reported.
        let id = USBPDSOP(
            id: 1,
            endpoint: .sopPrime,
            parentPortType: 0,
            parentPortNumber: 0,
            vendorID: 0x05AC,
            productID: 0,
            bcdDevice: 0,
            vdos: [
                (3 << 27) | UInt32(0x05AC) // only ID Header, no Cert Stat
            ],
            specRevision: 3
        )
        let payload = CableReport.payload(for: id)!
        #expect(payload.cable.usbifCertID == nil)
        let md = payload.markdown
        #expect(md.contains("USB-IF certification ID"))
        #expect(md.contains("not provided by this Mac"))
        #expect(
            md.contains("none (XID = 0)") == false,
            "Missing VDO[1] must not be rendered the same as a real zero XID"
        )
    }

    // MARK: - CIO Thunderbolt link context

    @Test("Markdown includes CIO section when present")
    func markdownIncludesCIOSectionWhenPresent() {
        let cio = CIOCableCapability(
            id: 1,
            portKey: "2/0",
            cableGeneration: 2,
            negotiatedLinkSpeed: 3,
            generation: 3,
            asymmetricModeSupported: true,
            legacyAdapter: false,
            linkTrainingMode: 2
        )
        let payload = CableReport.payload(
            for: cableIdentity(),
            cioCapability: cio
        )!
        let md = payload.markdown
        #expect(md.contains("### Thunderbolt link context"))
        #expect(md.contains("CableGeneration"))
        #expect(md.contains("| `2` |"))
        #expect(md.contains("CableSpeed"))
        #expect(md.contains("| `3` |"))
        #expect(md.contains("Generation"))
        #expect(md.contains("AsymmetricModeSupported"))
        #expect(md.contains("| Yes |"))
        #expect(md.contains("LegacyAdapter"))
        #expect(md.contains("| No |"))
        #expect(md.contains("LinkTrainingMode"))
    }

    @Test("Markdown omits CIO section when absent")
    func markdownOmitsCIOSectionWhenAbsent() {
        let payload = CableReport.payload(for: cableIdentity())!
        let md = payload.markdown
        #expect(md.contains("### Thunderbolt link context") == false)
        #expect(md.contains("CableGeneration") == false)
    }

    @Test("CIO section omitted when all fields nil")
    func cioSectionOmittedWhenAllFieldsNil() {
        let cio = CIOCableCapability(
            id: 1,
            portKey: "2/0",
            cableGeneration: nil,
            negotiatedLinkSpeed: nil,
            generation: nil,
            asymmetricModeSupported: nil,
            legacyAdapter: nil,
            linkTrainingMode: nil
        )
        let payload = CableReport.payload(
            for: cableIdentity(),
            cioCapability: cio
        )!
        let md = payload.markdown
        #expect(
            md.contains("### Thunderbolt link context") == false,
            "All-nil CIO should not render an empty table"
        )
    }

    @Test("CIO section omits nil fields")
    func cioSectionOmitsNilFields() {
        // CIO with only negotiatedLinkSpeed set, everything else nil.
        let cio = CIOCableCapability(
            id: 1,
            portKey: "2/0",
            cableGeneration: nil,
            negotiatedLinkSpeed: 3,
            generation: nil,
            asymmetricModeSupported: nil,
            legacyAdapter: nil,
            linkTrainingMode: nil
        )
        let payload = CableReport.payload(
            for: cableIdentity(),
            cioCapability: cio
        )!
        let md = payload.markdown
        #expect(md.contains("### Thunderbolt link context"))
        #expect(md.contains("CableSpeed"))
        #expect(md.contains("CableGeneration") == false)
        #expect(md.contains("AsymmetricModeSupported") == false)
        #expect(md.contains("LinkTrainingMode") == false)
    }

    @Test("Markdown labels extra VDOs as Other")
    func markdownLabelsExtraVDOsAsOther() {
        // PD response can include up to 7 VDOs (ID Header + Cert Stat +
        // Product + up to 4 Product Type VDOs). Index 4 is Active Cable VDO2;
        // anything past that we label "Other" rather than guessing.
        let id = USBPDSOP(
            id: 1,
            endpoint: .sopPrime,
            parentPortType: 0,
            parentPortNumber: 0,
            vendorID: 0x05AC,
            productID: 0x1234,
            bcdDevice: 0,
            vdos: [
                (3 << 27) | UInt32(0x05AC),
                0,
                0,
                (0b10 << 5) | 0b011 | (1 << 13), // valid 1m latency
                0xDEADBEEF,
                0xCAFEBABE
            ],
            specRevision: 3
        )
        let payload = CableReport.payload(for: id)!
        let md = payload.markdown
        #expect(md.contains("`0xDEADBEEF`"))
        #expect(md.contains("`0xCAFEBABE`"))
        // Index 4 is now "Active Cable VDO2"; index 5 falls through to "Other".
        #expect(md.contains("Active Cable VDO2"))
        #expect(md.contains("Other"))
    }

    // MARK: - VDO role labels (spec Figure 6.5)

    @Test("vdoRoleLabel returns correct labels for indices 0 to 4")
    func vdoRoleLabelKnownIndices() {
        // USB PD R3.2 Figure 6.5: 0=ID Header, 1=Cert Stat, 2=Product,
        // 3=Cable (Passive Cable VDO or Active Cable VDO1), 4=Active Cable VDO2.
        #expect(CableReport.vdoRoleLabel(at: 0) == "ID Header")
        #expect(CableReport.vdoRoleLabel(at: 1) == "Cert Stat")
        #expect(CableReport.vdoRoleLabel(at: 2) == "Product")
        #expect(CableReport.vdoRoleLabel(at: 3) == "Cable")
        #expect(CableReport.vdoRoleLabel(at: 4) == "Active Cable VDO2")
    }

    @Test("vdoRoleLabel returns Other for indices 5 and above")
    func vdoRoleLabelUnknownIndices() {
        #expect(CableReport.vdoRoleLabel(at: 5) == "Other")
        #expect(CableReport.vdoRoleLabel(at: 6) == "Other")
        #expect(CableReport.vdoRoleLabel(at: 99) == "Other")
    }

    // MARK: - Type source

    /// The CalDigit 2M Thunderbolt 4 cable from issue #111: passive ID
    /// Header, VDO[3] bit 3 set, which is the layout contradiction.
    private func caldigitBitThreeSet() -> USBPDSOP {
        USBPDSOP(
            id: 1, endpoint: .sopPrime,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0x2B1D, productID: 0x1901, bcdDevice: 0x97,
            vdos: [0x1C002B1D, 0x00000000, 0x19010097, 0x3208485A],
            specRevision: 3
        )
    }

    private func port(activeCable: Bool?) -> USBCPort {
        USBCPort(
            id: 1, serviceName: "Port-USB-C@1", className: "AppleHPMInterfaceType10",
            portDescription: "Port-USB-C@1", portTypeDescription: "USB-C",
            portNumber: 1, connectionActive: true, activeCable: activeCable, opticalCable: nil,
            usbActive: nil, superSpeedActive: nil, usbModeType: nil, usbConnectString: nil,
            transportsSupported: ["CC", "CIO"], transportsActive: ["CIO"],
            transportsProvisioned: [],
            plugOrientation: nil, plugEventCount: nil, connectionCount: nil,
            overcurrentCount: nil, pinConfiguration: [:], powerCurrentLimits: [],
            firmwareVersion: nil, bootFlagsHex: nil, rawProperties: [:]
        )
    }

    @Test("Layout contradiction files as active, sourced to the contradiction")
    func layoutContradictionFilesAsActive() {
        let payload = CableReport.payload(for: caldigitBitThreeSet())!
        #expect(payload.cable.type == "active")
        #expect(payload.cable.typeSource == "layoutContradiction")
    }

    @Test("A port reporting an active cable sources the type to the controller")
    func portControllerSourcesTheType() {
        let payload = CableReport.payload(for: caldigitBitThreeSet(), port: port(activeCable: true))!
        #expect(payload.cable.type == "active")
        #expect(payload.cable.typeSource == "portController")
    }

    @Test("Markdown keeps the Type cell verbatim and adds a Type source row")
    func markdownAddsTypeSourceRow() {
        let markdown = CableReport.payload(for: caldigitBitThreeSet())!.markdown
        // sync-cable-reports.swift reads this cell verbatim, so it must not move.
        #expect(markdown.contains("| Type | active |"))
        #expect(markdown.contains("| Type source | e-marker layout contradiction |"))

        let viaPort = CableReport.payload(for: caldigitBitThreeSet(), port: port(activeCable: true))!.markdown
        #expect(viaPort.contains("| Type source | port controller |"))
    }

    @Test("An ordinary passive cable gets no Type source row")
    func ordinaryPassiveCableHasNoTypeSourceRow() {
        let payload = CableReport.payload(for: cableIdentity())!
        #expect(payload.cable.typeSource == "emarker")
        #expect(payload.markdown.contains("| Type | passive |"))
        #expect(!payload.markdown.contains("| Type source |"))
    }
}
