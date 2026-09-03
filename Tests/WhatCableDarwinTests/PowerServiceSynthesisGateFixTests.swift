import Testing
import Foundation
import IOKit
@testable import WhatCableDarwinBackend
@testable import WhatCableCore

/// PR #599 review gate, round 1. Two findings against the commit that moved
/// the synthesis gate chain into a shared static.
@Suite("PowerService synthesis gate fixes")
struct PowerServiceSynthesisGateFixTests {

    // MARK: Finding 1, the 1 Hz bulk property fetch

    /// `PowerService.refresh()` calls `readAllPorts()` once a second. Before
    /// this fix that reached `IORegistryEntryCreateCFProperties`, the bulk
    /// fetch this repo documents as able to abort the process from inside
    /// `IOCFUnserializeBinary` when a service is torn down mid-read (issue
    /// #181). It paid that risk only to fill `rawProperties`, which exists
    /// for CLI verbose and `--raw`.
    ///
    /// The per-key fallback inside `AppleHPMInterface.from` is crash-safe and
    /// covers every key the synthesis chain actually reads, so the fix is to
    /// withhold the bulk closure here. This pins that: whatever this machine
    /// publishes, no key outside the documented fallback set comes back.
    @Test("readAllPorts does not use the bulk property fetch")
    func readAllPortsSkipsBulkFetch() {
        let ports = AppleHPMInterfaceWatcher.readAllPorts()
        // Floor, so a machine that returned nothing cannot pass this
        // vacuously. Every Mac this app supports has USB-C ports.
        #expect(!ports.isEmpty, "no HPM ports read; this test proves nothing on this machine")

        let allowed = Set(AppleHPMInterface.rawPropertyFallbackKeys)
        for port in ports {
            let extras = Set(port.rawProperties.keys).subtracting(allowed)
            #expect(extras.isEmpty,
                    "\(port.serviceName) carries keys only the bulk fetch produces: \(extras.sorted())")
        }
    }

    /// The fix must not degrade what the synthesis chain reads. The chain
    /// gates on `port.portKey`, which comes from `identity`, which reads
    /// `rawProperties["PortType"]`. That key is in the per-key fallback set,
    /// so withholding the bulk fetch leaves it intact. Pinned because the
    /// review brief assumed synthesis read none of `rawProperties`, and it
    /// does, through `portKey`.
    @Test("Withholding the bulk fetch still resolves the port key synthesis gates on")
    func portKeySurvivesWithoutBulkFetch() {
        let values: [String: Any] = [
            "PortTypeDescription": "USB-C",
            "PortType": 2,
            "PortNumber": 1,
            "ConnectionActive": true,
        ]
        let port = AppleHPMInterface.from(
            entryID: 1,
            serviceName: "Port-USB-C@1",
            className: "AppleHPMInterface",
            read: { values[$0] },
            readAll: nil,
            busIndex: nil,
            hpmControllerUUID: nil
        )
        let resolved = try? #require(port)
        #expect(resolved?.portKey == "2/1")
        #expect(resolved?.rawProperties["PortType"] == "2")
        #expect(resolved?.connectionActive == true)
    }

    // MARK: Finding 2, the pre-filter disagreeing with the chain

    /// `PowerService.refresh()` hoists an `externalConnected` check in front
    /// of the chain, to avoid a full HPM class walk once a second on a
    /// machine that is not charging. The value it hoisted was built with
    /// `wcBool`, which returns false for an absent key, while the chain
    /// defaults an absent key to true. On a battery dictionary without that
    /// key the service therefore skipped synthesis where the chain would have
    /// proceeded: a false negative in exactly the direction this feature
    /// exists to prevent.
    ///
    /// Both now read through this one helper, so they cannot disagree.
    @Test("An absent ExternalConnected key reads as connected, not disconnected")
    func absentExternalConnectedReadsAsConnected() {
        #expect(PowerSourceWatcher.externalConnectedFlag(from: [:]) == true)
        #expect(PowerSourceWatcher.externalConnectedFlag(from: ["BatteryInstalled": true]) == true)
        // The value the old pre-filter used, kept here so the disagreement
        // this test exists for is visible rather than described.
        #expect(wcBool([:]["ExternalConnected"]) == false)
    }

    @Test("A present ExternalConnected key is honoured either way")
    func presentExternalConnectedIsHonoured() {
        #expect(PowerSourceWatcher.externalConnectedFlag(from: ["ExternalConnected": true]) == true)
        #expect(PowerSourceWatcher.externalConnectedFlag(from: ["ExternalConnected": false]) == false)
    }

    /// Round 3, item 5. A present but unreadable value used to fall through
    /// the `as? NSNumber` cast to the absent-key default of `true`, which is
    /// the permissive branch: it lets synthesis run and lets the resolver
    /// start an estimate. That is the same anti-pattern this PR already fixed
    /// for `Class` in `parseOption`, where a present-but-unusable value now
    /// counts as "something was reported" instead of "nothing was".
    ///
    /// Fail-safe here points the other way from the absent case, and that is
    /// deliberate. Absent means the key was never published, which is the
    /// pre-existing "assume plugged in" default and stays. Present but
    /// unreadable means the key IS published and we could not decode it, so
    /// we do not know the machine is on external power, and claiming it is
    /// would start a charging-path measurement on a machine that may be on
    /// battery. Losing the estimate is recoverable; publishing a resistance
    /// figure measured on the wrong power state is not.
    @Test("A present but unreadable ExternalConnected value does not read as connected")
    func presentButUnreadableExternalConnectedIsNotConnected() {
        #expect(PowerSourceWatcher.externalConnectedFlag(from: ["ExternalConnected": NSNull()]) == false)
        #expect(PowerSourceWatcher.externalConnectedFlag(from: ["ExternalConnected": "true"]) == false)
        #expect(PowerSourceWatcher.externalConnectedFlag(from: ["ExternalConnected": Data([1])]) == false)
        // The absent-key default is unchanged by that, and this is the line
        // that would go red if the fix were written as a blanket `?? false`.
        #expect(PowerSourceWatcher.externalConnectedFlag(from: [:]) == true)
    }

    /// Round 3, item 3. The shared `externalConnected` binding in
    /// `PowerService.refresh()` now reads through `externalConnectedFlag`
    /// instead of `wcBool`. On every machine in the corpus the battery
    /// dictionary publishes the key (measured 2026-09-03: all 1338 folders
    /// with a non-empty `AppleSmartBattery` dump carry it), so this pins that
    /// the two agree wherever the key is present and an `NSNumber`, which is
    /// what IOKit publishes a `CFBoolean` as. The change is a no-op there and
    /// only bites on the absent and unreadable cases.
    @Test("With the key present the shared binding's old and new readings agree")
    func flagMatchesWCBoolWhereverTheKeyIsPresent() {
        for value in [true, false] {
            let dict: [String: Any] = ["ExternalConnected": NSNumber(value: value)]
            #expect(PowerSourceWatcher.externalConnectedFlag(from: dict) == wcBool(dict["ExternalConnected"]))
            #expect(PowerSourceWatcher.externalConnectedFlag(from: dict) == value)
        }
    }

    // MARK: Finding 2, round 2: the same disagreement one step further down

    /// Round 1 pointed the synthesis pre-filter at `externalConnectedFlag`,
    /// but `refresh()` went on handing the `wcBool`-derived value to
    /// `ChargingInputResolver.fingerprint`. On a battery dictionary with no
    /// `ExternalConnected` key that made the feature contradict itself:
    /// synthesis ran, produced a source, and the resolver then rejected the
    /// tick anyway on its own external-power gate, so the estimate still
    /// never appeared. The named line had changed; the behaviour had not.
    ///
    /// This pins the CONSEQUENCE the two values have at the resolver, which
    /// is what makes using the wrong one at that call site a bug. It does not
    /// reach into `refresh()`: that function takes no parameters and reads
    /// `AppleSmartBatteryReader.properties()` and the SMC directly, so there
    /// is no seam to inject an absent-key dictionary through, and building
    /// one is a wider change than this fix is allowed to be.
    @Test("The two external-power values disagree at the resolver on an absent key")
    func absentExternalConnectedChangesTheResolverVerdict() {
        // A dictionary shaped like a laptop that is charging but publishes no
        // `ExternalConnected` key.
        let battery: [String: Any] = ["BatteryInstalled": true]
        let winning = PowerOption(
            voltageMV: 20_000, maxCurrentMA: 4_700, maxPowerMW: 94_000, supplyKind: .fixed
        )
        let source = PowerSource(
            id: 1, name: "USB-PD", parentPortType: 0x2, parentPortNumber: 4,
            options: [winning], winning: winning, hpmControllerUUID: nil
        )
        func resolve(externalConnected: Bool) -> ChargingInputResolver.Fingerprint? {
            ChargingInputResolver.fingerprint(
                sources: [source],
                batteryInstalled: true,
                externalConnected: externalConnected,
                chargerAttached: true
            )
        }

        // The value the resistance feed now uses: an estimate can start.
        let viaFlag = PowerSourceWatcher.externalConnectedFlag(from: battery)
        #expect(viaFlag == true)
        #expect(resolve(externalConnected: viaFlag) != nil)

        // The value it used to be handed: the tick is rejected outright, so
        // the estimate stays `insufficient` forever no matter how long the
        // machine charges.
        let viaWCBool = wcBool(battery["ExternalConnected"])
        #expect(viaWCBool == false)
        #expect(resolve(externalConnected: viaWCBool) == nil)
    }
}
