---
title: WhatCable doesn't just take the cable's word for it
slug: why-whatcable-checks-the-whole-chain
date: 2026-07-17
summary: "WhatCable compares available reports from the port, cable, charger, device and display link to help explain the connection you actually have."
category: Deep dives
coverImage: https://images.whatcable.uk/1784302843898-0x0-jpg.webp
coverAlt: A Thunderbolt cable connecting a MacBook to a dock
ctaTitle: Check the claim against the connection.
ctaText: WhatCable compares what the port, cable and device support with what the link actually negotiated.
ctaHref: /pro
ctaLabel: Explore Negotiation Diagnostics
tags:
  - usb-c
  - whatcable
  - mac
  - cables
  - diagnostics
updated: 2026-09-09
faqs:
  - q: "Does WhatCable just read the e-marker?"
    a: "No. It combines available cable identity with information about the Mac port, connected equipment and negotiated connection. Display diagnostics also examines available monitor and display-link information."
  - q: "Can WhatCable prove a cable is counterfeit?"
    a: "No. It can identify inconsistent reports and connection behaviour that warrants investigation, but software readings alone cannot authenticate a cable or inspect its physical construction."
  - q: "Why can a 40 Gbps cable show a 10 Gbps connection?"
    a: "The cable rating and the negotiated connection describe different things. A 10 Gbps device or another part of the path may set the limit. A lower negotiated rate alone does not show that the cable rating is wrong."
---

A cable is one part of a connection. The Mac port, charger, dock, drive or display also affects the result. WhatCable brings the available information together so that a slow connection does not automatically become a recommendation to buy a new cable.

## Start with two different kinds of information

An **e-marker** is the cable's digital label. It declares properties such as current rating, data capability and active/passive construction. A **negotiated connection** is the operating mode established by the connected equipment.

These readings answer different questions. A 40 Gbps cable connected to a 10 Gbps drive can reasonably produce a 10 Gbps connection. The drive's capability explains the result without contradicting the cable's rating.

WhatCable reads what macOS exposes. Availability varies by hardware, connection and system reporting; not every setup exposes every field.

## Follow the path through a dock

The cable from the Mac to a dock is not necessarily operating in the same mode as the cable from the dock to a drive. Multiple devices may also share the upstream connection.

WhatCable uses available hub and Thunderbolt topology to help distinguish those links. Its diagnostics compares reported capabilities and negotiated results to help identify the part that explains a limit.

[Pro's connection diagnostics](/pro#connection-diagnostics) exposes the per-party figures behind the explanation. That makes it easier to understand why changing a cable might help, or why it would leave the same device limit in place.

## Cross-check cable identity against the controller report

On supported Thunderbolt or USB4 connections, the Mac's controller can provide a negotiated link rate in addition to cable identity. WhatCable can compare those sources rather than relying on the label alone.

The reported link rate is evidence of the mode the connection established. It is not a sustained file-transfer benchmark, a physical inspection or a guarantee that the link will remain stable under every workload.

A lower rate does not by itself disprove a cable's higher rating. Nor is a higher rate automatically evidence that the cable's label was dishonest. [USB-IF describes newer 80 Gbps operation over existing 40 Gbps passive cables](https://www.usb.org/sites/default/files/2022-10/USB-IF%20USB%2080Gbps%20Announcement_FINAL_v2.pdf). The interpretation needs to account for the connection generation and cable type.

## Charging: distinguish rating, agreement and draw

The charger advertises power options. The cable constrains the permitted current and voltage. The Mac requests a supported operating point. Actual power use can then vary beneath that agreement.

A low reading may reflect the battery approaching full charge, an intentional charging pause, a light demand, or a limitation elsewhere in the setup. It is not always a cable fault.

WhatCable compares available charging information and system state to help explain these cases. [Pro's charging view](/pro#charging-agreement) gives the technical figures, while the [charging guide](/blog/why-is-my-macbook-charging-so-slow) walks through practical checks.

## Displays: check the picture and the path

WhatCable also examines available monitor and display-link reports. These can include the current resolution and refresh rate, monitor capabilities, DisplayPort lane count and rate, and whether the display path goes through Thunderbolt or an adapter.

**EDID** is the monitor's description of its capabilities. It is one source of information; WhatCable also uses available macOS mode information. **DSC**, or Display Stream Compression, can allow a demanding display mode to fit within less link bandwidth than an uncompressed calculation suggests.

A lower DisplayPort link rate alone does not establish a poor cable. The selected display mode, Mac capabilities, adapter and compression can all affect the interpretation. A Thunderbolt tunnel is useful context, but it is not a universal promise that every monitor mode will fit.

[Pro's display diagnostics](/pro#display-diagnostics) helps compare the reported picture and link instead of treating a single bandwidth figure as the answer.

## What a report can establish

Inconsistent identity fields or repeated connection drops can be reasons to investigate. They are not, on their own, proof of counterfeit hardware. A missing or unrecognised manufacturer identifier alone does not make a cable faulty.

Likewise, a successful connection is evidence about that setup. It does not inspect conductor thickness, certify safe operation at every claimed power level or authenticate the product. Physical construction and electrical performance require appropriate hardware inspection and testing.

The useful outcome is a supported explanation and a sensible next step: change the selected display mode, investigate a dock, compare another port, or try a suitable cable when the evidence points there.

For a visual explanation of what the cable contributes, [look inside the cable diagram](/inside-a-cable). To compare community identity reports, visit the [cable library](/cables).
