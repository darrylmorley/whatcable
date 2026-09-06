import Foundation
import Testing
@testable import WhatCableCore

/// Tests for `CableDB.certifications(forXID:)`
/// (`Sources/WhatCableCore/Database/CableDB.swift`), the offline USB-IF
/// certification lookup compiled into `whatcable.db` by
/// `scripts/build-cable-db.swift`.
///
/// Two layers:
///  - fixed anchors on cables whose USB-IF listing is stable (Anker's
///    certified 240 W cable, and Apple's deliberately-absent Thunderbolt
///    cable), giving a real present-vs-absent contrast so the suite can
///    actually fail, and
///  - a corpus sweep over the committed `01_walk_pd_tree.json` probe files,
///    proving the XID -> cert join runs over real hardware XIDs and that a
///    meaningful share of them resolve.
///
/// The anchors assert on data bundled in the repo's `whatcable.db`; they move
/// only if a rebuild pulls a materially different USB-IF registry, which is
/// why the assertions are ranges ("at least"), not exact counts.
@Suite("CableDB: certification (XID) lookup")
struct CableCertLookupTests {

    // XID 0x219C. Anker's USB-IF-certified 240 W / 40 Gbps cable, the sample
    // cable used throughout research/usb-if-registry.md. Four listings share
    // this XID (Luxshare / Elecom x2 / Anker rebrands); Anker's VID is 10522.
    private static let ankerXID: UInt32 = 0x0000_219C
    private static let ankerVID = 10522

    // XID 0x2600. Apple's Thunderbolt 3 cable. Apple certifies through Intel's
    // Thunderbolt scheme, not USB-IF, so this XID resolves to nothing. The
    // most-seen XID in the corpus, and the anchor that makes "present" mean
    // something.
    private static let appleAbsentXID: UInt32 = 0x0000_2600

    @Test("XID 0 returns no certifications")
    func zeroXIDIsEmpty() {
        #expect(CableDB.certifications(forXID: 0).isEmpty)
    }

    @Test("The database loaded a substantial cert set")
    func certSetLoaded() {
        // ~1,090 XIDs at build time. A large floor catches a DB that shipped
        // without the cable_certs table (which fails soft to zero).
        #expect(CableDB.certXIDCount >= 800)
    }

    @Test("A certified cable resolves, with its listings and vendor id")
    func registeredXIDResolves() {
        let certs = CableDB.certifications(forXID: Self.ankerXID)
        // Four rebrands today; assert "at least" so a new rebrand doesn't
        // break the test.
        #expect(certs.count >= 4)
        // Every listing on this XID passed certification.
        #expect(certs.allSatisfy { $0.status == "Pass" })
        // The per-XID vendor_id path populated at least one listing with
        // Anker's VID: proof the vendor join (not just the bulk list) worked.
        #expect(certs.contains { $0.vendorID == Self.ankerVID })
        // Provenance fields are populated, not blank.
        #expect(certs.allSatisfy { !$0.company.isEmpty })
    }

    @Test("An unregistered cable resolves to nothing")
    func unregisteredXIDIsEmpty() {
        // The contrast to registeredXIDResolves: if the lookup ever returned
        // rows for everything (e.g. a broken key), this would catch it.
        #expect(CableDB.certifications(forXID: Self.appleAbsentXID).isEmpty)
    }

    // MARK: - Corpus sweep

    private static let corpusRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // WhatCableCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("research/customer-probes")
    }()

    /// Every distinct non-zero Cert Stat XID reported by a cable (SOP')
    /// across the committed `01_walk_pd_tree.json` probe files. These are the
    /// XIDs real hardware sends us. Reads the committed distillation only, so
    /// it runs on a fresh clone with no raw re-fetch.
    private static let corpusCableXIDs: Set<UInt32> = {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: corpusRoot, includingPropertiesForKeys: nil
        ) else { return [] }

        var out: Set<UInt32> = []
        for folder in files {
            let probe = folder.appendingPathComponent("01_walk_pd_tree.json")
            guard let data = try? Data(contentsOf: probe),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = obj["output"] as? String else { continue }

            // Split into registry blocks; keep those whose own Description is a
            // cable plug (".../SOP'" or ".../SOP''", both of which the app's
            // `USBPDSOP.certStatVDO` reads), then take VDO[1], the Cert Stat
            // XID. Kept in lockstep with `corpusXIDs()` in
            // scripts/build-cable-db.swift, which seeds the build from the
            // same blocks.
            for block in text.components(separatedBy: "=== ") {
                guard let desc = firstDescription(in: block),
                      desc.hasSuffix("/SOP'") || desc.hasSuffix("/SOP''")
                else { continue }
                guard let xid = certStatXID(in: block), xid != 0 else { continue }
                out.insert(xid)
            }
        }
        return out
    }()

    /// The first `Description = "..."` value on its own line within a block.
    /// The closing quote is required, so a truncated line can't lose its last
    /// character and become a value that matches (`.../SOP'X` -> `.../SOP'`).
    private static func firstDescription(in block: String) -> String? {
        let prefix = "Description = \""
        for line in block.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix(prefix), t.hasSuffix("\""), t.count > prefix.count
            else { continue }
            return String(t.dropFirst(prefix.count).dropLast())
        }
        return nil
    }

    /// VDO[1] decoded as a little-endian UInt32 from a block's `VDOs = [ ... ]`
    /// list, mirroring `PDVDO.vdoFromData`'s byte order. Every token must be
    /// valid hex: dropping unparseable ones could leave four survivors that
    /// decode to a plausible but wrong XID.
    private static func certStatXID(in block: String) -> UInt32? {
        guard let range = block.range(of: "[1] <data 4 bytes: ") else { return nil }
        let after = block[range.upperBound...]
        guard let end = after.firstIndex(of: ">") else { return nil }
        let tokens = after[..<end].split(separator: " ")
        guard tokens.count == 4 else { return nil }
        var value: UInt32 = 0
        for (i, token) in tokens.enumerated() {
            guard let byte = UInt8(token, radix: 16) else { return nil }
            value |= UInt32(byte) << (8 * i)
        }
        return value
    }

    @Test("The join runs over every corpus cable XID without crashing")
    func corpusLookupIsTotal() {
        // Sanity that the corpus parsing found XIDs at all (guards against a
        // silently-empty sweep passing vacuously).
        #expect(Self.corpusCableXIDs.count >= 50)
        for xid in Self.corpusCableXIDs {
            // Every resolved listing must carry a status; never a half-built row.
            for cert in CableDB.certifications(forXID: xid) {
                #expect(!cert.status.isEmpty)
            }
        }
    }

    @Test("A real share of corpus cable XIDs resolve to a USB-IF listing")
    func corpusCoverageIsMeaningful() {
        let resolved = Self.corpusCableXIDs.filter {
            !CableDB.certifications(forXID: $0).isEmpty
        }
        // 55 of 85 resolve today (many real cables aren't USB-IF certified;
        // absence is normal). Was 44 of 85 until the build started seeding its
        // XID universe from the corpus as well as the bulk catalogue, which
        // recovered 11 certified cables the bulk list omits (Anker, Belkin,
        // Plugable and friends: see research/usb-if-registry.md). The floor
        // sits above the old 44 so dropping that seeding fails this test
        // rather than silently losing those cables again.
        #expect(resolved.count >= 50)
    }

    // MARK: - Presentation (PortSummary bullets)

    private func makePort() -> USBCPort {
        USBCPort(
            id: 1, serviceName: "Port-USB-C@1",
            className: "AppleHPMInterfaceType10",
            portDescription: "Port-USB-C@1", portTypeDescription: "USB-C",
            portNumber: 1, connectionActive: true,
            activeCable: true, opticalCable: nil, usbActive: nil,
            superSpeedActive: true, usbModeType: nil, usbConnectString: nil,
            transportsSupported: ["CC", "USB3"], transportsActive: ["USB3"],
            transportsProvisioned: [], plugOrientation: nil, plugEventCount: nil,
            connectionCount: nil, overcurrentCount: nil, pinConfiguration: [:],
            powerCurrentLimits: [], firmwareVersion: nil, bootFlagsHex: nil,
            rawProperties: [:]
        )
    }

    /// A cable e-marker (SOP') reporting the given VID and Cert Stat XID,
    /// correlated to `makePort()` (USB-C port type 2, port number 1) so the
    /// JSON formatter attaches it as that port's cable.
    private func cable(vid: Int, xid: UInt32) -> USBPDSOP {
        USBPDSOP(
            id: 99, endpoint: .sopPrime,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: vid, productID: 0, bcdDevice: 0,
            // VDO[0] ID Header (passive cable), VDO[1] Cert Stat = XID.
            vdos: [(3 << 27) | UInt32(vid & 0xFFFF), xid, 0, 0],
            specRevision: 0
        )
    }

    @Test("A certified cable shows a neutral USB-IF provenance bullet")
    func certifiedCableShowsBullet() {
        // Anker's XID + VID: certified, and the VID matches the certificate.
        let summary = PortSummary(
            port: makePort(),
            identities: [cable(vid: Self.ankerVID, xid: Self.ankerXID)]
        )
        #expect(
            summary.bullets.contains {
                $0.contains("USB-IF certified") && $0.contains("Manufacturer")
                    && $0.contains("Pass")
            },
            "expected a USB-IF certified bullet, got: \(summary.bullets)"
        )
        // VID matches a certificate holder -> the confirming line appears.
        #expect(summary.bullets.contains { $0.contains("matches the USB-IF certificate") })
        // Never the headline: certification is provenance detail only.
        #expect(!summary.headline.contains("USB-IF"))
    }

    @Test("An unregistered cable shows no certification bullet")
    func unregisteredCableShowsNoBullet() {
        // Apple VID + Apple's absent XID: no certification line at all.
        let summary = PortSummary(
            port: makePort(),
            identities: [cable(vid: 0x05AC, xid: Self.appleAbsentXID)]
        )
        #expect(!summary.bullets.contains { $0.contains("USB-IF certified") })
    }

    @Test("A cable with an unpublished cert ID shows the neutral registry note")
    func unpublishedCertIDShowsNote() {
        // Apple's XID is real (the cable advertises it) but USB-IF publishes
        // no listing. The note fires, naming the raw ID, and never claims a
        // fault.
        let summary = PortSummary(
            port: makePort(),
            identities: [cable(vid: 0x05AC, xid: Self.appleAbsentXID)]
        )
        // The note moves to the database group: under the old flat list it
        // read as a verdict on the cable, and it is really a limit of our
        // records. The raw ID gets no line of its own on the card; it lives
        // in the Pro diagnostics cable-identity section.
        #expect(
            summary.group(.emarker)?.lines.contains { $0.contains("Certification ID") } != true,
            "the raw certification ID must not appear on the card, got: \(summary.groups)"
        )
        #expect(
            summary.group(.database)?.lines.contains {
                $0.contains("isn't in our copy of the USB-IF registry") && $0.contains("0x2600")
            } == true,
            "expected the unresolved-ID note in the database group, got: \(summary.groups)"
        )
        // It is a note, not a certification claim, and never a fault word.
        #expect(!summary.bullets.contains { $0.contains("USB-IF certified") })
        #expect(!summary.headline.contains("registry"))
    }

    @Test("A cable that carries no cert ID at all stays silent")
    func noCertIDShowsNoNote() {
        // XID 0 means the cable never advertised an ID (the 64% majority). It
        // claimed nothing to check, so neither the certified line nor the
        // unpublished-ID note appears.
        let summary = PortSummary(
            port: makePort(),
            identities: [cable(vid: Self.ankerVID, xid: 0)]
        )
        #expect(!summary.bullets.contains { $0.contains("isn't in the public registry") })
        #expect(!summary.bullets.contains { $0.contains("USB-IF certified") })
    }

    @Test("A certified cable shows the certified line, not the unpublished note")
    func certifiedCableHasNoUnpublishedNote() {
        let summary = PortSummary(
            port: makePort(),
            identities: [cable(vid: Self.ankerVID, xid: Self.ankerXID)]
        )
        #expect(summary.bullets.contains { $0.contains("USB-IF certified") })
        #expect(!summary.bullets.contains { $0.contains("isn't in the public registry") })
    }

    @Test("A registered cable whose VID matches no listing shows the maker but no match line")
    func mismatchVIDShowsMakerNoMatchLine() {
        // Registered XID, but a VID that is not one of the certificate
        // holders (a rebrand flashing its own VID). We still name the maker;
        // we must NOT claim a match, and must never present the mismatch as
        // anything negative.
        let summary = PortSummary(
            port: makePort(),
            identities: [cable(vid: 0x1234, xid: Self.ankerXID)]
        )
        #expect(summary.bullets.contains { $0.contains("USB-IF certified") })
        #expect(!summary.bullets.contains { $0.contains("matches the USB-IF certificate") })
    }

    @Test("A zero-VID cable with a registered XID still shows the certification")
    func zeroVIDCertifiedCableShowsBullet() {
        // Cert is keyed by the XID, not the VID, so a zero-VID cable (common
        // in this repo) with a real XID must still show its certification.
        // This is exactly the case the old vendorID-gated code dropped.
        let summary = PortSummary(
            port: makePort(),
            identities: [cable(vid: 0, xid: Self.ankerXID)]
        )
        #expect(summary.bullets.contains { $0.contains("USB-IF certified") })
        // A zero VID can never "match" a certificate holder.
        #expect(!summary.bullets.contains { $0.contains("matches the USB-IF certificate") })
    }

    // MARK: - JSON output

    private func renderedCable(vid: Int, xid: UInt32) throws -> [String: Any]? {
        let json = try JSONFormatter.render(
            ports: [makePort()], sources: [],
            identities: [cable(vid: vid, xid: xid)], showRaw: false
        )
        let obj = try #require(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let ports = obj["ports"] as? [[String: Any]] ?? []
        return ports.first?["cable"] as? [String: Any]
    }

    @Test("JSON carries the certification object for a certified cable")
    func jsonCertificationAppears() throws {
        let cableObj = try renderedCable(vid: Self.ankerVID, xid: Self.ankerXID)
        let cert = try #require(
            cableObj?["certification"] as? [String: Any],
            "expected a certification object, got cable: \(String(describing: cableObj))")
        let listings = cert["listings"] as? [[String: Any]] ?? []
        #expect(listings.count >= 4)
        // The cable's own VID (Anker) is among the certificate holders.
        #expect(cert["vendorMatch"] as? Bool == true)
        #expect(listings.contains { ($0["company"] as? String)?.contains("Anker") == true })
        #expect(listings.contains { $0["vendorId"] as? Int == Self.ankerVID })
        #expect(listings.allSatisfy { ($0["status"] as? String) == "Pass" })
    }

    @Test("JSON omits certification for an unregistered cable")
    func jsonCertificationOmitted() throws {
        let cableObj = try renderedCable(vid: 0x05AC, xid: Self.appleAbsentXID)
        // The cable object still renders; it just has no certification key.
        #expect(cableObj != nil)
        #expect(cableObj?["certification"] == nil)
    }

    @Test("JSON carries the raw cert ID even when nothing resolves")
    func jsonCertIDPresentWhenUnregistered() throws {
        // The point of the field: an unpublished XID and no XID at all used to
        // look identical in every output the app produces, which is what sent a
        // beta tester to a hardware e-marker reader to find a number the app
        // already had (public discussion #475).
        let cableObj = try renderedCable(vid: 0x05AC, xid: Self.appleAbsentXID)
        #expect(cableObj?["certID"] as? String == "0x2600")
        // Still no listing: the raw ID is not a certification claim.
        #expect(cableObj?["certification"] == nil)
    }

    @Test("JSON carries the raw cert ID for a certified cable too")
    func jsonCertIDPresentWhenRegistered() throws {
        let cableObj = try renderedCable(vid: Self.ankerVID, xid: Self.ankerXID)
        #expect(cableObj?["certID"] as? String == "0x219C")
        #expect(cableObj?["certification"] != nil)
    }

    @Test("JSON omits the cert ID when the cable carries none")
    func jsonCertIDOmittedWhenZero() throws {
        // XID 0 means "this e-marker was never issued a certification ID",
        // which is 64% of corpus cables. Absence, not "0x0".
        let cableObj = try renderedCable(vid: Self.ankerVID, xid: 0)
        #expect(cableObj != nil)
        #expect(cableObj?["certID"] == nil)
    }

    @Test("The reported cert ID is the tester's cable, decoded from its own bytes")
    func jsonCertIDMatchesReportedCable() throws {
        // The Cable Matters / Lintes TB5 cable from discussion #475: VDO[1]
        // bytes "fc 05 00 00" little-endian = 0x5FC. Its ID is real but
        // unpublished by USB-IF, so this is the exact case the field explains.
        let bytes: [UInt8] = [0xFC, 0x05, 0x00, 0x00]
        var xid: UInt32 = 0
        for (i, byte) in bytes.enumerated() { xid |= UInt32(byte) << (8 * i) }
        #expect(xid == 0x5FC)
        let cableObj = try renderedCable(vid: 0x2B1D, xid: xid)
        #expect(cableObj?["certID"] as? String == "0x5FC")
        #expect(cableObj?["certification"] == nil)
    }

    @Test("JSON certification for a VID mismatch has vendorMatch false")
    func jsonCertificationMismatchVID() throws {
        let cableObj = try renderedCable(vid: 0x1234, xid: Self.ankerXID)
        let cert = try #require(cableObj?["certification"] as? [String: Any])
        #expect(cert["vendorMatch"] as? Bool == false)
        #expect((cert["listings"] as? [[String: Any]])?.isEmpty == false)
    }

    @Test("JSON certification renders for a zero-VID cable, vendorMatch false")
    func jsonCertificationZeroVID() throws {
        // Symmetry with the PortSummary zero-VID case: JSONFormatter already
        // showed certification for a zero-VID cable (it was never gated on
        // VID), and the != 0 guard keeps vendorMatch false rather than letting
        // a stray zero vendor_id ever confirm.
        let cableObj = try renderedCable(vid: 0, xid: Self.ankerXID)
        let cert = try #require(cableObj?["certification"] as? [String: Any])
        #expect(cert["vendorMatch"] as? Bool == false)
    }

    @Test("JSON reads the cert from the populated e-marker, not an empty one")
    func jsonPrefersPopulatedEmarker() throws {
        // A port can carry both an SOP' and an SOP''; if the first is an empty
        // (unread) e-marker, JSON must not let it shadow the populated one, or
        // it would omit the certification that PortSummary shows. Mirrors
        // PortSummary's own selection rule.
        let empty = USBPDSOP(
            id: 1, endpoint: .sopPrime,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: 0, productID: 0, bcdDevice: 0, vdos: [], specRevision: 0)
        let populated = USBPDSOP(
            id: 2, endpoint: .sopDoublePrime,
            parentPortType: 2, parentPortNumber: 1,
            vendorID: Self.ankerVID, productID: 0, bcdDevice: 0,
            vdos: [(3 << 27) | UInt32(Self.ankerVID & 0xFFFF), Self.ankerXID, 0, 0],
            specRevision: 0)
        let json = try JSONFormatter.render(
            ports: [makePort()], sources: [],
            identities: [empty, populated], showRaw: false)
        let obj = try #require(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let cableObj = (obj["ports"] as? [[String: Any]])?.first?["cable"] as? [String: Any]
        #expect(cableObj?["certification"] != nil,
            "expected the cert from the populated SOP'', got cable: \(String(describing: cableObj))")
    }

    // MARK: - Empty-company backstop (single choke point in CableDB)

    @Test("A listing with an empty company is dropped before any surface sees it")
    func emptyCompanyListingsAreDropped() {
        // A malformed / schema-changed registry row with a blank company would
        // otherwise render as a bogus "USB-IF certified. Manufacturer:" line.
        // `CableDB.displayable` is the one runtime choke point both PortSummary
        // and JSON go through, so filtering here protects both.
        let kept = CableCert(company: "Anker Innovations Limited",
                             model: "A8487011", status: "Pass",
                             certDate: "2022-01-14", vendorID: 10522)
        let dropped = CableCert(company: "", model: "X", status: "Pass",
                                certDate: "", vendorID: nil)
        let out = CableDB.displayable([dropped, kept, dropped])
        #expect(out.count == 1)
        #expect(out.first?.company == "Anker Innovations Limited")
    }

    @Test("Every certification the db actually serves has a non-empty company")
    func allServedCertsHaveCompany() {
        // Invariant on real data: the build-side validation plus the runtime
        // filter mean no empty-company listing is ever surfaced.
        for xid in Self.corpusCableXIDs {
            for cert in CableDB.certifications(forXID: xid) {
                #expect(!cert.company.isEmpty)
            }
        }
    }
}
