import SwiftUI
import WhatCableCore
import WhatCableDarwinBackend
import WhatCableAppKit

struct ContentView: View {
    @ObservedObject private var portWatcher = WatcherHub.shared.portWatcher
    @ObservedObject private var deviceWatcher = WatcherHub.shared.deviceWatcher
    @ObservedObject private var powerWatcher = WatcherHub.shared.powerWatcher
    @ObservedObject private var pdWatcher = WatcherHub.shared.pdWatcher
    @ObservedObject private var tbWatcher = WatcherHub.shared.tbWatcher
    @ObservedObject private var usb3Watcher = WatcherHub.shared.usb3Watcher
    @ObservedObject private var trmWatcher = WatcherHub.shared.trmWatcher
    @ObservedObject private var uvdmWatcher = WatcherHub.shared.uvdmWatcher
    @ObservedObject private var displayWatcher = WatcherHub.shared.displayWatcher
    @EnvironmentObject private var refresh: RefreshSignal
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var updates = UpdateChecker.shared
    /// Whether this Mac has no internal battery (desktop). A hardware fact that
    /// can't change during a session, so it's resolved once at launch and used
    /// as the initial state. Resolving it here rather than in `.onAppear` means
    /// the desktop-gated UI (the charger-identity note, the Built-in USB ports
    /// card) is correct on the first frame instead of popping in a frame late.
    private static let isDesktopMacAtLaunch = AppleSmartBatteryReader.read().isDesktopMac
    @State private var isDesktopMac = ContentView.isDesktopMacAtLaunch
    @State private var refreshIconRotation = 0.0
    /// Tracks per-port fault-counter deltas across a connection so
    /// mid-session overcurrent trips and repeated drops surface as a free
    /// inline banner on the relevant port card.
    @StateObject private var faultTracker = ConnectionFaultTracker()
    /// Purely visual smoothing for macOS's #536 power-source attribution
    /// churn (the same power source flips between MagSafe and a USB-C port
    /// every 1-2 seconds). `@State` so the tracker's internal per-port
    /// history survives across `ContentView` re-inits, same as any other
    /// `@State`; it isn't `ObservableObject` because re-renders are driven
    /// by `portVisibilityStates` and the periodic tick below, not by the
    /// tracker itself.
    @State private var portVisibilityTracker = PortVisibilityTracker()
    /// Latest visibility verdict per port (`serviceName`), recomputed on the
    /// tick below. Only ever read to decide "Hide empty ports" membership
    /// and card opacity; never affects JSON/CLI/widget output.
    @State private var portVisibilityStates: [String: PortVisibilityState] = [:]

    private var showAdvanced: Bool {
        settings.showTechnicalDetails || refresh.optionHeld
    }

    @ViewBuilder
    private var rootContent: some View {
        if let route = refresh.activeProScreen,
           let screen = PluginRegistry.shared.proScreen(id: route.id, portCard: route.portCard) {
            ProScreenContainer(
                isMenuBarMode: settings.useMenuBarMode,
                isPinned: refresh.keepOpen,
                onTogglePin: { refresh.keepOpen.toggle() },
                onBack: { refresh.activeProScreen = nil },
                onDetach: {
                    DetachedProWindowManager.shared.open(route: route)
                    refresh.activeProScreen = nil
                }
            ) {
                screen
            }
        } else if refresh.showSettings {
            SettingsView(dismiss: { refresh.showSettings = false })
        } else {
            mainContent
        }
    }

    var body: some View {
        rootContent
        // Width: wide enough for the widest Pro screen's own minWidth
        // (Negotiation 560, Power Monitor 520, Cable Diagnostics 500) so
        // content never overflows and clips.
        //
        // The max cap is only applied in menu-bar mode, where the surface is
        // an NSPopover. A popover sizes itself to its content and can't be
        // user-resized, so the cap keeps a near-empty popover from being half
        // the screen (issue #159) and stops the wide Pro screens clipping.
        //
        // In Dock-app (window) mode the surface is a real resizable NSWindow,
        // so we drop the cap and let the content fill whatever size the user
        // drags the window to (issue #281). The min still applies.
        //
        // The outer popover frame is NOT keyed to the font slider on purpose.
        // Pro screens (Power Monitor, Negotiation, Display) carry their own
        // `frame(minWidth: 520 * fontScale)` etc., so opening one still grows
        // the popover to fit at any scale (a one-shot resize on entry, not a
        // per-step move). If we made the outer frame depend on fontSize too,
        // every 0.1 step of the slider would resize the popover under the
        // user's finger and the whole UI would judder during a drag.
        .frame(
            minWidth: 560,
            idealWidth: 560,
            maxWidth: settings.useMenuBarMode ? 760 : .infinity,
            minHeight: 200,
            // Height cap comes from the app, which recomputes it from the
            // status item's screen on each open (issue #454): the fixed 760
            // used to exceed the usable height on small or heavily scaled
            // displays, so the popover grew off the top of the screen and the
            // header (with the settings gear) went out of reach. Larger screens
            // still get the full 760 since the app never raises the cap above it.
            maxHeight: settings.useMenuBarMode ? refresh.maxPopoverHeight : .infinity
        )
        // `\.fontScale` is now injected at the NSHostingController root by
        // `ScaledHost`, which observes `FontScaleStore` so every SwiftUI
        // surface (popover, dock window, detached Pro windows, welcome,
        // licence) tracks the slider live. No need to re-inject here.
        .onChange(of: refresh.tick) { _, _ in
            withAnimation(.linear(duration: 0.35)) {
                refreshIconRotation += 360
            }
            WatcherHub.shared.refreshAll()
        }
        // Fold each refresh into the fault tracker. A counter tick changes the
        // port value (the counts are part of `AppleHPMInterface`'s equality),
        // so a real overcurrent or drop republishes `ports` and lands here.
        // `isPortLive` also reads the power/PD/device watchers, which don't
        // themselves trigger this closure; a port that turns live purely from
        // one of those just has its baseline set on the next `ports` change
        // (one refresh interval later at most). Setting a baseline late is
        // conservative, never a false fault. `initial` seeds baselines from
        // whatever is already plugged in when the popover opens.
        .onChange(of: portWatcher.ports, initial: true) { _, ports in
            let liveKeys = Set(ports.compactMap { isPortLive($0) ? $0.portKey : nil })
            faultTracker.ingest(ports: ports, liveKeys: liveKeys)
        }
        // If a Pro screen is re-opened while it's already detached into
        // its own window, focus that window instead of also showing it
        // in-place, so it's never in two places at once.
        .onChange(of: refresh.activeProScreen?.id) { _, newID in
            guard newID != nil, let route = refresh.activeProScreen else { return }
            if DetachedProWindowManager.shared.focusIfOpen(route: route) {
                refresh.activeProScreen = nil
            }
        }
        // Recompute immediately whenever any signal the tracker reads
        // changes, so a new plug-in or a real unplug shows up the same
        // frame instead of lagging up to 500ms behind the periodic tick
        // below. Mirrors the `onChange(of: portWatcher.ports)` plumbing
        // already above. Review finding.
        .onChange(of: portWatcher.ports) { _, _ in recomputePortVisibility() }
        .onChange(of: deviceWatcher.devices) { _, _ in recomputePortVisibility() }
        .onChange(of: pdWatcher.identities) { _, _ in recomputePortVisibility() }
        .onChange(of: powerWatcher.sources) { _, _ in recomputePortVisibility() }
        .onChange(of: tbWatcher.switches) { _, _ in recomputePortVisibility() }
        // A reopened popover/window starts from whatever `portVisibilityStates`
        // held last (SwiftUI `@State` can outlive a close), so recompute once
        // synchronously on appear rather than waiting for the first `onChange`
        // or the first tick. Review finding.
        .onAppear { recomputePortVisibility() }
        // The `onChange` handlers above cover every real transition, so this
        // tick exists for exactly one thing: expiring a fade into `.hidden`
        // once `PortVisibilityTracker.graceWindow` elapses with nothing else
        // changing (no new IOKit event fires to trigger an `onChange`).
        // `recomputePortVisibility` is a single cheap pass (one batched
        // structural-scoping call, then a dictionary build), so this just
        // re-runs it unconditionally rather than tracking "is anything
        // currently fading" separately; gating on that would need its own
        // bookkeeping to save re-running something that's already cheap.
        // `.task` is scoped to this view's lifetime (cancelled automatically
        // when the popover/window closes), matching the same "poll only
        // while a surface is visible" cadence `WatcherHub` already uses for
        // its own 1 Hz active poll (see its `activeInterval`). #536.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                recomputePortVisibility()
            }
        }
    }

    /// Rebuilds `portVisibilityStates` from the current watcher signals.
    /// Every physical port (not just currently-visible ones) is evaluated
    /// each pass, since `portWatcher.ports` always lists every port
    /// controller regardless of connection state (see `isRealPort`); only
    /// its liveness changes.
    ///
    /// `structurallyScopedTunnelledDevices` is computed once for the whole
    /// pass via the batched static helper (the same one `mainContent` uses),
    /// not per port: review finding, the per-port `TunnelledDeviceGrouping`
    /// call this used to make was the same O(ports × devices) walk repeated
    /// once per port for no reason.
    private func recomputePortVisibility() {
        // `systemUptime` is monotonic (immune to wall-clock/NTP jumps), which
        // is what a fade duration wants; `ConnectionFaultTracker` uses
        // `Date()` instead because it needs wall-clock semantics for its own
        // purpose, so the two clocks deliberately differ. One accepted
        // cosmetic effect: `systemUptime` pauses while the Mac sleeps, so a
        // fade started just before a nap can read as still-fading for a
        // moment after wake, one tick longer than 3 real seconds.
        let now = ProcessInfo.processInfo.systemUptime
        let ports = portWatcher.ports
        let structuralScoping = Self.structurallyScopedTunnelledDevices(
            ports: ports, devices: deviceWatcher.devices, thunderboltSwitches: tbWatcher.switches
        )
        var next: [String: PortVisibilityState] = [:]
        next.reserveCapacity(ports.count)
        for port in ports {
            let signals = liveSignals(
                for: port, structurallyScopedDevices: structuralScoping.byPort[port.serviceName] ?? []
            )
            next[port.serviceName] = portVisibilityTracker.evaluate(
                portKey: port.serviceName, nonPowerLive: signals.nonPower, powerLive: signals.power, now: now
            )
        }
        // Drop history for any port key that's dropped out of the registry
        // entirely (review finding: FIX 3), not just lost its signals.
        portVisibilityTracker.reconcile(keeping: Set(ports.map(\.serviceName)))
        if next != portVisibilityStates {
            // Per-task-review finding (round 1, important): wrapping the
            // WHOLE dictionary write in one `withAnimation` bundled every
            // port's state change into a single transaction, so two
            // unrelated ports changing state on the same tick animated
            // together, which violates "no global animation on
            // watcher-driven values". Gated now: only wrap the write in an
            // animated transaction when it ACTUALLY changes `visiblePorts`
            // membership (a port entering/leaving `.hidden`, the only thing
            // this state drives that needs `CardMotion.exit` to fire for the
            // `ForEach` insertion/removal, spec: "Parent-owned retention and
            // removal"). Per-port opacity dimming no longer lives at this
            // level at all (moved into `SettlingPortCardHost` itself, its
            // own narrowly scoped `.animation(value: settlingVisibility)`,
            // per the same review round's other finding), so the common
            // #536 opacity-only churn case now applies unanimated, same as
            // before this whole feature existed.
            //
            // This doesn't perfectly scope to a single port when two
            // DIFFERENT ports both flip visible membership in the exact
            // same tick (a single `@State` dictionary write is one
            // transaction; it can't be split key-by-key), but that's the
            // rare case, and it's the one where sharing a transaction is
            // arguably correct anyway (both really are transitioning in the
            // same frame).
            //
            // Per-branch-review finding (round 2, Codex gate, finding 3):
            // this used to compare raw `.hidden`-ness directly, which fires
            // regardless of `settings.hideEmptyPorts` even though a
            // `.live`/`.hidden` flip can't actually change `ForEach`
            // membership when that setting is off (`mainContent` falls
            // through to the unfiltered `portWatcher.ports` in that mode).
            //
            // Round 3 (Codex gate, "issue 2"): the round-2 fix still walked
            // per-key over CURRENT `ports` only, comparing `isVisible` on
            // each port's OLD vs NEW state. That treats a missing OLD entry
            // as "visible" (via `isVisible`'s own `nil` fallback), so a
            // port's FIRST appearance was never flagged as a membership
            // change, and a port's total DISAPPEARANCE from the registry
            // was invisible to a walk scoped to `ports` (the port to detect
            // it on is exactly the one no longer there to iterate over).
            // `membershipChanged` now builds the actual OLD and NEW
            // VISIBLE-PORT ID SETS and compares them for set inequality,
            // which catches both by construction (see that function's doc
            // comment).
            let membershipChanged = SettlingCardVisibleMembership.membershipChanged(
                old: portVisibilityStates, new: next, hideEmptyPorts: settings.hideEmptyPorts
            )
            if membershipChanged {
                withAnimation(CardMotion.animation(reduceMotion: reduceMotion)) {
                    portVisibilityStates = next
                }
            } else {
                portVisibilityStates = next
            }
        }
    }

    /// The two halves `PortVisibilityTracker` needs, delegating to
    /// `WhatCableCore.portLivenessSplit` (the pure, tested split of
    /// `isPortLive`'s branches) rather than duplicating that logic here.
    ///
    /// Review finding: an earlier version of this called `isPortLive` with
    /// `matchingDevices`/`identities` forced to `[]` to isolate "power", but
    /// `isPortLive` still returned `true` off its bare non-MagSafe
    /// `connectionActive` branch, which has nothing to do with power. That
    /// misclassified a USB2-only device or a power-role-less display as
    /// "power", so a real unplug of one of those would fade instead of
    /// hiding immediately. `portLivenessSplit` fixes that by mirroring
    /// `PortLiveness.swift`'s conditions one-for-one instead.
    private func liveSignals(
        for port: AppleHPMInterface, structurallyScopedDevices: [USBDevice]
    ) -> (nonPower: Bool, power: Bool) {
        WhatCableCore.portLivenessSplit(
            port: port,
            powerSources: powerWatcher.sources(for: port),
            identities: pdWatcher.identities(for: port),
            matchingDevices: matchingDevices(for: port),
            chargerAttached: chargerAttached,
            hasStructurallyScopedTunnelledDevices: !structurallyScopedDevices.isEmpty
        )
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            header
            if let update = updates.available {
                UpdateBanner(update: update)
            }
            Divider()
            if isDesktopMac {
                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                    Text(String(localized: "Desktop Mac: charger identity (FedDetails) is not available.", bundle: _appLocalizedBundle))
                }
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            // Structural: a tunnelled device whose `tunnelRootName` names a
            // specific port's own `apciecN` root joins that port's tree
            // directly (fed to `PortCard`'s `structuralTunnelledDevices`
            // below), instead of the single-active-port fallback. Computed
            // BEFORE `visiblePorts` (moved up from below "Hide empty ports"
            // review finding): a port whose only connected devices are
            // structurally-scoped tunnelled ones carries nothing in
            // `matchingDevices` (that join explicitly excludes anything
            // `isThunderboltTunnelled`), so without feeding this into
            // `isPortLive` the port reads as empty and "Hide empty ports"
            // removed the whole card, tree and all: a dock full of devices
            // vanished. Extracted to a free function (not a bare `for` loop
            // here) because a result-builder body cannot contain control-flow
            // statements outside `ForEach`/`if`/`switch`.
            let structuralScoping = Self.structurallyScopedTunnelledDevices(
                ports: portWatcher.ports,
                devices: deviceWatcher.devices,
                thunderboltSwitches: tbWatcher.switches
            )
            let structurallyScopedByPort = structuralScoping.byPort
            // "Hide empty ports" consults `portVisibilityStates` (the
            // fading-aware tracker) rather than raw `isPortLive`, so a
            // charger-only port whose power attribution flaps away for a
            // moment stays in the list instead of popping in and out (#536).
            let visiblePorts = settings.hideEmptyPorts
                ? portWatcher.ports.filter { port in
                    switch portVisibilityStates[port.serviceName] {
                    case .hidden: return false
                    case .live, .fading: return true
                    case nil:
                        // Not yet evaluated by the periodic tick (e.g. the
                        // very first frame). Fall back to the immediate
                        // signal so a freshly-plugged port isn't briefly
                        // hidden.
                        return isPortLive(port, structurallyScopedDevices: structurallyScopedByPort[port.serviceName] ?? [])
                    }
                }
                : portWatcher.ports
            // Native HDMI / built-in display ports come from a parallel source.
            // They only exist when a display is plugged in (the IOKit transport
            // node has no idle representation), so the list is empty whenever
            // the user has no HDMI display connected. Issue #352.
            let builtInDisplayPorts = displayWatcher.builtInDisplayPorts
            // Devices behind a Thunderbolt dock or display match no port
            // (issue #274). Group once: nest under the single connected
            // Thunderbolt port when unambiguous, else show a flat card.
            // Grouped here, above the empty-state check, because these cards
            // (and the desktop-only built-in front-port card, #348) can be the
            // only thing to show when every port is filtered out: without this
            // a Mac mini with a drive only in a front port and "hide empty
            // ports" on would read "nothing connected".
            //
            // `structurallyScoped` excludes a device from this flat fallback
            // ONLY when its own port actually made it into `visiblePorts`:
            // belt-and-braces alongside the `isPortLive` fix above. With that
            // fix, a structurally-scoped device's port is never hidden, so
            // this is expected to always be the full set; if a future change
            // ever lets the two drift apart again, a device whose port got
            // hidden anyway still renders here instead of vanishing entirely.
            let visiblePortNames = Set(visiblePorts.map(\.serviceName))
            let structurallyScopedIDs = structuralScoping.allIDs
            let structurallyScopedIDsOnVisiblePorts = Set(
                structurallyScopedByPort
                    .filter { visiblePortNames.contains($0.key) }
                    .values
                    .flatMap { $0.map(\.id) }
            )
            let tunnelledGroup = TunnelledDeviceGrouping.group(
                devices: deviceWatcher.devices,
                ports: portWatcher.ports,
                thunderboltSwitches: tbWatcher.switches,
                isDesktopMac: isDesktopMac,
                structurallyScoped: structurallyScopedIDsOnVisiblePorts
            )
            let hasOffPortUSBContent = !tunnelledGroup.devices.isEmpty
                || !tunnelledGroup.internalHubDevices.isEmpty
                || !structurallyScopedIDs.isEmpty
            if visiblePorts.isEmpty && builtInDisplayPorts.isEmpty && !hasOffPortUSBContent {
                if portWatcher.ports.isEmpty {
                    noPortsState
                } else {
                    nothingConnectedState
                }
            } else {
                let activePortCount = portWatcher.ports.filter { $0.connectionActive == true }.count
                let chargerSourceCount = ChargerWattageSource.chargerSourceCount(
                    ports: portWatcher.ports, sources: powerWatcher.sources)
                let adapter = SystemPower.currentAdapter()
                // One AppleSmartBattery read per body pass, not three: the
                // battery-full / is-charging / FedDetails values all come from
                // the same registry entry, and `SystemPower.batteryFullyCharged()`
                // / `batteryIsCharging()` each re-read it. FedDetails carries the
                // per-port charger identity used to explain a charger connected
                // but not the source on M1 Pro/Max/Ultra (issue #459).
                let batteryResult = AppleSmartBatteryReader.read()
                let federatedIdentities = batteryResult.federatedIdentities
                let batteryFull = batteryResult.battery?.fullyCharged
                let batteryCharging = batteryResult.battery?.isCharging
                // Port keys with a live negotiated contract, so a connected-
                // but-idle second charger can tell another port is the active
                // source rather than being stuck mid-negotiation (#264).
                // Deliberately ungated on adapter/battery: this only feeds
                // `anotherPortActivelyCharging`, and ChargingDiagnostic applies
                // the system-power gate before acting on it, so a stale PDO
                // here can't surface a charging claim.
                let chargingPortKeys = Set(portWatcher.ports.compactMap { port -> String? in
                    PowerSource.hasLiveChargingContract(in: powerWatcher.sources(for: port)) ? port.portKey : nil
                })
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(visiblePorts) { port in
                            let portSources = powerWatcher.sources(for: port)
                            let wattageSource = ChargerWattageSource.resolve(
                                portSources: portSources,
                                portIsActive: port.connectionActive == true,
                                activePortCount: activePortCount,
                                chargerSourceCount: chargerSourceCount,
                                adapter: adapter
                            )
                            let generation = portWatcher.connectionSessionGeneration(for: port.id)
                            let structurallyScopedDevices = structurallyScopedByPort[port.serviceName] ?? []
                            // Computed once and reused for both `isLive` and
                            // the visibility resolution below (issue #585,
                            // task 3), instead of calling `isPortLive` twice
                            // per row.
                            let portIsLive = isPortLive(port, structurallyScopedDevices: structurallyScopedDevices)
                            SettlingPortCardHost(
                                port: port,
                                devices: matchingDevices(for: port),
                                tunnelledDevices: port.serviceName == tunnelledGroup.hostPortServiceName ? tunnelledGroup.devices : [],
                                structuralTunnelledDevices: structurallyScopedDevices,
                                powerSources: portSources,
                                identities: pdWatcher.identities(for: port),
                                thunderboltSwitches: tbWatcher.switches,
                                usb3Transports: usb3Watcher.transports(for: port),
                                trmTransports: trmWatcher.transports.filter { $0.canonicallyMatches(port: port) },
                                isLive: portIsLive,
                                showAdvanced: showAdvanced,
                                cioCapability: trmWatcher.cioCapabilities.first { $0.canonicallyMatches(port: port) },
                                accessoryIdentity: uvdmWatcher.identities.first { $0.canonicallyMatches(port: port) },
                                displayPorts: displayWatcher.statuses.filter { $0.status.canonicallyMatches(port: port) }.map(\.status),
                                chargerWattageSource: wattageSource,
                                batteryFullyCharged: batteryFull,
                                batteryIsCharging: batteryCharging,
                                adapter: adapter,
                                anotherPortActivelyCharging: port.portKey.map { key in chargingPortKeys.contains { $0 != key } } ?? false,
                                connectionDiagnostic: faultTracker.diagnostic(for: port.portKey),
                                federatedIdentities: federatedIdentities,
                                connectionAttachInstant: portWatcher.connectionAttachInstant(for: port.id),
                                connectionSessionGeneration: generation,
                                retainedAttachInstant: portWatcher.connectionRetainedAttachInstant(for: port.id),
                                // `.resolveAtMount`, not the plain `.resolve`
                                // (issue #585, task 3): `portVisibilityStates` is a
                                // separate `@State` dictionary that only
                                // catches up to a fresh generation one
                                // `.onChange` later, so a stale `.hidden`
                                // entry here would wrongly fold to `.ended`
                                // and skip the settling spinner on this same
                                // body evaluation. See that function's doc
                                // comment for the full mechanism.
                                settlingVisibility: SettlingCardVisibilityResolver.resolveAtMount(
                                    portVisibilityStates[port.serviceName],
                                    isPortLiveNow: portIsLive
                                )
                            )
                            // Generation-scoped identity (spec: "the old
                            // machine is discarded whole" on a genuine
                            // replug). `ForEach` alone keys on `port.id`,
                            // which is stable across a replug, so this `.id`
                            // is what actually tears down and recreates the
                            // host's `@State` phase machine.
                            .id(SettlingCardIdentity(portID: port.id, generation: generation))
                            // Parent-owned insertion/removal (spec:
                            // "Parent-owned retention and removal"): when
                            // "Hide empty ports" drops a port out of
                            // `visiblePorts` entirely, THIS transition (not
                            // the child's internal `.fading`) owns the exit,
                            // since the child is unmounted before it could
                            // ever run one.
                            .transition(CardMotion.exit(reduceMotion: reduceMotion))
                            // The reduced-opacity dimming for a charger-only
                            // port whose power attribution just flapped away
                            // (#536) is now applied INSIDE SettlingPortCardHost
                            // itself (`SettlingCardOpacity.effectiveOpacity`,
                            // combined with the card's own exit fade). Moved
                            // there by per-task-review finding (round 1): a
                            // single `.opacity(...)` modifier here, driven by
                            // the shared `portVisibilityStates` dictionary,
                            // both coupled unrelated ports into one animated
                            // transaction on any tick where any port's state
                            // changed, and raced independently against the
                            // child's own internal exit fade (two separate
                            // transactions matched only by a shared duration
                            // could skew and momentarily brighten old live
                            // content past its dimmed value). Nothing left to
                            // apply here.
                        }
                        // Tunnelled devices normally nest inside their host
                        // port's card (above). Fall back to a flat card when the
                        // host port can't show them: either it's unknown
                        // (hostPortServiceName nil) or it was filtered out of
                        // visiblePorts (e.g. "hide empty ports" dropped a host
                        // whose connectionActive lagged the TB link). Without the
                        // visibility check those devices would render nowhere.
                        let hostPortVisible = tunnelledGroup.hostPortServiceName.map { name in
                            visiblePorts.contains { $0.serviceName == name }
                        } ?? false
                        if !hostPortVisible, !tunnelledGroup.devices.isEmpty {
                            OtherUSBDevicesCard(devices: tunnelledGroup.devices, kind: .thunderboltTunnelled)
                        }
                        // internalHubDevices is already desktop-gated by group(),
                        // so it is empty on a laptop and this card renders only
                        // on Mac mini / Studio / Pro (issue #348).
                        if !tunnelledGroup.internalHubDevices.isEmpty {
                            OtherUSBDevicesCard(devices: tunnelledGroup.internalHubDevices, kind: .builtInUSBPort)
                        }
                        // Native HDMI ports render after the USB-C / MagSafe
                        // group. They have no PD, no transports, no e-marker,
                        // so the card is a slim variant: just the port label
                        // and the display verdict(s). Issue #352.
                        ForEach(builtInDisplayPorts) { hdmiPort in
                            BuiltInDisplayPortCard(port: hdmiPort)
                        }
                    }
                    .padding(12)
                }
            }
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "cable.connector.horizontal")
                .scaledFont(.title2)
            Text(AppInfo.name).scaledFont(.headline, weight: .bold)
            Spacer()
            ForEach(Array(PluginRegistry.shared.headerButtonBuilders.enumerated()), id: \.offset) { _, builder in
                builder()
            }
            if settings.useMenuBarMode {
                Button {
                    refresh.keepOpen.toggle()
                } label: {
                    Image(systemName: refresh.keepOpen ? "pin.fill" : "pin")
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(refresh.keepOpen
                    ? String(localized: "Unpin (popover closes when you click away)", bundle: _appLocalizedBundle)
                    : String(localized: "Keep window open", bundle: _appLocalizedBundle))
            }
            Button {
                refresh.bump()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
                    .rotationEffect(.degrees(refreshIconRotation))
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Refresh", bundle: _appLocalizedBundle))
            Button {
                refresh.showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Settings", bundle: _appLocalizedBundle))
        }
        .padding(12)
        .background(
            Button("") {
                refresh.showSettings = true
            }
            .keyboardShortcut(",", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
        )
    }

    private var footer: some View {
        HStack {
            Toggle(String(localized: "Show technical details", bundle: _appLocalizedBundle), isOn: $settings.showTechnicalDetails)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .scaledFont(.caption)
            Spacer()
            Text(String(localized: "\(deviceWatcher.devices.count) USB devices", bundle: _appLocalizedBundle))
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: "·").scaledFont(.caption).foregroundStyle(.secondary)
            Button {
                NSWorkspace.shared.open(AppInfo.releaseURL)
            } label: {
                Text(verbatim: "v\(AppInfo.version)")
                    .scaledFont(.caption)
                    .underline()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            Text(verbatim: "· \(AppInfo.credit)")
                .scaledFont(.caption)
                .foregroundStyle(.tertiary)
            Text(verbatim: "·").scaledFont(.caption).foregroundStyle(.secondary)
            ForEach(Array(PluginRegistry.shared.footerButtonBuilders.enumerated()), id: \.offset) { _, builder in
                builder()
            }
            Button(String(localized: "Quit", bundle: _appLocalizedBundle)) { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var noPortsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "powerplug")
                .scaledFont(.largeTitle)
                .foregroundStyle(.secondary)
            Text(String(localized: "No USB-C ports detected", bundle: _appLocalizedBundle))
                .scaledFont(.headline, weight: .bold)
            Text(String(localized: "This Mac doesn't seem to expose its port-controller services. Hit refresh, or check System Information > USB.", bundle: _appLocalizedBundle))
                .scaledFont(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }

    private var nothingConnectedState: some View {
        VStack(spacing: 8) {
            Image(systemName: "cable.connector.slash")
                .scaledFont(.largeTitle)
                .foregroundStyle(.secondary)
            Text(String(localized: "Nothing connected", bundle: _appLocalizedBundle))
                .scaledFont(.headline, weight: .bold)
            Text(emptyPortsSummary)
                .scaledFont(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The "nothing plugged in" line, counting USB-C and MagSafe separately.
    ///
    /// `portWatcher.ports` holds both port types (see `AppleHPMInterface`'s
    /// `isRealPort` gate), so counting the array and calling the total "USB-C
    /// ports" mislabelled the MagSafe port on every laptop. Issue #471.
    ///
    /// The MagSafe clause is written for exactly one port because no Mac has
    /// ever shipped with two: 349 of the 523 machines in
    /// `research/customer-probes/` report a single `Port-MagSafe 3@1`, 174
    /// report none, and none report more. Anything outside that (a MagSafe-less
    /// desktop, or hardware that breaks the rule) falls back to the USB-C-only
    /// count, which stays true either way because it no longer counts MagSafe.
    private var emptyPortsSummary: String {
        let magSafeCount = portWatcher.ports.filter {
            $0.portTypeDescription?.hasPrefix("MagSafe") == true
        }.count
        let usbCCount = portWatcher.ports.count - magSafeCount
        if magSafeCount == 1 {
            return String(localized: "\(usbCCount) USB-C ports and 1 MagSafe port detected, but nothing is currently plugged in. Turn off \"Hide empty ports\" in Settings to see them.", bundle: _appLocalizedBundle)
        }
        return String(localized: "\(usbCCount) USB-C ports detected, but nothing is currently plugged in. Turn off \"Hide empty ports\" in Settings to see them.", bundle: _appLocalizedBundle)
    }

    /// Live-signal check delegating to the pure helper in `WhatCableCore`,
    /// so the same rules apply to both the GUI and any test harness.
    private func isPortLive(_ port: AppleHPMInterface, structurallyScopedDevices: [USBDevice] = []) -> Bool {
        WhatCableCore.isPortLive(
            port: port,
            powerSources: powerWatcher.sources(for: port),
            identities: pdWatcher.identities(for: port),
            matchingDevices: matchingDevices(for: port),
            chargerAttached: chargerAttached,
            hasStructurallyScopedTunnelledDevices: !structurallyScopedDevices.isEmpty
        )
    }

    /// True when the Mac reports an external power adapter attached right now.
    /// Corroborates a MagSafe `connectionActive` in `isPortLive`: M1/M2 MagSafe
    /// ports expose no per-port power source, so without this a connected
    /// MagSafe charger reads as "nothing connected". Read from the system
    /// adapter, which clears on unplug, so a lingering `connectionActive` can't
    /// keep the port live.
    private var chargerAttached: Bool {
        (SystemPower.currentAdapter()?.watts ?? 0) > 0
    }

    /// Match USB devices to their physical port. The IOKit relationship
    /// isn't direct: USB devices live under the XHCI controller subtree,
    /// physical ports under the SPMI/HPM subtree. Two strategies, in order:
    ///
    ///   1. `controllerPortName`: each XHCI controller exposes a `UsbIOPort`
    ///      property whose path ends in the physical port's service name
    ///      (e.g. ".../Port-USB-C@1"). When present, this gives a direct
    ///      link with no ambiguity.
    ///   2. `busIndex`: derived from the `hpm<N>` ancestor on the port side
    ///      and the XHCI controller's `locationID` upper byte on the device
    ///      side. Fragile, breaks when devices sit deeper behind a hub
    ///      than the parent walk reaches, or when hpm numbering diverges
    ///      from controller numbering.
    ///
    /// If neither is available we return [] rather than dumping every
    /// device onto the port. Showing all devices on every active USB port
    /// is worse than showing none, and it caused the bug that issue #21
    /// reported.
    private func matchingDevices(for port: AppleHPMInterface) -> [USBDevice] {
        port.matchingDevices(from: deviceWatcher.devices)
    }

    /// Per-port structural tunnel scoping, extracted out
    /// of `body` because a SwiftUI result-builder body cannot contain a bare
    /// `for` loop (only `ForEach`/`if`/`switch` are allowed as control flow).
    /// Pure: no IOKit, no view state, so it is unit-testable on its own.
    static func structurallyScopedTunnelledDevices(
        ports: [AppleHPMInterface],
        devices: [USBDevice],
        thunderboltSwitches: [IOThunderboltSwitch]
    ) -> (byPort: [String: [USBDevice]], allIDs: Set<UInt64>) {
        var byPort: [String: [USBDevice]] = [:]
        var allIDs: Set<UInt64> = []
        for port in ports {
            let scoped = TunnelledDeviceGrouping.structurallyScopedTunnelledDevices(
                for: port, in: devices, thunderboltSwitches: thunderboltSwitches
            )
            guard !scoped.isEmpty else { continue }
            byPort[port.serviceName] = scoped
            allIDs.formUnion(scoped.map(\.id))
        }
        return (byPort, allIDs)
    }
}

struct UpdateBanner: View {
    let update: AvailableUpdate
    @ObservedObject private var installer = Installer.shared

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "WhatCable \(update.version) is available", bundle: _appLocalizedBundle))
                    .scaledFont(.callout, weight: .bold)
                statusLine
                    .scaledFont(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            actionButtons
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.12))
    }

    @ViewBuilder
    private var statusLine: some View {
        switch installer.state {
        case .idle:
            Text(String(localized: "You're on \(AppInfo.version)", bundle: _appLocalizedBundle))
        case .resolving:
            Text(String(localized: "Checking for the latest version…", bundle: _appLocalizedBundle))
        case .downloading, .verifying, .installing:
            // When the re-check bumped to a newer release, keep saying so for
            // the whole install (download/verify/install), not just the brief
            // download phase, so a fast install doesn't hide the note.
            if installer.didFindNewerVersion {
                Text(String(localized: "Newer version found, installing it…", bundle: _appLocalizedBundle))
            } else if case .verifying = installer.state {
                Text(String(localized: "Verifying signature…", bundle: _appLocalizedBundle))
            } else if case .installing = installer.state {
                Text(String(localized: "Installing, WhatCable will relaunch", bundle: _appLocalizedBundle))
            } else {
                Text(String(localized: "Downloading…", bundle: _appLocalizedBundle))
            }
        case .failed(let message):
            Text(String(localized: "Install failed: \(message)", bundle: _appLocalizedBundle)).foregroundStyle(.red)
        case .blocked(let message):
            Text(message).foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch installer.state {
        case .idle, .failed:
            HStack(spacing: 6) {
                Button(String(localized: "View release", bundle: _appLocalizedBundle)) {
                    NSWorkspace.shared.open(update.url)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if update.downloadURL != nil {
                    Button(String(localized: "Install update", bundle: _appLocalizedBundle)) {
                        Installer.shared.install(update)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        case .blocked:
            // Self-update can't run here; only offer the manual download path.
            Button(String(localized: "View release", bundle: _appLocalizedBundle)) {
                NSWorkspace.shared.open(update.url)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .resolving, .downloading, .verifying, .installing:
            ProgressView().controlSize(.small)
        }
    }
}

// MARK: - Port card

/// A flat top-level card listing USB devices reached over a Thunderbolt tunnel,
/// shown when two or more Thunderbolt devices are connected so we can't safely
/// say which one they sit behind (issue #274). The single-device case nests
/// under that port's card instead, so this card is the ambiguous fallback.
struct OtherUSBDevicesCard: View {
    enum Kind {
        /// Devices behind a TB dock or display (issue #274).
        case thunderboltTunnelled
        /// Devices on built-in plain-USB ports behind the Mac's internal hub
        /// (front USB-C / USB-A on Mac mini, Studio, Pro; issue #348).
        case builtInUSBPort
    }

    let devices: [USBDevice]
    let kind: Kind

    /// Per-physical-port grouping for the built-in section (issue #490):
    /// one tree per Port-USB-A@N / Port-USB-C@N node, fallback group last.
    /// Empty for the tunnelled kind, which renders the flat list.
    private var builtInGroups: [BuiltInPortGrouping.Group] {
        kind == .builtInUSBPort ? BuiltInPortGrouping.groups(from: devices) : []
    }

    private var title: String {
        switch kind {
        case .thunderboltTunnelled:
            return String(localized: "Other USB devices", bundle: _appLocalizedBundle)
        case .builtInUSBPort:
            // Say the connector type outright when every device is on a
            // USB-A node (issue #490's headline ask).
            return BuiltInPortGrouping.allOnUSBA(builtInGroups)
                ? String(localized: "Built-in USB-A ports", bundle: _appLocalizedBundle)
                : String(localized: "Built-in USB ports", bundle: _appLocalizedBundle)
        }
    }

    private var footer: String {
        switch kind {
        case .thunderboltTunnelled:
            return String(localized: "Reached through a Thunderbolt dock or display, so there's no cable, power, or Thunderbolt data for them.", bundle: _appLocalizedBundle)
        case .builtInUSBPort:
            return String(localized: "Plain USB ports behind the Mac's internal hub, so there's no cable, power, or Thunderbolt data for them.", bundle: _appLocalizedBundle)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "cable.connector.horizontal")
                    .foregroundStyle(.secondary)
                Text(title)
                    .scaledFont(.headline, weight: .semibold)
            }
            if kind == .builtInUSBPort {
                // One tree per physical port, with a header naming the
                // connector ("Built-in USB-A port 1"). The unattributed
                // fallback group (macOS 15, no port node) has no header and
                // renders exactly like the pre-#490 combined list.
                ForEach(builtInGroups, id: \.portNodeName) { group in
                    if let connector = group.connector, let number = group.portNumber {
                        Text(String(localized: "Built-in \(connector) port \(number)", bundle: _appLocalizedBundle))
                            .scaledFont(.caption, weight: .semibold)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                        // Flat tree, no bus sub-headers: a USB-A port's USB2
                        // and USB3 personas sit on different buses, and
                        // splitting one physical port's tree by bus is
                        // exactly the plumbing noise the port header replaces.
                        ForEach(USBDeviceNode.flatten(USBDeviceNode.buildTree(from: group.devices))) { node in
                            USBDeviceRow(node: node)
                                .padding(.leading, 12)
                        }
                    } else {
                        GroupedUSBDeviceList(devices: group.devices)
                    }
                }
            } else {
                GroupedUSBDeviceList(devices: devices)
            }
            Text(footer)
                .scaledFont(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// A downstream USB device list, grouped under one header per USB controller
/// when the devices span more than one, and rendered flat when they don't.
///
/// This is the single renderer for that list. It exists because there are two
/// places the same list appears: the standalone "Other USB devices" card, used
/// when the devices can't be attributed to a port, and the "Connected over
/// Thunderbolt" section inside a port card, used when they can. Those two had
/// drifted: only the card grouped, so the bus headers appeared exactly when
/// WhatCable had failed to identify the dock's port and vanished when it
/// succeeded, which is backwards. Both call here now, so they cannot disagree
/// again.
struct GroupedUSBDeviceList: View {
    let devices: [USBDevice]

    var body: some View {
        // A dock fans its devices out across several USB controllers, so
        // group them by bus to show which ones share one. Nil when there
        // is only one bus: the flat tree then renders exactly as before.
        if let groups = USBDeviceNode.groupedByBus(from: devices) {
            ForEach(groups, id: \.bus) { group in
                Text(verbatim: USBDeviceNode.busLabel(group.bus))
                    .scaledFont(.caption, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                ForEach(USBDeviceNode.flatten(group.roots)) { node in
                    USBDeviceRow(node: node)
                        .padding(.leading, 12)
                }
            }
        } else {
            ForEach(USBDeviceNode.flatten(USBDeviceNode.buildTree(from: devices))) { node in
                USBDeviceRow(node: node)
            }
        }
    }
}

/// One device in a downstream USB tree: name, speed, indented by hub depth.
///
/// **Deliberately shallow, and it is a product boundary rather than an
/// oversight.** This tree answers "what is plugged in". Per-device inspection
/// (vendor, serial number, USB version, device class, power requested and
/// available, raw IOKit properties) is what the Pro Cable Diagnostics screen is
/// for, and it already shows all of it.
///
/// It briefly showed more. Between v1.2.1 and the 1.3.0 betas this row grew an
/// expandable detail panel (#451) and the maker inline in the name (#424), which
/// made the free tree strictly richer than the Pro screen's own device card:
/// free had the hierarchy AND the detail, Pro had a flat list. Nobody compared
/// the two while four separate PRs each added a reasonable-looking increment.
/// Both were pulled before they reached a stable release.
///
/// So: if you are about to add a field here, check the Pro card first.
/// `Tests/WhatCableAppTests/FreeDeviceTreeDepthTests.swift` will fail if you add
/// one of the inspection fields back.
///
/// Shared by `OtherUSBDevicesCard` and `PortCard`'s device tree so the two
/// render the same content.
struct USBDeviceRow: View {
    let node: USBDeviceNode

    /// Depth in the tree AS DISPLAYED, which is not always the device's depth
    /// within its own USB subtree.
    ///
    /// Under a Thunderbolt dock the rows come from two builders: the dock root
    /// and display rows from `ConnectedDeviceTree`, and the USB devices from
    /// `USBDeviceNode`. A hub that roots its own subtree has `node.depth == 0`
    /// while sitting at display depth 1, under the dock. Deriving the "↳"
    /// connector from `node.depth` therefore dropped it from exactly those
    /// rows, so they hung to the left with no connector while their own
    /// children had one. Regression from the #451/#452 grouping work, visible
    /// in the 1.3.0 betas and not in v1.2.1.
    ///
    /// Defaults to `node.depth` for the flat case, where the two agree.
    var displayDepth: Int? = nil

    /// Pre-built label from `ConnectedDeviceTree`, used verbatim when present.
    ///
    /// Without this the row rebuilt its own text from the device and silently
    /// dropped anything the row builder had added, which is how the "via N
    /// hubs" annotation ended up computed, tested in Core, and never once
    /// rendered. Core-side tests passed throughout: they asserted on `Row.label`
    /// while the view ignored it.
    ///
    /// `nil` for the bus-grouped and flat lists, which have no annotation to
    /// carry and build the same text locally.
    var label: String? = nil

    private var device: USBDevice { node.device }
    private var depth: Int { displayDepth ?? node.depth }

    var body: some View {
        // The maker stays: it is identification, not inspection. Without it
        // four rows on a UGreen dock read identically as
        // "USB2.0 Hub - High Speed (480 Mbps)" with nothing to tell them apart.
        // The tier line is the DETAIL PANEL (serial, USB version, device class,
        // power figures), which is gone; a maker printed on the device's own
        // label is not what Pro sells.
        // `ConnectedDeviceTree.deviceLabel` builds exactly this text, so the
        // fallback matches the supplied label rather than diverging from it.
        let text = label ?? "\(device.displayName) - \(device.speedLabel)"
        // "↳" marks "behind a hub". With no disclosure chevron competing for the
        // leading edge it is the only depth cue besides the indent, which is how
        // this read in v1.2.1. Keyed on the DISPLAY depth so a subtree root
        // under a dock still gets its connector.
        let prefix = depth > 0 ? "\u{21B3} " : ""
        Text(verbatim: "\(prefix)\(text)")
            .scaledFont(.callout)
            .padding(.leading, CGFloat(depth) * 16)
    }
}

struct PortCard: View {
    let port: AppleHPMInterface
    let devices: [USBDevice]
    /// USB devices reached over a Thunderbolt tunnel that belong behind this
    /// port's dock or display (issue #274), for devices with NO structural
    /// root data at all (the single-active-port fallback). Non-empty only on
    /// the one port a single connected Thunderbolt device is on; rendered as
    /// its own "Connected over Thunderbolt" subsection. Empty otherwise.
    var tunnelledDevices: [USBDevice] = []
    /// Tunnelled devices STRUCTURALLY scoped to this specific port (the
    /// follow-up): merged into the same "Connected devices" tree as
    /// `devices`, nested under their chain device, rather than rendered as
    /// a separate section. See `TunnelledDeviceGrouping
    /// .structurallyScopedTunnelledDevices`.
    var structuralTunnelledDevices: [USBDevice] = []
    let powerSources: [PowerSource]
    let identities: [USBPDSOP]
    let thunderboltSwitches: [IOThunderboltSwitch]
    let usb3Transports: [USB3Transport]
    /// Per-port TRM state, so the card can tell a live data link from one
    /// macOS is withholding until the accessory is approved.
    var trmTransports: [TRMTransport] = []
    /// Authoritative connection state derived from the live IOKit watchers,
    /// passed in from the parent so we don't have to consult them from here
    /// and so PortSummary doesn't fall back to the unreliable
    /// `port.connectionActive` property.
    let isLive: Bool
    let showAdvanced: Bool
    let cioCapability: CIOCableCapability?
    /// Apple's own name for what is attached, read from the port's UVDM node.
    /// Nil for every non-Apple accessory, which never publishes one.
    var accessoryIdentity: AppleAccessoryIdentity?
    /// DisplayPort transports for this port (link rate, lanes, monitor EDID),
    /// matched by `portKey`. One entry per connected monitor: a dock can drive
    /// several through a single port (issue #271). Empty when none.
    let displayPorts: [IOPortTransportStateDisplayPort]
    let chargerWattageSource: ChargerWattageSource
    let batteryFullyCharged: Bool?
    /// AppleSmartBattery's IsCharging flag. `nil` on desktops. `false` when
    /// macOS has paused charging (charge limit or Optimized Battery Charging).
    let batteryIsCharging: Bool?
    /// System-wide adapter info from `SystemPower.currentAdapter()`.
    /// Threaded through so the "Charger: <Manufacturer> <Name>" bullet
    /// can fire on the active charging port.
    let adapter: AdapterInfo?
    /// True when a different port holds the live charging contract, so a
    /// connected-but-idle charger here reads as on standby rather than
    /// stuck mid-negotiation. See issue #264.
    var anotherPortActivelyCharging: Bool = false
    /// Mid-session fault banner for this port: overcurrent trip or
    /// repeated drops observed while the cable stayed plugged in. `nil` when
    /// the session is clean. Owned by `ConnectionFaultTracker` upstream.
    var connectionDiagnostic: ConnectionDiagnostic? = nil
    /// Per-port FedDetails, so `ChargingDiagnostic` can explain a charger that
    /// is connected but not the active source on M1 Pro/Max/Ultra, where macOS
    /// publishes no USB-C PowerSource node (issue #459).
    var federatedIdentities: [FederatedIdentity] = []
    /// The monotonic instant (same clock as `DispatchTime.now().uptimeNanoseconds`)
    /// this port's current connection session was stamped, from
    /// `AppleHPMInterfaceWatcher.connectionAttachInstant(for:)`. `nil` means
    /// unknown (no session stamped yet, or the observer never saw the start of
    /// this connection). Deliberately an INSTANT, not a sampled age: a sampled
    /// number frozen at render time would stay "young" forever on re-render.
    /// `connectionAge` below is recomputed from this fresh on every render.
    var connectionAttachInstant: TimeInterval?
    /// The session token for this port's current connection
    /// (`AppleHPMInterfaceWatcher.connectionSessionGeneration(for:)`). Changes
    /// only on a genuine (re)stamp, never on churn reuse. Used to key the
    /// expiry `.task(id:)` below so a replug on an already-visible card
    /// restarts the wait.
    var connectionSessionGeneration: Int?

    @State private var reportingCable: USBPDSOP?
    /// Bumped by the expiry task below to force a body recompute once the
    /// e-marker read window has elapsed, without any new watcher publication.
    /// Never read directly; SwiftUI invalidates the view on any `@State`
    /// write regardless of whether the value itself is consulted in `body`.
    @State private var emarkerWindowExpiryTick = 0
    /// Whether the connected-devices list shows hubs.
    ///
    /// Off by default. Hubs are ~47% of devices in the probe corpus and a
    /// docked setup buries the display and the Ethernet adapter under five
    /// levels of them, which is the state this defaults away from. Per port,
    /// deliberately: a user inspecting one dock should not have every other
    /// card expand with it.
    @State private var showHubs = false

    var summary: PortSummary {
        PortSummary(
            port: port,
            sources: powerSources,
            identities: identities,
            devices: devices,
            thunderboltSwitches: thunderboltSwitches,
            federatedIdentities: federatedIdentities,
            usb3Transports: usb3Transports,
            trmTransports: trmTransports,
            cioCapability: cioCapability,
            accessoryIdentity: accessoryIdentity,
            isConnectedOverride: isLive,
            chargerWattageSource: chargerWattageSource,
            batteryFullyCharged: batteryFullyCharged,
            batteryIsCharging: batteryIsCharging,
            adapter: adapter,
            connectionAge: connectionAge
        )
    }

    /// The current monotonic instant, same clock as
    /// `AppleHPMInterfaceWatcher`'s attach-instant stamps
    /// (`DispatchTime`'s `uptimeNanoseconds`), so subtracting one from the
    /// other yields a real elapsed duration unaffected by wall-clock jumps.
    private static func monotonicNow() -> TimeInterval {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    /// Elapsed time since this port's current connection session was
    /// stamped, recomputed fresh on every render from `connectionAttachInstant`.
    /// `nil` when the instant is unknown, which `PortSummary` treats as "age
    /// unknown" and renders post-window wording for.
    private var connectionAge: TimeInterval? {
        connectionAttachInstant.map { instant in
            max(0, Self.monotonicNow() - instant)
        }
    }

    /// Identity for the expiry `.task(id:)` below. Includes the port id so
    /// distinct ports never share a task, and the session generation so a
    /// genuine replug of an already-visible card (same `ForEach` identity,
    /// unchanged port id) restarts the wait: the generation is the session
    /// token from `PortConnectionSessionTracker`, and it only changes on a
    /// real (re)stamp, never on #536 churn reuse.
    private struct EmarkerWindowTaskID: Hashable {
        let portID: UInt64
        let generation: Int?
    }

    private var emarkerWindowTaskID: EmarkerWindowTaskID {
        EmarkerWindowTaskID(portID: port.id, generation: connectionSessionGeneration)
    }

    /// Waits out the remainder of the e-marker read window for THIS
    /// connection session, then bumps `emarkerWindowExpiryTick` so `body`
    /// recomputes `summary` and falls out of "Reading cable details…".
    ///
    /// Keyed by `.task(id: emarkerWindowTaskID)` below: SwiftUI cancels and
    /// restarts this task whenever the id changes (a replug bumping the
    /// generation, or the card being removed), so there's no manual timer
    /// bookkeeping and no risk of a stale wait firing against a later
    /// session.
    private func waitForEmarkerWindowExpiry() async {
        guard let instant = connectionAttachInstant else { return }
        let age = max(0, Self.monotonicNow() - instant)
        guard age < PortSummary.emarkerReadWindow else { return }
        // Small epsilon past the window boundary so the re-render lands
        // just after macOS's own schedule, not exactly on it.
        let remaining = PortSummary.emarkerReadWindow - age + 0.1
        try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        guard !Task.isCancelled else { return }
        emarkerWindowExpiryTick &+= 1
    }

    /// The host root switch for this port, if it maps to one.
    var thunderboltRoot: IOThunderboltSwitch? {
        guard let socketID = ThunderboltTopology.socketID(for: port) else { return nil }
        return ThunderboltTopology.hostRoot(forSocketID: socketID, in: thunderboltSwitches)
    }

    /// The full downstream Thunderbolt fabric tree for this port, following
    /// every branch (a dock with two TB devices yields two subtrees, issue
    /// #280). Empty if the port doesn't map to any TB switch.
    var thunderboltTree: [IOThunderboltSwitchNode] {
        guard let root = thunderboltRoot else { return [] }
        return ThunderboltTopology.tree(from: root, in: thunderboltSwitches)
    }

    /// A titled USB device tree (the "Connected over Thunderbolt" subsection
    /// inside a port card). `note` adds a caption line.
    ///
    /// Renders through `GroupedUSBDeviceList`, the same view the standalone
    /// "Other USB devices" card uses. This list used to build its own flat
    /// tree, which meant a dock's devices were grouped by controller only when
    /// WhatCable could NOT tell which port the dock was on (the fallback card)
    /// and never when it could (here). The CLI grouped in both cases, so the
    /// app disagreed with the CLI on the most common setup there is.
    @ViewBuilder
    private func deviceTree(_ devices: [USBDevice], title: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .scaledFont(.subheadline, weight: .semibold)
                .foregroundStyle(.secondary)
            GroupedUSBDeviceList(devices: devices)
            if let note {
                Text(note)
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 48)
        .padding(.top, 4)
    }

    /// The "Connected devices" list built from pre-labelled rows
    /// (`ConnectedDeviceTree`), so the app and the CLI render the identical
    /// tree: the Thunderbolt device as root with its live link speed, then
    /// monitors and USB devices indented under it.
    @ViewBuilder
    private func rowTree(_ rows: [ConnectedDeviceTree.Row], title: String, hiddenHubs: Int = 0) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .scaledFont(.subheadline, weight: .semibold)
                .foregroundStyle(.secondary)
            // Device rows key on the IOKit entry ID so USBDeviceRow's expanded
            // state follows its device across a replug that reorders the list.
            // Offset-keying them would migrate the state to whichever device
            // landed at that index. Non-device rows (the Thunderbolt root, a
            // display, a bus header) stay offset-keyed: they hold no state, and
            // two identical monitors would collide on a label-derived id.
            let identified = rows.enumerated().map { offset, row in
                (id: row.device.map { "device-\($0.id)" } ?? "row-\(offset)", row: row)
            }
            ForEach(identified, id: \.id) { _, row in
                // A row carrying its node is a USB device, so it gets the same
                // expandable detail as the Thunderbolt-tunnelled list. Rows
                // without one describe the Thunderbolt root, a display, or a
                // bus header, and stay plain text.
                if let node = row.device {
                    // Hand the row its DISPLAY depth and let it own both the
                    // indent and the connector, so the two cannot disagree.
                    // Previously the caller padded by the structural difference
                    // while the row indented by `node.depth` and derived its
                    // connector from the same value, which dropped the "↳" from
                    // any device rooting its own subtree.
                    USBDeviceRow(node: node, displayDepth: row.depth, label: row.label)
                } else {
                    let prefix = row.depth > 0 ? "\u{21B3} " : "\u{2022} "
                    Text(verbatim: "\(prefix)\(row.label)")
                        .scaledFont(.callout)
                        .padding(.leading, CGFloat(row.depth) * 16)
                }
            }
            if hiddenHubs > 0 || showHubs {
                Button {
                    showHubs.toggle()
                } label: {
                    // Plural handled by Localizable.stringsdict, not by a
                    // hand-rolled singular/other switch: that reads wrong in
                    // languages with more than two plural categories, which is
                    // exactly what stringsdict exists for.
                    Text(showHubs
                         ? String(localized: "Hide hubs", bundle: _appLocalizedBundle)
                         : String(localized: "Show \(hiddenHubs) hubs", bundle: _appLocalizedBundle))
                        .scaledFont(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)
            }
        }
        .padding(.leading, 48)
        .padding(.top, 4)
    }

    private var cableEmarker: USBPDSOP? {
        identities.first { $0.endpoint == .sopPrime || $0.endpoint == .sopDoublePrime }
    }

    private var cablePartner: USBPDSOP? {
        identities.first { $0.endpoint == .sop }
    }

    var body: some View {
        let summary = self.summary
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: summary.icon)
                    .scaledFont(.title2)
                    .foregroundStyle(summary.iconColor)
                    .frame(width: 36)
                // Split into three rows instead of one HStack (issue #584):
                // trailing labels (the Diagnostics button, cable-tracking
                // control) used to share a row with the headline/subtitle,
                // so a long trailing label (worst case, the no-e-marker
                // tracking message) squeezed the title into a mid-phrase
                // wrap. Putting the port name + trailing controls on their
                // own row means they can never constrain the headline or
                // subtitle width, which now each get the full card width.
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .top, spacing: 12) {
                        Text(port.portDescription ?? port.serviceName)
                            .scaledFont(.caption)
                            .foregroundStyle(.secondary)
                            .layoutPriority(1)
                        Spacer()
                        // Diagnostics (and any other trailing plugin button) only
                        // makes sense once a cable is actually connected (owner
                        // ruling, issue #585, task 2: "no need for diagnostics to
                        // show until there is a cable connected"). Gating on `isLive`
                        // hides it on every disconnected card, launch-time empty
                        // ports included, not just the `.retained` steady state task
                        // 1 fixes above.
                        if isLive {
                            let ctx = PortCardContext(
                                portKey: port.portKey,
                                portNumber: port.portNumber,
                                serviceName: port.serviceName,
                                portTypeDescription: port.portTypeDescription,
                                pinConfiguration: port.pinConfiguration,
                                plugOrientation: port.plugOrientation
                            )
                            ForEach(Array(PluginRegistry.shared.portCardTrailingBuilders.enumerated()), id: \.offset) { _, builder in
                                if let view = builder(ctx) {
                                    view
                                }
                            }
                        }
                    }
                    Text(summary.headline)
                        .scaledFont(.title3, weight: .bold)
                    if !summary.subtitle.isEmpty {
                        Text(summary.subtitle)
                            .scaledFont(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // A mid-session fault (overcurrent trip, repeated drops) is the
            // most urgent thing on the card, so it leads the callout group.
            if let connectionDiagnostic {
                ConnectionBanner(diagnostic: connectionDiagnostic)
                    .padding(.leading, 48)
            }

            if let diag = ChargingDiagnostic(port: port, sources: powerSources, identities: identities, adapter: adapter, wattageSource: chargerWattageSource, batteryFullyCharged: batteryFullyCharged, batteryIsCharging: batteryIsCharging, anotherPortActivelyCharging: anotherPortActivelyCharging, federatedIdentities: federatedIdentities) {
                DiagnosticBanner(diagnostic: diag)
                    .padding(.leading, 48)
            }

            if let dataDiag = DataLinkDiagnostic(
                port: port,
                identities: identities,
                devices: devices,
                usb3Transports: usb3Transports,
                cio: cioCapability,
                thunderboltSwitches: thunderboltSwitches
            ) {
                DataLinkBanner(diagnostic: dataDiag)
                    .padding(.leading, 48)
            }

            // One banner per connected monitor (a dock can drive several
            // through one port, issue #271). Keyed by offset because the
            // DisplayPort node carries no unique id and two identical monitors
            // would otherwise collide.
            ForEach(Array(displayPorts.enumerated()), id: \.offset) { _, displayPort in
                if let displayDiag = DisplayDiagnostic(dp: displayPort, cable: cableEmarker, port: port) {
                    DisplayBanner(diagnostic: displayDiag)
                        .padding(.leading, 48)
                }
            }

            // Trust signals sit with the other top-of-card callouts (charging,
            // link speed, display) rather than below the bullets, so the cable
            // verdict is read alongside the link-speed verdict.
            if let cable = cableEmarker {
                let trust = CableTrustReport(identity: cable, partner: cablePartner)
                if !trust.isEmpty {
                    TrustFlagsCard(flags: trust.flags)
                        .padding(.leading, 48)
                }
            }

            // Name only, no diagnosis: a Billboard device is often benign, so
            // the inline card just names it. Any inference about a failed Alt
            // Mode lives only in the Pro Display Diagnostics screen, gated on a
            // degraded link.
            if let billboard = port.billboardDevice(among: devices) {
                HStack(alignment: .top, spacing: 6) {
                    Text(verbatim: "•").foregroundStyle(.secondary)
                    Text(billboard.billboardPresenceLabel(bundle: _appLocalizedBundle))
                        .scaledFont(.callout)
                    Spacer()
                }
                .padding(.leading, 48)
            }

            if !summary.groups.isEmpty {
                // One subheading per source, replacing the old single "Cable
                // details" heading. The card's facts come from four places
                // with four different reliabilities (the cable's e-marker and
                // the charger both make claims; the Mac measures; our database
                // is our own records), and a flat list of equal-weight bullets
                // let a claim read as a fact. The extra top gap still marks the
                // break from the callout verdicts above.
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(summary.groups, id: \.kind) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.header)
                                .scaledFont(.subheadline, weight: .semibold)
                                .foregroundStyle(.secondary)
                            // The group's state, e.g. "not read on this
                            // connection". Deliberately not a bullet: it is not
                            // one of the facts, it is why there are none.
                            if let subtitle = group.subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .scaledFont(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(group.lines, id: \.self) { line in
                                HStack(alignment: .top, spacing: 6) {
                                    Text(verbatim: "•").foregroundStyle(.secondary)
                                    Text(line).scaledFont(.callout)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                .padding(.leading, 48)
                .padding(.top, 4)
            }

            let connectedRows = ConnectedDeviceTree.rows(
                devices: devices,
                tunnelledDevices: structuralTunnelledDevices,
                port: port,
                thunderboltSwitches: thunderboltSwitches,
                displayPorts: displayPorts,
                hubs: showHubs ? .all : .endpointsOnly
            )
            if !connectedRows.isEmpty {
                // Count what is ACTUALLY hidden by diffing the two views, not by
                // counting hubs. Those differ on the all-hub fallback path,
                // where collapsing would leave an empty section so the full
                // tree is shown instead: counting hubs there produced a
                // "Show 9 hubs" button next to nine visible hubs, and clicking
                // it changed the caption without changing a single row.
                let shownIDs = Set(connectedRows.compactMap { $0.device?.id })
                let allRows = ConnectedDeviceTree.rows(
                    devices: devices,
                    tunnelledDevices: structuralTunnelledDevices,
                    port: port,
                    thunderboltSwitches: thunderboltSwitches,
                    displayPorts: displayPorts,
                    hubs: .all
                )
                let hiddenHubs = allRows.compactMap { $0.device?.id }
                    .filter { !shownIDs.contains($0) }
                    .count
                rowTree(
                    connectedRows,
                    title: String(localized: "Connected devices", bundle: _appLocalizedBundle),
                    hiddenHubs: hiddenHubs
                )
            }

            if !tunnelledDevices.isEmpty {
                deviceTree(
                    tunnelledDevices,
                    title: String(localized: "Connected over Thunderbolt", bundle: _appLocalizedBundle),
                    note: String(localized: "Reached through a Thunderbolt dock or display, so there's no cable, power, or Thunderbolt data for them.", bundle: _appLocalizedBundle)
                )
            }

            if !powerSources.isEmpty && isLive {
                PowerSourceList(sources: powerSources)
                    .padding(.leading, 48)
                    .padding(.top, 4)
            }

            // Trust card is rendered up with the callouts above; only the
            // report action stays at the bottom of the card.
            //
            // Issue #573: hidden on MagSafe. The cable DB keys on
            // VID+PID+Cable VDO, and MagSafe never publishes a Cable VDO, so
            // a report would carry nothing the DB could use. Gated on the
            // PORT fact (`parentPortType`, the one source of truth this
            // whole feature reads), not on the e-marker payload being empty.
            if let cable = cableEmarker, cable.parentPortType != PortIdentity.magSafeTypeCode {
                HStack {
                    Spacer()
                    Button {
                        reportingCable = cable
                    } label: {
                        Label(String(localized: "Report this cable", bundle: _appLocalizedBundle), systemImage: "exclamationmark.bubble")
                            .scaledFont(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "File a GitHub issue with this cable's e-marker fingerprint", bundle: _appLocalizedBundle))
                }
                .padding(.leading, 48)
            }

            // Owner ruling, issue #585: "clearly the technical details
            // section should be gated on isLive regardless if this is a new
            // or old issue". Same reasoning as the trailing Diagnostics
            // button gate above: raw port details make no sense on a
            // disconnected card, launch-time empty or retained alike.
            if showAdvanced && isLive {
                Divider()
                AdvancedPortDetails(
                    port: port,
                    cableEmarker: cableEmarker,
                    thunderboltRoot: thunderboltRoot,
                    thunderboltTree: thunderboltTree,
                    thunderboltSwitches: thunderboltSwitches
                )
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        // Re-renders the card once this connection session's e-marker read
        // window elapses, so "Reading cable details…" doesn't get stuck
        // forever without a fresh watcher publication. Keyed by port id +
        // session generation: a replug on an already-visible card changes
        // the generation, which cancels the old wait and starts a new one;
        // unmounting the card cancels it automatically.
        .task(id: emarkerWindowTaskID) {
            await waitForEmarkerWindowExpiry()
        }
        .sheet(item: $reportingCable) { cable in
            // Wrapped so the sheet's own window picks up the opacity slider too
            // (sheets are separate child windows, not covered by the parent's
            // ScaledHost).
            ScaledHost {
                CableReportSheet(cableIdentity: cable, cioCapability: cioCapability, port: port) {
                    reportingCable = nil
                }
            }
        }
    }

}

/// Visual weight of a top-of-card callout, by severity. Warnings get a filled
/// box so they stand out; positive, info, and neutral notes are lighter (no
/// fill) so the eye lands on problems first within the callout group.
enum CalloutRole {
    case warning    // a problem worth the user's attention
    case caution    // a softer heads-up: worth a look, not "act now"
    case positive   // reassurance: everything is fine
    case info       // an informational note, no problem
    case neutral    // could not determine, no verdict

    var accent: Color {
        switch self {
        case .warning: return .orange
        // Amber, distinct from the orange warning tier so the eye can tell a
        // "worth a look" note (repeated drops) from an "act now" one
        // (overcurrent, cable bottleneck).
        case .caution: return Color(red: 0.85, green: 0.6, blue: 0.0)
        case .positive: return .green
        case .info: return .blue
        case .neutral: return .secondary
        }
    }

    var isWarning: Bool { self == .warning }
}

extension View {
    /// Shared chrome for every callout (diagnostic banners + trust card) so
    /// the group reads as one family: a tinted, rounded fill keyed to the
    /// callout's accent colour.
    func calloutChrome(role: CalloutRole) -> some View {
        self
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(role.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// One consistent callout for a single verdict (charging, link speed, display).
/// All four top-of-card callouts share this chrome and anatomy: a coloured
/// icon, a bold summary, and a secondary detail line.
struct CalloutBanner: View {
    let role: CalloutRole
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(role.accent)
                .scaledFont(.callout)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).scaledFont(.callout, weight: .bold)
                Text(detail)
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .calloutChrome(role: role)
    }
}

struct DiagnosticBanner: View {
    let diagnostic: ChargingDiagnostic

    // Only a cable limit is a warning. A fine/standby charger reads positive;
    // the benign/transient states (Mac drawing less, negotiation pending,
    // adapter-fallback wattage) read as calm neutral notes, not alarms.
    private var role: CalloutRole {
        switch diagnostic.bottleneck {
        case .cableLimit: return .warning
        case .fine, .standbyCharger: return .positive
        case .macLimit, .chargerLimit, .noCharger: return .neutral
        }
    }

    var body: some View {
        CalloutBanner(
            role: role,
            icon: diagnostic.icon,
            title: diagnostic.summary,
            detail: diagnostic.detail
        )
    }
}

struct DataLinkBanner: View {
    let diagnostic: DataLinkDiagnostic

    var body: some View {
        CalloutBanner(
            role: diagnostic.isWarning ? .warning : .positive,
            icon: diagnostic.icon,
            title: diagnostic.summary,
            detail: diagnostic.detail
        )
    }
}

/// Mid-session fault banner. Overcurrent reads as an orange warning
/// (a hardware protection trip, "act now"); repeated drops read as an amber
/// caution ("worth a look").
struct ConnectionBanner: View {
    let diagnostic: ConnectionDiagnostic

    private var role: CalloutRole {
        switch diagnostic.severity {
        case .warning: return .warning
        case .caution: return .caution
        }
    }

    private var icon: String {
        switch diagnostic.fault {
        case .overcurrent: return "exclamationmark.triangle.fill"
        case .repeatedConnectionEvents: return "bolt.horizontal.circle.fill"
        }
    }

    var body: some View {
        CalloutBanner(
            role: role,
            icon: icon,
            title: diagnostic.summary,
            detail: diagnostic.detail
        )
    }
}

struct DisplayBanner: View {
    let diagnostic: DisplayDiagnostic

    private var role: CalloutRole {
        switch diagnostic.bottleneck {
        case .fine, .compressionActive: return .positive
        case .belowMonitorMax, .adapterLimit: return .warning
        case .unknownMode, .compressionPlausible: return .neutral
        }
    }

    private var icon: String {
        switch diagnostic.bottleneck {
        case .fine: return "checkmark.seal.fill"
        case .belowMonitorMax: return "exclamationmark.triangle.fill"
        case .adapterLimit: return "arrow.triangle.swap"
        case .unknownMode: return "questionmark.circle"
        case .compressionPlausible, .compressionActive: return "info.circle"
        }
    }

    var body: some View {
        CalloutBanner(role: role, icon: icon, title: diagnostic.summary, detail: diagnostic.detail)
    }
}

/// Thin chrome around an in-place Pro screen: a Back button to return to
/// the main content, and (menu-bar mode only) the pin toggle so the
/// popover can be kept open while plugging cables in and out. The screen
/// keeps its own header/title below this bar.
struct ProScreenContainer<Content: View>: View {
    let isMenuBarMode: Bool
    let isPinned: Bool
    let onTogglePin: () -> Void
    let onBack: () -> Void
    let onDetach: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Label(
                        String(localized: "Back", bundle: _appLocalizedBundle),
                        systemImage: "chevron.left"
                    )
                    .scaledFont(.callout)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                if isMenuBarMode {
                    Button(action: onDetach) {
                        Image(systemName: "macwindow")
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "Open in a separate window", bundle: _appLocalizedBundle))
                    Button(action: onTogglePin) {
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help(isPinned
                        ? String(localized: "Unpin (popover closes when you click away)", bundle: _appLocalizedBundle)
                        : String(localized: "Keep window open", bundle: _appLocalizedBundle))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            content
        }
    }
}

struct PowerSourceList: View {
    let sources: [PowerSource]

    /// Apple's analog charger identity node (issue #592). Its options are
    /// junk placeholder values (5V @ 0.5A) and never carry a winning
    /// contract, so they must not render as PD profile rows.
    private static let brickIDName = "Brick ID"

    /// True when a source's options should render as PD profile rows.
    static func showsPDProfiles(for source: PowerSource) -> Bool {
        source.name != brickIDName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(sources) { src in
                if PowerSourceList.showsPDProfiles(for: src) {
                    if !src.options.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            let srcName = src.name
                            Text(String(localized: "\(srcName) profiles", bundle: _appLocalizedBundle))
                                .scaledFont(.subheadline, weight: .semibold)
                                .foregroundStyle(.secondary)
                            ForEach(src.options.sorted(by: { $0.voltageMV < $1.voltageMV }), id: \.self) { opt in
                                let isWinning = opt == src.winning
                                HStack(spacing: 6) {
                                    Image(systemName: isWinning ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isWinning ? Color.green : Color.secondary)
                                        .scaledFont(.caption)
                                    Text(verbatim: "\(opt.voltsLabel) @ \(opt.ampsLabel) - \(opt.wattsLabel)")
                                        .scaledFont(.callout, monospacedDigit: true)
                                    if isWinning {
                                        Text(String(localized: "active", bundle: _appLocalizedBundle)).scaledFont(.caption2).foregroundStyle(.green)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: src.name)
                            .scaledFont(.subheadline, weight: .semibold)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "Analog charger identifier, no PD profiles", bundle: _appLocalizedBundle))
                            .scaledFont(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct AdvancedPortDetails: View {
    let port: AppleHPMInterface
    let cableEmarker: USBPDSOP?
    let thunderboltRoot: IOThunderboltSwitch?
    let thunderboltTree: [IOThunderboltSwitchNode]
    /// Full live switch list, needed (beyond `thunderboltRoot`/`thunderboltTree`)
    /// to resolve `ActiveTunnelPresentation`'s tunnel terminal switches, which
    /// can sit anywhere in the fabric, not just on the direct root-to-leaf path.
    let thunderboltSwitches: [IOThunderboltSwitch]
    @Environment(\.fontScale) private var fontScale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            group(String(localized: "Connection", bundle: _appLocalizedBundle)) {
                row(String(localized: "Active", bundle: _appLocalizedBundle), bool(port.connectionActive))
                row(String(localized: "Active cable electronics", bundle: _appLocalizedBundle), bool(port.activeCable))
                row(String(localized: "Optical", bundle: _appLocalizedBundle), bool(port.opticalCable))
                row(String(localized: "USB active", bundle: _appLocalizedBundle), bool(port.usbActive))
                row(String(localized: "SuperSpeed", bundle: _appLocalizedBundle), bool(port.superSpeedActive))
                row(String(localized: "Plug events", bundle: _appLocalizedBundle), port.plugEventCount.map(String.init) ?? "—")
            }
            group(String(localized: "Transports", bundle: _appLocalizedBundle)) {
                row(String(localized: "Supported", bundle: _appLocalizedBundle), port.transportsSupported.joined(separator: ", "))
                row(String(localized: "Provisioned", bundle: _appLocalizedBundle), port.transportsProvisioned.joined(separator: ", "))
                row(String(localized: "Active", bundle: _appLocalizedBundle), port.transportsActive.isEmpty ? "—" : port.transportsActive.joined(separator: ", "))
            }
            if let v2 = cableEmarker?.activeCableVDO2 {
                ActiveCableVDO2Section(vdo2: v2)
            }
            if let root = thunderboltRoot, !thunderboltTree.isEmpty {
                ThunderboltFabricSection(root: root, nodes: thunderboltTree)
            }
            if let root = thunderboltRoot {
                // Bundle is Core's, not the app's: ActiveTunnelPresentation's
                // strings ("Video" / "USB data" / "adapter %lld" / the
                // "Active tunnels:" header reused below) live in
                // WhatCableCore's Localizable.strings, the same catalog the
                // CLI reads, so both surfaces render identical text without
                // a second app-bundle copy of the same keys.
                let tunnels = ThunderboltTopology.tunnels(from: root, in: thunderboltSwitches)
                let tunnelLines = ActiveTunnelPresentation.lines(tunnels: tunnels, switches: thunderboltSwitches, bundle: _coreLocalizedBundle)
                if !tunnelLines.isEmpty {
                    group(String(localized: "Active tunnels:", bundle: _coreLocalizedBundle)) {
                        ForEach(Array(tunnelLines.enumerated()), id: \.offset) { _, line in
                            Text(verbatim: line).scaledFont(.caption, design: .monospaced)
                        }
                    }
                }
            }
            let rawCount = port.redactedRawProperties.count
            DisclosureGroup(String(localized: "All raw IOKit properties (\(rawCount))", bundle: _appLocalizedBundle)) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(port.redactedRawProperties.sorted(by: { $0.key < $1.key }), id: \.key) { kv in
                        HStack(alignment: .top) {
                            Text(kv.key).scaledFont(.caption, design: .monospaced)
                                .foregroundStyle(.secondary)
                                .frame(width: 200 * fontScale, alignment: .leading)
                            Text(kv.value).scaledFont(.caption, design: .monospaced)
                                .textSelection(.enabled)
                            Spacer()
                        }
                    }
                }
                .padding(.top, 4)
            }
            .scaledFont(.caption)
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).scaledFont(.caption, weight: .bold).foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).scaledFont(.caption).foregroundStyle(.secondary).frame(width: 160 * fontScale, alignment: .leading)
            Text(value).scaledFont(.caption, design: .monospaced)
            Spacer()
        }
    }

    private func bool(_ v: Bool?) -> String {
        guard let v else { return "—" }
        return v ? String(localized: "Yes", bundle: _appLocalizedBundle) : String(localized: "No", bundle: _appLocalizedBundle)
    }
}

/// Renders every field in Active Cable VDO 2. Hidden behind the
/// existing "show technical details" toggle. The bullet list above the
/// fold already surfaces the user-facing essentials (medium, active
/// element, optical isolation), so this section is the deep view for
/// people who want to see USB protocol support, lane count, idle power,
/// thermal limits, etc.
struct ActiveCableVDO2Section: View {
    let vdo2: PDVDO.ActiveCableVDO2
    @Environment(\.fontScale) private var fontScale

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "Active cable (VDO 2)", bundle: _appLocalizedBundle))
                .scaledFont(.caption, weight: .bold)
                .foregroundStyle(.secondary)
            row(String(localized: "Physical connection", bundle: _appLocalizedBundle), vdo2.physicalConnection.label)
            row(String(localized: "Active element", bundle: _appLocalizedBundle), vdo2.activeElement.label)
            row(String(localized: "Optically isolated", bundle: _appLocalizedBundle), bool(vdo2.opticallyIsolated))
            row(String(localized: "USB lanes", bundle: _appLocalizedBundle), vdo2.twoLanesSupported ? String(localized: "Two", bundle: _appLocalizedBundle) : String(localized: "One", bundle: _appLocalizedBundle))
            row(String(localized: "USB Gen", bundle: _appLocalizedBundle), vdo2.usbGen2OrHigher ? String(localized: "Gen 2 or higher", bundle: _appLocalizedBundle) : String(localized: "Gen 1", bundle: _appLocalizedBundle))
            row(String(localized: "USB4 supported", bundle: _appLocalizedBundle), bool(vdo2.usb4Supported))
            row(String(localized: "USB 3.2 supported", bundle: _appLocalizedBundle), bool(vdo2.usb32Supported))
            row(String(localized: "USB 2.0 supported", bundle: _appLocalizedBundle), bool(vdo2.usb2Supported))
            row(String(localized: "USB 2.0 hub hops", bundle: _appLocalizedBundle), String(vdo2.usb2HubHopsConsumed))
            row(String(localized: "USB4 asymmetric", bundle: _appLocalizedBundle), bool(vdo2.usb4AsymmetricMode))
            row(String(localized: "U3 to U0 transition", bundle: _appLocalizedBundle), vdo2.u3ToU0TransitionThroughU3S ? String(localized: "Through U3S", bundle: _appLocalizedBundle) : String(localized: "Direct", bundle: _appLocalizedBundle))
            row(String(localized: "Idle power (U3/CLd)", bundle: _appLocalizedBundle), vdo2.u3CLdPower.label)
            row(String(localized: "Max operating temp", bundle: _appLocalizedBundle), temp(vdo2.maxOperatingTempC))
            row(String(localized: "Shutdown temp", bundle: _appLocalizedBundle), temp(vdo2.shutdownTempC))
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).scaledFont(.caption).foregroundStyle(.secondary).frame(width: 160 * fontScale, alignment: .leading)
            Text(value).scaledFont(.caption, design: .monospaced)
            Spacer()
        }
    }

    private func bool(_ v: Bool) -> String {
        v ? String(localized: "Yes", bundle: _appLocalizedBundle) : String(localized: "No", bundle: _appLocalizedBundle)
    }

    /// 0 in this field means "not specified" per the spec text. Show
    /// the dash placeholder rather than the misleading literal "0°C".
    private func temp(_ v: Int) -> String {
        v == 0 ? "—" : "\(v)°C"
    }
}

/// Expandable tree view of the Thunderbolt fabric for one port. Shows the
/// host root and every downstream switch, following all branches (a dock with
/// two TB devices shows both, issue #280). Each row shows the device name and
/// the link by which it connects. Hidden behind the existing "show technical
/// details" toggle, and collapsible within it.
struct ThunderboltFabricSection: View {
    let root: IOThunderboltSwitch
    let nodes: [IOThunderboltSwitchNode]
    @State private var expanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 4) {
                row(
                    depth: 0,
                    arrow: "",
                    name: String(localized: "Host (\(root.className))", bundle: _appLocalizedBundle),
                    port: ThunderboltTopology.activeDownstreamLanePort(root)
                )
                ForEach(ThunderboltTopology.flatten(nodes), id: \.id) { node in
                    row(
                        depth: node.depth + 1,
                        arrow: "↳ ",
                        name: ThunderboltLabels.deviceName(for: node.sw),
                        port: ThunderboltTopology.connectionLanePort(node.sw)
                    )
                }
            }
            .padding(.top, 2)
        } label: {
            Text(String(localized: "Thunderbolt fabric", bundle: _appLocalizedBundle))
                .scaledFont(.caption, weight: .bold).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func row(depth: Int, arrow: String, name: String, port: IOThunderboltPort?) -> some View {
        let indent = String(repeating: "  ", count: depth)
        let linkLabel = port.flatMap { ThunderboltLabels.linkLabel(for: $0) } ?? String(localized: "no active link", bundle: _appLocalizedBundle)
        HStack(alignment: .top) {
            Text(verbatim: "\(indent)\(arrow)\(name)")
                .scaledFont(.caption, design: .monospaced)
            Spacer()
            Text(linkLabel)
                .scaledFont(.caption, design: .monospaced)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TrustFlagsCard: View {
    let flags: [TrustFlag]

    /// A card with any real warning reads as a warning (orange triangle).
    /// A card with only neutral notes reads calm (blue info), so a softened
    /// false-positive doesn't look like an alarm.
    private var hasWarning: Bool {
        flags.contains { $0.severity == .warning }
    }

    // Shares the callout family's chrome (see CalloutRole / calloutChrome):
    // a real warning fills the box; a softened note reads as a calm, unfilled
    // info note, so a false-positive does not look like an alarm.
    private var role: CalloutRole { hasWarning ? .warning : .info }

    private var headerIcon: String {
        hasWarning ? "exclamationmark.triangle.fill" : "info.circle.fill"
    }

    private var headerText: String {
        hasWarning
            ? String(localized: "Cable trust signals", bundle: _appLocalizedBundle)
            : String(localized: "Cable note", bundle: _appLocalizedBundle)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: headerIcon)
                .foregroundStyle(role.accent)
                .scaledFont(.callout)
            VStack(alignment: .leading, spacing: 4) {
                Text(headerText)
                    .scaledFont(.caption, weight: .bold)
                    .foregroundStyle(.secondary)
                ForEach(flags, id: \.code) { flag in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(flag.title).scaledFont(.callout, weight: .bold)
                        Text(flag.detail)
                            .scaledFont(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .calloutChrome(role: role)
    }
}
