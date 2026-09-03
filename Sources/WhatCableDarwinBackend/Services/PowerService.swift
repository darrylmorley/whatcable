import Foundation
import IOKit
import WhatCableCore

/// Joins `AppleSmartBattery`, the SMC and the port tree into one per-tick
/// power picture.
///
/// Named a watcher until now, and it never was one: a watcher reads a single
/// IOKit class and publishes it, with no joins. This reads three sources,
/// merges them by precedence, tracks a regression across ticks and assembles a
/// snapshot. The locked architecture calls that a service, and puts services in
/// this folder, so it now lives here under that name.
///
/// The rename is the whole of the change: no logic moved with it.
@MainActor
public final class PowerService: ObservableObject {
    @Published public private(set) var latestSnapshot: PowerMonitorSnapshot?

    public let snapshots: AsyncStream<PowerMonitorSnapshot>

    private var continuation: AsyncStream<PowerMonitorSnapshot>.Continuation?
    private var pollTask: Task<Void, Never>?

    /// Test seam. `WatcherDeallocationTests` needs to hold the task itself to
    /// prove `deinit` cancels it: reading it through the service would keep the
    /// service alive and defeat the test.
    var pollTaskForTesting: Task<Void, Never>? { pollTask }
    private var accumulator = RegressionAccumulator()
    private var cachedPortKeys: [String]?
    // Per-port power lives in the SMC, not IOKit. The reader is opened lazily on
    // the first refresh that needs it; the UUID map ties each SMC channel to its
    // physical port.
    private let smcReader: SMCPowerReader
    /// Whether `stop()` may close the reader.
    ///
    /// This is the whole point of the injection below. This service is
    /// exclusive to one screen and tears itself down when that screen closes,
    /// whereas the shared reader belongs to `WatcherHub` and feeds the
    /// always-on menu bar readout. Closing a shared connection when the Power
    /// Monitor window closes would pull it out from under the menu bar. It
    /// would self-heal on the next read, since `open()` is lazy and idempotent,
    /// which is exactly why the bug would be invisible rather than absent.
    private let ownsSMCReader: Bool

    /// Test seam. The invariant it guards (only an owner may close the shared
    /// AppleSMC connection) is one whose breakage self-heals silently, so it
    /// needs a test rather than a hand trace.
    var ownsSMCReaderForTesting: Bool { ownsSMCReader }
    private var cachedUUIDMap: [String: String]?

    /// - Parameter smcReader: the process-wide reader to share, or nil to own a
    ///   private one. In-process callers pass `WatcherHub.shared.smcReader`; the
    ///   CLI and widget, being separate processes with no hub, pass nothing.
    public init(smcReader: SMCPowerReader? = nil) {
        self.smcReader = smcReader ?? SMCPowerReader()
        self.ownsSMCReader = smcReader == nil
        var continuation: AsyncStream<PowerMonitorSnapshot>.Continuation?
        snapshots = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    public func start() {
        guard pollTask == nil else { return }
        cachedPortKeys = Self.hpmPortKeys()
        // Store nil (not an empty map) when the lookup comes back empty, so the
        // desktop path below re-fetches rather than negative-caching "no ports"
        // for the whole session.
        let uuidMap = HPMPortUUIDMap.current()
        cachedUUIDMap = uuidMap.isEmpty ? nil : uuidMap
        // `[weak self]` is load-bearing, not decoration. A bare `refresh()` here
        // captures self strongly, and self holds pollTask, so the two keep each
        // other alive: the object can then only ever be freed if someone calls
        // stop() first. Every sibling watcher captures weakly for this reason.
        //
        // SLEEP FIRST, THEN GUARD. The order matters and is easy to get wrong.
        // Binding `guard let self` at the TOP of the loop body holds a strong
        // reference for the rest of that iteration, which includes the sleep,
        // so the service stays alive for up to a full poll interval after its
        // owner lets go. That defeats the point: for ~99.98% of any 1 Hz cycle
        // the task is asleep, so that is the case that actually happens.
        // Binding after the sleep confines the strong reference to the
        // synchronous refresh() call. Same shape as PortDiagnosticsWatcher.
        //
        // The first refresh stays outside the loop so opening the monitor still
        // paints immediately rather than after a 1s wait.
        pollTask = Task { @MainActor [weak self] in
            self?.refresh()
            while !Task.isCancelled {
                // 1s for a snappier live monitor. Only runs while the Power
                // Monitor window (or `whatcable --monitor`) is open, so the
                // extra IOKit reads are bounded to that session.
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                // `guard let self` rather than `self?.refresh()`: the optional
                // form would keep looping and sleeping forever once the service
                // is gone, since nothing else ends the loop.
                guard let self else { return }
                self.refresh()
            }
        }
    }

    /// Cancels the poll promptly when the service is dropped without `stop()`.
    ///
    /// With the retain cycle above removed, that is now reachable: an owner can
    /// release its only reference and expect teardown. This is a tidiness
    /// backstop, not a leak fix, and the distinction is worth keeping straight:
    /// the `[weak self]` capture is what actually bounds the work. Without this
    /// deinit the task would still stop, but only after waking from its current
    /// sleep (up to one poll interval), finding `self` nil and returning. What
    /// this buys is that the task ends immediately rather than sitting in a
    /// pointless sleep first.
    ///
    /// `Task.cancel()` is safe from any thread, which is what lets this run in a
    /// `nonisolated deinit` on a `@MainActor` class. Unlike
    /// `PortDiagnosticsWatcher` this service registers no IOKit notification
    /// callbacks holding an unretained refcon, so there is no use-after-free
    /// window here, only a leak to close.
    deinit {
        pollTask?.cancel()
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
        accumulator.reset()
        cachedPortKeys = nil
        cachedUUIDMap = nil
        // Only close a reader this service created. See `ownsSMCReader`.
        if ownsSMCReader { smcReader.close() }
        latestSnapshot = nil
    }

    /// Updates the cached UUID-to-portKey map from already-captured HPM port
    /// data. Call this whenever the `AppleHPMInterfaceWatcher` publishes a
    /// fresh port list so this service uses the live-captured UUIDs
    /// instead of performing a redundant IOKit sweep via `HPMPortUUIDMap.current()`.
    ///
    /// When the supplied ports carry UUIDs (M3+) the map is rebuilt from them.
    /// When no UUIDs are present (M1/M2 or empty list) the existing cached map
    /// is left untouched so a valid map captured at `start()` is not evicted.
    public func updatePorts(_ ports: [AppleHPMInterface]) {
        let map = HPMPortUUIDMap.from(ports: ports)
        if !map.isEmpty {
            cachedUUIDMap = map
        }
    }

    /// Discards the accumulated regression samples so the resistance estimate
    /// rebuilds from scratch. Call this when the charging cable changes outside
    /// of a PD renegotiation: the accumulator auto-resets on contract fingerprint
    /// change, but an explicit reset is provided for cases (e.g. the session
    /// monitor's cable-swap detection) where the caller needs the buffer cleared
    /// immediately. The next `refresh()` returns an `insufficient` estimate until
    /// enough new samples accumulate.
    public func resetResistanceBaseline() {
        accumulator.reset()
    }

    public func refresh() {
        let timestamp = Date()
        // Optional now: desktop Macs (Mac mini / Studio / Pro) may have no
        // AppleSmartBattery node at all. The old early-return on a missing node
        // is what left the Power Monitor spinning forever there (#285). We now
        // always emit a snapshot and fill per-port data from the SMC instead.
        let dict = AppleSmartBatteryReader.properties()
        let telemetry = wcDictionary(dict?["PowerTelemetryData"])
        // On a laptop this comes from the battery controller. On a desktop the
        // battery telemetry is absent, so every field is 0; the desktop branch
        // below overrides it from the SMC's DC-in rail.
        var system = PowerSample(
            timestamp: timestamp,
            systemVoltageIn: wcInt(telemetry["SystemVoltageIn"]),
            systemCurrentIn: wcInt(telemetry["SystemCurrentIn"]),
            systemPowerIn: wcInt(telemetry["SystemPowerIn"])
        )

        let portKeys = cachedPortKeys ?? []
        // The contracted per-port data is attributed from the self-keyed power
        // sources (IOPortFeaturePowerSource), which state the port outright.
        // PortControllerInfo (an unlabelled array inside AppleSmartBattery) only
        // enriches the decoded volts/amps, matched by watts; it never assigns a
        // port. The old code keyed it by array offset, which landed a charger's
        // watts on the wrong port's card.
        let realSources = PowerSourceWatcher.readAllPowerSources()
        // Per-port power-out, live-first. Priority: live SMC channel (M3+) >
        // PowerOutDetails > contracted controller info. PowerOutDetails is the
        // AppleSmartBattery per-port array, and it is FROZEN under load on Apple
        // Silicon (confirmed M5 Pro 2026-06-15: an iPad charging on @1 held
        // PowerOutDetails at 6098 mW for 20 s while the SMC channel tracked the
        // real 6.6-7.5 W draw). So the live SMC value wins wherever a channel
        // resolves to a port by controller UUID; PowerOutDetails and the
        // source-attributed contract only fill ports the SMC did not resolve
        // (M1/M2, App Store sandbox, or a port with no SMC channel). The order
        // itself lives in `PortPowerMerge.merge` (Core), called below.
        let batteryInstalled = wcBool(dict?["BatteryInstalled"])
        // ExternalConnected: bound ONCE and reused by everything below that
        // needs it (the system-input override, the synthesis pre-filter, the
        // on-battery discharge gate, the snapshot field, the hasContract gate
        // and the charging-path resistance feed). Read through the synthesis
        // chain's own helper, so this function and the chain cannot disagree.
        // `dict == nil` (a desktop, which has no battery node) defaults true
        // exactly as the helper does, so a desktop still reads as plugged in.
        //
        // This used to be built with `wcBool` and a SECOND value was bound
        // further down for the resistance feed alone. That split was the
        // round-2 fix and it achieved nothing: `smcInput` below is gated on
        // THIS binding, so on the one dictionary the two disagreed about (a
        // battery node publishing no `ExternalConnected` key) the accumulator
        // received `input: nil` every tick and the estimate stayed
        // `insufficient` whatever the resolver returned. Proved by execution
        // in the PR #599 gate, round 2: 2000 ticks, 0 samples accepted.
        //
        // Widening it is safe to do rather than something to hedge about.
        // Measured 2026-09-03 over probe 32: every one of the 1338 folders
        // with a non-empty `AppleSmartBattery` dump publishes the key, so no
        // corpus machine reaches the case where the old and new expressions
        // differ, and where the key IS present as the CFBoolean IOKit
        // publishes, `wcBool` and the helper return the same thing.
        let externalConnected = dict.map { PowerSourceWatcher.externalConnectedFlag(from: $0) } ?? true

        // M1 Pro/Max/Ultra publish no real USB-C `IOPortFeaturePowerSource`
        // node at all (issue #401), so `readAllPowerSources()` above returns
        // nothing for the port that is actually charging and every consumer
        // below, the charging-path resistance resolver included, sees no
        // charging input. The watcher pipeline already synthesizes one; this
        // service bypassed it by reading the static directly. Same gate chain,
        // one copy, so the two surfaces cannot drift.
        //
        // The pre-filter here is not the same as the watcher's, and the
        // difference is deliberate. The watcher gets `context.ports` from an
        // already-published property, so building a context costs it nothing.
        // This service has no port watcher, so it has to read the ports
        // itself, and `readAllPorts()` walks every HPM controller class. That
        // read has to happen BEFORE the chain's own "is there an active
        // uncovered USB-C port" gate, because it is what produces the ports
        // that gate looks at. So the cheap conditions have to be hoisted up
        // here instead, or an idle laptop on battery with the Power Monitor
        // open would pay for a full class walk once a second to learn
        // nothing.
        //
        // Both hoisted conditions are already hard gates inside the chain
        // (`PowerSourceSynthesis` gate 1 and `SMCContractSynthesis` gate 1
        // both refuse when not externally connected; the chain returns nil
        // outright without a battery dictionary), so hoisting them changes
        // what this costs and never what it returns.
        //
        // `identities` is empty because this service runs no SOP watcher, the
        // same as `MonitorCommand.runTextMonitor` and for the same reason. It
        // costs the DECODED fallback its brick-partner attribution rung and
        // costs the SMC route nothing, and the SMC route is the one that
        // answers on M1 Pro/Max/Ultra (23 corpus machines against 4).
        var sources = realSources
        // The external-power check uses the single `externalConnected` bound
        // above, which is now the chain's own helper. It used to be built
        // here separately because the binding above disagreed with the chain
        // on a battery dictionary with no `ExternalConnected` key, and
        // skipping synthesis there was a false negative on exactly the
        // machines this feature exists for. Found by the PR #599 review gate;
        // see `externalConnectedFlag`.
        let anyRealLiveContract = realSources.contains { ($0.winning?.maxPowerMW ?? 0) > 0 }
        if !anyRealLiveContract,
           let batteryProperties = dict,
           externalConnected {
            let context = PowerSourceSynthesisContext(
                ports: AppleHPMInterfaceWatcher.readAllPorts(),
                identities: [],
                positionalPortKeys: { Self.hpmPortKeysRIDOrdered() }
            )
            if let synthesized = PowerSourceWatcher.synthesizedSource(
                realSources: realSources,
                context: context,
                smcReader: smcReader,
                batteryProperties: batteryProperties
            ) {
                sources.append(synthesized)
            }
        }

        // System power input (the charger / PSU feeding the logic board). The
        // telemetry SystemPowerIn built above comes from AppleSmartBattery, which
        // does not update under load on Apple Silicon (it sits stale). The SMC
        // DC-in rail (VD0R / ID0R / PDTR) is live (~1 Hz), so override with it
        // whenever externally powered: a desktop always is; a plugged-in laptop
        // too. On battery there is no input to show (the discharge figure below
        // drives the card instead). This also fixes the desktop input card, which
        // used to stay 0 and spin on "Negotiating…" forever (#291).
        let smcInput = externalConnected ? smcReader.readSystemPowerInput() : nil
        if let input = smcInput {
            system = Self.smcSystemSample(input, timestamp: timestamp)
        }

        // Adapter PRESENCE, not rated watts (see the snapshot field's doc
        // comment). Read once, up here, because the resistance eligibility
        // gate below needs it on the same tick as the samples.
        let chargerAttached = SystemPower.currentAdapter() != nil

        // Per-port power-OUT from the SMC, tied to each physical port by
        // controller UUID (M3+). This runs on laptops and desktops alike: the
        // SMC is the only LIVE per-port source (PowerOutDetails is frozen, see
        // above). An empty UUID map (M1/M2, where the stable UUID is absent, or a
        // Mac Pro) skips this entirely: we never guess a positional mapping, we
        // fall through to PowerOutDetails below.
        //
        // The cache only ever holds a non-empty map (see start()), so a nil cache
        // means "not looked up yet, or last lookup was empty": re-fetch and cache
        // a non-empty result. On M1/M2 (no UUID) this stays empty and is
        // re-fetched each tick, which is cheap.
        let uuidMap: [String: String]
        if let cachedUUIDMap {
            uuidMap = cachedUUIDMap
        } else {
            uuidMap = HPMPortUUIDMap.current()
            if !uuidMap.isEmpty { cachedUUIDMap = uuidMap }
        }
        // Channels carry a UUID even when idle (present=false, 0 W). An empty
        // map (M1/M2, Mac Pro) short-circuits the SMC read entirely: without a
        // UUID map nothing could resolve to a port anyway, so the user-client
        // round trip is pure cost. `merge` re-checks the same condition, so the
        // two cannot drift apart.
        let channels = uuidMap.isEmpty ? [] : smcReader.readPortPowerChannels()
        let podSamples = Self.portPowerSamples(from: dict?["PowerOutDetails"], portKeys: portKeys)
        let controllerSamples = Self.portPowerSamplesFromControllerInfo(dict?["PortControllerInfo"], sources: sources)

        // The merge order (SMC beats PowerOutDetails beats contract) and the
        // separate resistance feed both live in Core now, so they can be
        // replayed against the probe corpus. See `PortPowerMerge`.
        let merged = PortPowerMerge.merge(
            smcChannels: channels,
            uuidMap: uuidMap,
            powerOutDetailSamples: podSamples,
            contractedSamples: controllerSamples
        )
        let portSamples = merged.displaySamples
        let perPortMeteringSupported = merged.perPortMeteringSupported

        // Charging-path resistance feed (charging-path resistance rework, 2026-08): the live SMC DC-in pair,
        // accepted only when exactly one fixed-SPR USB-C charging input is
        // resolved on this laptop. Every gate lives in the resolver; the
        // accumulator handles reset, settle, the distinct-tuple rule and the
        // PDTR sanity check. When the SMC is unreadable (older silicon,
        // sandbox) `smcInput` is nil and the estimate stays `insufficient`.
        //
        // External power comes from the single `externalConnected` binding at
        // the top of this function, the same value `smcInput` and the
        // synthesis pre-filter use. It has to be that one: `smcInput` is
        // gated on it, so a resolver handed a different value could never
        // produce an estimate anyway, whatever it returned.
        let chargingFingerprint = ChargingInputResolver.fingerprint(
            sources: sources,
            batteryInstalled: batteryInstalled,
            externalConnected: externalConnected,
            chargerAttached: chargerAttached
        )
        accumulator.append(input: smcInput, fingerprint: chargingFingerprint)
        // Battery discharge, so the System Power card keeps tracking on battery.
        // Voltage is the pack voltage.
        let batteryVoltageMV = wcInt(dict?["Voltage"])
        let reportedBatteryPower = abs(wcInt(telemetry["BatteryPower"]))
        let gaugeBatteryPower = reportedBatteryPower != 0 ? reportedBatteryPower : wcInt(telemetry["SystemLoad"])
        // AppleSmartBattery's BatteryPower / SystemLoad do not update under load
        // on Apple Silicon (the fuel gauge holds a value for tens of seconds), so
        // a discharge figure read from there sits stale. The SMC battery rail
        // (PPBR) is live (updates ~1 Hz, tracks load), so prefer it when on
        // battery; fall back to the gauge when the SMC is unavailable or the key
        // is absent. `open()` inside the reader is lazy and idempotent.
        let onBattery = batteryInstalled && !externalConnected
        let liveBatteryPower = onBattery ? smcReader.readBatteryPowerMW() : nil
        let batteryPowerMW = liveBatteryPower ?? gaugeBatteryPower
        // Pack current. Apple Silicon usually reports 0 for Amperage /
        // InstantAmperage, and when we are on the live SMC power the gauge current
        // would be stale anyway, so derive current from the (live) power and pack
        // voltage: P = V x I, hence I[mA] = P[mW] x 1000 / V[mV]. Exact, and
        // consistent with the displayed P and V. Only when falling back to the
        // gauge do we use a non-zero measured current if the gauge reports one.
        let instant = wcInt(dict?["InstantAmperage"])
        let measuredCurrent = abs(instant != 0 ? instant : wcInt(dict?["Amperage"]))
        let derivedCurrent = batteryVoltageMV > 0 ? batteryPowerMW * 1000 / batteryVoltageMV : 0
        let batteryCurrentMA = (liveBatteryPower == nil && measuredCurrent != 0)
            ? measuredCurrent
            : derivedCurrent
        // hasContract is gated on a live connection (externalConnected, bound
        // above): a winning contract can linger for a moment after unplug on this
        // stack, and only means anything while a charger is actually plugged in.
        let snapshot = PowerMonitorSnapshot(
            timestamp: timestamp,
            systemSample: system,
            portSamples: portSamples,
            resistanceEstimate: accumulator.reportedEstimate(),
            resistancePortKey: accumulator.attributedPortKey,
            externalConnected: externalConnected,
            batteryInstalled: batteryInstalled,
            batteryVoltageMV: batteryVoltageMV,
            batteryCurrentMA: batteryCurrentMA,
            batteryPowerMW: batteryPowerMW,
            hasContract: externalConnected && sources.contains { $0.winning != nil },
            perPortMeteringSupported: perPortMeteringSupported,
            // Adapter PRESENCE, not rated watts. An attached adapter that
            // publishes no Watts field still means external power is available,
            // and 118 of 585 corpus machines report exactly that while
            // ExternalConnected is true, so a watts-based test would call them
            // unplugged. Read once above (the resistance gate needs it too), so
            // every surface qualifies this tick's samples with this tick's
            // answer.
            chargerAttached: chargerAttached
        )
        latestSnapshot = snapshot
        continuation?.yield(snapshot)
    }

    /// Converts an SMC DC-in reading (volts / amps / watts) into the System
    /// Power sample the UI expects, which is in mV / mA / mW. A static seam so
    /// the conversion is unit-testable without live IOKit.
    nonisolated static func smcSystemSample(_ input: SMCSystemPowerInput, timestamp: Date) -> PowerSample {
        PowerSample(
            timestamp: timestamp,
            systemVoltageIn: Int((input.volts * 1000).rounded()),
            systemCurrentIn: Int((input.amps * 1000).rounded()),
            systemPowerIn: Int((input.watts * 1000).rounded())
        )
    }

    // Internal (not private) so tests can call it directly without live IOKit.
    // The logic is pure: no IOKit, no MainActor. nonisolated so it is callable
    // from non-isolated test code without wrapping in a Task.
    nonisolated static func portPowerSamples(from value: Any?, portKeys: [String]) -> [PortPowerSample] {
        wcArray(value).enumerated().compactMap { offset, item in
            let dict = wcDictionary(item)
            guard !dict.isEmpty else { return nil }
            let rawPortIndex = wcInt(dict["PortIndex"])
            let effectiveIndex = rawPortIndex > 0 ? rawPortIndex : offset + 1
            // PowerOutDetails entries carry their own PortIndex. Match
            // against the number component of portKeys (the part after "/")
            // rather than using the array offset, because PowerOutDetails
            // order doesn't match HPM traversal order.
            // PowerOutDetails only contains USB-C ports, so default to "2/".
            let key: String
            if rawPortIndex > 0,
               let match = portKeys.first(where: { $0.hasSuffix("/\(rawPortIndex)") && !$0.hasPrefix("17/") }) {
                key = match
            } else if rawPortIndex > 0 {
                key = "2/\(rawPortIndex)"
            } else {
                key = "2/\(offset + 1)"
            }
            return PortPowerSample(
                portIndex: effectiveIndex,
                portKey: key,
                current: wcInt(dict["Current"]),
                watts: wcInt(dict["Watts"]),
                configuredVoltage: wcInt(dict["ConfiguredVoltage"]),
                configuredCurrent: wcInt(dict["ConfiguredCurrent"]),
                adapterVoltage: wcInt(dict["AdapterVoltage"]),
                vconnCurrent: wcInt(dict["VConnCurrent"]),
                vconnPower: wcInt(dict["VConnPower"]),
                filteredPower: wcInt(dict["FilteredPower"]),
                pdPowerMW: wcInt(dict["PDPowermW"]),
                vconnMaxCurrent: wcInt(dict["VConnMaxCurrent"]),
                accumulatedPower: wcInt(dict["AccumulatedPower"]),
                accumulatorCount: wcInt(dict["AccumulatorCount"]),
                accumulatorErrorCount: wcInt(dict["AccumulatorErrorCount"]),
                vconnAccumulatedPower: wcInt(dict["VConnAccumulatedPower"]),
                vconnAccumulatorCount: wcInt(dict["VConnAccumulatorCount"]),
                vconnAccumulatorErrorCount: wcInt(dict["VConnAccumulatorErrorCount"]),
                numLDCMCollisions: wcInt(dict["NumLDCMCollisions"]),
                usbSleepPoolPowerMW: wcInt(dict["USBSleepPoolPowermW"]),
                usbWakePoolPowerMW: wcInt(dict["USBWakePoolPowermW"]),
                powerState: wcInt(dict["PowerState"]),
                portType: wcInt(dict["PortType"])
            )
        }
    }

    /// Build one contracted power sample per port that has a winning power
    /// source. The port, watts, and a baseline voltage/current come from the
    /// self-keyed source (`IOPortFeaturePowerSource`), which states the port
    /// outright, so a contract can never land on the wrong port.
    ///
    /// `PortControllerInfo` (the unlabelled array inside `AppleSmartBattery`)
    /// is used only to *enrich* the decoded volts/amps. Its items carry no port
    /// id, so each is matched to its port by watts (`PowerControllerPortJoin`)
    /// and its PDO decode is preferred where present, because it recovers the
    /// exact negotiated tier even where the source's winning PDO is coarse
    /// (e.g. MagSafe). No match, or an ambiguous one, falls back to the
    /// source's own winning figures: never a guessed key.
    nonisolated static func portPowerSamplesFromControllerInfo(_ controllerInfo: Any?, sources: [PowerSource]) -> [PortPowerSample] {
        let items = wcArray(controllerInfo)
        let maxPowers = items.map { wcInt(wcDictionary($0)["PortControllerMaxPower"]) }
        let joinByIndex = PowerControllerPortJoin.portKeysByContent(
            controllerMaxPowerMW: maxPowers,
            sources: sources
        )

        return Dictionary(grouping: sources, by: \.portKey).compactMap { portKey, portSources -> PortPowerSample? in
            guard let source = PowerSource.preferredChargingSource(in: portSources) ?? portSources.first,
                  let winning = source.winning, winning.maxPowerMW > 0 else { return nil }

            var voltage = winning.voltageMV
            var current = winning.maxCurrentMA

            // Enrichment: the PortControllerInfo item watts-matched to this port
            // (if any) carries the precisely decoded contract. Prefer it; the
            // source's winning figures are the fallback.
            if let index = joinByIndex.first(where: { $0.value == portKey })?.key {
                let dict = wcDictionary(items[index])
                let rdo = UInt32(bitPattern: Int32(truncatingIfNeeded: wcInt(dict["PortControllerActiveContractRdo"])))
                // The operating-current field (bits 19:10, 10 mA units) is only
                // valid for Fixed/Variable PDOs. Battery PDOs encode power in
                // 250 mW units there; PPS/AVS APDOs encode output voltage. Pass 0
                // for non-Fixed contracts so the tie-breaker inside
                // decodeNegotiatedContract falls back to the highest-voltage pick
                // rather than matching a mis-scaled value.
                let selectedPdoType = rdoSelectedPdoType(rdo: rdo, pdoList: dict["PortControllerPortPDO"])
                let operatingCurrent = selectedPdoType == .fixedOrVariable ? Int((rdo >> 10) & 0x3FF) * 10 : 0
                if let negotiated = decodeNegotiatedContract(
                    pdoList: dict["PortControllerPortPDO"],
                    maxPowerMW: wcInt(dict["PortControllerMaxPower"]),
                    operatingCurrentMA: operatingCurrent
                ) {
                    voltage = negotiated.voltageMV
                    current = negotiated.currentMA
                }
            }

            let portNumber = PortIdentity(key: portKey)?.number ?? 0
            return PortPowerMerge.contractedSample(
                portNumber: portNumber,
                portKey: portKey,
                watts: winning.maxPowerMW,
                voltageMV: voltage,
                currentMA: current
            )
        }
    }

    /// Decodes the negotiated fixed-supply PD contract from a port's source
    /// PDO list. Picks the fixed PDO whose power is closest to `maxPowerMW`
    /// (the authoritative contracted max), because the RDO object-position
    /// field is wrong for MagSafe. A charger can offer two PDOs at the same
    /// wattage (e.g. a 45W brick advertises both 15V/3A and 20V/2.25A); that
    /// tie is broken with the RDO operating current, then by preferring the
    /// higher voltage. Returns nil when there is no PDO list, no fixed PDO,
    /// or no usable max-power reference, so callers leave voltage at 0
    /// rather than inventing one.
    nonisolated static func decodeNegotiatedContract(
        pdoList: Any?,
        maxPowerMW: Int,
        operatingCurrentMA: Int
    ) -> (voltageMV: Int, currentMA: Int)? {
        guard maxPowerMW > 0 else { return nil }
        let pdos = wcArray(pdoList)
        guard !pdos.isEmpty else { return nil }

        var candidates: [(voltageMV: Int, currentMA: Int, deltaMW: Int)] = []
        for entry in pdos {
            let pdo = wcUInt32(entry)
            guard pdo != 0 else { continue }
            // Fixed-supply PDOs have bits 31:30 == 00. Battery, variable,
            // and augmented/PPS PDOs don't carry a plain fixed voltage.
            guard (pdo >> 30) & 0x3 == 0 else { continue }
            // Fixed PDO: voltage in 50 mV units (bits 19:10), max current
            // in 10 mA units (bits 9:0).
            let voltageMV = Int((pdo >> 10) & 0x3FF) * 50
            let currentMA = Int(pdo & 0x3FF) * 10
            guard voltageMV > 0, currentMA > 0 else { continue }
            let powerMW = voltageMV * currentMA / 1000
            candidates.append((voltageMV, currentMA, abs(powerMW - maxPowerMW)))
        }
        guard let minDelta = candidates.map(\.deltaMW).min() else { return nil }
        let tied = candidates.filter { $0.deltaMW == minDelta }
        if tied.count == 1 {
            return (tied[0].voltageMV, tied[0].currentMA)
        }
        // Tie: the RDO operating current pins the actual PDO (it matches the
        // selected PDO's max current). If that doesn't single one out, the
        // Mac negotiates the highest voltage tier at a given wattage.
        if operatingCurrentMA > 0,
           let match = tied.first(where: { $0.currentMA == operatingCurrentMA }) {
            return (match.voltageMV, match.currentMA)
        }
        // tied.count >= 2 here (count == 1 returned above), so max(by:) is
        // guaranteed to return a value; the guard is defensive documentation.
        guard let pick = tied.max(by: { $0.voltageMV < $1.voltageMV }) else { return nil }
        return (pick.voltageMV, pick.currentMA)
    }

    // Classifies the PDO type that an RDO selects, for safe field extraction.
    // The object position is bits 30:28 of the RDO; position 0 means no active
    // contract. Returns .fixedOrVariable when the position is out of range or
    // the PDO list is empty, since Fixed is the only type seen in captured data
    // and the Fixed path is always safe as a fallback.
    enum SelectedPdoType { case fixedOrVariable, battery, apdo }
    nonisolated static func rdoSelectedPdoType(rdo: UInt32, pdoList: Any?) -> SelectedPdoType {
        let position = Int((rdo >> 28) & 0x7)
        let idx = position - 1
        let pdos = wcArray(pdoList)
        guard idx >= 0, idx < pdos.count else { return .fixedOrVariable }
        let raw = wcUInt32(pdos[idx])
        switch (raw >> 30) & 0x3 {
        case 1: return .battery
        case 3: return .apdo
        default: return .fixedOrVariable
        }
    }

    /// Every HPM port-controller service as a portKey ("portType/portNumber").
    ///
    /// **The order of this array is not meaningful.** It is whatever IOKit
    /// hands back, class by class, which is neither port-number order nor the
    /// order `AppleSmartBattery` builds `PortControllerInfo` in. Use it only to
    /// search by content. Anything that needs to line an array up with
    /// `PortControllerInfo` by index must call `hpmPortKeysRIDOrdered()`.
    public nonisolated static func hpmPortKeys() -> [String] {
        hpmPortKeysWithRIDs().map(\.key)
    }

    /// Port keys in the order Apple builds `PortControllerInfo` in, or an empty
    /// array when that order cannot be established.
    ///
    /// Empty means "no trustworthy order", not "no ports". Callers must treat
    /// it as a refusal to answer and fall back to something that does not rely
    /// on index alignment, because the alternative (raw IOKit order) is a guess
    /// that presents one port's data under another port's name. Both current
    /// callers already do the right thing with an empty array:
    /// `PowerSourceSynthesis`'s positional rung requires
    /// `entriesCount == positionalPortKeys.count` and so skips to its
    /// content-based rungs, and `PortDiagnosticsWatcher.portKeyMap` maps only
    /// the entries its wattage join can place.
    ///
    /// This is a defensive path, not an expected one: every one of the 1518
    /// real ports in the probe-35 corpus carries an `RID`, and no machine
    /// repeats one.
    public nonisolated static func hpmPortKeysRIDOrdered() -> [String] {
        orderedPortKeys(hpmPortKeysWithRIDs())
    }

    // Walks HPM port-controller services and pairs each portKey with its
    // owning controller's RID. Order here is raw IOKit traversal order.
    nonisolated static func hpmPortKeysWithRIDs() -> [(key: String, rid: Int?)] {
        // The named classes only. `AppleHPMInterfaceWatcher` also matches the
        // `IOPort` superclass as a catch-all; that is not copied here, because
        // adding it would widen what this function matches with no evidence
        // either way. Every probe in the corpus enumerates HPM classes from its
        // own hardcoded list, so no corpus test can currently say whether a
        // port exists outside the named families. Settling that needs a probe
        // that walks `IOPort` subclasses generically.
        var found: [(key: String, rid: Int?)] = []
        for cls in HPMPortControllerClasses.named {
            var iter: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(cls), &iter) == KERN_SUCCESS else {
                continue
            }
            defer { IOObjectRelease(iter) }

            // Collect this class's entries with the retry-safe helper first,
            // then merge into `found` once the walk is done. Doing the merge
            // (and its cross-class dedup check) after keeps the walk itself
            // side-effect free, so a discarded, retried pass never partially
            // populates `found`.
            let classEntries = wcDrainAllRetrying(iter) { service -> (key: String, rid: Int?)? in
                func read(_ key: String) -> Any? {
                    IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
                }
                let portType = read("PortTypeDescription") as? String
                let isRealPort = (portType == "USB-C" || portType?.hasPrefix("MagSafe") == true)
                guard isRealPort else { return nil }
                let portNumber = wcPortIndex(read: read, service: service)
                guard portNumber != 0 else { return nil }
                let key = PortIdentity.from(
                    typeDescription: portType,
                    reportedTypeCode: read("PortType") as? Int,
                    number: portNumber
                ).key
                return (key: key, rid: wcHPMControllerRID(for: service))
            }
            for entry in classEntries {
                guard let entry else { continue }
                if !found.contains(where: { $0.key == entry.key }) {
                    found.append(entry)
                }
            }
        }
        return found
    }

    /// Puts port keys into the order Apple builds `AppleSmartBattery`'s
    /// `PortControllerInfo` array in, which is by the owning HPM controller's
    /// `RID` ascending.
    ///
    /// This matters because `PortControllerInfo` entries carry no port
    /// identifier at all. Two consumers
    /// (`PortDiagnosticsWatcher.portKeyMap` and `PowerSourceSynthesis`'s
    /// positional rung) tie entry N back to a port by index, so this array's
    /// order IS the join. Before this ordering existed the list came back in
    /// raw IOKit iterator order, which is neither RID order nor port-number
    /// order: on a 14" M5 the classes hand back USB-C@4 first, so port health
    /// counters were being shown against the wrong ports (issue #460).
    ///
    /// Corpus evidence for the RID rule, ground truth being which port holds
    /// the live charge contract: 133 machines tested against the committed
    /// corpus, 133 agree, 0 disagree (51 of them via a MagSafe port). See
    /// `HPMPortKeyOrderCorpusSweepTests`.
    ///
    /// Returns an **empty array** when any port is missing an `RID`, or when
    /// two ports report the same one. Not the input order: this commit's whole
    /// finding is that the input order does not line up with
    /// `PortControllerInfo`, so handing it back would be passing off a guess as
    /// an answer, and the caller could not tell the difference. Refusing lets
    /// each caller degrade in a way it can reason about. A partial sort is
    /// equally rejected, for the same reason plus it would reorder some ports
    /// and not others.
    nonisolated static func orderedPortKeys(_ ports: [(key: String, rid: Int?)]) -> [String] {
        let rids = ports.compactMap(\.rid)
        guard rids.count == ports.count, Set(rids).count == rids.count else {
            return []
        }
        return ports.sorted { ($0.rid ?? 0) < ($1.rid ?? 0) }.map(\.key)
    }
}
