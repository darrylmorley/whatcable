# Known cables

A working list of USB-C cables that have been reported to WhatCable via the
in-app "Report this cable" flow. This is a memory aid for future trust-signal
and inventory work, seeded from the closed [`cable-report`](https://github.com/darrylmorley/whatcable/issues?q=label%3Acable-report)
issues on GitHub.

The full reports (with reporter notes, dates, and triage replies) live on the
issue tracker. This file holds a condensed, deduplicated view of the e-marker
fingerprints. Vendor names below come from the bundled USB-IF list (shipped
with WhatCable v0.8.1 onwards), not from whatever name the reporting build
showed at the time.

## Why this file exists

WhatCable's [issue template](../.github/ISSUE_TEMPLATE/cable-report.yml)
states the goal: a public database of known-good and counterfeit USB-C cable
fingerprints. The Cable Trust Signals work (see `planning/cable-trust-signals.md`)
will eventually consume a curated subset of this. For now it is a flat
hand-maintained markdown table; format may change once the consumer exists.

## Table

| Brand / model context | VID | PID | Vendor (USB-IF) | XID | Speed | Power | Type | Source |
|---|---|---|---|---|---|---|---|---|
| UGOURD TB5/USB4 cable, AliExpress (no USB-IF cert) | `0x0138` | `0x0310` | Unregistered | none | USB4 Gen 4 (80 Gbps) | 5 A / 50 V (250 W) | passive | [#71](https://github.com/darrylmorley/whatcable/issues/71) |
| Bundled in UGREEN Revodok Max 213 (U710) dock; housing marked TB4 | `0x0522` | `0x0A06` | ACON, Advanced-Connectek, Inc. | `0x939` | USB4 Gen 3 (20 / 40 Gbps) | 5 A / 20 V (100 W) | passive | [#84](https://github.com/darrylmorley/whatcable/issues/84) |
| Anker 333 USB-C 3.3 ft nylon | `0x201C` | `0x0000` | Hongkong Freeport Electronics Co., Limited | none | USB 2.0 (480 Mbps) | 5 A / 20 V (100 W) | passive | [#60](https://github.com/darrylmorley/whatcable/issues/60) |
| Monoprice Essentials USB-C 10 Gbps 0.5 m | `0x2095` | `0x004F` | CE LINK LIMITED | none | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | passive | [#48](https://github.com/darrylmorley/whatcable/issues/48) |
| delock TB3-branded cable | `0x20C2` | `0x0005` | Sumitomo Electric Ind., Ltd., Optical Comm. R&D Lab | none | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | passive | [#44](https://github.com/darrylmorley/whatcable/issues/44) |
| CalDigit TS4 dock bundled cable (likely) | `0x2B1D` | `0x1512` | Lintes Technology Co., Ltd. | none | USB4 Gen 3 (20 / 40 Gbps) | 5 A / 20 V (100 W) | passive | [#62](https://github.com/darrylmorley/whatcable/issues/62) |
| Dbilida TB4-branded 240 W cable, Amazon (no USB-IF cert) | `0x2E99` | `0x0000` | Hynetek Semiconductor Co., Ltd | none | USB4 Gen 3 (20 / 40 Gbps) | 5 A / 50 V (250 W) | passive | [#49](https://github.com/darrylmorley/whatcable/issues/49) |
| acasis cable bundled with TBU405M1 enclosure | `0x315C` | `0x0000` | Chengdu Convenientpower Semiconductor Co., LTD | none | USB4 Gen 3 (20 / 40 Gbps) | 5 A / 20 V (100 W) | passive | [#45](https://github.com/darrylmorley/whatcable/issues/45) |
| CUKTECH No.6 140 W (e-marker present but VID/PID/speed all zeroed) | `0x0000` | `0x0000` | (zeroed) | none | (none advertised) | (not advertised) | passive | [#61](https://github.com/darrylmorley/whatcable/issues/61) |

Sorted by VID. The zeroed-fingerprint entry is parked at the bottom because it
is identity-less.

## Patterns worth flagging for trust-signals work

Three of the nine reports show patterns that the planned Cable Trust Signals
heuristics should pick up:

1. **Marketing claim outpaces e-marker capability.** #49 (Dbilida) is sold as
   "Thunderbolt 4 / 40 Gbps / 240 W" but the e-marker reports passive USB4
   Gen 3 with no USB-IF cert. The cable may carry the advertised data rate,
   but there is no cert backing the claim.
2. **Genuinely unregistered VID with no XID.** #71 (UGOURD AliExpress) reports
   80 Gbps USB4 Gen 4 from an unregistered VID and zero XID. Plausibly real
   silicon, but unverifiable from the e-marker alone.
3. **Zeroed identity fields.** #61 (CUKTECH No.6) has a present e-marker that
   reports `0x0000` for VID, PID, and no speed. Already flagged by trust
   signals today; the report confirms the pattern is real and not a parser
   bug.

The other six reports describe cables whose e-marker matches their marketing.

## Adding new entries

When a new cable-report issue lands and you've triaged + closed it,
the workflow is:

```bash
swift scripts/sync-cable-reports.swift     # pulls rows from gh
swift scripts/render-known-cables.swift    # rebuilds docs/cables.html
```

The sync script reads every closed `cable-report` issue via `gh`, parses
the e-marker fingerprint table, looks up canonical USB-IF vendor names
from the bundled TSV, and rewrites the table block above. Existing rows'
"Brand / model context" cells are preserved by issue number; brand new
rows land with `(needs review)` as a placeholder.

After running the sync:

1. Look at any rows still showing `(needs review)`. Open the source issue,
   read the reporter's "What's the story" notes, and replace the
   placeholder with a one-line phrase covering brand and purchase context.
   Strip Amazon affiliate links, full product titles, and anything that
   reads as personal context.
2. If the report shows a trust-signal pattern (marketing / e-marker
   mismatch, unregistered VID + no cert, zeroed fields, impossible PDOs),
   add a bullet to the Patterns section above.
3. Re-run the renderer if you edited the markdown again.
4. Commit `data/known-cables.md` and `docs/cables.html` together.

If you need to fix a row by hand (say a vendor name TSV entry was wrong
upstream), edit `data/known-cables.md` directly. The sync script will
preserve your edits as long as they live in the "Brand / model context"
column. Other columns get rewritten on next sync, so structural changes
need to land in the script or the underlying issue body.

This file is not bundled into the app. It is a human reference. When the
trust-signals or inventory features need this data at runtime, we'll
formalise it then.
