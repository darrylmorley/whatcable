# WhatCable

> **What can this USB-C cable actually do?**

A small macOS menu bar app that tells you, in plain English, what each USB-C cable plugged into your Mac can actually do, and **why your Mac might be charging slowly**.

USB-C hides a lot under one connector. Anything from a USB 2.0 charge-only cable to a 240W / 40 Gbps Thunderbolt 4 cable, all looking identical in your drawer. macOS already exposes the relevant info via IOKit; WhatCable surfaces it as a friendly menu bar popover.

[![Latest release](https://img.shields.io/github/v/release/darrylmorley/whatcable)](https://github.com/darrylmorley/whatcable/releases/latest)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)](https://github.com/darrylmorley/whatcable)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

![WhatCable popover](docs/screenshot.png)

## What it shows

Per port, in plain English:

- **At-a-glance headline** — Thunderbolt / USB4, USB device, Charging only, Slow USB / charge-only cable, Nothing connected
- **Charging diagnostic** — when something's plugged in, a banner identifies the bottleneck:
  - *"Cable is limiting charging speed"* (cable rated below the charger)
  - *"Charging at 30W (charger can do up to 96W)"* (Mac is asking for less, e.g. battery near full)
  - *"Charging well at 96W"* (everything matches)
- **Cable e-marker info** — the cable's actual speed (USB 2.0, 5 / 10 / 20 / 40 / 80 Gbps), current rating (3 A / 5 A → up to 60W / 100W / 240W), and the chip's vendor
- **Charger PDO list** — every voltage profile the charger advertises (5V / 9V / 12V / 15V / 20V…) with the currently negotiated profile highlighted in real time
- **Connected device identity** — vendor name and product type, decoded from the PD Discover Identity response
- **Active transports** — USB 2 / USB 3 / Thunderbolt / DisplayPort
- **⌥-click the menu bar icon** to reveal the underlying IOKit properties for engineers

Right-click the menu bar icon for **Refresh**, a **Keep window open** toggle (handy for screenshots and demos), **About**, and **Quit**.

## Install

Download the latest `WhatCable.zip` from the [Releases page](https://github.com/darrylmorley/whatcable/releases/latest), unzip, and drag `WhatCable.app` to `/Applications`.

The app is universal (Apple silicon + Intel), signed with a Developer ID, and notarised by Apple — no Gatekeeper warnings.

Requires macOS 14 (Sonoma) or later.

## How it works

WhatCable reads three families of IOKit services. No entitlements, no private APIs, no helper daemons:

| Service | What it gives us |
| --- | --- |
| `AppleHPMInterfaceType10/11` | Per-port state: connection, transports, plug orientation, e-marker presence |
| `IOPortFeaturePowerSource` | Full PDO list from the connected source, with the live "winning" PDO |
| `IOPortTransportComponentCCUSBPDSOP` | PD Discover Identity VDOs for SOP (port partner) and SOP' (cable e-marker) |

Cable speed and power decoding follow the USB Power Delivery 3.x spec.

## Build from source

```bash
swift run WhatCable
```

Requires Swift 5.9 (Xcode 15+).

## Build a distributable .app

```bash
./scripts/build-app.sh
```

Produces a universal `dist/WhatCable.app` (arm64 + x86_64) and `dist/WhatCable.zip`.

**Modes:**

| Configuration | Result |
| --- | --- |
| No `.env` | Ad-hoc signed. Works locally; Gatekeeper warns on other Macs. |
| `.env` with `DEVELOPER_ID` | Developer ID signed + hardened runtime. |
| `.env` with `DEVELOPER_ID` + `NOTARY_PROFILE` | Full notarisation + stapled ticket. Gatekeeper-clean for everyone. |

**One-time setup for full notarisation:**

```bash
# 1. Find your signing identity
security find-identity -v -p codesigning

# 2. Store notarytool credentials in the keychain
xcrun notarytool store-credentials "WhatCable-notary" \
    --apple-id "you@example.com" \
    --team-id "ABCDE12345" \
    --password "<app-specific-password>"   # generate at appleid.apple.com

# 3. Create your .env from the template
cp .env.example .env
# ...and fill in DEVELOPER_ID
```

## Caveats

- **Cable e-marker info only appears for cables that carry one.** Most USB-C cables under 60 W are unmarked. Any Thunderbolt / USB4 cable, any 5 A / 100 W+ cable, and most quality data cables will be e-marked.
- **PD spec coverage:** the decoder targets PD 3.0 / 3.1. PD 3.2 EPR variants may need tweaks once we see real data.
- **Vendor name lookup is bundled but not exhaustive** — common cable, charger, hub, dock, and storage vendors are recognised; others fall back to the hex VID.
- **macOS only.** iOS sandboxing makes USB-C e-marker access much harder.
- **Not on the App Store.** App Sandbox blocks the IOKit reads we depend on.

## Contributing

Issues and PRs welcome. The code is small and tries to stay readable — start at [`Sources/CableTest/ContentView.swift`](Sources/CableTest/ContentView.swift) for the UI, [`PortSummary.swift`](Sources/CableTest/PortSummary.swift) for the plain-English logic, or [`PDVDO.swift`](Sources/CableTest/PDVDO.swift) for the bit-twiddling.

## Credits

Built by [Darryl Morley](https://github.com/darrylmorley).

Inspired by every time someone has asked "*is this cable any good?*".
