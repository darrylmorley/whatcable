import Foundation
import Testing
@testable import WhatCableCore

/// Unit tests for `ChainDeviceAttribution`
/// (`Sources/WhatCableCore/Devices/ChainDeviceAttribution.swift`): which
/// Thunderbolt chain device each USB device sits inside.
///
/// This is inference, so most of these tests are about it NOT firing. The
/// requirement they exist to hold is "anything unattributable hangs at chain
/// level with no guessed parent": a device shown inside the wrong dock is worse
/// than a flat list, because the flat list at least does not lie.
///
/// The corpus sweep in `ChainAttributionProbeSweepTests` replays the same
/// resolver over every probe-29 + probe-38 pair on disk. Two of the guards here
/// exist because that sweep found real counterexamples, and the counterexample
/// folder is named in each.
@Suite("ChainDeviceAttribution")
struct ChainDeviceAttributionTests {

    // MARK: - Fixtures

    private func chainSwitch(
        id: Int64,
        parent: Int64?,
        vendor: String,
        model: String,
        depth: Int,
        dromVendorID: Int? = nil,
        dromModelID: Int? = nil
    ) -> IOThunderboltSwitch {
        IOThunderboltSwitch(
            id: id,
            className: "IOThunderboltSwitchIntelJHL9580",
            vendorID: 0x8086,
            vendorName: vendor,
            modelName: model,
            routerID: 1,
            depth: depth,
            routeString: Int64(depth),
            upstreamPortNumber: 1,
            maxPortNumber: 12,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xE),
            ports: [],
            parentSwitchUID: parent,
            dromVendorID: dromVendorID,
            dromModelID: dromModelID
        )
    }

    private func device(
        id: UInt64,
        locationID: UInt32,
        vendorID: UInt16,
        productID: UInt16 = 0x1234,
        vendor: String?,
        product: String?,
        isHub: Bool
    ) -> USBDevice {
        USBDevice(
            id: id,
            locationID: locationID,
            vendorID: vendorID,
            productID: productID,
            vendorName: vendor,
            productName: product,
            serialNumber: nil,
            usbVersion: nil,
            speedRaw: 3,
            busPowerMA: nil,
            currentMA: nil,
            deviceClass: isHub ? 0x09 : 0x00,
            rawProperties: [:]
        )
    }

    /// Host root -> dock. `ThunderboltTopology.tree` numbers the first hop
    /// depth 0, so the dock is the only chain node here.
    private func oneDeviceChain() -> [IOThunderboltSwitchNode] {
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let dock = chainSwitch(id: 200, parent: 100, vendor: "Ugreen", model: "TBT5 Dock", depth: 1)
        return ThunderboltTopology.tree(from: root, in: [root, dock])
    }

    /// Host root -> display -> dock, the reference machine's shape.
    private func twoDeviceChain(
        displayModel: String = "Studio Display ",
        dockModel: String = "TBT5 Docking Station 10-in-1"
    ) -> [IOThunderboltSwitchNode] {
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let display = chainSwitch(id: 200, parent: 100, vendor: "Apple", model: displayModel, depth: 1)
        let dock = chainSwitch(id: 300, parent: 200, vendor: "Ugreen Group Limited", model: dockModel, depth: 2)
        return ThunderboltTopology.tree(from: root, in: [root, display, dock])
    }

    private func resolve(_ chain: [IOThunderboltSwitchNode], _ devices: [USBDevice]) -> ChainDeviceAttribution {
        ChainDeviceAttribution.resolve(chain: chain, forest: USBDeviceNode.buildTree(from: devices))
    }

    /// A tunnelled USB device: carries `isThunderboltTunnelled` and
    /// `tunnelBridgeDepth`, with no product name by default, since the whole
    /// point of the structural join is placing devices a name cannot (a
    /// Studio Display's internal "USB2 Hub" persona names nothing about the
    /// display).
    private func tunnelledDevice(
        id: UInt64,
        locationID: UInt32,
        bridgeDepth: Int,
        product: String? = nil,
        isHub: Bool,
        tunnelRootName: String? = "apciec2"
    ) -> USBDevice {
        USBDevice(
            id: id,
            locationID: locationID,
            vendorID: 0x05AC,
            productID: 0x1234,
            vendorName: nil,
            productName: product,
            serialNumber: nil,
            usbVersion: nil,
            speedRaw: 3,
            busPowerMA: nil,
            currentMA: nil,
            isThunderboltTunnelled: true,
            tunnelBridgeDepth: bridgeDepth,
            tunnelRootName: tunnelRootName,
            // These fixtures model captured AppleUSBXHCITR ancestry, so the
            // carrier is set explicitly: the structural join now requires a
            // known carrier, and nil (unknown) deliberately joins nothing.
            tunnelCarrier: .usbTunnel,
            deviceClass: isHub ? 0x09 : 0x00,
            rawProperties: [:]
        )
    }

    // MARK: - The name match

    @Test("A device named exactly like a chain device IS that device, so it is absorbed")
    func exactNameAbsorbs() {
        let devices = [
            device(id: 1, locationID: 0x0310_0000, vendorID: 0x1D5C, vendor: "Fresco Logic, Inc.", product: "USB2.0 Hub", isHub: true),
            device(id: 2, locationID: 0x0311_0000, vendorID: 0x2B89, vendor: "UGREEN", product: "TBT5 Dock", isHub: false),
        ]
        let result = resolve(oneDeviceChain(), devices)
        #expect(result.absorbed == [2], "The dock's own USB identity endpoint should be absorbed into the chain row")
        #expect(result.regionRoots[1] == 200, "Its parent hub is the dock's upstream hub")
        #expect(result.regionOwner[1] == 200)
        #expect(result.regionOwner[2] == 200)
    }

    @Test("A device named like PART of a chain device marks its hub but is never absorbed")
    func affiliateMarksWithoutAbsorbing() {
        // CalDigit's whole TS line: the fabric reports "TS5", the USB
        // descriptors only ever say "TS5 USB 3 Hub" or "CalDigit TS5 Audio -
        // Rear", so exact equality recognises the dock never, on any machine.
        // Absorbing on a loose match would be a different bug: the audio
        // endpoint is a real thing inside the dock, and deleting it from the
        // tree is not de-duplication.
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let dock = chainSwitch(id: 200, parent: 100, vendor: "CalDigit", model: "TS5", depth: 1)
        let chain = ThunderboltTopology.tree(from: root, in: [root, dock])
        let devices = [
            device(id: 1, locationID: 0x0310_0000, vendorID: 0x2109, vendor: "VIA Labs, Inc.", product: "TS5 USB 3 Hub", isHub: true),
            device(id: 2, locationID: 0x0311_0000, vendorID: 0x0D8C, vendor: "CalDigit", product: "CalDigit TS5 Audio - Rear", isHub: false),
        ]
        let result = resolve(chain, devices)
        #expect(result.absorbed.isEmpty, "A partial name match must not delete a device from the tree")
        #expect(result.regionOwner[1] == 200)
        #expect(result.regionOwner[2] == 200)
    }

    @Test("Word runs match in both directions, and only on whole words")
    func affiliateMatchesWholeWordsOnly() {
        #expect(ChainDeviceAttribution.affiliated(product: "TS5 USB 3 Hub", model: "TS5"))
        #expect(ChainDeviceAttribution.affiliated(product: "Apple Thunderbolt Display", model: "Thunderbolt Display"))
        #expect(ChainDeviceAttribution.affiliated(product: "WD_BLACK D50", model: "WD_BLACK D50 Game Dock"))
        #expect(ChainDeviceAttribution.affiliated(product: "Microsoft Surface Thunderbolt(TM) 4 Dock Audio", model: "Surface Thunderbolt(TM) 4 Dock"))
        // A short model name inside an unrelated word is the reason this is
        // word-level and not `contains`.
        #expect(!ChainDeviceAttribution.affiliated(product: "ATS5000 Scanner", model: "TS5"))
        #expect(!ChainDeviceAttribution.affiliated(product: "Docking Station", model: "Dock"))
        #expect(!ChainDeviceAttribution.affiliated(product: "Thunderbolt 4 Hub", model: "Thunderbolt 4 Dock"))
        // Non-contiguous words are not a match: the run has to be intact.
        #expect(!ChainDeviceAttribution.affiliated(product: "TS5 Fancy USB Hub", model: "TS5 USB Hub"))
    }

    @Test("Two chain devices with the same model name match neither")
    func duplicateModelNamesMatchNothing() {
        // Two identical daisy-chained displays: "UltraFine 4K" twice in the
        // corpus (`intel_corei9_9980hk_macos26.5.2`, `m2max_macos26.5.2_c`).
        // Nothing in the USB descriptors says which one a device is behind.
        let chain = twoDeviceChain(displayModel: "UltraFine 4K", dockModel: "UltraFine 4K")
        let devices = [
            device(id: 1, locationID: 0x0310_0000, vendorID: 0x05AC, vendor: "Apple", product: "USB2.0 Hub", isHub: true),
            device(id: 2, locationID: 0x0311_0000, vendorID: 0x043E, vendor: "LG", product: "UltraFine 4K", isHub: false),
        ]
        let result = resolve(chain, devices)
        #expect(result.absorbed.isEmpty)
        #expect(result.regionRoots.isEmpty)
        #expect(result.regionOwner.isEmpty, "An ambiguous name must place nothing at all")
    }

    @Test("A name shorter than three characters is not a name")
    func shortNamesDoNotMatch() {
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let dock = chainSwitch(id: 200, parent: 100, vendor: "Some", model: "X5", depth: 1)
        let chain = ThunderboltTopology.tree(from: root, in: [root, dock])
        let devices = [
            device(id: 1, locationID: 0x0310_0000, vendorID: 0x2109, vendor: "VIA", product: "X5", isHub: false)
        ]
        #expect(resolve(chain, devices).regionOwner.isEmpty)
    }

    // MARK: - The guards

    @Test("A hub claimed by two different chain devices is claimed by neither")
    func sharedHubClaimsNothing() {
        // Corpus counterexample: `m4_macos26.5.2_x`, an Echo 13 Thunderbolt 5
        // SSD Dock with an Envoy Ultra chained behind it, both exposing their
        // identity endpoint on the SAME hub. The hub is therefore upstream of
        // both, and an earlier draft that let the deeper device win moved five
        // of that machine's endpoints inside a bare SSD.
        let chain = twoDeviceChain(displayModel: "Echo 13 Thunderbolt 5 SSD Dock", dockModel: "Envoy Ultra")
        let devices = [
            device(id: 1, locationID: 0x0310_0000, vendorID: 0x1D5C, vendor: "Fresco Logic, Inc.", product: "USB2.0 Hub", isHub: true),
            device(id: 2, locationID: 0x0311_0000, vendorID: 0x1E91, vendor: "OWC", product: "Echo 13 Thunderbolt 5 SSD Dock", isHub: false),
            device(id: 3, locationID: 0x0312_0000, vendorID: 0x1E91, vendor: "OWC", product: "Envoy Ultra", isHub: false),
            device(id: 4, locationID: 0x0313_0000, vendorID: 0x0BDA, vendor: "Realtek", product: "USB 10/100/1000 LAN", isHub: false),
        ]
        let result = resolve(chain, devices)
        #expect(result.regionRoots.isEmpty, "The shared hub must not be marked for either device")
        #expect(result.absorbed == [2, 3], "Both are still their own chain device, so both are still absorbed")
        #expect(result.regionOwner[4] == nil, "The LAN adapter must not be handed a guessed parent")
    }

    @Test("Vendor continuity places a device by its hub vendor when every chain device is matched")
    func vendorContinuityPlacesTheEthernetAdapter() {
        // The reference machine's shape, reduced: the dock's USB2 subtree is
        // anchored, its USB3 subtree is not, and the two are linked only by both
        // containing VIA Labs hubs.
        let chain = twoDeviceChain()
        let devices = [
            device(id: 1, locationID: 0x0310_0000, vendorID: 0x05AC, vendor: "Apple", product: "USB2.0 Hub", isHub: true),
            device(id: 2, locationID: 0x0313_0000, vendorID: 0x05AC, vendor: "Apple Inc.", product: "Studio Display", isHub: false),
            device(id: 3, locationID: 0x0312_0000, vendorID: 0x1D5C, vendor: "Fresco Logic, Inc.", product: "USB2.0 Hub", isHub: true),
            device(id: 4, locationID: 0x0312_1000, vendorID: 0x2B89, vendor: "UGREEN", product: "TBT5 Docking Station 10-in-1", isHub: false),
            device(id: 5, locationID: 0x0312_4000, vendorID: 0x2109, vendor: "VIA Labs, Inc.", product: "USB2.0 Hub", isHub: true),
            // The unanchored USB3 branch.
            device(id: 6, locationID: 0x0320_0000, vendorID: 0x8087, vendor: "Intel Corporation", product: "USB3 HUB", isHub: true),
            device(id: 7, locationID: 0x0321_4000, vendorID: 0x2109, vendor: "VIA Labs, Inc.", product: "USB3.1 Hub", isHub: true),
            device(id: 8, locationID: 0x0321_4100, vendorID: 0x0BDA, vendor: "Realtek", product: "USB 10/100/1000 LAN", isHub: false),
        ]
        let result = resolve(chain, devices)
        #expect(result.allAnchored)
        #expect(result.regionOwner[7] == 300, "A VIA Labs hub is only in the dock's vendor set")
        #expect(result.regionOwner[8] == 300, "So the adapter behind it inherits the dock")
        #expect(result.regionOwner[6] == nil, "Intel is in nobody's set, so the hub above stays put")
        #expect(result.regionRoots[7] == 300, "Vendor continuity marks a region, so the expanded view agrees")
    }

    @Test("Vendor continuity is off entirely unless every chain device is matched")
    func vendorContinuityNeedsEveryChainDeviceMatched() {
        // Vendor sets are built only from matched regions, so an unmatched chain
        // device contributes nothing at all. A device inside it would then be
        // handed to the matched device purely for being the only candidate with
        // a set, which is not discrimination. VIA Labs, Genesys Logic, Terminus
        // and Fresco Logic hubs are inside nearly every dock, so this is the
        // common case rather than an edge one.
        let chain = twoDeviceChain(displayModel: "Some Unnamed Dock")
        let devices = [
            device(id: 3, locationID: 0x0312_0000, vendorID: 0x1D5C, vendor: "Fresco Logic, Inc.", product: "USB2.0 Hub", isHub: true),
            device(id: 4, locationID: 0x0312_1000, vendorID: 0x2B89, vendor: "UGREEN", product: "TBT5 Docking Station 10-in-1", isHub: false),
            device(id: 5, locationID: 0x0312_4000, vendorID: 0x2109, vendor: "VIA Labs, Inc.", product: "USB2.0 Hub", isHub: true),
            device(id: 7, locationID: 0x0321_4000, vendorID: 0x2109, vendor: "VIA Labs, Inc.", product: "USB3.1 Hub", isHub: true),
            device(id: 8, locationID: 0x0321_4100, vendorID: 0x0BDA, vendor: "Realtek", product: "USB 10/100/1000 LAN", isHub: false),
        ]
        let result = resolve(chain, devices)
        #expect(!result.allAnchored, "One chain device has no matching USB device")
        #expect(result.regionOwner[7] == nil, "The unanchored VIA hub must stay unplaced")
        #expect(result.regionOwner[8] == nil)
        #expect(result.regionOwner[3] == 300, "The structural pass is unaffected and still places the dock's own subtree")
    }

    @Test("A vendor in two chain devices' regions places nothing")
    func ambiguousVendorPlacesNothing() {
        let chain = twoDeviceChain(displayModel: "Alpha Dock", dockModel: "Beta Dock")
        let devices = [
            // Both docks' anchored regions contain a VIA Labs hub.
            device(id: 1, locationID: 0x0310_0000, vendorID: 0x2109, vendor: "VIA Labs, Inc.", product: "USB2.0 Hub", isHub: true),
            device(id: 2, locationID: 0x0311_0000, vendorID: 0x1111, vendor: "Alpha", product: "Alpha Dock", isHub: false),
            device(id: 3, locationID: 0x0320_0000, vendorID: 0x2109, vendor: "VIA Labs, Inc.", product: "USB2.0 Hub", isHub: true),
            device(id: 4, locationID: 0x0321_0000, vendorID: 0x2222, vendor: "Beta", product: "Beta Dock", isHub: false),
            // A third VIA hub in neither region: the vendor cannot discriminate.
            device(id: 5, locationID: 0x0330_0000, vendorID: 0x2109, vendor: "VIA Labs, Inc.", product: "USB3.1 Hub", isHub: true),
            device(id: 6, locationID: 0x0331_0000, vendorID: 0x0BDA, vendor: "Realtek", product: "USB 10/100/1000 LAN", isHub: false),
        ]
        let result = resolve(chain, devices)
        #expect(result.allAnchored)
        #expect(result.regionOwner[5] == nil, "VIA Labs is in both regions, so it decides nothing")
        #expect(result.regionOwner[6] == nil)
    }

    @Test("The structural pass always wins over vendor continuity")
    func structuralBeatsVendor() {
        // A hub inside the display's anchored region whose vendor belongs to the
        // dock's set. Structure is direct evidence and the vendor is not, so the
        // hub must stay with the display.
        let chain = twoDeviceChain()
        let devices = [
            device(id: 1, locationID: 0x0310_0000, vendorID: 0x05AC, vendor: "Apple", product: "USB2.0 Hub", isHub: true),
            device(id: 2, locationID: 0x0313_0000, vendorID: 0x05AC, vendor: "Apple Inc.", product: "Studio Display", isHub: false),
            device(id: 3, locationID: 0x0311_0000, vendorID: 0x2109, vendor: "VIA Labs, Inc.", product: "USB2.0 Hub", isHub: true),
            device(id: 4, locationID: 0x0320_0000, vendorID: 0x1D5C, vendor: "Fresco Logic, Inc.", product: "USB2.0 Hub", isHub: true),
            device(id: 5, locationID: 0x0321_0000, vendorID: 0x2B89, vendor: "UGREEN", product: "TBT5 Docking Station 10-in-1", isHub: false),
            device(id: 6, locationID: 0x0322_0000, vendorID: 0x2109, vendor: "VIA Labs, Inc.", product: "USB3.1 Hub", isHub: true),
        ]
        let result = resolve(chain, devices)
        #expect(result.regionOwner[3] == 200, "Nested inside the display's marked hub, so it is the display's")
    }

    @Test("Vendor continuity stays off when a chain device matched a name but holds no region")
    func vendorGateKeysOnRegionsNotNames() {
        // Found by an adversarial review, and it is the shared-hub guard being
        // walked around rather than broken. Three chain devices: Alpha and Beta
        // both name endpoints on ONE hub, so that hub is claimed by two and
        // marked for neither; Gamma is cleanly matched elsewhere. Every chain
        // device has a name match, so a gate keyed on matches passes, and vendor
        // continuity then sees the disputed hub's VIA Labs vendor in Gamma's
        // region (the only region there is) and hands it, plus everything
        // physically inside Alpha and Beta, to Gamma.
        //
        // The gate keys on RESOLVED REGIONS instead: Alpha and Beta hold none, so
        // it never opens.
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let alpha = chainSwitch(id: 200, parent: 100, vendor: "OWC", model: "Alpha Dock", depth: 1)
        let beta = chainSwitch(id: 300, parent: 200, vendor: "OWC", model: "Beta Dock", depth: 2)
        let gamma = chainSwitch(id: 400, parent: 300, vendor: "Other", model: "Gamma Dock", depth: 3)
        let chain = ThunderboltTopology.tree(from: root, in: [root, alpha, beta, gamma])
        let devices = [
            // The disputed hub, with both docks' identity endpoints on it.
            device(id: 1, locationID: 0x0310_0000, vendorID: 0x2109, vendor: "VIA Labs, Inc.", product: "USB3.1 Hub", isHub: true),
            device(id: 2, locationID: 0x0311_0000, vendorID: 0x1E91, vendor: "OWC", product: "Alpha Dock", isHub: false),
            device(id: 3, locationID: 0x0312_0000, vendorID: 0x1E91, vendor: "OWC", product: "Beta Dock", isHub: false),
            // A real endpoint inside one of them, which must not move.
            device(id: 6, locationID: 0x0313_0000, vendorID: 0x0BDA, vendor: "Realtek", product: "USB 10/100/1000 LAN", isHub: false),
            // Gamma's region, whose hub shares the disputed hub's vendor.
            device(id: 4, locationID: 0x0320_0000, vendorID: 0x2109, vendor: "VIA Labs, Inc.", product: "USB2.0 Hub", isHub: true),
            device(id: 5, locationID: 0x0321_0000, vendorID: 0x2222, vendor: "Other", product: "Gamma Dock", isHub: false),
        ]
        let result = resolve(chain, devices)
        #expect(!result.allAnchored, "Alpha and Beta matched a name but hold no region, so the gate must stay shut")
        #expect(result.regionOwner[1] == nil, "The disputed hub belongs to none of them")
        #expect(result.regionOwner[6] == nil, "And nothing under it may be handed to Gamma")
        #expect(result.regionRoots[4] == 400, "Gamma's own region is unaffected")
    }

    @Test("A hub two chain devices both named stays unowned even when the vendor gate opens")
    func contestedHubIsOffLimitsToVendorContinuity() {
        // The re-verification finding, and the reason the region-based gate alone
        // was not enough. Alpha and Beta both name endpoints on hub 1, so it is
        // marked for neither. They ALSO each hold a second region elsewhere, so
        // every chain device holds a region and the vendor gate opens honestly.
        // Hub 1 is still unowned, which is exactly what vendor continuity looks
        // for, and its VIA Labs vendor appears only in Gamma's region: so it, and
        // the Ethernet adapter inside it, went to a dock they have nothing to do
        // with.
        //
        // Refusing to mark a disputed hub is only half a guard. Where the
        // ambiguity was seen has to stay on the record, and the whole subtree
        // under it is off limits to vendor evidence, because every device down
        // there is inside one of the two contenders and nothing says which.
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let alpha = chainSwitch(id: 200, parent: 100, vendor: "OWC", model: "Alpha Dock", depth: 1)
        let beta = chainSwitch(id: 300, parent: 200, vendor: "OWC", model: "Beta Dock", depth: 2)
        let gamma = chainSwitch(id: 400, parent: 300, vendor: "Other", model: "Gamma Dock", depth: 3)
        let chain = ThunderboltTopology.tree(from: root, in: [root, alpha, beta, gamma])
        let devices = [
            // The disputed hub, both docks' identity endpoints on it, and a real
            // device inside it that shares the hub's vendor so it would also be
            // claimed if the subtree were not off limits.
            device(id: 1, locationID: 0x0310_0000, vendorID: 0x2109, vendor: "VIA Labs, Inc.", product: "USB3.1 Hub", isHub: true),
            device(id: 2, locationID: 0x0311_0000, vendorID: 0x1E91, vendor: "OWC", product: "Alpha Dock", isHub: false),
            device(id: 3, locationID: 0x0312_0000, vendorID: 0x1E91, vendor: "OWC", product: "Beta Dock", isHub: false),
            device(id: 6, locationID: 0x0313_0000, vendorID: 0x2109, vendor: "VIA Labs, Inc.", product: "USB 10/100/1000 LAN", isHub: false),
            // Gamma's region, whose hub shares the disputed hub's vendor.
            device(id: 4, locationID: 0x0320_0000, vendorID: 0x2109, vendor: "VIA Labs, Inc.", product: "USB2.0 Hub", isHub: true),
            device(id: 5, locationID: 0x0321_0000, vendorID: 0x3333, vendor: "Other", product: "Gamma Dock", isHub: false),
            // The second region each contender needs for the gate to open.
            device(id: 7, locationID: 0x0330_0000, vendorID: 0x1111, vendor: "Someone", product: "USB2.0 Hub", isHub: true),
            device(id: 8, locationID: 0x0331_0000, vendorID: 0x1E91, vendor: "OWC", product: "Alpha Dock", isHub: false),
            device(id: 9, locationID: 0x0340_0000, vendorID: 0x2222, vendor: "Someone", product: "USB2.0 Hub", isHub: true),
            device(id: 10, locationID: 0x0341_0000, vendorID: 0x1E91, vendor: "OWC", product: "Beta Dock", isHub: false),
        ]
        let result = resolve(chain, devices)
        #expect(result.allAnchored, "Every chain device does hold a region here, so the gate opens")
        #expect(result.regionOwner[1] == nil, "The disputed hub must belong to none of them")
        #expect(result.regionOwner[6] == nil, "Nor may anything inside it be claimed on vendor evidence")
        #expect(result.regionRoots[4] == 400, "Gamma's own region is untouched")
        #expect(result.regionRoots[7] == 200, "And so is Alpha's second region")
    }

    @Test("A disputed hub inside an anchored region still inherits that region, and that is correct")
    func contestedSubtreeStillInheritsItsEnclosingRegion() {
        // Raised in review as a third wrong-parent route and REJECTED after
        // working through what the two attributions actually claim. Pinned here so
        // nobody "fixes" it later.
        //
        // Shape: the display is exactly matched, and inside its region sits a hub
        // that two chained docks both name, so that hub is marked for neither.
        // Plain inheritance then gives the hub, and everything under it, to the
        // display.
        //
        // That is not a wrong parent. A region root is the hub a chain device's
        // own identity endpoint hangs off, which is that device's upstream hub, so
        // everything below it reaches the Mac THROUGH that device. Both docks are
        // chained behind the display, so a device inside either of them is inside
        // the display too. The row says "this is behind the Studio Display", and
        // it is: one level less precise than naming the dock, and true.
        //
        // The two real bugs this is often mistaken for said something false
        // instead: they put a device inside a chain device that does NOT enclose it
        // (a sibling dock, an unrelated third device). True-but-less-precise and
        // false are not the same finding, and only the second is worth degrading
        // for. The ticket's own requirement, "anything unattributable hangs at
        // chain level", is this behaviour.
        //
        // What blocking inheritance would actually do, measured rather than
        // assumed (the first version of this comment claimed "nothing", which was
        // wrong for the collapsed view and was corrected in review):
        //
        //  - expanded: nothing, genuinely. `nestedRows` reads direct marks and the
        //    absorbed set, never `regionOwner`, so the rendering is unchanged.
        //  - collapsed: the row would move to the leftover group, which is
        //    appended after every chain device's rows rather than inline, and it
        //    would keep its "via N hubs" suffix, since only the leftover group is
        //    rendered with hop counts.
        //
        // So there IS a residual, and it is the second bullet: an inherited row
        // shows no hop count, which reads more definite than the evidence behind
        // it. The device is genuinely inside the display, but two docks were
        // candidates and neither could be ruled in. The honest marker would be
        // "ownership was inherited across a contested boundary", which is narrower
        // than "inherited" (the reference machine's Ethernet adapter is inherited
        // too, from its hub's vendor mark, and there the dock IS the most specific
        // answer, which is why its row correctly carries no suffix).
        //
        // Not built, deliberately: no corpus machine has this shape at all (one
        // contested hub exists in 84 chains, and it is not nested inside another
        // chain device's region), and getting the condition subtly wrong would put
        // a suffix on the reference machine's approved output. Left as a follow-up
        // rather than guessed at here.
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let display = chainSwitch(id: 200, parent: 100, vendor: "Apple", model: "Studio Display", depth: 1)
        let dockOne = chainSwitch(id: 300, parent: 200, vendor: "OWC", model: "Alpha Dock", depth: 2)
        let dockTwo = chainSwitch(id: 400, parent: 300, vendor: "OWC", model: "Beta Dock", depth: 3)
        let chain = ThunderboltTopology.tree(from: root, in: [root, display, dockOne, dockTwo])
        let devices = [
            // The display's own hub and identity endpoint: an exact match.
            device(id: 1, locationID: 0x0310_0000, vendorID: 0x05AC, vendor: "Apple", product: "USB2.0 Hub", isHub: true),
            device(id: 2, locationID: 0x0311_0000, vendorID: 0x05AC, vendor: "Apple Inc.", product: "Studio Display", isHub: false),
            // Nested inside it: a hub both docks name, so marked for neither.
            device(id: 3, locationID: 0x0312_0000, vendorID: 0x2109, vendor: "VIA Labs, Inc.", product: "USB3.1 Hub", isHub: true),
            device(id: 4, locationID: 0x0312_1000, vendorID: 0x1E91, vendor: "OWC", product: "Alpha Dock", isHub: false),
            device(id: 5, locationID: 0x0312_2000, vendorID: 0x1E91, vendor: "OWC", product: "Beta Dock", isHub: false),
            device(id: 6, locationID: 0x0312_3000, vendorID: 0x0BDA, vendor: "Realtek", product: "USB 10/100/1000 LAN", isHub: false),
        ]
        let result = resolve(chain, devices)
        #expect(result.regionRoots[3] == nil, "The disputed hub is still marked for neither dock")
        #expect(result.regionOwner[3] == 200, "But it is inside the display, and saying so is true")
        #expect(result.regionOwner[6] == 200, "As is the adapter behind it")
        // What must NOT happen is a claim of containment that is false.
        #expect(result.regionOwner[6] != 300)
        #expect(result.regionOwner[6] != 400)
    }

    @Test("A generically named chain device cannot steal a device an exact match already placed")
    func affiliateMatchCannotOverrideAnExactMatch() {
        // Also from the adversarial review. A chain device whose model name is one
        // generic word clears the three-character floor, and "Hub" word-matches
        // the internal hub chips of unrelated devices, because "USB3.0 Hub"
        // contains the whole word and so does nearly every hub descriptor ever
        // written. With both match strengths running together, that partial match
        // re-parented a hub the display's exact match had already placed, taking
        // its whole subtree under an unrelated dock.
        //
        // Exact matches settle ownership first; an affiliate match is refused
        // wherever it would contradict them.
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let display = chainSwitch(id: 200, parent: 100, vendor: "Apple", model: "Studio Display", depth: 1)
        let genericDock = chainSwitch(id: 300, parent: 200, vendor: "Nobody", model: "Hub", depth: 2)
        let chain = ThunderboltTopology.tree(from: root, in: [root, display, genericDock])
        let devices = [
            device(id: 1, locationID: 0x0310_0000, vendorID: 0x05AC, vendor: "Apple", product: "USB2.0 Hub", isHub: true),
            device(id: 2, locationID: 0x0313_0000, vendorID: 0x05AC, vendor: "Apple Inc.", product: "Studio Display", isHub: false),
            // Inside the display's hub, and named like every hub chip on earth.
            device(id: 3, locationID: 0x0311_0000, vendorID: 0x2109, vendor: "VIA Labs, Inc.", product: "USB3.0 Hub", isHub: true),
            device(id: 4, locationID: 0x0311_1000, vendorID: 0x046D, vendor: "Logitech", product: "Webcam", isHub: false),
        ]
        let result = resolve(chain, devices)
        #expect(result.regionOwner[3] == 200, "The hub is nested inside the display's region and stays there")
        #expect(result.regionOwner[4] == 200, "And so does the device behind it")
        #expect(result.regionRoots[3] == nil, "No region may be opened for the generically named dock here")
    }

    // MARK: - Degenerate inputs

    @Test("No chain and no devices resolve to nothing, and nothing crashes")
    func emptyInputs() {
        #expect(ChainDeviceAttribution.resolve(chain: [], forest: []).isEmpty)
        #expect(resolve(oneDeviceChain(), []).isEmpty)
        let devices = [device(id: 1, locationID: 0x0310_0000, vendorID: 0x2109, vendor: "VIA", product: "USB2.0 Hub", isHub: true)]
        #expect(ChainDeviceAttribution.resolve(chain: [], forest: USBDeviceNode.buildTree(from: devices)).isEmpty)
    }

    @Test("A forest whose parent links form a cycle still terminates")
    func cyclicParentLinksTerminate() {
        // `parentOf` inside the resolver is keyed by IOKit entry ID, not by
        // locationID. The forest itself cannot contain a cycle (each parent
        // locationID clears a nibble, so the path strictly shortens), but two
        // devices arriving with the SAME entry ID collide in that map and can
        // close a loop. IOKit does not hand out duplicate entry IDs; a stale
        // snapshot or a hand-built fixture can. A hang in the render path is the
        // worst failure available here, so it is ruled out structurally rather
        // than assumed away.
        //
        // Building a fixture that actually hangs took three attempts, and the two
        // that did not are worth recording because both looked convincing:
        //
        //  - a single `3 -> 2` link is not a cycle at all, and the test stayed
        //    green with the guard removed;
        //  - a cycle CONTAINING a marked node also terminates, because the walk
        //    stops at the first marked ancestor it meets.
        //
        // What hangs is a marked node whose parent chain leads into a cycle none
        // of whose members is marked. Here id 1 is marked (a hub that names the
        // dock, so it roots the region itself) and ids 2 and 3 are each other's
        // parent: node id 2 has children 1 and 3, and node id 3 has child 2.
        // The chain is deliberately only half matched, so vendor continuity
        // cannot run and mark a cycle member on the way past.
        //
        // If this regresses, the symptom is this test never finishing.
        let devices = [
            device(id: 2, locationID: 0x0310_0000, vendorID: 0x8087, vendor: "Intel", product: "USB3 HUB", isHub: true),
            device(id: 1, locationID: 0x0311_0000, vendorID: 0x2B89, vendor: "UGREEN", product: "TBT5 Docking Station 10-in-1", isHub: true),
            device(id: 3, locationID: 0x0312_0000, vendorID: 0x8087, vendor: "Intel", product: "USB3 HUB", isHub: true),
            device(id: 3, locationID: 0x0320_0000, vendorID: 0x8087, vendor: "Intel", product: "USB3 HUB", isHub: true),
            device(id: 2, locationID: 0x0321_0000, vendorID: 0x8087, vendor: "Intel", product: "USB3 HUB", isHub: true),
        ]
        let result = resolve(twoDeviceChain(), devices)
        #expect(!result.allAnchored, "Only the dock is named, so vendor continuity must be off")
        #expect(result.regionRoots[1] == 300, "The hub that names the dock still roots its region")
    }

    @Test("A device with no product name matches nothing")
    func namelessDeviceMatchesNothing() {
        let devices = [device(id: 1, locationID: 0x0310_0000, vendorID: 0x2109, vendor: nil, product: nil, isHub: false)]
        #expect(resolve(oneDeviceChain(), devices).isEmpty)
    }

    @Test("Two matches for one chain device, nested, mark only the outer hub")
    func nestedSameOwnerMarksAreCollapsed() {
        // A CalDigit dock publishes `TS5 USB 3 Hub` (a hub, which marks itself)
        // and `CalDigit TS5 Audio - Rear` (an endpoint further in, which marks
        // the hub it hangs off). Both name the same chain device, and the second
        // hub is inside the first. Keeping both marks renders that subtree twice
        // in the expanded view: once inside its ancestor and once as a region of
        // its own.
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let dock = chainSwitch(id: 200, parent: 100, vendor: "CalDigit", model: "TS5", depth: 1)
        let chain = ThunderboltTopology.tree(from: root, in: [root, dock])
        let devices = [
            device(id: 1, locationID: 0x0310_0000, vendorID: 0x2109, vendor: "VIA Labs, Inc.", product: "TS5 USB 3 Hub", isHub: true),
            device(id: 2, locationID: 0x0311_0000, vendorID: 0x2109, vendor: "VIA Labs, Inc.", product: "USB2.0 Hub", isHub: true),
            device(id: 3, locationID: 0x0311_1000, vendorID: 0x0D8C, vendor: "CalDigit", product: "CalDigit TS5 Audio - Rear", isHub: false),
        ]
        let result = resolve(chain, devices)
        #expect(result.regionRoots[1] == 200, "The outer hub roots the dock's region")
        #expect(result.regionRoots[2] == nil, "The inner hub adds nothing: its subtree already inherits the dock")
        #expect(result.regionOwner[2] == 200, "Ownership is unaffected, only the redundant mark is gone")
        #expect(result.regionOwner[3] == 200)
    }

    @Test("A hub that names a chain device claims itself, not its parent")
    func hubAnchorClaimsItself() {
        let devices = [
            device(id: 1, locationID: 0x0310_0000, vendorID: 0x05AC, vendor: "Apple", product: "USB2.0 Hub", isHub: true),
            device(id: 2, locationID: 0x0311_0000, vendorID: 0x2B89, vendor: "UGREEN", product: "TBT5 Dock", isHub: true),
            device(id: 3, locationID: 0x0311_1000, vendorID: 0x0BDA, vendor: "Realtek", product: "USB 10/100/1000 LAN", isHub: false),
        ]
        let result = resolve(oneDeviceChain(), devices)
        #expect(result.regionRoots[2] == 200, "The hub IS the dock, so it roots the region itself")
        #expect(result.regionRoots[1] == nil, "Its parent hub belongs to nothing in particular")
        #expect(result.regionOwner[3] == 200)
    }

    // MARK: - #493: a lone claim over a shared hub, numeric-first

    /// Root -> OWC dock only (no second chain device). The dock's own
    /// identity endpoint sits on its own OWC-branded hub. Nothing else on the
    /// fabric shares that vendor, so there is no ambiguity to refuse: this is
    /// the ordinary case the promotion exists for, and it must still work.
    /// No numeric DROM data on this fixture, so it resolves entirely on tier
    /// (d), the string fallback.
    @Test("A single same-brand chain device still promotes onto its own hub")
    func singleChainDeviceSameBrandStillPromotes() {
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let dock = chainSwitch(id: 200, parent: 100, vendor: "OWC", model: "OWC Dock", depth: 1)
        let chain = ThunderboltTopology.tree(from: root, in: [root, dock])
        let devices = [
            device(id: 1, locationID: 0x0310_0000, vendorID: 0x1E91, vendor: "OWC", product: "USB2.0 Hub", isHub: true),
            device(id: 2, locationID: 0x0311_0000, vendorID: 0x1E91, vendor: "OWC", product: "OWC Dock", isHub: false),
        ]
        let result = resolve(chain, devices)
        #expect(result.regionRoots[1] == 200,
            "With only one chain device on the fabric, its own hub still gets claimed")
        #expect(result.absorbed.contains(2),
            "The exact name match still absorbs the dock's own identity endpoint")
    }

    /// Tier (d), STRING fallback, no numeric DROM data anywhere on the fabric:
    /// a same-brand lone claim over a shared hub now PROMOTES, reverting to
    /// round 2's ordering (a hub vendor name match to the claimer wins over a
    /// match to a different chain device). This is a deliberate design
    /// change from round 3, which refused this unconditionally as its ONLY
    /// rule. Once numeric identity became the primary signal (tiers a-c), a
    /// bare name-string coincidence surviving all the way to tier (d) is weak
    /// enough that over-blocking on it costs more correct attributions than
    /// the residual same-brand ambiguity it protects against; real hardware
    /// in this shape almost always also carries a numeric identity, which
    /// resolves it correctly in an earlier tier (see the two tests below).
    @Test("Tier (d): a same-brand lone claim promotes when no numeric evidence exists at all")
    func tierDSameBrandLoneClaimPromotesWithoutNumericEvidence() {
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let dock = chainSwitch(id: 200, parent: 100, vendor: "OWC", model: "OWC Dock", depth: 1)
        let drive = chainSwitch(id: 300, parent: 200, vendor: "OWC", model: "OWC Drive", depth: 2)
        let chain = ThunderboltTopology.tree(from: root, in: [root, dock, drive])
        let devices = [
            device(id: 1, locationID: 0x0310_0000, vendorID: 0x1E91, vendor: "OWC", product: "USB2.0 Hub", isHub: true),
            device(id: 2, locationID: 0x0311_0000, vendorID: 0x1E91, vendor: "OWC", product: "OWC Drive", isHub: false),
        ]
        let result = resolve(chain, devices)
        #expect(result.regionRoots[1] == 300,
            "No numeric evidence anywhere: the hub vendor name matching the claimer promotes, per tier (d)")
    }

    /// Tier (d), STRING fallback, the ORIGINAL #493 shape with no numeric DROM
    /// data at all (i.e. what would happen if Thunderbolt switches never
    /// carried a numeric DROM vendor/model pair): the hub vendor names a
    /// DIFFERENT chain device only, so it stays on the leaf, exactly as round
    /// 2 and round 3 both had it. Proves the string fallback still protects
    /// this case on its own when numeric evidence genuinely is not there.
    @Test("Tier (d): the original #493 shape still refuses to promote on strings alone")
    func tierDOriginalShapeStillRefusesWithoutNumericEvidence() {
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let dock = chainSwitch(id: 200, parent: 100, vendor: "CalDigit, Inc.", model: "Thunderbolt 4 Pro Dock", depth: 1)
        let drive = chainSwitch(id: 300, parent: 200, vendor: "OWC", model: "Express 1M2", depth: 2)
        let chain = ThunderboltTopology.tree(from: root, in: [root, dock, drive])
        let devices = [
            device(id: 1, locationID: 0x0310_0000, vendorID: 0x2188, vendor: "CalDigit, Inc.", product: "TBT4 Pro USB2.0 Hub", isHub: true),
            device(id: 2, locationID: 0x0311_0000, vendorID: 0x174C, vendor: "OWC", product: "Express 1M2", isHub: false),
        ]
        let result = resolve(chain, devices)
        #expect(result.regionRoots[2] == 300,
            "The drive's claim must stay on itself")
        #expect(result.regionRoots[1] == nil,
            "The CalDigit hub must not be claimed by the OWC drive")
    }

    /// Tier (a): the hub's OWN idVendor/idProduct exactly identify it as the
    /// CLAIMING chain device's DROM. Decisive, no string ever read.
    @Test("Tier (a): a hub that numerically identifies as the claiming chain device promotes")
    func tierAHubNumericallyIdentifiesAsClaimerPromotes() {
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let dock = chainSwitch(
            id: 200, parent: 100, vendor: "Widget Co", model: "Widget Dock", depth: 1,
            dromVendorID: 0x1000, dromModelID: 0x2000
        )
        let chain = ThunderboltTopology.tree(from: root, in: [root, dock])
        let devices = [
            // Hub's own idVendor/idProduct exactly equal the dock's DROM
            // pair: this IS the dock's own hub. Vendor name deliberately left
            // unrelated ("Unrelated Inc"), so a string-based rule would have
            // refused this; the numeric tier does not consult it at all.
            device(id: 1, locationID: 0x0310_0000, vendorID: 0x1000, productID: 0x2000, vendor: "Unrelated Inc", product: "Hub", isHub: true),
            // An affiliate match (not exact) so the endpoint is a distinct
            // accessory from the dock's own identity, with no numeric
            // identity of its own.
            device(id: 2, locationID: 0x0311_0000, vendorID: 0x9999, productID: 0x8888, vendor: "Widget Co", product: "Widget Dock Audio", isHub: false),
        ]
        let result = resolve(chain, devices)
        #expect(result.regionRoots[1] == 200,
            "The hub's own numeric identity says it IS the dock, so it is promoted")
    }

    /// Tier (b): the hub's OWN idVendor/idProduct exactly identify it as a
    /// DIFFERENT chain device than the one naming it. Decisive leaf, no
    /// string ever read, even though nothing here uses matching brand names.
    @Test("Tier (b): a hub that numerically identifies as a DIFFERENT chain device stays on the leaf")
    func tierBHubNumericallyIdentifiesAsDifferentChainDeviceStaysOnLeaf() {
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let dockA = chainSwitch(
            id: 200, parent: 100, vendor: "Alpha Co", model: "Alpha Dock", depth: 1,
            dromVendorID: 0x1000, dromModelID: 0x2000
        )
        let dockB = chainSwitch(
            id: 300, parent: 200, vendor: "Beta Co", model: "Beta Dock", depth: 2,
            dromVendorID: 0x3000, dromModelID: 0x4000
        )
        let chain = ThunderboltTopology.tree(from: root, in: [root, dockA, dockB])
        let devices = [
            // The hub's own idVendor/idProduct exactly equal DOCK B's DROM,
            // even though the claiming device below names DOCK A.
            device(id: 1, locationID: 0x0310_0000, vendorID: 0x3000, productID: 0x4000, vendor: "Alpha Co", product: "Hub", isHub: true),
            device(id: 2, locationID: 0x0311_0000, vendorID: 0x9999, productID: 0x8888, vendor: "Alpha Co", product: "Alpha Dock Audio", isHub: false),
        ]
        let result = resolve(chain, devices)
        #expect(result.regionRoots[2] == 200,
            "The claiming endpoint's own claim stays on itself")
        #expect(result.regionRoots[1] == nil,
            "The hub's own numeric identity says it belongs to Dock B, not Dock A, so it is refused")
    }

    /// Tier (c), promote branch: the CLAIMING ENDPOINT is numerically
    /// identified, the hub itself is not, but the hub's VID equals the
    /// claiming chain device's own DROM VID. This is the multi-chip-dock
    /// pattern: the hub is one of the dock's own internal chips, sharing the
    /// chassis VID but carrying its own model id.
    @Test("Tier (c): a hub sharing the claiming chain device's VID (but not its PID) promotes")
    func tierCHubVIDMatchesClaimingChainDevicePromotes() {
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let dock = chainSwitch(
            id: 200, parent: 100, vendor: "Widget Co", model: "Widget Dock", depth: 1,
            dromVendorID: 0x1000, dromModelID: 0x2000
        )
        let chain = ThunderboltTopology.tree(from: root, in: [root, dock])
        let devices = [
            // Same VID as the dock's DROM (0x1000), but a different PID
            // (0x9999, not 0x2000): no EXACT match, so tier (a)/(b) do not
            // fire, but the shared chassis VID is still real evidence.
            device(id: 1, locationID: 0x0310_0000, vendorID: 0x1000, productID: 0x9999, vendor: "Unrelated Inc", product: "Hub", isHub: true),
            // The claiming endpoint IS numerically identified: exact VID+PID
            // match to the dock's own DROM.
            device(id: 2, locationID: 0x0311_0000, vendorID: 0x1000, productID: 0x2000, vendor: "Widget Co", product: "Widget Dock", isHub: false),
        ]
        let result = resolve(chain, devices)
        #expect(result.regionRoots[1] == 200,
            "The hub's VID matches the claiming chain device's DROM VID, so it promotes")
    }

    /// Tier (c), leaf branch: the numeric replay of the #493 bug itself. The
    /// OWC Express 1M2's real corpus numbers (0x174c/0x2465) exactly identify
    /// the claiming endpoint. The CalDigit dock's real corpus hub numbers
    /// (VID 0x2188, PID 0x5803, which does not match the dock's own DROM
    /// model id 0x5988) match no chain device exactly, but the hub's VID
    /// matches a DIFFERENT chain device's (CalDigit's) DROM VID. No
    /// vendor-name string is ever read for this decision.
    @Test("Tier (c): a hub sharing a DIFFERENT chain device's VID stays on the leaf (the #493 numbers)")
    func tierCHubVIDMatchesDifferentChainDeviceStaysOnLeaf() {
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let dock = chainSwitch(
            id: 200, parent: 100, vendor: "CalDigit, Inc.", model: "Thunderbolt 4 Pro Dock", depth: 1,
            dromVendorID: 0x2188, dromModelID: 0x5988
        )
        let drive = chainSwitch(
            id: 300, parent: 200, vendor: "OWC", model: "Express 1M2", depth: 2,
            dromVendorID: 0x174C, dromModelID: 0x2465
        )
        let chain = ThunderboltTopology.tree(from: root, in: [root, dock, drive])
        let devices = [
            device(id: 1, locationID: 0x0310_0000, vendorID: 0x2188, productID: 0x5803, vendor: "CalDigit, Inc.", product: "TBT4 Pro USB2.0 Hub", isHub: true),
            device(id: 2, locationID: 0x0311_0000, vendorID: 0x174C, productID: 0x2465, vendor: "OWC", product: "Express 1M2", isHub: false),
        ]
        let result = resolve(chain, devices)
        #expect(result.regionRoots[2] == 300,
            "The OWC endpoint's claim stays on itself")
        #expect(result.regionRoots[1] == nil,
            "The hub's VID (0x2188) matches the CalDigit dock, a different chain device from the OWC (0x174c)")
    }

    /// The 0x1e91 corpus quirk: some OWC units report Thunderbolt vendor id
    /// 0x1e91 while their USB idVendor stays 0x174c. A VID mismatch is NOT
    /// itself proof of a different vendor (only a POSITIVE match counts as
    /// evidence anywhere in this function), so this must NOT force a leaf on
    /// its own: `numericIdentity` simply finds no exact match at all (VID
    /// differs, so the pair does not match), tier (c) never fires (it
    /// requires the endpoint to BE numerically identified), and the decision
    /// falls straight through to the string tier, unaffected by the
    /// mismatched number.
    @Test("A numeric VID mismatch alone does not force a leaf; the string tier decides")
    func numericVIDMismatchAloneDoesNotForceLeaf() {
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let dock = chainSwitch(
            id: 200, parent: 100, vendor: "OWC", model: "OWC Drive", depth: 1,
            // Thunderbolt-side vendor id (0x1e91) differs from this unit's
            // USB-side idVendor (0x174c) below: the corpus-observed quirk.
            dromVendorID: 0x1E91, dromModelID: 0x2465
        )
        let chain = ThunderboltTopology.tree(from: root, in: [root, dock])
        let devices = [
            device(id: 1, locationID: 0x0310_0000, vendorID: 0x1E91, vendor: "OWC", product: "USB2.0 Hub", isHub: true),
            // idVendor 0x174c does not match the switch's dromVendorID
            // (0x1e91), even though idProduct (0x2465) does match
            // dromModelID: VID+PID must BOTH match for a numeric identity, so
            // this endpoint has none.
            device(id: 2, locationID: 0x0311_0000, vendorID: 0x174C, productID: 0x2465, vendor: "OWC", product: "OWC Drive", isHub: false),
        ]
        let result = resolve(chain, devices)
        #expect(result.regionRoots[1] == 200,
            "No numeric identity either way, so the string tier decides: hub vendor matches the claimer, promotes")
    }

    // MARK: - #493 round 5: hardening findings

    /// Two identical daisy-chained docks (same product, same DROM VID+PID)
    /// both numerically match a device carrying those same numbers.
    /// `numericIdentity` must refuse to pick "whichever comes first": the
    /// match is ambiguous, so it returns nil and the NAME match's switch id
    /// is used instead, exactly like a duplicate model NAME already does
    /// elsewhere in this file ("Two chain devices with the same model name
    /// match neither"). Reproduced before this fix: both regions
    /// cross-attributed to one switch.
    @Test("Item 1: an ambiguous numeric match (two identical chain devices) fails closed")
    func ambiguousNumericMatchFailsClosed() {
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        // Two docks with DIFFERENT names (so the NAME match is unambiguous
        // and isolates the numeric ambiguity this test is about) but the
        // SAME DROM VID+PID pair (the actual hardware scenario: identical
        // internal chips or identical product units). dockA (200, the FIRST
        // chain node in traversal order) is deliberately the one the device
        // does NOT name, and dockB (300, second in order) is the one it
        // DOES: a `.first`-based (no ambiguity check) implementation would
        // silently resolve to dockA, since it comes first in the array,
        // which is the wrong answer AND a different one from the name match.
        // Ordering the fixture this way is what makes this test able to
        // fail red on the unfixed code, rather than coincidentally agreeing
        // with it because "first in the array" and "the name match" happen
        // to be the same node.
        let dockA = chainSwitch(
            id: 200, parent: 100, vendor: "Widget Co", model: "Gadget Dock", depth: 1,
            dromVendorID: 0x1000, dromModelID: 0x2000
        )
        let dockB = chainSwitch(
            id: 300, parent: 200, vendor: "Widget Co", model: "Widget Dock", depth: 2,
            dromVendorID: 0x1000, dromModelID: 0x2000
        )
        let chain = ThunderboltTopology.tree(from: root, in: [root, dockA, dockB])
        let devices = [
            // Own idVendor/idProduct EXACTLY match both docks' identical DROM
            // pair. Product name affiliate-matches only dockB's model
            // ("Widget Dock"), not dockA's ("Gadget Dock"), so the NAME
            // match unambiguously proposes dockB (300).
            device(id: 1, locationID: 0x0310_0000, vendorID: 0x1000, productID: 0x2000, vendor: "Widget Co", product: "Widget Dock Audio", isHub: false),
        ]
        let result = resolve(chain, devices)
        // The ambiguous numeric match must NOT silently resolve to "whichever
        // dock comes first in the array" (dockA, 200): it falls back to the
        // name match's own chain device, dockB (300).
        #expect(result.regionRoots[1] != 200,
            "The ambiguous numeric identity must never resolve to the unrelated dock just because it came first")
        #expect(result.regionRoots[1] == 300,
            "With numeric identity refused as ambiguous, the name match (dockB) decides")
    }

    /// Tier (c)'s own ambiguity case: the hub's VID matches TWO different
    /// chain devices (neither of them the claimer). Must still refuse
    /// (leaf), the same "any different switch in the set refuses" rule as
    /// the single-different-switch case, just with two matches instead of
    /// one.
    @Test("Item 1: tier (c) VID-only match against MULTIPLE different chain devices still refuses")
    func tierCVIDMatchesMultipleDifferentChainDevicesStillRefuses() {
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let claimant = chainSwitch(
            id: 200, parent: 100, vendor: "Claimant Co", model: "Claimant Dock", depth: 1,
            dromVendorID: 0x1000, dromModelID: 0x2000
        )
        let other1 = chainSwitch(
            id: 300, parent: 200, vendor: "Other Co", model: "Other Dock 1", depth: 2,
            dromVendorID: 0x9999, dromModelID: 0x4000
        )
        let other2 = chainSwitch(
            id: 400, parent: 300, vendor: "Other Co", model: "Other Dock 2", depth: 3,
            dromVendorID: 0x9999, dromModelID: 0x5000
        )
        let chain = ThunderboltTopology.tree(from: root, in: [root, claimant, other1, other2])
        let devices = [
            // Hub VID (0x9999) matches BOTH other1 and other2, neither of
            // which is the claimant.
            device(id: 1, locationID: 0x0310_0000, vendorID: 0x9999, productID: 0x1234, vendor: "Other Co", product: "Hub", isHub: true),
            device(id: 2, locationID: 0x0311_0000, vendorID: 0x1000, productID: 0x2000, vendor: "Claimant Co", product: "Claimant Dock", isHub: false),
        ]
        let result = resolve(chain, devices)
        #expect(result.regionRoots[1] == nil,
            "The hub's VID matches two DIFFERENT chain devices, neither the claimant: must refuse")
    }

    /// Tier (c)'s priority ordering, the part of item 1 the previous test
    /// does not exercise: the hub's VID matches BOTH the claiming chain
    /// device AND a different one. An implementation that checks "does the
    /// VID match the claimer" before "does the VID match anyone else" would
    /// promote here (the claimer-match check passes first); the correct
    /// order refuses whenever a DIFFERENT chain device is in the set too,
    /// regardless of whether the claimer is also in it.
    @Test("Item 1: tier (c) refuses when the hub's VID matches the claimant AND a different chain device")
    func tierCVIDMatchesClaimantAndDifferentChainDeviceStillRefuses() {
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let claimant = chainSwitch(
            id: 200, parent: 100, vendor: "Claimant Co", model: "Claimant Dock", depth: 1,
            dromVendorID: 0x1000, dromModelID: 0x2000
        )
        let other = chainSwitch(
            id: 300, parent: 200, vendor: "Other Co", model: "Other Dock", depth: 2,
            // SAME VID as the claimant, different model id: shares the VID,
            // ambiguous, must not rescue the promotion.
            dromVendorID: 0x1000, dromModelID: 0x4000
        )
        let chain = ThunderboltTopology.tree(from: root, in: [root, claimant, other])
        let devices = [
            // Hub VID (0x1000) matches BOTH the claimant and the other dock.
            // No exact PID match to either, so tier (a)/(b) do not fire.
            device(id: 1, locationID: 0x0310_0000, vendorID: 0x1000, productID: 0x9999, vendor: "Claimant Co", product: "Hub", isHub: true),
            device(id: 2, locationID: 0x0311_0000, vendorID: 0x1000, productID: 0x2000, vendor: "Claimant Co", product: "Claimant Dock", isHub: false),
        ]
        let result = resolve(chain, devices)
        #expect(result.regionRoots[1] == nil,
            "The hub's VID matches a DIFFERENT chain device too, so even matching the claimant does not promote")
    }

    /// Item 2: a device that IS ITSELF a hub, named by one chain device but
    /// numerically identified as a DIFFERENT one. Before the fix, the
    /// early `if node.device.isHub { return deviceID }` path used the raw
    /// NAME-matched switch id because `effectiveSwitchID` was computed AFTER
    /// it; the promised numeric correction never reached this path.
    @Test("Item 2: a hub-claimant's own numeric identity overrides a disagreeing name match")
    func hubClaimantNumericIdentityOverridesNameMatch() {
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let x = chainSwitch(
            id: 200, parent: 100, vendor: "X Co", model: "X Hub", depth: 1,
            dromVendorID: 0x1000, dromModelID: 0x2000
        )
        let y = chainSwitch(
            id: 300, parent: 200, vendor: "Y Co", model: "Y Hub", depth: 2,
            dromVendorID: 0x3000, dromModelID: 0x4000
        )
        let chain = ThunderboltTopology.tree(from: root, in: [root, x, y])
        let devices = [
            // A HUB device, exact name match to X ("X Hub" -> switch 200),
            // but its own idVendor/idProduct exactly match Y's DROM.
            device(id: 1, locationID: 0x0310_0000, vendorID: 0x3000, productID: 0x4000, vendor: "X Co", product: "X Hub", isHub: true),
        ]
        let result = resolve(chain, devices)
        #expect(result.regionRoots[1] == 300,
            "A hub's own numeric identity (Y) must win over the name match that proposed X")
    }

    /// Item 2: a device with NO hub parent at all (a top-level / bare
    /// endpoint), named by one chain device but numerically identified as a
    /// different one. Same early-return-before-effectiveSwitchID bug as the
    /// hub-claimant case, on the "no parent" path instead of the "isHub"
    /// one.
    @Test("Item 2: a parentless claimant's own numeric identity overrides a disagreeing name match")
    func parentlessClaimantNumericIdentityOverridesNameMatch() {
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let x = chainSwitch(
            id: 200, parent: 100, vendor: "X Co", model: "X Drive", depth: 1,
            dromVendorID: 0x1000, dromModelID: 0x2000
        )
        let y = chainSwitch(
            id: 300, parent: 200, vendor: "Y Co", model: "Y Drive", depth: 2,
            dromVendorID: 0x3000, dromModelID: 0x4000
        )
        let chain = ThunderboltTopology.tree(from: root, in: [root, x, y])
        let devices = [
            // Top-level device (locationID 0, no parent in the forest at
            // all), exact name match to X, numeric identity is Y.
            device(id: 1, locationID: 0, vendorID: 0x3000, productID: 0x4000, vendor: "X Co", product: "X Drive", isHub: false),
        ]
        let result = resolve(chain, devices)
        #expect(result.regionRoots[1] == 300,
            "A parentless device's own numeric identity (Y) must win over the name match that proposed X")
    }

    /// Item 3: idVendor/idProduct both 0 (what `USBWatcher` falls back to on
    /// a failed descriptor read) must never "exact match" a DROM pair that
    /// is ALSO 0/0, even one constructed directly (bypassing
    /// `IOThunderboltSwitch.from`'s own zero-to-nil normalisation, which a
    /// hand-built fixture or a future caller could do). Reproduced before
    /// this defensive guard: a 0/0-vs-0/0 "exact match" promoted an
    /// unrelated hub.
    @Test("Item 3: zero idVendor/idProduct never counts as a numeric match, even against a zero DROM pair")
    func zeroIdentityNeverMatchesEvenAgainstZeroDROM() {
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        // Constructed directly with a 0/0 DROM pair, bypassing
        // IOThunderboltSwitch.from's own normalisation, to prove the
        // defensive check inside ChainDeviceAttribution itself, not just the
        // parse-time one.
        let dock = chainSwitch(
            id: 200, parent: 100, vendor: "Unrelated Co", model: "Unrelated Dock", depth: 1,
            dromVendorID: 0, dromModelID: 0
        )
        let chain = ThunderboltTopology.tree(from: root, in: [root, dock])
        let devices = [
            // Hub also reports 0/0 (as a device that failed its own
            // descriptor read would).
            device(id: 1, locationID: 0x0310_0000, vendorID: 0, productID: 0, vendor: "Unrelated Co", product: "Hub", isHub: true),
            // The claiming device: idVendor/idProduct both 0 (failed read),
            // affiliate name match to the unrelated dock.
            device(id: 2, locationID: 0x0311_0000, vendorID: 0, productID: 0, vendor: "Someone Else", product: "Unrelated Dock Extra", isHub: false),
        ]
        let result = resolve(chain, devices)
        // Must NOT promote via a false "numeric" match. Falls through to the
        // string tier: hub vendor "Unrelated Co" matches the claiming chain
        // device's own vendor (chainVendorByID), so it promotes on THAT
        // (real) evidence, not on the bogus 0/0 numeric one. The assertion
        // that matters is the hub's numeric identity was never treated as a
        // match; verified indirectly via the zero-VID test below, which
        // isolates the case where the string tier would NOT rescue it.
        #expect(result.regionRoots[1] == 200)
    }

    /// Same zero case, but with nothing for the string tier to rescue: the
    /// hub vendor name matches a DIFFERENT chain device, so if the 0/0
    /// numeric pair were wrongly treated as a match (promoting via tier a),
    /// this would promote onto the wrong hub. It must refuse instead.
    @Test("Item 3: a zero DROM pair does not let a zero-ID device promote onto an unrelated hub")
    func zeroIdentityDoesNotPromoteOntoUnrelatedHub() {
        // Deliberately only ONE chain device carries a 0/0 DROM pair (the
        // other has a real, distinct one): a fixture where BOTH chain
        // devices are 0/0 would be caught by item 1's ambiguity guard
        // regardless of whether the zero guard held, which would not
        // isolate this specific defence. Here, without the zero guard, the
        // 0/0 endpoint and 0/0 hub would numerically identify UNIQUELY (and
        // wrongly) as "other", diverging from the correct, name-driven
        // answer (unattributed/leaf).
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let claimant = chainSwitch(
            id: 200, parent: 100, vendor: "Claimant Co", model: "Claimant Drive", depth: 1,
            dromVendorID: 0x1000, dromModelID: 0x2000
        )
        let other = chainSwitch(
            id: 300, parent: 200, vendor: "Other Co", model: "Other Dock", depth: 2,
            dromVendorID: 0, dromModelID: 0
        )
        let chain = ThunderboltTopology.tree(from: root, in: [root, claimant, other])
        let devices = [
            // Hub reports 0/0 idVendor/idProduct (a failed descriptor read)
            // and is named for the "other" chain device on strings too, so
            // even the string tier would (wrongly) agree with a numeric
            // false-positive here; this isolates the zero guard rather than
            // relying on the string tier to save it.
            device(id: 1, locationID: 0x0310_0000, vendorID: 0, productID: 0, vendor: "Other Co", product: "Hub", isHub: true),
            // The claimant: also reports 0/0 idVendor/idProduct, but its
            // NAME affiliate-matches "Claimant Drive" (200), not "Other
            // Dock" (300).
            device(id: 2, locationID: 0x0311_0000, vendorID: 0, productID: 0, vendor: "Someone Else", product: "Claimant Drive Extra", isHub: false),
        ]
        let result = resolve(chain, devices)
        // Correct: the claim stays on the leaf. The hub's own name matches
        // "Other Co" (a DIFFERENT chain device from the claimant, per the
        // string tier), so it refuses; nothing here promotes it to "other"
        // (300) on legitimate evidence, and a bogus 0/0 numeric match must
        // not promote it there either.
        #expect(result.regionRoots[1] == nil,
            "A 0/0 'numeric match' must never promote the hub onto the unrelated chain device")
        #expect(result.regionRoots[2] == 200,
            "The claimant's own claim stays on itself, on its real name match")
    }

    /// Item 4: the switchID-override half of the (target, switchID) tuple is
    /// what makes the numeric correction actually visible to the CALLER
    /// (`marks()`'s grouping and the region roots it produces), not just to
    /// `claimTarget`'s own internal promote/leaf decision. This test is
    /// built so disabling the override (using the raw name-matched switchID
    /// instead of `effectiveSwitchID` everywhere) flips its own PROMOTE
    /// decision to a LEAF, which is a clean, mechanically checkable failure
    /// mode: proven red separately by mutating `effectiveSwitchID` in
    /// production and re-running this test (see the PR description for the
    /// captured failure).
    @Test("Item 4: the switch id a promoted claim is recorded under reflects numeric identity, not the name match")
    func switchIDOverrideIsRecordedNotJustCheckedInternally() {
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let x = chainSwitch(
            id: 200, parent: 100, vendor: "X Co", model: "X Dock", depth: 1,
            dromVendorID: 0x1000, dromModelID: 0x2000
        )
        let y = chainSwitch(
            id: 300, parent: 200, vendor: "Y Co", model: "Y Dock", depth: 2,
            dromVendorID: 0x3000, dromModelID: 0x4000
        )
        let chain = ThunderboltTopology.tree(from: root, in: [root, x, y])
        let devices = [
            // Hub's own idVendor/idProduct exactly identify it as Y (tier a).
            device(id: 1, locationID: 0x0310_0000, vendorID: 0x3000, productID: 0x4000, vendor: "Unrelated Inc", product: "Hub", isHub: true),
            // The endpoint is an AFFILIATE name match to X ("X Dock" ->
            // switch 200 proposed), but its own idVendor/idProduct exactly
            // match Y too.
            device(id: 2, locationID: 0x0311_0000, vendorID: 0x3000, productID: 0x4000, vendor: "X Co", product: "X Dock Audio", isHub: false),
        ]
        let result = resolve(chain, devices)
        // With the override working: effectiveSwitchID is Y (300), the
        // hub's own numeric identity is ALSO Y, tier (a) promotes, and the
        // claim is grouped and recorded under 300, not the name match's 200.
        #expect(result.regionRoots[1] == 300,
            "The hub promotes under Y (300), the numerically corrected switch id, not X (200), the name match")
    }

    // MARK: - Structural tunnel join

    /// The ground-truth shape (`research/customer-probes/m3pro_macos27.0_l`,
    /// issue #493's own reporter): Mac -> CalDigit dock (depth 1, no USB
    /// tunnel of its own) -> LaCie 1big (depth 2, tunnel bridge depth 4) ->
    /// Studio Display (depth 3, chained behind the LaCie, tunnel bridge
    /// depth 6).
    private func laCieStudioDisplayChain() -> [IOThunderboltSwitchNode] {
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let dock = chainSwitch(id: 200, parent: 100, vendor: "CalDigit, Inc.", model: "Thunderbolt 4 Pro Dock", depth: 1)
        let laCie = chainSwitch(id: 300, parent: 200, vendor: "LaCie", model: "1big Dock v2", depth: 2)
        let display = chainSwitch(id: 400, parent: 300, vendor: "Apple Inc.", model: "Studio Display", depth: 3)
        return ThunderboltTopology.tree(from: root, in: [root, dock, laCie, display])
    }

    /// The reporter's REAL fabric shape: LaCie (300) and the OWC Express 1M2
    /// (250, PCIe tunnel only, no USB tunnel of its own) are depth-2
    /// siblings under the CalDigit dock. `usbTunnelSwitchUIDs` in these
    /// tests reflects that: only 300 and 400 (the Studio Display, chained
    /// behind the LaCie) are ever passed as USB-tunnel-bearing, mirroring
    /// what `ThunderboltTopology.tunnels(...).filter { $0.kind == .usb }`
    /// would report for this fabric. 250 is never in that set, which is what
    /// makes the per-depth gate resolve 300 despite the depth collision.
    private func laCieOwcSiblingChain() -> [IOThunderboltSwitchNode] {
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let dock = chainSwitch(id: 200, parent: 100, vendor: "CalDigit, Inc.", model: "Thunderbolt 4 Pro Dock", depth: 1)
        let laCie = chainSwitch(id: 300, parent: 200, vendor: "LaCie", model: "1big Dock v2", depth: 2)
        let owc = chainSwitch(id: 250, parent: 200, vendor: "OWC", model: "Express 1M2", depth: 2)
        let display = chainSwitch(id: 400, parent: 300, vendor: "Apple Inc.", model: "Studio Display", depth: 3)
        return ThunderboltTopology.tree(from: root, in: [root, dock, laCie, owc, display])
    }

    @Test("Structural tunnel join places devices by PCIe bridge depth, no name required")
    func structuralJoinPlacesDevicesByBridgeDepth() {
        let chain = laCieStudioDisplayChain()
        let devices = [
            // LaCie's own USB2 hub persona: bridge depth 4 -> DROM depth 2 -> LaCie (300).
            tunnelledDevice(id: 1, locationID: 0x0310_0000, bridgeDepth: 4, product: "1big Dock", isHub: false),
            // Studio Display's internal hub personas name NOTHING about the
            // display ("USB2 Hub", "USB3 Gen2 Hub"): this is exactly the case
            // a name match cannot place, and structural join can.
            tunnelledDevice(id: 2, locationID: 0x0311_0000, bridgeDepth: 6, product: "USB2 Hub", isHub: true),
            tunnelledDevice(id: 3, locationID: 0x0311_1000, bridgeDepth: 6, product: nil, isHub: false),
        ]
        let forest = USBDeviceNode.buildTree(from: devices)
        let result = ChainDeviceAttribution.resolve(
            chain: chain, forest: forest,
            usbTunnelSwitchUIDs: [300, 400], expectedTunnelRootName: "apciec2"
        )
        #expect(result.regionOwner[1] == 300, "bridge depth 4 -> DROM depth 2 -> the LaCie switch")
        #expect(result.regionOwner[2] == 400, "bridge depth 6 -> DROM depth 3 -> the Studio Display switch")
        #expect(result.regionOwner[3] == 400, "a device nested inside a structurally-placed hub inherits its owner")
    }

    @Test("Structural join resolves a depth even when a PCIe-only sibling shares it, only the confirmed USB-tunnel switch counts")
    func structuralJoinIgnoresNonUSBTunnelSiblingAtSameDepth() {
        // The reporter's actual fabric: OWC (PCIe-only) and LaCie (USB
        // tunnel) are BOTH depth-2 siblings. A whole-chain "no two switches
        // share a depth" gate would refuse this; restricting depthCounts to
        // `usbTunnelSwitchUIDs` (which excludes the OWC) resolves it.
        let chain = laCieOwcSiblingChain()
        let devices = [
            tunnelledDevice(id: 1, locationID: 0x0310_0000, bridgeDepth: 4, product: nil, isHub: false),
        ]
        let forest = USBDeviceNode.buildTree(from: devices)
        let result = ChainDeviceAttribution.resolve(
            chain: chain, forest: forest,
            usbTunnelSwitchUIDs: [300, 400], expectedTunnelRootName: "apciec2"
        )
        #expect(result.regionOwner[1] == 300, "the OWC sibling at the same depth does not block the LaCie's join")
    }

    @Test("Structural join marks only the boundary device of a nested group, like the name-based pass does")
    func structuralJoinCollapsesRedundantNestedMarks() {
        let chain = laCieStudioDisplayChain()
        let devices = [
            tunnelledDevice(id: 1, locationID: 0x0310_0000, bridgeDepth: 4, isHub: true),
            tunnelledDevice(id: 2, locationID: 0x0310_1000, bridgeDepth: 4, isHub: false),
        ]
        let forest = USBDeviceNode.buildTree(from: devices)
        let result = ChainDeviceAttribution.resolve(
            chain: chain, forest: forest,
            usbTunnelSwitchUIDs: [300, 400], expectedTunnelRootName: "apciec2"
        )
        #expect(result.regionRoots[1] == 300, "the outer device roots the structural region")
        #expect(result.regionRoots[2] == nil, "the nested device adds no mark: inheritance already covers it")
        #expect(result.regionOwner[2] == 300, "ownership is unaffected, only the redundant mark is gone")
    }

    @Test("A genuine structural/name disagreement fails closed: name placement is kept, but the device is not absorbed")
    func structuralConflictWithNameMatchFailsClosed() {
        // A GENUINE disagreement: the device's own product name matches the
        // Studio Display exactly (name says 400), but its bridge depth
        // resolves to the LaCie (structural says 300). Two strong signals
        // that cannot both be right. Policy: keep the name placement, refuse
        // the structural override, and do not treat this device as the
        // chain device's own identity endpoint.
        let chain = laCieStudioDisplayChain()
        let devices = [
            tunnelledDevice(id: 1, locationID: 0x0310_0000, bridgeDepth: 4, product: "Studio Display", isHub: false),
        ]
        let forest = USBDeviceNode.buildTree(from: devices)
        let result = ChainDeviceAttribution.resolve(
            chain: chain, forest: forest,
            usbTunnelSwitchUIDs: [300, 400], expectedTunnelRootName: "apciec2"
        )
        #expect(result.regionOwner[1] == 400, "the exact name match is kept: structural does not override it")
        #expect(!result.absorbed.contains(1), "a device with disagreeing evidence is not collapsed into the chain row")
    }

    @Test("A tunnelled device with no bridge depth falls back to name matching")
    func tunnelledDeviceWithoutBridgeDepthFallsBackToNameMatch() {
        let chain = laCieStudioDisplayChain()
        let devices = [
            USBDevice(
                id: 1, locationID: 0x0310_0000, vendorID: 0x05AC, productID: 0x1234,
                vendorName: nil, productName: "1big Dock v2", serialNumber: nil,
                usbVersion: nil, speedRaw: 3, busPowerMA: nil, currentMA: nil,
                isThunderboltTunnelled: true, tunnelBridgeDepth: nil, tunnelRootName: nil,
                deviceClass: 0x00, rawProperties: [:]
            ),
        ]
        let forest = USBDeviceNode.buildTree(from: devices)
        let result = ChainDeviceAttribution.resolve(
            chain: chain, forest: forest,
            usbTunnelSwitchUIDs: [300, 400], expectedTunnelRootName: "apciec2"
        )
        #expect(result.regionOwner[1] == 300, "no bridge depth: falls back to the exact name match")
    }

    @Test("An odd bridge depth never resolves structurally")
    func oddBridgeDepthNeverResolves() {
        // `bridgeDepth.isMultiple(of: 2)` guards this: an odd count cannot
        // be divided into a DROM depth at all (the Intel-topology shape,
        // where the doubles-per-depth relationship does not hold).
        let chain = laCieStudioDisplayChain()
        let devices = [
            tunnelledDevice(id: 1, locationID: 0x0310_0000, bridgeDepth: 5, product: nil, isHub: false),
        ]
        let forest = USBDeviceNode.buildTree(from: devices)
        let result = ChainDeviceAttribution.resolve(
            chain: chain, forest: forest,
            usbTunnelSwitchUIDs: [300, 400], expectedTunnelRootName: "apciec2"
        )
        #expect(result.regionOwner[1] == nil, "an odd bridge depth is not a valid DROM-depth-times-two value")
    }

    @Test("Equal-depth chain fails closed: structural join places nothing, name matching still runs")
    func equalDepthChainFailsClosed() {
        // Two GENUINELY USB-tunnel-bearing switches at the SAME DROM depth:
        // the unproven case (research/usb-chain-attribution-identifiers.md
        // records zero corpus examples of this). The whole port's
        // structural pass must fail closed rather than guess which sibling
        // a bridge-depth-2 device belongs to.
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let dockA = chainSwitch(id: 200, parent: 100, vendor: "Vendor A", model: "Dock A", depth: 1)
        let dockB = chainSwitch(id: 201, parent: 100, vendor: "Vendor B", model: "Dock B", depth: 1)
        let chain = ThunderboltTopology.tree(from: root, in: [root, dockA, dockB])
        let devices = [
            tunnelledDevice(id: 1, locationID: 0x0310_0000, bridgeDepth: 2, product: nil, isHub: false),
            // Name matching is untouched by the equal-depth gate: a device
            // naming one of the two docks exactly still resolves normally.
            tunnelledDevice(id: 2, locationID: 0x0311_0000, bridgeDepth: 2, product: "Dock A", isHub: false),
        ]
        let forest = USBDeviceNode.buildTree(from: devices)
        let result = ChainDeviceAttribution.resolve(
            chain: chain, forest: forest,
            usbTunnelSwitchUIDs: [200, 201], expectedTunnelRootName: "apciec0"
        )
        #expect(result.regionOwner[1] == nil, "structural evidence is refused when two CONFIRMED USB-tunnel switches share a depth")
        #expect(result.regionOwner[2] == 200, "name matching is unaffected by the structural gate")
    }

    @Test("An empty usbTunnelSwitchUIDs set (no hop-table data) places nothing structurally")
    func emptyUSBTunnelSwitchUIDsPlacesNothing() {
        let chain = laCieStudioDisplayChain()
        let devices = [
            tunnelledDevice(id: 1, locationID: 0x0310_0000, bridgeDepth: 4, product: nil, isHub: false),
        ]
        let forest = USBDeviceNode.buildTree(from: devices)
        // The default: no usbTunnelSwitchUIDs, no expectedTunnelRootName.
        let result = ChainDeviceAttribution.resolve(chain: chain, forest: forest)
        #expect(result.regionOwner[1] == nil, "no confirmed USB-tunnel switches: the structural pass is a no-op, not a guess")
    }

    @Test("A tunnelRootName that names a DIFFERENT port fails closed")
    func rootMismatchFailsClosed() {
        let chain = laCieStudioDisplayChain()
        // apciec2 belongs to a DIFFERENT physical port from the one this
        // resolve() call is scoped to (apciec1): a cross-port mixup, e.g.
        // from a wiring bug that fed the wrong port's devices in.
        let devices = [
            tunnelledDevice(id: 1, locationID: 0x0310_0000, bridgeDepth: 4, product: nil, isHub: false, tunnelRootName: "apciec2"),
        ]
        let forest = USBDeviceNode.buildTree(from: devices)
        let result = ChainDeviceAttribution.resolve(
            chain: chain, forest: forest,
            usbTunnelSwitchUIDs: [300, 400], expectedTunnelRootName: "apciec1"
        )
        #expect(result.regionOwner[1] == nil, "a device whose tunnelRootName names a different port is refused, however clean the depth arithmetic is")
    }

    @Test("Without a known expected root, internally CONSISTENT candidates still resolve")
    func consistentRootsResolveWithoutExpectedRoot() {
        let chain = laCieStudioDisplayChain()
        let devices = [
            tunnelledDevice(id: 1, locationID: 0x0310_0000, bridgeDepth: 4, product: nil, isHub: false, tunnelRootName: "apciec2"),
            tunnelledDevice(id: 2, locationID: 0x0311_0000, bridgeDepth: 6, product: nil, isHub: false, tunnelRootName: "apciec2"),
        ]
        let forest = USBDeviceNode.buildTree(from: devices)
        // expectedTunnelRootName is nil: falls back to the internal
        // consistency check. Both candidates agree on "apciec2", so both
        // resolve.
        let result = ChainDeviceAttribution.resolve(
            chain: chain, forest: forest,
            usbTunnelSwitchUIDs: [300, 400]
        )
        #expect(result.regionOwner[1] == 300)
        #expect(result.regionOwner[2] == 400)
    }

    @Test("Without a known expected root, DISAGREEING candidates all fail closed")
    func disagreeingRootsFailClosedWithoutExpectedRoot() {
        let chain = laCieStudioDisplayChain()
        let devices = [
            tunnelledDevice(id: 1, locationID: 0x0310_0000, bridgeDepth: 4, product: nil, isHub: false, tunnelRootName: "apciec2"),
            // A different root than device 1: internally inconsistent,
            // which is itself evidence of a cross-port mixup upstream (two
            // different ports' devices ended up in the same resolve() call).
            tunnelledDevice(id: 2, locationID: 0x0311_0000, bridgeDepth: 6, product: nil, isHub: false, tunnelRootName: "apciec7"),
        ]
        let forest = USBDeviceNode.buildTree(from: devices)
        let result = ChainDeviceAttribution.resolve(
            chain: chain, forest: forest,
            usbTunnelSwitchUIDs: [300, 400]
        )
        #expect(result.regionOwner[1] == nil, "disagreeing roots refuse EVERY candidate, not just the minority one")
        #expect(result.regionOwner[2] == nil)
    }

    // MARK: - TB5 Gen T shared-controller tunnel-hub mapping
    //
    // Fixtures below reproduce the exact reported bug (owner's M5 MacBook,
    // Mac -> Studio Display -> Ugreen TBT5 dock, WD Game Drive rendered under
    // the display) from real capture data:
    // `whatcable-app-notes/tree-attribution/json-dock.json` (USB tree,
    // locationIDs) and `dock-switch5-raw.txt` / `display-raw-ioreg.txt`
    // (route strings, USB Port Map). See `USBDeviceTreeTests`'
    // `childHubPortRealCapture` for the same locationIDs checked directly.

    /// Mac -> Studio Display (depth 1, Route String 1) -> Ugreen TBT5 dock
    /// (depth 2, Route String 769 = 0x301, so byte index 1 = 3, hub port
    /// (3-1)/2 = 1). `displayUsbPortMap` lets tests exercise the USB Port Map
    /// cross-check (spec 3.3): the display switch is the PARENT whose map is
    /// consulted for the dock's edge.
    private func tb5TwoBoxChain(displayUsbPortMap: Data? = nil) -> [IOThunderboltSwitchNode] {
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let display = IOThunderboltSwitch(
            id: 200, className: "IOThunderboltSwitchIntelJHL9580", vendorID: 32903,
            vendorName: "Apple", modelName: "Studio Display ", routerID: 1, depth: 1,
            routeString: 1, upstreamPortNumber: 1, maxPortNumber: 23,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xE), ports: [],
            parentSwitchUID: 100, dromVendorID: 1452, dromModelID: 30978,
            usbPortMap: displayUsbPortMap
        )
        let dock = IOThunderboltSwitch(
            id: 300, className: "IOThunderboltSwitchIntelJHL9580", vendorID: 32903,
            vendorName: "Ugreen Group Limited", modelName: "TBT5 Docking Station 10-in-1",
            routerID: 1, depth: 2, routeString: 769, upstreamPortNumber: 1, maxPortNumber: 23,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xE), ports: [],
            parentSwitchUID: 200, dromVendorID: 11145, dromModelID: 1810
        )
        return ThunderboltTopology.tree(from: root, in: [root, display, dock])
    }

    /// The two anonymous Intel tunnel hubs plus the WD Game Drive, at their
    /// real captured locationIDs. `dockHubProduct` defaults to 0x5787 (the
    /// captured PID); tests that need to break the silicon-table gate
    /// override it.
    private func tb5TunnelHubDevices(dockHubProduct: UInt16 = 0x5787) -> [USBDevice] {
        [
            device(id: 10, locationID: 0x0320_0000, vendorID: 0x8087, productID: 0x0B41, vendor: "Intel Corporation", product: nil, isHub: true),
            device(id: 11, locationID: 0x0321_0000, vendorID: 0x8087, productID: dockHubProduct, vendor: "Intel Corporation", product: nil, isHub: true),
            device(id: 12, locationID: 0x0321_1000, vendorID: 0x1058, productID: 9811, vendor: "WD", product: "Game Drive", isHub: false),
        ]
    }

    private static let jhl9580PortMapHex = "018194028295038396048497050000"
    private static func portMapData(_ hex: String) -> Data {
        var bytes: [UInt8] = []
        var chars = Array(hex)
        while chars.count >= 2 {
            bytes.append(UInt8(String(chars[0..<2]), radix: 16)!)
            chars.removeFirst(2)
        }
        return Data(bytes)
    }

    @Test("TB5 reported bug: WD Game Drive attributes to the Ugreen dock, not the Studio Display")
    func tb5GameDriveAttributesToDock() {
        let chain = tb5TwoBoxChain()
        let devices = tb5TunnelHubDevices()
        let forest = USBDeviceNode.buildTree(from: devices)
        let result = ChainDeviceAttribution.resolve(chain: chain, forest: forest, usbTunnelSwitchUIDs: [200, 300])
        #expect(result.regionOwner[10] == 200, "the display's own tunnel hub must attribute to the display")
        #expect(result.regionOwner[11] == 300, "the dock's tunnel hub must attribute to the dock, not the display")
        #expect(result.regionOwner[12] == 300, "the WD Game Drive, nested under the dock's hub, must inherit the dock, not the display")
    }

    @Test("TB5: fires with a real expectedTunnelRootName even though its own hubs carry no tunnelRootName")
    func tb5FiresWithExpectedTunnelRootNameSet() {
        // Live-rig regression: every OTHER TB5 test in this file calls
        // resolve() with expectedTunnelRootName left at its nil default,
        // which is exactly why this shipped past the whole suite twice. With
        // it nil, rootIsTrusted() falls back to the internal-consistency
        // check (do all candidates in THIS resolve() call agree on
        // rootName), and since neither TB5 hub ever carries a rootName at
        // all, that check trivially passes. The live call site passes a
        // real value (this port's own "apciecN" root), which switches
        // rootIsTrusted() to an exact-match comparison against that string,
        // and nil (what these hubs always carry) never equals a string.
        let chain = tb5TwoBoxChain()
        let devices = tb5TunnelHubDevices()
        let forest = USBDeviceNode.buildTree(from: devices)
        let result = ChainDeviceAttribution.resolve(
            chain: chain, forest: forest, usbTunnelSwitchUIDs: [200, 300],
            expectedTunnelRootName: "apciec3"
        )
        #expect(result.regionOwner[10] == 200, "the display's own tunnel hub must still attribute to the display")
        #expect(result.regionOwner[11] == 300, "the dock's tunnel hub must still attribute to the dock")
        #expect(result.regionOwner[12] == 300, "the WD Game Drive must still inherit the dock")
    }

    @Test("TB5: a hub with the WRONG non-nil rootName is still refused even with expectedTunnelRootName set")
    func tb5WrongRootNameStillRefusedWithExpectedTunnelRootNameSet() {
        // Proves fix 1 only special-cases nil, not "any root": a tb5TunnelHubMap
        // candidate whose rootName is non-nil but wrong must still be dropped.
        // A device's tunnelRootName comes from the USB watcher's own walk, not
        // from this pass, so a hub can only carry a non-nil root if some future
        // change starts stamping one; this fixture forces that shape directly
        // via the device's own tunnelRootName field to prove the guard holds
        // regardless of how a wrong root gets there.
        let chain = tb5TwoBoxChain()
        var devices = tb5TunnelHubDevices()
        devices[1] = USBDevice(
            id: 11, locationID: 0x0321_0000, vendorID: 0x8087, productID: 0x5787,
            vendorName: "Intel Corporation", productName: nil, serialNumber: nil,
            usbVersion: nil, speedRaw: 3, busPowerMA: nil, currentMA: nil,
            tunnelRootName: "apciec9", deviceClass: 0x09, rawProperties: [:]
        )
        let forest = USBDeviceNode.buildTree(from: devices)
        let result = ChainDeviceAttribution.resolve(
            chain: chain, forest: forest, usbTunnelSwitchUIDs: [200, 300],
            expectedTunnelRootName: "apciec3"
        )
        #expect(result.regionOwner[10] == 200, "the display's hub, still rootless, is unaffected")
        #expect(result.regionOwner[11] != 300,
            "a wrong non-nil rootName must still be refused: fix 1 only trusts nil, never a disagreeing value")
    }

    @Test("TB5: the USB Port Map cross-check corroborates the formula without contradicting it")
    func tb5GameDriveWithConsistentPortMap() {
        let chain = tb5TwoBoxChain(displayUsbPortMap: Self.portMapData(Self.jhl9580PortMapHex))
        let devices = tb5TunnelHubDevices()
        let forest = USBDeviceNode.buildTree(from: devices)
        let result = ChainDeviceAttribution.resolve(chain: chain, forest: forest, usbTunnelSwitchUIDs: [200, 300])
        #expect(result.regionOwner[11] == 300)
        #expect(result.regionOwner[12] == 300)
    }

    @Test("TB5: a USB Port Map that contradicts the formula aborts the whole pass")
    func tb5PortMapContradictionAborts() {
        // A map that names USB4 ports 2-5 but never port 1, the formula's
        // own prediction for the dock's edge: a contradiction, not a
        // missing/truncated map, so the pass must abort rather than guess.
        let contradictingMap = Self.portMapData("028295038396048497058198")
        let chain = tb5TwoBoxChain(displayUsbPortMap: contradictingMap)
        let devices = tb5TunnelHubDevices()
        let forest = USBDeviceNode.buildTree(from: devices)
        let result = ChainDeviceAttribution.resolve(chain: chain, forest: forest, usbTunnelSwitchUIDs: [200, 300])
        #expect(result.regionOwner[11] == nil, "a contradicting port map must abort the pass, not fall back to the formula alone")
        #expect(result.regionOwner[12] == nil)
    }

    @Test("TB5: a USB Port Map with the right port numbers but a swapped adapter pairing aborts")
    func tb5PortMapSwappedAdapterPairingAborts() {
        // Same reference hex as `jhl9580PortMapHex`, but usb4Ports 1 and 2
        // have their adapters genuinely SWAPPED (1 -> 21, 2 -> 20, instead
        // of 1 -> 20, 2 -> 21), not merely one entry overwritten with a
        // duplicate value: the port numbers in the map are still all correct
        // (1-4) and every adapter number still appears exactly once, so a
        // check that only noticed a missing or repeated adapter would pass
        // this map by accident. The pairing is still wrong under the
        // increasing-order rule (USB4 2.0 s5.2.5), which the display's own
        // ordered adapter ports (20-23) below make checkable.
        let swappedMap = Self.portMapData("018195028294038396048497050000")
        let orderedAdapterPorts: [IOThunderboltPort] = [20, 21, 22, 23].map {
            IOThunderboltPort(
                portNumber: $0, socketID: nil, adapterType: .usb3Down,
                currentSpeed: nil, currentWidth: nil, targetWidth: nil,
                rawTargetSpeed: nil, linkBandwidthRaw: nil
            )
        }
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let display = IOThunderboltSwitch(
            id: 200, className: "IOThunderboltSwitchIntelJHL9580", vendorID: 32903,
            vendorName: "Apple", modelName: "Studio Display ", routerID: 1, depth: 1,
            routeString: 1, upstreamPortNumber: 1, maxPortNumber: 23,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xE), ports: orderedAdapterPorts,
            parentSwitchUID: 100, dromVendorID: 1452, dromModelID: 30978,
            usbPortMap: swappedMap
        )
        let dock = IOThunderboltSwitch(
            id: 300, className: "IOThunderboltSwitchIntelJHL9580", vendorID: 32903,
            vendorName: "Ugreen Group Limited", modelName: "TBT5 Docking Station 10-in-1",
            routerID: 1, depth: 2, routeString: 769, upstreamPortNumber: 1, maxPortNumber: 23,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xE), ports: [],
            parentSwitchUID: 200, dromVendorID: 11145, dromModelID: 1810
        )
        let chain = ThunderboltTopology.tree(from: root, in: [root, display, dock])
        let devices = tb5TunnelHubDevices()
        let forest = USBDeviceNode.buildTree(from: devices)
        let result = ChainDeviceAttribution.resolve(chain: chain, forest: forest, usbTunnelSwitchUIDs: [200, 300])
        #expect(result.regionOwner[11] == nil,
            "the map pairs usb4Port 1 with adapter 23, not the switch's own ordinal-0 adapter (20): a swapped pairing must abort, not just a missing port number")
        #expect(result.regionOwner[12] == nil)
    }

    @Test("TB5: the live rig's port map (upstream adapter paired with usb4Port 1) still fires")
    func tb5PortMapPairsUpstreamAdapterWithFirstPort() {
        // Regression tripwire for a real failure on the owner's own rig,
        // found by live verification after the swapped-pairing fix above
        // shipped: the parent switch's real ports are ONE upstream USB3
        // adapter (port 20) plus three downstream ones (21-23), not four
        // downstream ones. An ordered-adapters list built from downstream
        // adapters only put port 21 at ordinal 0, which the map's own
        // usb4Port-1 entry (adapter 20) then failed to match, aborting the
        // whole pass on the exact machine it exists for. The reference map
        // pairs usb4Port 1 with the UPSTREAM adapter (20), confirming the
        // ordering has to include it.
        let liveAdapterPorts: [IOThunderboltPort] = [
            IOThunderboltPort(
                portNumber: 20, socketID: nil, adapterType: .usb3Up,
                currentSpeed: nil, currentWidth: nil, targetWidth: nil,
                rawTargetSpeed: nil, linkBandwidthRaw: nil
            )
        ] + [21, 22, 23].map {
            IOThunderboltPort(
                portNumber: $0, socketID: nil, adapterType: .usb3Down,
                currentSpeed: nil, currentWidth: nil, targetWidth: nil,
                rawTargetSpeed: nil, linkBandwidthRaw: nil
            )
        }
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let display = IOThunderboltSwitch(
            id: 200, className: "IOThunderboltSwitchIntelJHL9580", vendorID: 32903,
            vendorName: "Apple", modelName: "Studio Display ", routerID: 1, depth: 1,
            routeString: 1, upstreamPortNumber: 1, maxPortNumber: 23,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xE), ports: liveAdapterPorts,
            parentSwitchUID: 100, dromVendorID: 1452, dromModelID: 30978,
            usbPortMap: Self.portMapData(Self.jhl9580PortMapHex)
        )
        let dock = IOThunderboltSwitch(
            id: 300, className: "IOThunderboltSwitchIntelJHL9580", vendorID: 32903,
            vendorName: "Ugreen Group Limited", modelName: "TBT5 Docking Station 10-in-1",
            routerID: 1, depth: 2, routeString: 769, upstreamPortNumber: 1, maxPortNumber: 23,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xE), ports: [],
            parentSwitchUID: 200, dromVendorID: 11145, dromModelID: 1810
        )
        let chain = ThunderboltTopology.tree(from: root, in: [root, display, dock])
        let devices = tb5TunnelHubDevices()
        let forest = USBDeviceNode.buildTree(from: devices)
        let result = ChainDeviceAttribution.resolve(chain: chain, forest: forest, usbTunnelSwitchUIDs: [200, 300])
        #expect(result.regionOwner[11] == 300,
            "the dock's hub must still attribute correctly when the parent's ordered adapters include its own upstream port")
        #expect(result.regionOwner[12] == 300)
    }

    // Review fix: red-proofing both tests below by temporarily relaxing the
    // named `candidates.count == chainNodes.count` gate to a no-op (still
    // requiring `!candidates.isEmpty`) showed BOTH still fail red, meaning
    // neither test isolates that gate specifically. "Fewer" is independently
    // caught by the per-edge "no candidate found at the expected hub port"
    // check inside the BFS walk (the dock's edge simply has nowhere to land
    // once the display's lone hub is claimed as the root); "more" is
    // independently caught by the walk's own final bijection check
    // (`claimedHubs.count == candidates.count`, since the extra hub is never
    // reached by any edge and so is never claimed). That is honest defense
    // in depth, not a flaw: production code is not weakened to make these
    // two tests isolate a single line, since a real topology could trip
    // either gate depending on exactly where the extra/missing hub sits.
    // These tests prove the PAIR of shapes (too few, too many) both abort
    // the whole pass, which is the requirement (spec 3.2's one-to-one
    // invariant); they do not prove which specific guard line catches each
    // one.

    @Test("TB5: candidate count mismatch (fewer hubs than boxes) aborts the pass")
    func tb5FewerCandidatesThanBoxesAborts() {
        let chain = tb5TwoBoxChain()
        // Only the display's own hub is present; the dock's is missing
        // (e.g. the dock fell back to plain USB, its own follow-up ticket).
        let devices = [
            device(id: 10, locationID: 0x0320_0000, vendorID: 0x8087, productID: 0x0B41, vendor: "Intel Corporation", product: nil, isHub: true),
        ]
        let forest = USBDeviceNode.buildTree(from: devices)
        let result = ChainDeviceAttribution.resolve(chain: chain, forest: forest, usbTunnelSwitchUIDs: [200, 300])
        #expect(result.regionOwner[10] == nil, "count mismatch must abort the whole pass, including the box that DOES have a candidate")
    }

    @Test("TB5: candidate count mismatch (an extra unrecognised hub) aborts the pass")
    func tb5MoreCandidatesThanBoxesAborts() {
        let chain = tb5TwoBoxChain()
        var devices = tb5TunnelHubDevices()
        // A THIRD candidate nested under the display's hub at hub port 2, a
        // port no switch in this 2-box chain ever asks for: the BFS walk
        // never looks for it (only the dock's port-1 edge exists), so
        // `rootCandidates` still comes out to exactly 1 and the per-edge
        // match still succeeds cleanly, leaving the final bijection check
        // (every candidate hub claimed) as the one that catches this shape.
        devices.append(
            device(id: 20, locationID: 0x0322_0000, vendorID: 0x8087, productID: 0x0B40, vendor: "Intel Corporation", product: nil, isHub: true)
        )
        let forest = USBDeviceNode.buildTree(from: devices)
        let result = ChainDeviceAttribution.resolve(chain: chain, forest: forest, usbTunnelSwitchUIDs: [200, 300])
        #expect(result.regionOwner[10] == nil, "3 candidates for 2 boxes must abort the whole pass, even when the extra one sits where nothing asks for it")
        #expect(result.regionOwner[11] == nil)
    }

    @Test("TB5: unrecognised silicon (unknown PID) never becomes a candidate, so the count gate fails closed")
    func tb5UnknownSiliconNeverCandidate() {
        let chain = tb5TwoBoxChain()
        // The dock's hub carries an Intel VID but a PID outside the
        // known-silicon table: not a candidate at all, so only 1 candidate
        // remains for 2 boxes.
        let devices = tb5TunnelHubDevices(dockHubProduct: 0xDEAD)
        let forest = USBDeviceNode.buildTree(from: devices)
        let result = ChainDeviceAttribution.resolve(chain: chain, forest: forest, usbTunnelSwitchUIDs: [200, 300])
        #expect(result.regionOwner[10] == nil)
        #expect(result.regionOwner[11] == nil)
    }

    @Test("TB5: an even (or zero) route byte aborts the pass")
    func tb5EvenRouteByteAborts() {
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let display = IOThunderboltSwitch(
            id: 200, className: "IOThunderboltSwitchIntelJHL9580", vendorID: 32903,
            vendorName: "Apple", modelName: "Studio Display ", routerID: 1, depth: 1,
            routeString: 1, upstreamPortNumber: 1, maxPortNumber: 23,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xE), ports: [], parentSwitchUID: 100
        )
        // Route String 1025 = 0x401: byte index 1 = 4, an EVEN adapter
        // number. Deliberately NOT the "obviously wrong port" case (an even
        // byte that lands nowhere): integer division makes (4-1)/2 == 1,
        // the SAME hub port byte 3 (the real, odd, dock reading) predicts,
        // so this specifically catches a parity check that was dropped
        // rather than one masked by a downstream "no candidate found" abort.
        let dock = IOThunderboltSwitch(
            id: 300, className: "IOThunderboltSwitchIntelJHL9580", vendorID: 32903,
            vendorName: "Ugreen Group Limited", modelName: "TBT5 Docking Station 10-in-1",
            routerID: 1, depth: 2, routeString: 1025, upstreamPortNumber: 1, maxPortNumber: 23,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xE), ports: [], parentSwitchUID: 200
        )
        let chain = ThunderboltTopology.tree(from: root, in: [root, display, dock])
        let devices = tb5TunnelHubDevices()
        let forest = USBDeviceNode.buildTree(from: devices)
        let result = ChainDeviceAttribution.resolve(chain: chain, forest: forest, usbTunnelSwitchUIDs: [200, 300])
        #expect(result.regionOwner[11] == nil, "an even route byte is not a valid Adapter Number under this formula")
    }

    @Test("TB5: no hub found at the expected port aborts the pass")
    func tb5MissingHubAtExpectedPortAborts() {
        let chain = tb5TwoBoxChain()
        // The dock's hub is at the WRONG locationID for its expected port
        // (0x03220000, hub port 2, not the expected port 1).
        let devices = [
            device(id: 10, locationID: 0x0320_0000, vendorID: 0x8087, productID: 0x0B41, vendor: "Intel Corporation", product: nil, isHub: true),
            device(id: 11, locationID: 0x0322_0000, vendorID: 0x8087, productID: 0x5787, vendor: "Intel Corporation", product: nil, isHub: true),
        ]
        let forest = USBDeviceNode.buildTree(from: devices)
        let result = ChainDeviceAttribution.resolve(chain: chain, forest: forest, usbTunnelSwitchUIDs: [200, 300])
        #expect(result.regionOwner[10] == nil, "no candidate at the expected hub port aborts the whole pass")
        #expect(result.regionOwner[11] == nil)
    }

    @Test("TB5: two boxes resolving to the same hub aborts the pass")
    func tb5TwoBoxesSameHubAborts() {
        // Two chain switches whose route bytes both predict hub port 1 under
        // the SAME parent: an impossible topology in practice, but the
        // isomorphism gate must still refuse it rather than let the second
        // walk silently overwrite the first's claim.
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let display = IOThunderboltSwitch(
            id: 200, className: "IOThunderboltSwitchIntelJHL9580", vendorID: 32903,
            vendorName: "Apple", modelName: "Studio Display ", routerID: 1, depth: 1,
            routeString: 1, upstreamPortNumber: 1, maxPortNumber: 23,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xE), ports: [], parentSwitchUID: 100
        )
        let dockA = IOThunderboltSwitch(
            id: 300, className: "IOThunderboltSwitchIntelJHL9580", vendorID: 32903,
            vendorName: "Ugreen Group Limited", modelName: "Dock A",
            routerID: 1, depth: 2, routeString: 769, upstreamPortNumber: 1, maxPortNumber: 23,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xE), ports: [], parentSwitchUID: 200
        )
        let dockB = IOThunderboltSwitch(
            id: 301, className: "IOThunderboltSwitchIntelJHL9580", vendorID: 32903,
            vendorName: "Ugreen Group Limited", modelName: "Dock B",
            routerID: 1, depth: 2, routeString: 769, upstreamPortNumber: 1, maxPortNumber: 23,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xE), ports: [], parentSwitchUID: 200
        )
        let chain = ThunderboltTopology.tree(from: root, in: [root, display, dockA, dockB])
        // Only ONE hub at hub port 1, for two switches that both expect it.
        // A third hub exists so the count gate (3 candidates for 3 boxes)
        // does not itself abort the pass before the port-collision check runs.
        let devices = [
            device(id: 10, locationID: 0x0320_0000, vendorID: 0x8087, productID: 0x0B41, vendor: "Intel Corporation", product: nil, isHub: true),
            device(id: 11, locationID: 0x0321_0000, vendorID: 0x8087, productID: 0x5787, vendor: "Intel Corporation", product: nil, isHub: true),
            device(id: 12, locationID: 0x0329_0000, vendorID: 0x8087, productID: 0x0B40, vendor: "Intel Corporation", product: nil, isHub: true),
        ]
        let forest = USBDeviceNode.buildTree(from: devices)
        let result = ChainDeviceAttribution.resolve(chain: chain, forest: forest, usbTunnelSwitchUIDs: [200, 300, 301])
        #expect(result.regionOwner[11] == nil, "only one candidate can sit at hub port 1; the second box's edge finds none and the whole pass aborts")
    }

    @Test("TB5: the Gen T adapter alone (without a confirmed shared controller) still opens the scope gate")
    func tb5GenTAdapterAloneOpensScopeGate() {
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let genTPort = IOThunderboltPort(
            portNumber: 20, socketID: nil, adapterType: .usbGenTUp,
            currentSpeed: nil, currentWidth: nil, targetWidth: nil,
            rawTargetSpeed: nil, linkBandwidthRaw: nil
        )
        let display = IOThunderboltSwitch(
            id: 200, className: "IOThunderboltSwitchIntelJHL9580", vendorID: 32903,
            vendorName: "Apple", modelName: "Studio Display ", routerID: 1, depth: 1,
            routeString: 1, upstreamPortNumber: 1, maxPortNumber: 23,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xE), ports: [genTPort], parentSwitchUID: 100
        )
        let dock = IOThunderboltSwitch(
            id: 300, className: "IOThunderboltSwitchIntelJHL9580", vendorID: 32903,
            vendorName: "Ugreen Group Limited", modelName: "TBT5 Docking Station 10-in-1",
            routerID: 1, depth: 2, routeString: 769, upstreamPortNumber: 1, maxPortNumber: 23,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xE), ports: [], parentSwitchUID: 200
        )
        let chain = ThunderboltTopology.tree(from: root, in: [root, display, dock])
        let devices = tb5TunnelHubDevices()
        let forest = USBDeviceNode.buildTree(from: devices)
        // usbTunnelSwitchUIDs deliberately empty: only the Gen T adapter
        // signals the shared-controller shape here.
        let result = ChainDeviceAttribution.resolve(chain: chain, forest: forest, usbTunnelSwitchUIDs: [])
        #expect(result.regionOwner[11] == 300, "a Gen T adapter alone must open the scope gate, per spec 3.1's corroborating OR")
    }

    @Test("TB5: neither the shared-controller shape nor a Gen T adapter, so the scope gate stays closed")
    func tb5ScopeGateClosedWithoutEitherSignal() {
        let chain = tb5TwoBoxChain()
        let devices = tb5TunnelHubDevices()
        let forest = USBDeviceNode.buildTree(from: devices)
        // usbTunnelSwitchUIDs empty and no Gen T adapter anywhere in the
        // chain (tb5TwoBoxChain's switches carry no ports at all): the
        // scope gate must refuse to run, leaving the hubs unattributed by
        // this pass. They also carry no name/vendor evidence, so they stay
        // fully unattributed.
        let result = ChainDeviceAttribution.resolve(chain: chain, forest: forest, usbTunnelSwitchUIDs: [])
        #expect(result.regionOwner[11] == nil)
        #expect(result.regionOwner[12] == nil)
    }

    @Test("TB5: a structural hub whose own NUMERIC identity disagrees is demoted to structurallyConflicted, not absorbed or forcedPortLevel")
    func tb5NumericConflictDemotesToStructurallyConflicted() {
        // Review fix: the old body changed device 11's vendorID/productID to
        // Apple's numeric identity (1452/30978) to force a "conflict". That
        // removed it from the Intel silicon table (spec 3.2: vendorID must
        // be 0x8087), so the candidate-count gate (only 1 candidate for 2
        // boxes) aborted the WHOLE TB5 pass before the conflict path could
        // ever run: the nil assertion passed because the pass never fired,
        // not because it correctly demoted a conflict.
        //
        // A later fix kept device 11's valid Intel TB5 identity but forced
        // the conflict through its `productName` (an exact-NAME conflict),
        // which made the pass run for real but tested the wrong precedence
        // branch: this test's own name and description promise a NUMERIC
        // conflict, and `namedConflict` and `numericConflict` are two
        // separately-computed booleans in `resolve()`'s candidate loop, so a
        // name-only fixture never touches `numericIdentity(of:)` at all.
        //
        // Fixed for real: device 11 keeps its valid Intel TB5 identity
        // (vendorID 0x8087, productID 0x5787) AND a nil `productName`, so no
        // `exact`/`namedConflict` evidence exists for it whatsoever. The
        // conflict instead comes from `numericIdentity(of:)`: the DISPLAY
        // switch's own DROM is set to that SAME vendorID/productID pair
        // (0x8087/0x5787), so `numericIdentity(of: hub11)` resolves to the
        // display (200) purely on the number pair, while the structural
        // route-string/locationID walk independently proposes the dock
        // (300). That is a genuine `numericConflict`, with `namedConflict`
        // structurally impossible to have fired (there is no name to match).
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let display = IOThunderboltSwitch(
            id: 200, className: "IOThunderboltSwitchIntelJHL9580", vendorID: 32903,
            vendorName: "Apple", modelName: "Studio Display ", routerID: 1, depth: 1,
            routeString: 1, upstreamPortNumber: 1, maxPortNumber: 23,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xE), ports: [],
            parentSwitchUID: 100, dromVendorID: 0x8087, dromModelID: 0x5787
        )
        let dock = IOThunderboltSwitch(
            id: 300, className: "IOThunderboltSwitchIntelJHL9580", vendorID: 32903,
            vendorName: "Ugreen Group Limited", modelName: "TBT5 Docking Station 10-in-1",
            routerID: 1, depth: 2, routeString: 769, upstreamPortNumber: 1, maxPortNumber: 23,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xE), ports: [],
            parentSwitchUID: 200, dromVendorID: 11145, dromModelID: 1810
        )
        let chain = ThunderboltTopology.tree(from: root, in: [root, display, dock])
        let devices = tb5TunnelHubDevices()
        let forest = USBDeviceNode.buildTree(from: devices)
        let result = ChainDeviceAttribution.resolve(chain: chain, forest: forest, usbTunnelSwitchUIDs: [200, 300])
        // hub11 sits nested UNDER hub10 in the raw USB tree (locationID
        // 0x03210000 climbs to 0x03200000, hub10's own locationID), which is
        // exactly the shape the TB5 pass exists to override: without it, hub
        // 11 would inherit the display purely from USB nesting. A
        // `structurallyConflicted` demotion is not a `forcedPortLevel`
        // boundary: it removes the TB5 claim but does not block plain
        // inheritance, so once the claim is refused, hub 11 falls straight
        // back to inheriting from hub10's own region (the display, 200).
        // That is the SAME observable outcome as the exact-name-conflict
        // case just above it in this file, reached for a different reason:
        // there the display placement was the device's OWN evidence kept in
        // preference to the conflicting structural one; here it is the
        // fallback default with no placement of its own at all. Distinguishing
        // the two is exactly why `regionRoots` is checked directly below,
        // not just `regionOwner`.
        #expect(result.regionOwner[11] == 200,
            "with its TB5 claim refused, the hub falls back to inheriting hub10's region (the display), not the conflicting dock")
        #expect(result.regionRoots[11] == nil,
            "unlike the exact-name-conflict case, this device has no evidence of its own: 200 is inherited, not a region root")
        #expect(result.regionOwner[11] != 300,
            "the TB5-derived switch id must not win over a genuine numeric disagreement")
        // Excluded from absorbed only (per `.tb5TunnelHubMap`'s precedence
        // tier, spec 3.5): unlike `.pcieStageBMatch`, a conflict here never
        // reaches `forcedPortLevel`.
        #expect(!result.absorbed.contains(11),
            "a device with disagreeing structural and numeric evidence is not collapsed into the chain row")
        #expect(!result.portLevelBoundaries.contains(11),
            "a tb5TunnelHubMap conflict demotes to structurallyConflicted, never forcedPortLevel (that tier is Stage B's PCI-path proof)")
    }

    @Test("TB5: a forcedPortLevel boundary nested inside a TB5-attributed hub blocks inheritance, and the TB5 attribution elsewhere is unaffected")
    func tb5AttributionCoexistsWithForcedPortLevelBoundary() {
        // A Stage B PCIe join (`resolvePCIeTunnelCandidate`, modelled on
        // `PCIeTunnelStageBv2Tests`' Test 16b) that runs with COMPLETE,
        // usable inputs but finds zero matches: a genuine `.portLevel`
        // finding, which lands the device straight in `forcedPortLevelIDs`
        // with no name/numeric conflict needed. Both chain switches
        // (display, dock) carry a valid PCIe up-adapter so the completeness
        // gate lets the join actually run rather than falling back to the
        // Stage A shortcut.
        let displayUpPath = "IOService:/AppleARMPE/arm-io/apciec2@30000000/pcic1-bridge@0"
        let dockUpPath = "IOService:/AppleARMPE/arm-io/apciec2@30000000/pcic1-bridge@1"
        let displayPcieUp = IOThunderboltPort(
            portNumber: 5, socketID: nil, adapterType: .pcieUp,
            currentSpeed: nil, currentWidth: nil, targetWidth: nil,
            rawTargetSpeed: nil, linkBandwidthRaw: nil,
            pciPath: displayUpPath, pciEntryID: 1
        )
        let dockPcieUp = IOThunderboltPort(
            portNumber: 5, socketID: nil, adapterType: .pcieUp,
            currentSpeed: nil, currentWidth: nil, targetWidth: nil,
            rawTargetSpeed: nil, linkBandwidthRaw: nil,
            pciPath: dockUpPath, pciEntryID: 2
        )
        let root = chainSwitch(id: 100, parent: nil, vendor: "Apple", model: "Mac", depth: 0)
        let display = IOThunderboltSwitch(
            id: 200, className: "IOThunderboltSwitchIntelJHL9580", vendorID: 32903,
            vendorName: "Apple", modelName: "Studio Display ", routerID: 1, depth: 1,
            routeString: 1, upstreamPortNumber: 1, maxPortNumber: 23,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xE), ports: [displayPcieUp],
            parentSwitchUID: 100, dromVendorID: 1452, dromModelID: 30978
        )
        let dock = IOThunderboltSwitch(
            id: 300, className: "IOThunderboltSwitchIntelJHL9580", vendorID: 32903,
            vendorName: "Ugreen Group Limited", modelName: "TBT5 Docking Station 10-in-1",
            routerID: 1, depth: 2, routeString: 769, upstreamPortNumber: 1, maxPortNumber: 23,
            supportedSpeed: SupportedSpeedMask(rawValue: 0xE), ports: [dockPcieUp],
            parentSwitchUID: 200, dromVendorID: 11145, dromModelID: 1810
        )
        let chain = ThunderboltTopology.tree(from: root, in: [root, display, dock])

        var devices = tb5TunnelHubDevices()
        // Nested UNDER the dock's own TB5 hub (id 11, locationID
        // 0x0321_0000), the same position the WD Game Drive occupies, so
        // this proves the boundary specifically, not just "an unrelated
        // top-level device stays unattributed" (which inheritance would
        // never have reached anyway).
        devices.append(contentsOf: [
            // Complete, usable Stage B inputs, but its ancestor entry IDs
            // (9999) match neither switch's `pciEntryID` (1, 2): zero
            // matches, so this is `.portLevel`, not `.fallbackToStageA`.
            USBDevice(
                id: 40, locationID: 0x0321_2000, vendorID: 0x0BDA, productID: 0x1,
                vendorName: nil, productName: nil, serialNumber: nil,
                usbVersion: nil, speedRaw: 3, busPowerMA: nil, currentMA: nil,
                isThunderboltTunnelled: true,
                tunnelBridgeDepth: nil,
                tunnelRootName: "apciec2",
                tunnelCarrier: .pcieTunnel,
                tunnelControllerRegistryPath: dockUpPath + "/pcic1-bridge@9/xhci@0",
                tunnelAncestorEntryIDs: [9999],
                deviceClass: 0x09,
                rawProperties: [:]
            ),
            // A child of the forced device: proves the boundary is sticky
            // down the subtree, not just refused for the forced node itself.
            device(id: 41, locationID: 0x0321_2100, vendorID: 0x0BDA, vendor: "Realtek", product: nil, isHub: false),
        ])
        let forest = USBDeviceNode.buildTree(from: devices)
        let result = ChainDeviceAttribution.resolve(chain: chain, forest: forest, usbTunnelSwitchUIDs: [200, 300])

        // The TB5 attribution elsewhere in the SAME forest is unaffected.
        #expect(result.regionOwner[10] == 200, "the display's own tunnel hub still attributes to the display")
        #expect(result.regionOwner[11] == 300, "the dock's own tunnel hub still attributes to the dock")
        #expect(result.regionOwner[12] == 300, "the WD Game Drive, the dock hub's OTHER child, still inherits the dock")

        // The forced boundary itself, and its subtree, are not swallowed by
        // the dock's TB5 ownership even though they sit physically nested
        // inside it.
        #expect(result.portLevelBoundaries.contains(40), "fixture: device 40 must be the forced boundary")
        #expect(result.regionOwner[40] == nil, "a forcedPortLevel device never inherits ownership, even from a TB5-attributed parent hub")
        #expect(result.regionOwner[41] == nil, "the boundary is sticky: a device below a forced node stays unattributed too")
    }
}
