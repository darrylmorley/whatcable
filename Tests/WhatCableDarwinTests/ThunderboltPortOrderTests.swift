import Foundation
import Testing
@testable import WhatCableDarwinBackend
@testable import WhatCableCore

// Unit coverage for `IOIOThunderboltSwitchWatcher.portsInPortNumberOrder(_:)`,
// the ordering rule behind `parsePorts(of:)`. Following the convention
// `HPMPortKeyOrderTests` documents: the pure rule is pinned here, and the
// consequence that depends on it (a lane pair whose two lanes decode
// different rates) is pinned in `ThunderboltLabelsTests`.
//
// Registry order is NOT port order. The corpus dump prints lane 2 before
// lane 1 on 21 machines, and one live consumer in `WhatCableCore` takes the
// first trained lane of what it is handed:
// `ThunderboltTopology.trainedDownstreamLanePort`, which feeds the link rate.
// On the 4 dual-link pairs whose lanes decode different rates, the wrong pick
// publishes the higher figure on the lower link (`m4max_macos26.5.2_f`
// socket 2: 120 Gb/s on an 80 Gb/s link).
//
// `DataLinkDiagnostic.partnerSwitch` used to be a second consumer, and in
// registry order 21 CIO-active ports lost their Thunderbolt partner. It now
// consults both lanes of the socket, so it is order-independent: the
// device-cap corpus replay returns the same 40 device limits either way.
@Suite("IOThunderboltSwitch port ordering")
struct ThunderboltPortOrderTests {

    private func lane(_ portNumber: Int) -> IOThunderboltPort {
        IOThunderboltPort(
            portNumber: portNumber,
            socketID: "1",
            adapterType: .lane,
            currentSpeed: .usb4Tb4,
            currentWidth: LinkWidth(rawValue: 0x2),
            targetWidth: nil,
            rawTargetSpeed: nil,
            linkBandwidthRaw: nil
        )
    }

    @Test("Ports come back in port-number order, not the order the registry gave them")
    func sortsByPortNumber() {
        // m3max_macos26.5_h socket 1 verbatim: the probe prints port 2, then
        // the protocol adapters, then port 1.
        let found = [lane(2), lane(6), lane(5), lane(1), lane(4), lane(3)]
        let ordered = IOIOThunderboltSwitchWatcher.portsInPortNumberOrder(found)
        #expect(ordered.map(\.portNumber) == [1, 2, 3, 4, 5, 6])
    }

    @Test("Already-ordered input is left alone")
    func alreadyOrdered() {
        let found = [lane(1), lane(2), lane(7)]
        #expect(IOIOThunderboltSwitchWatcher.portsInPortNumberOrder(found).map(\.portNumber) == [1, 2, 7])
    }

    @Test("Degenerate inputs are handled")
    func degenerateCases() {
        #expect(IOIOThunderboltSwitchWatcher.portsInPortNumberOrder([]).isEmpty)
        #expect(IOIOThunderboltSwitchWatcher.portsInPortNumberOrder([lane(4)]).map(\.portNumber) == [4])
    }

    // The three tests above pin the ordering RULE. This one pins the only
    // place production applies it. `parsePorts` is where a switch gets its
    // ports and nowhere else does, and the version of it that walks IOKit
    // needs a live `io_service_t` on a Thunderbolt Mac, so the registry walk
    // is injected here and the assembly step driven directly. Without this,
    // deleting the sort from `parsePorts` left every test in the suite green
    // while production went back to publishing registry order.
    @Test("parsePorts orders what the registry walk returned")
    func parsePortsOrdersWhatTheRegistryWalkReturned() {
        // m3max_macos26.5_h socket 1 verbatim, the order the walk hands back.
        let walked = [lane(2), lane(6), lane(5), lane(1), lane(4), lane(3)]
        let assembled = IOIOThunderboltSwitchWatcher.parsePorts(readChildren: { walked })
        #expect(assembled.map(\.portNumber) == [1, 2, 3, 4, 5, 6])
    }

    @Test("parsePorts passes an empty walk straight through")
    func parsePortsHandlesEmptyWalk() {
        #expect(IOIOThunderboltSwitchWatcher.parsePorts(readChildren: { [] }).isEmpty)
    }
}
