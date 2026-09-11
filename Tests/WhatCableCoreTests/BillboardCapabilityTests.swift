import Foundation
import Testing
@testable import WhatCableCore

@Suite("Billboard Capability Descriptor parsing")
struct BillboardCapabilityTests {

    // Real BOS descriptor bytes captured by the Test Kit probe
    // (research/customer-probes/.../25_usb_bos_descriptor.json). Using verbatim
    // corpus samples is the acceptance check for DAR-141.

    /// m2max_macos26.5: a dock advertising Thunderbolt then DisplayPort, both
    /// configured. Has SuperSpeed + Container ID caps ahead of the Billboard cap.
    private let m2maxBOS: [UInt8] = [
        0x05, 0x0f, 0x5d, 0x00, 0x04, 0x14, 0x10, 0x04, 0x00, 0x40, 0x33, 0x9d,
        0x16, 0xb0, 0x25, 0x7f, 0xa7, 0xff, 0x4b, 0x8a, 0xf1, 0xd2, 0x2c, 0xbd,
        0x7a, 0x34, 0x10, 0x0d, 0x04, 0x02, 0x00, 0x00, 0x80, 0x0f, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x21, 0x01, 0x00, 0x00, 0x87, 0x80, 0x00,
        0x05, 0x01, 0xff, 0x00, 0x06, 0x08, 0x10, 0x0f, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x08, 0x10, 0x0f, 0x01, 0x00, 0x00, 0x00, 0x00,
    ]

    /// m4_macos26.5_q: a device advertising DisplayPort in an *error* state
    /// (bmConfigured = 0x00). The Billboard cap is the first cap in the BOS.
    private let m4ErrorBOS: [UInt8] = [
        0x05, 0x0f, 0x49, 0x00, 0x02, 0x30, 0x10, 0x0d, 0x03, 0x01, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x01, 0x00,
        0x00, 0x01, 0xff, 0x01, 0x03, 0x14, 0x10, 0x04, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00,
    ]

    @Test("Parses Thunderbolt + DisplayPort, both configured")
    func parsesHealthyDock() throws {
        let cap = try #require(BillboardCapability.parse(bos: m2maxBOS))
        #expect(cap.altModes.count == 2)
        #expect(cap.altModes[0].svid == 0x8087)
        #expect(cap.altModes[0].protocolName == "Thunderbolt")
        #expect(cap.altModes[0].state == .configured)
        #expect(cap.altModes[1].svid == 0xFF01)
        #expect(cap.altModes[1].protocolName == "DisplayPort")
        #expect(cap.altModes[1].state == .configured)
        #expect(cap.advertisesDisplayPort)
        #expect(!cap.hasFailedAltMode)
        #expect(cap.namedProtocols == ["Thunderbolt", "DisplayPort"])
        #expect(cap.preferredIndex == 0)
    }

    @Test("Parses a DisplayPort Alt Mode in an error state")
    func parsesFailedDisplayPort() throws {
        let cap = try #require(BillboardCapability.parse(bos: m4ErrorBOS))
        #expect(cap.altModes.count == 1)
        #expect(cap.altModes[0].svid == 0xFF01)
        #expect(cap.altModes[0].state == .error)
        #expect(cap.advertisesDisplayPort)
        #expect(cap.hasFailedAltMode)
    }

    @Test("Returns nil for a BOS with no Billboard capability")
    func ignoresBOSWithoutBillboard() {
        // BOS header + a single USB 2.0 Extension cap (type 0x02), no 0x0d.
        let bos: [UInt8] = [
            0x05, 0x0f, 0x0c, 0x00, 0x01,
            0x07, 0x10, 0x02, 0x02, 0x00, 0x00, 0x00,
        ]
        #expect(BillboardCapability.parse(bos: bos) == nil)
    }

    @Test("Returns nil for empty or non-BOS bytes")
    func rejectsGarbage() {
        #expect(BillboardCapability.parse(bos: []) == nil)
        #expect(BillboardCapability.parse(bos: [0x05, 0x00, 0x00, 0x00, 0x00]) == nil)
    }

    @Test("Rejects a descriptor that claims more Alt Modes than it carries")
    func rejectsTruncatedDescriptor() {
        // 44-byte header + room for only one Alt Mode, but bNumberOfAlternateModes
        // claims three. A partial result would be misleading, so parse returns nil.
        var cap = [UInt8](repeating: 0, count: 48)
        cap[0] = 0x30          // bLength = 48
        cap[1] = 0x10          // DEVICE CAPABILITY
        cap[2] = 0x0d          // Billboard
        cap[4] = 3             // claims 3 alt modes
        cap[44] = 0x01         // one DisplayPort entry (0xFF01)
        cap[45] = 0xff
        var bos: [UInt8] = [0x05, 0x0f, UInt8(5 + cap.count), 0x00, 0x01]
        bos.append(contentsOf: cap)
        #expect(BillboardCapability.parse(bos: bos) == nil)
    }

    @Test("Only error / unsuccessful states count as failures")
    func failureStateSemantics() {
        #expect(BillboardCapability.AltModeState.error.isFailure)
        #expect(BillboardCapability.AltModeState.unsuccessful.isFailure)
        #expect(!BillboardCapability.AltModeState.notAttempted.isFailure)
        #expect(!BillboardCapability.AltModeState.configured.isFailure)
    }

    @Test("An out-of-range preferred index is dropped")
    func clampsPreferredIndex() {
        let one = BillboardCapability(altModes: [.init(svid: 0xFF01, state: .configured)],
                                      preferredIndex: 5)
        #expect(one.preferredIndex == nil)
    }

    @Test("Round-trips through Codable")
    func codableRoundTrip() throws {
        let original = try #require(BillboardCapability.parse(bos: m2maxBOS))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BillboardCapability.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - Registry keys (macOS's own decode)

    // The BOS control transfer is refused on every standalone Billboard node
    // in the corpus, but macOS publishes the decoded modes as UsbBillboard*
    // string properties on the same node. These cover that path.

    @Test("Registry: live Mac mini dock strings build the full table")
    func registryLiveDock() throws {
        let cap = try #require(BillboardCapability.fromRegistry(
            supportedModes: ["SVID 0xff00 VDO 0x2687e000", "Thunderbolt", "DisplayPort"],
            currentMode: "SVID 0xff00 VDO 0x2687e000",
            preferredMode: "SVID 0xff00 VDO 0x2687e000",
            altModeFailed: false,
            version: "1.22"))
        #expect(cap.altModes.count == 3)
        #expect(cap.altModes.map(\.svid) == [0xFF00, 0x8087, 0xFF01])
        #expect(cap.altModes.map(\.state) == [.configured, .notAttempted, .notAttempted])
        #expect(cap.preferredIndex == 0)
        #expect(cap.namedProtocols == ["USB", "Thunderbolt", "DisplayPort"])
        #expect(!cap.hasFailedAltMode)
        #expect(cap.advertisesDisplayPort)
    }

    @Test("Registry: the common corpus shape, DisplayPort only")
    func registryDisplayPortOnly() throws {
        let cap = try #require(BillboardCapability.fromRegistry(
            supportedModes: ["DisplayPort"],
            currentMode: "DisplayPort",
            preferredMode: "DisplayPort",
            altModeFailed: false,
            version: nil))
        #expect(cap.altModes.count == 1)
        #expect(cap.altModes[0].svid == 0xFF01)
        #expect(cap.altModes[0].state == .configured)
        #expect(cap.preferredIndex == 0)
    }

    @Test("Registry: AltModeFailed marks every mode as an error")
    func registryAltModeFailed() throws {
        let cap = try #require(BillboardCapability.fromRegistry(
            supportedModes: ["DisplayPort", "SVID 0x8087 VDO 0x00000000"],
            currentMode: nil,
            preferredMode: "SVID 0x8087 VDO 0x00000000",
            altModeFailed: true,
            version: nil))
        #expect(cap.altModes.map(\.state) == [.error, .error])
        #expect(cap.hasFailedAltMode)
        #expect(cap.preferredIndex == 1)
    }

    @Test("Registry: malformed entries are dropped, the rest survive")
    func registryDropsMalformed() throws {
        let cap = try #require(BillboardCapability.fromRegistry(
            supportedModes: ["DisplayPort", "garbage", "SVID zz VDO 0x0", ""],
            currentMode: nil,
            preferredMode: nil,
            altModeFailed: false,
            version: nil))
        #expect(cap.altModes.count == 1)
        #expect(cap.altModes[0].svid == 0xFF01)
    }

    @Test("Registry: nothing parseable means no table")
    func registryNothingParseable() {
        #expect(BillboardCapability.fromRegistry(
            supportedModes: ["garbage", ""],
            currentMode: nil, preferredMode: nil, altModeFailed: false, version: nil) == nil)
        #expect(BillboardCapability.fromRegistry(
            supportedModes: [],
            currentMode: nil, preferredMode: nil, altModeFailed: false, version: nil) == nil)
    }

    @Test("Registry: SVID 0x0000 is kept as an unnamed mode")
    func registryKeepsZeroSVID() throws {
        let cap = try #require(BillboardCapability.fromRegistry(
            supportedModes: ["SVID 0x0000 VDO 0x00000000"],
            currentMode: "SVID 0x0000 VDO 0x00000000",
            preferredMode: nil,
            altModeFailed: false,
            version: nil))
        #expect(cap.altModes.count == 1)
        #expect(cap.altModes[0].svid == 0)
        #expect(cap.altModes[0].state == .configured)
        #expect(cap.altModes[0].protocolName == nil)
    }

    @Test("Registry: current or preferred mode outside the list matches nothing")
    func registryUnlistedCurrentAndPreferred() throws {
        let cap = try #require(BillboardCapability.fromRegistry(
            supportedModes: ["DisplayPort", "Thunderbolt"],
            currentMode: "USB",
            preferredMode: "SVID 0xff00 VDO 0x0",
            altModeFailed: false,
            version: nil))
        #expect(cap.altModes.map(\.state) == [.notAttempted, .notAttempted])
        #expect(cap.preferredIndex == nil)
    }

    @Test("Registry: mode strings parse case-insensitively")
    func registryModeStringCase() {
        #expect(BillboardCapability.registryModeSVID("svid 0xFF01 vdo 0x0") == 0xFF01)
        #expect(BillboardCapability.registryModeSVID("displayport") == 0xFF01)
        #expect(BillboardCapability.registryModeSVID("SVID 0xff00 VDO 0x2687e000") == 0xFF00)
        #expect(BillboardCapability.registryModeSVID("Thunderbolt") == 0x8087)
        #expect(BillboardCapability.registryModeSVID("SVID zz VDO 0x0") == nil)
        #expect(BillboardCapability.registryModeSVID("") == nil)
    }
}
