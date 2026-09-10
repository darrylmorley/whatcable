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

| Brand / model context | VID | PID | Cable VDO | Vendor (USB-IF) | XID | Speed | Power | Type | Source |
|---|---|---|---|---|---|---|---|---|---|
| UGOURD TB5/USB4 cable, AliExpress (no USB-IF cert) | `0x0138` | `0x0310` | `0x000A2644` | Unregistered | none | USB4 Gen 4 (80 Gbps, Thunderbolt 5 class) | 5 A / 50 V (240 W) | passive | [#71](https://github.com/darrylmorley/whatcable/issues/71) |
| Unbranded TB4 cable, Shopee Taiwan | `0x0138` | `0x0000` | `0x0008204B` | Unregistered | `0x40D` | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 20 V (100 W) | passive | [#205](https://github.com/darrylmorley/whatcable/issues/205) |
| Unbranded cable, marked 20 Gbps (reads 10 Gbps) | `0x0138` | `0x0168` | `0x0008404A` | Unregistered | `0x40D` | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | passive | [#215](https://github.com/darrylmorley/whatcable/issues/215) |
| CalDigit Thunderbolt 5 cable (also bundled with TS5 Plus dock), Amazon / Apple Store | `0x01B6` | `0x4003` | `0x110A2644` | CalDigit, Inc. | `0x303C` | USB4 Gen 4 (80 Gbps, Thunderbolt 5 class) | 5 A / 50 V (240 W) | passive | [#89](https://github.com/darrylmorley/whatcable/issues/89), [#90](https://github.com/darrylmorley/whatcable/issues/90), [#211](https://github.com/darrylmorley/whatcable/issues/211), [#243](https://github.com/darrylmorley/whatcable/issues/243), [#254](https://github.com/darrylmorley/whatcable/issues/254) |
| CalDigit TB5 Pro Cable 0.5 m, Apple Store | `0x01B6` | `0x4002` | `0x110A2644` | CalDigit, Inc. | `0x303B` | USB4 Gen 4 (80 Gbps, Thunderbolt 5 class) | 5 A / 50 V (240 W) | passive | [#209](https://github.com/darrylmorley/whatcable/issues/209) |
| HP USB-C dock (built-in cable, ~2020 era) | `0x03F0` | `0x0967` | `0x00402FB2` | HP Inc. | none | USB 3.2 Gen 2 (10 Gbps) | 3 A / 50 V (144 W) | passive | [#112](https://github.com/darrylmorley/whatcable/issues/112) |
| Bundled in UGREEN Revodok Max 213 (U710) dock; housing marked TB4 | `0x0522` | `0x0A06` | `0x11082043` | ACON, Advanced-Connectek, Inc. | `0x939` | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 20 V (100 W) | passive | [#84](https://github.com/darrylmorley/whatcable/issues/84) |
| noda Thunderbolt 4 cable, ACON silicon, Intel-certified | `0x0522` | `0x0A18` | `0x110A2643` | ACON, Advanced-Connectek, Inc. | `0x944` | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 50 V (240 W) | passive | [#265](https://github.com/darrylmorley/whatcable/issues/265) |
| Apple Thunderbolt 5 cable 1 m (model A3189) | `0x05AC` | `0x720A` | `0x110A2644` | Apple | none | USB4 Gen 4 (80 Gbps, Thunderbolt 5 class) | 5 A / 50 V (240 W) | passive | [#93](https://github.com/darrylmorley/whatcable/issues/93), [#131](https://github.com/darrylmorley/whatcable/issues/131) |
| Apple USB-C EarPods (e-marker on built-in plug, audio accessory) | `0x05AC` | `0x110B` | `0x11000000` | Apple | none | USB 2.0 (480 Mbps) | USB default at up to 20V (~60W) | passive | [#173](https://github.com/darrylmorley/whatcable/issues/173) |
| Apple USB-C to 3.5 mm headphone jack adapter (e-marker on built-in plug) | `0x05AC` | `0x110A` | `0x11000000` | Apple | none | USB 2.0 (480 Mbps) | USB default at up to 20V (~60W) | passive | [#175](https://github.com/darrylmorley/whatcable/issues/175) |
| Apple Thunderbolt 3 (USB-C) to Thunderbolt 2 Adapter | `0x05AC` | `0x1657` | `0x200C2032` | Apple | none | USB 3.2 Gen 2 (10 Gbps) | 3 A / 20 V (60 W) | passive | [#216](https://github.com/darrylmorley/whatcable/issues/216) |
| LG 27UP85NP-W monitor bundled USB-C cable (unbranded) | `0x163E` | `0x0CE9` | `0x00084841` | Huizhou Bohui Connection Technology Co., Ltd | `0x99` | USB 3.2 Gen 1 (5 Gbps) | 5 A / 20 V (100 W) | passive | [#165](https://github.com/darrylmorley/whatcable/issues/165) |
| Anker 333 USB-C 3.3 ft nylon | `0x201C` | `0x0000` | `0x00082040` | Hongkong Freeport Electronics Co., Limited | none | USB 2.0 (480 Mbps) | 5 A / 20 V (100 W) | passive | [#60](https://github.com/darrylmorley/whatcable/issues/60) |
| LG monitor bundled cable (27UP850N-W and others; also seen labelled Dell) | `0x201C` | `0x0001` | `0x00084841` | Hongkong Freeport Electronics Co., Limited | `0xBBB` | USB 3.2 Gen 1 (5 Gbps) | 5 A / 20 V (100 W) | passive | [#192](https://github.com/darrylmorley/whatcable/issues/192), [#197](https://github.com/darrylmorley/whatcable/issues/197) |
| Anker Nylon USB-C 100W 3m, Hongkong Freeport silicon | `0x201C` | `0x0000` | `0x00086040` | Hongkong Freeport Electronics Co., Limited | none | USB 2.0 (480 Mbps) | 5 A / 20 V (100 W) | passive | [#261](https://github.com/darrylmorley/whatcable/issues/261) |
| Eizo EV2740X monitor bundled cable (KVM connection) | `0x208E` | `0xC026` | `0x00084041` | Luxshare-ICT | none | USB 3.2 Gen 1 (5 Gbps) | 5 A / 20 V (100 W) | passive | [#137](https://github.com/darrylmorley/whatcable/issues/137) |
| Monoprice Essentials USB-C 10 Gbps 0.5 m | `0x2095` | `0x004F` |  | CE LINK LIMITED | none | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | passive | [#48](https://github.com/darrylmorley/whatcable/issues/48) |
| Amazon Basics USB-C TB4 cable 1 m (240 W), USB-IF certified | `0x2095` | `0x03CF` | `0x110A2E43` | CE LINK LIMITED | `0x34F2` | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 50 V (240 W) | passive | [#231](https://github.com/darrylmorley/whatcable/issues/231) |
| delock TB3-branded cable | `0x20C2` | `0x0005` |  | Sumitomo Electric Ind., Ltd., Optical Comm. R&D Lab | none | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | passive | [#44](https://github.com/darrylmorley/whatcable/issues/44) |
| OWC Thunderbolt 3 cable, bundled with Mercury Elite Pro Dock | `0x20C2` | `0x0007` | `0x31082052` | Sumitomo Electric Ind., Ltd., Optical Comm. R&D Lab | none | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | passive | [#143](https://github.com/darrylmorley/whatcable/issues/143) |
| SanDisk Extreme SSD bundled cable | `0x2109` | `0x0000` | `0x00082022` | VIA Labs, Inc. | none | USB 3.2 Gen 2 (10 Gbps) | 3 A / 20 V (60 W) | passive | [#202](https://github.com/darrylmorley/whatcable/issues/202) |
| Generic USB-C cable used with Dell P2422HE monitor (unbranded) | `0x228A` | `0x0000` | `0x00084041` | Hotron Precision Electronic Ind. Corp. | `0x294` | USB 3.2 Gen 1 (5 Gbps) | 5 A / 20 V (100 W) | passive | [#177](https://github.com/darrylmorley/whatcable/issues/177) |
| Monitor bundled cable (Hotron ODM) | `0x228A` | `0x0000` | `0x00082042` | Hotron Precision Electronic Ind. Corp. | `0x293` | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | passive | [#207](https://github.com/darrylmorley/whatcable/issues/207) |
| OnePlus SuperVOOC 10A cable (Type-C to Type-C) | `0x22D9` | `0x1428` | `0x60082A40` | GuangDong OPPO Mobile Telecommunications Corp., Ltd. | none | USB 2.0 (480 Mbps) | 5 A / 30 V (150 W) | passive | [#148](https://github.com/darrylmorley/whatcable/issues/148) |
| Anker Nano 240 W USB-C cable 1.8 m | `0x291A` | `0x82E2` | `0x000A4E40` | Anker Innovations Limited | none | USB 2.0 (480 Mbps) | 5 A / 50 V (240 W) | passive | [#233](https://github.com/darrylmorley/whatcable/issues/233) |
| CUKTECH CTC615N 6A 240 W 1.5 m, USB-IF certified | `0x2B01` | `0x4051` | `0x000A4640` | Zimi Corporation | `0x9DC` | USB 2.0 (480 Mbps) | 5 A / 50 V (240 W) | passive | [#138](https://github.com/darrylmorley/whatcable/issues/138) |
| CalDigit TS4 dock bundled cable (Lintes silicon) | `0x2B1D` | `0x1512` | `0x11082043` | Lintes Technology Co., Ltd. | none | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 20 V (100 W) | passive | [#62](https://github.com/darrylmorley/whatcable/issues/62) |
| Cable Matters Thunderbolt 5 cable 1 m | `0x2B1D` | `0x1533` | `0x110A2644` | Lintes Technology Co., Ltd. | `0x5F5` | USB4 Gen 4 (80 Gbps, Thunderbolt 5 class) | 5 A / 50 V (240 W) | passive | [#110](https://github.com/darrylmorley/whatcable/issues/110) |
| CalDigit 2 m TB4 active cable | `0x2B1D` | `0x1901` | `0x3208485A` | Lintes Technology Co., Ltd. | none | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | active | [#111](https://github.com/darrylmorley/whatcable/issues/111) |
| AGFINEST / ULT-unite TB5-class USB4 80 Gbps cable, 3.94 ft (no USB-IF cert) | `0x2BD3` | `0x0000` | `0x000A4644` | Dongguan ULT-unite Electronic Technology Co., LTD | none | USB4 Gen 4 (80 Gbps, Thunderbolt 5 class) | 5 A / 50 V (240 W) | passive | [#151](https://github.com/darrylmorley/whatcable/issues/151) |
| Baseus Pudding Series 100 W 1.2 m | `0x2E87` | `0x0000` | `0x00082040` | Shenzhen Injoinic Technology Co., Ltd. | none | USB 2.0 (480 Mbps) | 5 A / 20 V (100 W) | passive | [#167](https://github.com/darrylmorley/whatcable/issues/167) |
| CUKTECH PB200N powerbank built-in cable | `0x2E87` | `0x0000` | `0x00082040` | Shenzhen Injoinic Technology Co., Ltd. | none | USB 2.0 (480 Mbps) | 5 A / 20 V (100 W) | passive | [#168](https://github.com/darrylmorley/whatcable/issues/168) |
| Dbilida TB4-branded 240 W cable, Amazon (no USB-IF cert) | `0x2E99` | `0x0000` |  | Hynetek Semiconductor Co., Ltd | none | USB4 Gen 3 (20 / 40 Gbps) | 5 A / 50 V (240 W) | passive | [#49](https://github.com/darrylmorley/whatcable/issues/49) |
| Anker PowerLine III Flow 100 W 1.8 m, Amazon | `0x2E99` | `0x0000` | `0x00084040` | Hynetek Semiconductor Co., Ltd | `0x1514` | USB 2.0 (480 Mbps) | 5 A / 20 V (100 W) | passive | [#152](https://github.com/darrylmorley/whatcable/issues/152) |
| Satechi Thunderbolt 5 cable 1 m | `0x310E` | `0x4000` | `0x110A2644` | Sariana LLC (dba SATECHI) | `0x5F5` | USB4 Gen 4 (80 Gbps, Thunderbolt 5 class) | 5 A / 50 V (240 W) | passive | [#109](https://github.com/darrylmorley/whatcable/issues/109) |
| acasis cable bundled with TBU405M1 enclosure | `0x315C` | `0x0000` |  | Chengdu Convenientpower Semiconductor Co., LTD | none | USB4 Gen 3 (20 / 40 Gbps) | 5 A / 20 V (100 W) | passive | [#45](https://github.com/darrylmorley/whatcable/issues/45) |
| PX 1 m USB4 40 Gbps cable (local brand, likely ODM) | `0x315C` | `0x0000` | `0x000A2643` | Chengdu Convenientpower Semiconductor Co., LTD | none | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 50 V (240 W) | passive | [#144](https://github.com/darrylmorley/whatcable/issues/144) |
| Generic AliExpress TB4-branded cable (Chengdu Convenientpower silicon, no USB-IF cert) | `0x315C` | `0x0000` | `0x000A4843` | Chengdu Convenientpower Semiconductor Co., LTD | none | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 20 V (100 W) | passive | [#169](https://github.com/darrylmorley/whatcable/issues/169) |
| Sabrent NTP10G TB 10GbE adapter captive cable (claims EPR, 20 V max VBUS) | `0x315C` | `0x0000` | `0x000A2843` | Chengdu Convenientpower Semiconductor Co., LTD | none | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 20 V (100 W) | passive | [#234](https://github.com/darrylmorley/whatcable/issues/234) |
| Cable Matters USB4 40 Gbps 240 W 2 m, Amazon DE | `0x32EB` | `0x0000` | `0x000A4643` | GuangDong Quanjie Technology Co., Ltd. | none | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 50 V (240 W) | passive | [#244](https://github.com/darrylmorley/whatcable/issues/244) |
| Orico USB4 Gen 3 / Thunderbolt 4 class cable, USB-IF certified | `0x34BD` | `0x0000` | `0x45082043` | Shenzhen Orico Technologies Co., Ltd | `0x10536` | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 20 V (100 W) | passive | [#162](https://github.com/darrylmorley/whatcable/issues/162) |
| Silkland USB4 80 Gbps cable 3.3 ft, Amazon | `0x3678` | `0x0000` | `0x000A2644` | (Silkland) Shenzhen Guanhai Technology Co., Ltd. | none | USB4 Gen 4 (80 Gbps, Thunderbolt 5 class) | 5 A / 50 V (240 W) | passive | [#98](https://github.com/darrylmorley/whatcable/issues/98) |
| CANDYSIGN MagTie 100W USB-C cable | `0x36E9` | `0x3000` | `0x140A4040` | ifanr Inc. | `0x15141` | USB 2.0 (480 Mbps) | 5 A / 20 V (100 W) | passive | [#113](https://github.com/darrylmorley/whatcable/issues/113) |
| Possibly Logitech BRIO webcam cable (reporter unsure) | `0x6666` | `0x0000` | `0x00084042` | Unregistered | `0x52C` | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | passive | [#99](https://github.com/darrylmorley/whatcable/issues/99) |
| Kramer C-U32/MFF-10, 10 ft AV cable | `0x7857` | `0x1005` | `0x00086842` | Unregistered | none | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | passive | [#259](https://github.com/darrylmorley/whatcable/issues/259) |
| Kramer C-U32/MFF-6, 6 ft AV cable | `0x7857` | `0x1004` | `0x00084842` | Unregistered | none | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | passive | [#260](https://github.com/darrylmorley/whatcable/issues/260) |
| CUKTECH No.6 140 W (e-marker present but VID/PID/speed all zeroed) | `0x0000` | `0x0000` |  | (zeroed) | none | (none advertised) | (not advertised) | passive | [#61](https://github.com/darrylmorley/whatcable/issues/61) |
| vorodcip generic USB-C cable, Amazon Japan (VID/PID zeroed) | `0x0000` | `0x0000` | `0x000A6642` | (zeroed) | none | USB 3.2 Gen 2 (10 Gbps) | 5 A / 50 V (240 W) | passive | [#91](https://github.com/darrylmorley/whatcable/issues/91) |
| Dockcase 100 W 10 Gbps 0.5 m (VID/PID zeroed) | `0x0000` | `0x0000` | `0x00082042` | (zeroed) | none | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | passive | [#92](https://github.com/darrylmorley/whatcable/issues/92) |
| Aulumu M07 (VID/PID zeroed) | `0x0000` | `0x0000` | `0x000A4642` | (zeroed) | none | USB 3.2 Gen 2 (10 Gbps) | 5 A / 50 V (240 W) | passive | [#108](https://github.com/darrylmorley/whatcable/issues/108) |
| Lindy Anthra Line USB 3.2 Gen 2x2 1 m (Part No. 36901), Amazon Italy | `0x0000` | `0x0000` | `0x00082052` | (zeroed) | none | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | passive | [#116](https://github.com/darrylmorley/whatcable/issues/116) |
| UGreen Revodok 9-in-1 USB-C hub cable, Amazon France | `0x0000` | `0x0000` | `0x00084841` | (zeroed) | none | USB 3.2 Gen 1 (5 Gbps) | 5 A / 20 V (100 W) | passive | [#126](https://github.com/darrylmorley/whatcable/issues/126) |
| Vorodcip generic USB-C cable, Amazon Italy (VID/PID zeroed) | `0x0000` | `0x0000` | `0x000A6642` | (zeroed) | none | USB 3.2 Gen 2 (10 Gbps) | 5 A / 50 V (240 W) | passive | [#132](https://github.com/darrylmorley/whatcable/issues/132) |
| INIU 100W USB-C cable (VID/PID zeroed) | `0x0000` | `0x0000` | `0x00082042` | (zeroed) | none | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | passive | [#134](https://github.com/darrylmorley/whatcable/issues/134) |
| Anker braided cable, bundled with 140W adapter | `0x0000` | `0x0000` |  | (zeroed) | none | (none advertised) | (not advertised) | passive | [#136](https://github.com/darrylmorley/whatcable/issues/136) |
| OnePlus 8T original USB-C cable (e-marker present, no PD Discover Identity response) | `0x0000` | `0x0000` |  | (zeroed) | none | (none advertised) | (not advertised) | passive | [#156](https://github.com/darrylmorley/whatcable/issues/156) |
| SUNGUY 30 cm USB-C cable, Amazon Italy (rated 60 W) | `0x0000` | `0x0000` |  | (zeroed) | none | (none advertised) | (not advertised) | passive | [#158](https://github.com/darrylmorley/whatcable/issues/158) |
| Anker Zolo 240 W 3 ft (A8060) (VID/PID zeroed; Cable VDO encodes 250 W EPR) | `0x0000` | `0x0000` | `0x000A2640` | (zeroed) | none | USB 2.0 (480 Mbps) | 5 A / 50 V (240 W) | passive | [#166](https://github.com/darrylmorley/whatcable/issues/166) |
| Anker USB-C cable, model not provided (e-marker present, no PD Discover Identity response) | `0x0000` | `0x0000` |  | (zeroed) | none | (none advertised) | (not advertised) | passive | [#170](https://github.com/darrylmorley/whatcable/issues/170) |
| MediaStorm (YingShi JuFeng) TB5 cable, Taobao | `0x0000` | `0x0001` | `0x000A4644` | (zeroed) | none | USB4 Gen 4 (80 Gbps, Thunderbolt 5 class) | 5 A / 50 V (240 W) | passive | [#193](https://github.com/darrylmorley/whatcable/issues/193) |
| UGREEN 240W USB-C cable, Amazon | `0x0000` | `0x0000` | `0x000A2642` | (zeroed) | none | USB 3.2 Gen 2 (10 Gbps) | 5 A / 50 V (240 W) | passive | [#201](https://github.com/darrylmorley/whatcable/issues/201) |
| Anker 643 USB-C 6 ft silicone (A8553), Amazon | `0x0000` | `0x0000` | `0x00084040` | (zeroed) | none | USB 2.0 (480 Mbps) | 5 A / 20 V (100 W) | passive | [#203](https://github.com/darrylmorley/whatcable/issues/203) |
| SmallRig USB-C cable, Amazon | `0x0000` | `0x0000` | `0x00082042` | (zeroed) | none | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | passive | [#208](https://github.com/darrylmorley/whatcable/issues/208) |
| Mcdodo Digital Pro 100W PD cable with display | `0x0000` | `0x0000` | `0x00082042` | (zeroed) | none | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | passive | [#210](https://github.com/darrylmorley/whatcable/issues/210) |
| Vention USB-C cable | `0x0000` | `0x0000` | `0x00082042` | (zeroed) | none | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | passive | [#214](https://github.com/darrylmorley/whatcable/issues/214) |
| Maxonar TH33 TB4 cable, Amazon | `0x0000` | `0x0000` | `0x000A4643` | (zeroed) | none | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 50 V (240 W) | passive | [#219](https://github.com/darrylmorley/whatcable/issues/219) |
| Anker 10 ft USB-C 100 W (2-pack), Amazon | `0x0000` | `0x0000` | `0x00086840` | (zeroed) | none | USB 2.0 (480 Mbps) | 5 A / 20 V (100 W) | passive | [#220](https://github.com/darrylmorley/whatcable/issues/220) |
| iottie IOTACC610 100 W cable | `0x0000` | `0x0000` | `0x00084040` | (zeroed) | none | USB 2.0 (480 Mbps) | 5 A / 20 V (100 W) | passive | [#223](https://github.com/darrylmorley/whatcable/issues/223) |
| Statik PUP-0550 magnetic 100 W cable | `0x0000` | `0x0000` | `0x00084040` | (zeroed) | none | USB 2.0 (480 Mbps) | 5 A / 20 V (100 W) | passive | [#224](https://github.com/darrylmorley/whatcable/issues/224) |
| Anker A8756 3.3 ft USB-C cable | `0x0000` | `0x0000` | `0x00082840` | (zeroed) | none | USB 2.0 (480 Mbps) | 5 A / 20 V (100 W) | passive | [#230](https://github.com/darrylmorley/whatcable/issues/230) |
| Hoco HB28 USB hub (built-in e-marker; data link ran at USB 2.0) | `0x0000` | `0x0000` | `0x00084841` | (zeroed) | none | USB 3.2 Gen 1 (5 Gbps) | 5 A at up to 20V (~100W) | passive | [#232](https://github.com/darrylmorley/whatcable/issues/232) |
| Statik MagStack Pro 2.0 | `0x0000` | `0x0000` | `0x00084040` | (zeroed) | none | USB 2.0 (480 Mbps) | 5 A / 20 V (100 W) | passive | [#240](https://github.com/darrylmorley/whatcable/issues/240) |
| Anker Zolo USB-C to USB-C cable, Amazon | `0x0000` | `0x0000` |  | (zeroed) | none | (none advertised) | (not advertised) | passive | [#250](https://github.com/darrylmorley/whatcable/issues/250) |
| Native Union Belt Duo Pro 240W, Apple Store Sweden | `0x0000` | `0x0000` |  | (zeroed) | none | (none advertised) | (not advertised) | passive | [#252](https://github.com/darrylmorley/whatcable/issues/252) |
| Apple USB-C cable from iPad A16 box | `0x0000` | `0x0000` |  | (zeroed) | none | (none advertised) | (not advertised) | passive | [#263](https://github.com/darrylmorley/whatcable/issues/263) |
| j5create USB4 40 Gbps coaxial cable, braided, OfficeDepot | `0x2DE5` | `0x2601` | `0x12084043` | KaiJet Technology International Limited, Inc. dba j5create | none | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 20 V (100 W) | passive | [#258](https://github.com/darrylmorley/whatcable/issues/258) |
| Satechi USB4 Pro cable 1.2 m | `0x310E` | `0x03B7` | `0x110A4E43` | Sariana LLC (dba SATECHI) | `0x384E` | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 50 V (240 W) | passive | [#267](https://github.com/darrylmorley/whatcable/issues/267) |
| Plugable TB3 dock bundled cable | `0x20C2` | `0x0009` | `0x41082052` | Sumitomo Electric Ind., Ltd., Optical Comm. R&D Lab | none | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | passive | [#276](https://github.com/darrylmorley/whatcable/issues/276) |
| Acasis TB501Pro enclosure bundled cable | `0x315C` | `0x0000` | `0x00022643` | Chengdu Convenientpower Semiconductor Co., LTD | none | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 50 V (240 W) | passive | [#307](https://github.com/darrylmorley/whatcable/issues/307) |
| UGreen retractable 100W (L531), zeroed e-marker | `0x0000` | `0x0000` | `0x00082040` | (zeroed) | none | USB 2.0 (480 Mbps) | 5 A / 20 V (100 W) | passive | [#302](https://github.com/darrylmorley/whatcable/issues/302) |
| Unbranded TB5-class 80 Gbps, zeroed e-marker | `0x0000` | `0x0000` | `0x000A4644` | (zeroed) | none | USB4 Gen 4 (80 Gbps, Thunderbolt 5 class) | 5 A / 50 V (240 W) | passive | [#309](https://github.com/darrylmorley/whatcable/issues/309) |
| CalDigit Thunderbolt 4 Pro Braided Cable (1 m) | `0x01B6` | `0x4001` | `0x110A2643` | CalDigit, Inc. | `0x302F` | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 50 V (240 W) | passive | [#329](https://github.com/darrylmorley/whatcable/issues/329) |
| Apple Thunderbolt 3 cable (1 m) | `0x05AC` | `0x1782` | `0x11082052` | Apple | `0x2600` | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | passive | [#332](https://github.com/darrylmorley/whatcable/issues/332) |
| Apple Thunderbolt 4 Pro Cable (1.8 m) | `0x05AC` | `0x7205` | `0x4368F8DB` | Apple | none | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 20 V (100 W) | active | [#333](https://github.com/darrylmorley/whatcable/issues/333) |
| LG 27MD5KL bundled Thunderbolt 3 cable (Sumitomo silicon) | `0x20C2` | `0x0004` | `0x21085858` | Sumitomo Electric Ind., Ltd., Optical Comm. R&D Lab | none | USB 2.0 (480 Mbps) | 5 A / 20 V (100 W) | active | [#331](https://github.com/darrylmorley/whatcable/issues/331) |
| LOGIIX Piston Connect USB-C cable (240W / 40 Gbps) | `0x315C` | `0x0000` | `0x000A2E43` | Chengdu Convenientpower Semiconductor Co., LTD | none | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 50 V (240 W) | passive | [#328](https://github.com/darrylmorley/whatcable/issues/328) |
| UGREEN 140 W charger bundled cable (VID/PID zeroed) | `0x0000` | `0x0000` | `0x000A4640` | (zeroed) | none | USB 2.0 (480 Mbps) | 5 A / 50 V (240 W) | passive | [#327](https://github.com/darrylmorley/whatcable/issues/327) |
| Apple Thunderbolt 4 Pro Cable (1.8 m) | `0x05AC` | `0x7208` | `0x12082042` | Apple | `0x2600` | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | passive | [#342](https://github.com/darrylmorley/whatcable/issues/342) |
| WD My Passport SSD bundled cable (Joinsoon) | `0x060F` | `0x0000` | `0x00082022` | Joinsoon Electronics Mfg. Co., Ltd. | none | USB 3.2 Gen 2 (10 Gbps) | 3 A / 20 V (60 W) | passive | [#345](https://github.com/darrylmorley/whatcable/issues/345) |
| Cable Matters Thunderbolt 5 80 Gbps / 240 W cable (VID/PID zeroed) | `0x0000` | `0x0000` | `0x000A2644` | (zeroed) | none | USB4 Gen 4 (80 Gbps, Thunderbolt 5 class) | 5 A / 50 V (240 W) | passive | [#343](https://github.com/darrylmorley/whatcable/issues/343) |
| RØDE Wireless Pro SuperSpeed cable (bundled with mic kit) | `0x19F7` | `0x8001` | `0x00082021` | RØDE | `0x3290` | USB 3.2 Gen 1 (5 Gbps) | 3 A / 20 V (60 W) | passive | [#361](https://github.com/darrylmorley/whatcable/issues/361) |
| PAXO USB 3.2 Gen 2 cable, Amazon DE | `0x7880` | `0x0000` | `0x00082042` | Unregistered | `0xB1BD` | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | passive | [#360](https://github.com/darrylmorley/whatcable/issues/360) |
| UGREEN L705 USB4 / TB4-class cable, Amazon (VID/PID zeroed) | `0x0000` | `0x0000` | `0x000A2643` | (zeroed) | none | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 50 V (240 W) | passive | [#359](https://github.com/darrylmorley/whatcable/issues/359) |
| OWC Thunderbolt 4 cable, Amazon (Lintes silicon) | `0x2B1D` | `0x150F` | `0x110A2643` | Lintes Technology Co., Ltd. | none | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 50 V (240 W) | passive | [#382](https://github.com/darrylmorley/whatcable/issues/382) |
| Cable Matters USB4 80 Gbps cable 4.9 ft, Amazon (USB-IF certified) | `0x2BD5` | `0x7A49` | `0x000A4644` | Cable Matters Inc. | `0x1E94` | USB4 Gen 4 (80 Gbps, Thunderbolt 5 class) | 5 A / 50 V (240 W) | passive | [#378](https://github.com/darrylmorley/whatcable/issues/378) |
| iVANKY Thunderbolt 5 cable, bundled with iVANKY dock | `0x0000` | `0x1201` | `0x110A2644` | (zeroed) | none | USB4 Gen 4 (80 Gbps, Thunderbolt 5 class) | 5 A / 50 V (240 W) | passive | [#381](https://github.com/darrylmorley/whatcable/issues/381) |
| No-brand USB4 40 Gbps L-shaped cable, Taobao/AliExpress | `0x0138` | `0x0000` | `0x000A4843` | Unregistered | `0x40D` | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 20 V (100 W) | passive | [#395](https://github.com/darrylmorley/whatcable/issues/395) |
| Elecom Thunderbolt 5 / USB4 80 Gbps cable, Osaka pop-up shop | `0x0214` | `0x4011` | `0x110A2644` | Unregistered | `0x303E` | USB4 Gen 4 (80 Gbps, Thunderbolt 5 class) | 5 A / 50 V (240 W) | passive | [#396](https://github.com/darrylmorley/whatcable/issues/396) |
| Apple USB-C Charging Cable (bundled with the 61 W A1718 adapter onwards, incl. M1 MacBook Air) | `0x05AC` | `0x1781` | `0xA1084050` | Apple | `0xA26` | USB 2.0 (480 Mbps) | 5 A / 20 V (100 W) | passive | [#397](https://github.com/darrylmorley/whatcable/issues/397), [#488](https://github.com/darrylmorley/whatcable/issues/488) |
| OWC Thunderbolt 4 cable, 28 in, Amazon | `0x2B1D` | `0x152A` | `0x110A2643` | Lintes Technology Co., Ltd. | none | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 50 V (240 W) | passive | [#388](https://github.com/darrylmorley/whatcable/issues/388) |
| (needs review) | `0x05AC` | `0x7209` | `0x4368F8DB` | Apple | none | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 20 V (100 W) | active | Test-kit corpus (11 machines), no GitHub issue filed. Unconfirmed guess: possibly the Studio Display captive cable, seen alongside a Studio Display on 3 of 8 machines at the time it was added |
| CalDigit TS4 dock bundled cable (Sumitomo silicon) | `0x20C2` | `0x080F` | `0x45082043` | Sumitomo Electric Ind., Ltd., Optical Comm. R&D Lab | none | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 20 V (100 W) | passive | [#410](https://github.com/darrylmorley/whatcable/issues/410) |
| Sumitomo OEM Thunderbolt 4 cable, dock bundled (40 Gbps variant of PID 0x0714) | `0x20C2` | `0x0714` | `0x460A2643` | Sumitomo Electric Ind., Ltd., Optical Comm. R&D Lab | none | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 50 V (240 W) | passive | Test-kit corpus, no GitHub issue filed |
| Apple Thunderbolt 4 Pro Cable (3 m) | `0x05AC` | `0x7203` | `0x4368F8DB` | Apple | none | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 20 V (100 W) | active | Test-kit corpus (7 machines), identified by @cannotcollide in [discussion #478](https://github.com/darrylmorley/whatcable/discussions/478) |
| Chant Sincere OEM monitor cable, Lenovo and Dell (5 A variant of PID 0xC8F1) | `0x0C62` | `0xC8F1` | `0x00082042` | Chant Sincere Co., Ltd | none | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | passive | Test-kit corpus, no GitHub issue filed |
| Lenovo ThinkVision P34w-20 bundled cable (Foxconn silicon) | `0x0489` | `0xF681` | `0x11084041` | Foxconn / Hon Hai | `0x1C1` | USB 3.2 Gen 1 (5 Gbps) | 5 A / 20 V (100 W) | passive | [#403](https://github.com/darrylmorley/whatcable/issues/403) |
| iVanky USB-C monitor cable (ACON silicon) | `0x0522` | `0x0002` | `0x11082052` | ACON, Advanced-Connectek, Inc. | `0x92C` | USB 3.2 Gen 2 (10 Gbps) | 5 A / 20 V (100 W) | passive | [#409](https://github.com/darrylmorley/whatcable/issues/409) |
| Lenovo ThinkVision P34w-20 bundled cable (Chant Sincere silicon, 3 A variant) | `0x0C62` | `0xC8F1` | `0x00082022` | Chant Sincere Co., Ltd | `0x573` | USB 3.2 Gen 2 (10 Gbps) | 3 A / 20 V (60 W) | passive | [#402](https://github.com/darrylmorley/whatcable/issues/402) |
| Wokyis M5 dock bundled Thunderbolt 5 cable, 0.5 m (Sumitomo silicon, 80 Gbps variant of PID 0x0714) | `0x20C2` | `0x0714` | `0x460A2644` | Sumitomo Electric Ind., Ltd., Optical Comm. R&D Lab | none | USB4 Gen 4 (80 Gbps, Thunderbolt 5 class) | 5 A / 50 V (240 W) | passive | [#405](https://github.com/darrylmorley/whatcable/issues/405) |
| Cable Matters active Thunderbolt 5 cable, 2 m | `0x2B1D` | `0x192F` | `0x426A5E5C` | Lintes Technology Co., Ltd. | none | USB4 Gen 4 (80 Gbps, Thunderbolt 5 class) | 5 A / 50 V (240 W) | active | [#406](https://github.com/darrylmorley/whatcable/issues/406) |
| OWC Thunderbolt 5 cable, 12 in (Lintes silicon) | `0x2B1D` | `0x153E` | `0x110A2644` | Lintes Technology Co., Ltd. | `0x5FD` | USB4 Gen 4 (80 Gbps, Thunderbolt 5 class) | 5 A / 50 V (240 W) | passive | [#408](https://github.com/darrylmorley/whatcable/issues/408) |
| Silkland cable sold as USB4, e-marker reports 10 Gbps 240W | `0x3678` | `0x0000` | `0x00084652` | (Silkland) Shenzhen Guanhai Technology Co., Ltd. | `0x281E` | USB 3.2 Gen 2 (10 Gbps) | 5 A / 50 V (240 W) | passive | [#431](https://github.com/darrylmorley/whatcable/issues/431) |
| CalDigit Thunderbolt 4 (USB-C) Pro Cable 0.5 m, Apple Store | `0x01B6` | `0x4002` | `0x110A2643` | Unregistered | `0x3030` | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 50 V (240 W) | passive | [#414](https://github.com/darrylmorley/whatcable/issues/414) |
| Anker Prime Thunderbolt 5 cable, bundled with Anker Prime TB5 Dock, Amazon | `0x0522` | `0x0A33` | `0x110A2644` | ACON, Advanced-Connectek, Inc. | `0x943` | USB4 Gen 4 (80 Gbps, Thunderbolt 5 class) | 5 A / 50 V (240 W) | passive | [#418](https://github.com/darrylmorley/whatcable/issues/418) |
| UGREEN Thunderbolt 5 cable 80Gbps 240W, Amazon | `0x0522` | `0x0A33` | `0x110A2644` | ACON, Advanced-Connectek, Inc. | `0x943` | USB4 Gen 4 (80 Gbps, Thunderbolt 5 class) | 5 A / 50 V (240 W) | passive | [#505](https://github.com/darrylmorley/whatcable/issues/505) |
| UGREEN TB5/USB4 cable (model 65383), Amazon UK | `0x1AAE` | `0x0000` | `0x000A2644` | Johnson Component & Equipments Co., Ltd. | `0x265E` | USB4 Gen 4 (80 Gbps, Thunderbolt 5 class) | 5 A / 50 V (240 W) | passive | [#435](https://github.com/darrylmorley/whatcable/issues/435) |
| StarTech TBLT3MM2M Thunderbolt 3 cable 2 m (20 Gbps, 100 W) | `0x20C2` | `0x0008` | `0x31084051` | Sumitomo Electric Ind., Ltd., Optical Comm. R&D Lab | none | USB 3.2 Gen 1 (5 Gbps) | 5 A / 20 V (100 W) | passive | [#422](https://github.com/darrylmorley/whatcable/issues/422) |
| FDBRO USB4 cable 40 Gbps 240 W, AliExpress (USB-IF certified) | `0x315C` | `0x0002` | `0x110A4643` | Chengdu Convenientpower Semiconductor Co., LTD | `0x1094` | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 50 V (240 W) | passive | [#420](https://github.com/darrylmorley/whatcable/issues/420) |
| ADT-Link UT3G USB4 eGPU bundled cable | `0x03F0` | `0x9488` | `0x11082043` | HP Inc. | none | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 20 V (100 W) | passive | [#446](https://github.com/darrylmorley/whatcable/issues/446) |
| OWC Thunderbolt 4 passive cable 0.72 m, Amazon (ACON silicon) | `0x0522` | `0x0B70` | `0x11082043` | ACON, Advanced-Connectek, Inc. | `0x938` | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 20 V (100 W) | passive | [#449](https://github.com/darrylmorley/whatcable/issues/449) |
| OWC Thunderbolt dock bundled cable, MacSales (Sumitomo silicon) | `0x20C2` | `0x080D` | `0x45082043` | Sumitomo Electric Ind., Ltd., Optical Comm. R&D Lab | none | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 20 V (100 W) | passive | [#467](https://github.com/darrylmorley/whatcable/issues/467) |
| Satechi USB4 V2 cable (ST-YU4120K), Amazon | `0x310E` | `0x0042` | `0x110A4E44` | Sariana LLC (dba SATECHI) | `0x3CA6` | USB4 Gen 4 (80 Gbps, Thunderbolt 5 class) | 5 A / 50 V (240 W) | passive | [#437](https://github.com/darrylmorley/whatcable/issues/437) |
| LIONWEI USB4 40 Gbps cable, Amazon | `0x315C` | `0x080D` | `0x45084043` | Chengdu Convenientpower Semiconductor Co., LTD | `0x1094` | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 20 V (100 W) | passive | [#463](https://github.com/darrylmorley/whatcable/issues/463) |
| Ikea RUNDHULT USB-C cable 1.5 m 100 W, Ikea | `0xFFFF` | `0x0000` | `0x00084848` | No vendor ID assigned (USB-PD spec sentinel) | none | USB 2.0 (480 Mbps) | 5 A / 20 V (100 W) | passive | [#464](https://github.com/darrylmorley/whatcable/issues/464) |
| Anker 2-in-1 USB-C cable 1.8 m, Amazon | `0x291A` | `0x8895` | `0x000A2640` | Anker Innovations Limited | none | USB 2.0 (480 Mbps) | 5 A / 50 V (240 W) | passive | [#485](https://github.com/darrylmorley/whatcable/issues/485) |
| Anker A80E6 240 W Bio-Braided USB-C cable 6 ft, Amazon | `0x291A` | `0xA8F6` | `0x000A4640` | Anker Innovations Limited | `0x38A7` | USB 2.0 (480 Mbps) | 5 A / 50 V (240 W) | passive | [#519](https://github.com/darrylmorley/whatcable/issues/519) |
| Cuktech Rainbow 240 W USB-C cable 1.5 m, Amazon (Zimi silicon) | `0x2B01` | `0x4091` | `0x000A0640` | Zimi Corporation | none | USB 2.0 (480 Mbps) | 5 A / 50 V (240 W) | passive | [#521](https://github.com/darrylmorley/whatcable/issues/521) |
| DJI Power 7 A USB-C digital-display charging cable 1 m | `0x2CA3` | `0xC701` | `0x000A2640` | DJI Technology Co., Ltd. | none | USB 2.0 (480 Mbps) | 5 A / 50 V (240 W) | passive | [#499](https://github.com/darrylmorley/whatcable/issues/499) |
| j5create JUCX27L12 USB4 40 Gbps coaxial cable, Best Buy | `0x2DE5` | `0x2409` | `0x12084043` | KaiJet Technology International Limited, Inc. dba j5create | none | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 20 V (100 W) | passive | [#509](https://github.com/darrylmorley/whatcable/issues/509) |
| DELTACO USBC-1362 braided 10 Gbps cable 1 m | `0x2EC8` | `0x0000` | `0x00082022` | Ningbo Prime Electronic Co., Ltd. | none | USB 3.2 Gen 2 (10 Gbps) | 3 A / 20 V (60 W) | passive | [#487](https://github.com/darrylmorley/whatcable/issues/487) |
| SmallRig USB4 40 Gbps 240 W cable, Amazon (Chengdu Convenientpower silicon) | `0x315C` | `0x0001` | `0x450A4643` | Chengdu Convenientpower Semiconductor Co., LTD | `0x1094` | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 50 V (240 W) | passive | [#486](https://github.com/darrylmorley/whatcable/issues/486) |
| samzhe USB4 40 Gbps cable (eEver silicon, unregistered VID) | `0x7880` | `0x0913` | `0x110A2E43` | Unregistered | `0x2EE` | USB4 Gen 3 (40 Gbps, Thunderbolt 4 class) | 5 A / 50 V (240 W) | passive | [#502](https://github.com/darrylmorley/whatcable/issues/502) |
| Anker 737 power bank bundled USB-C cable (VID/PID zeroed) | `0x0000` | `0x0000` | `0x000A2E40` | (zeroed) | none | USB 2.0 (480 Mbps) | 5 A / 50 V (240 W) | passive | [#497](https://github.com/darrylmorley/whatcable/issues/497) |

Sorted by VID. The zeroed-fingerprint entry is parked at the bottom because it
is identity-less.

## Patterns worth flagging for trust-signals work

Patterns the planned Cable Trust Signals heuristics should pick up:

1. **Marketing claim outpaces e-marker capability.** #49 (Dbilida) is sold as
   "Thunderbolt 4 / 40 Gbps / 240 W" but the e-marker reports passive USB4
   Gen 3 with no USB-IF cert. #169 (generic AliExpress TB4 cable) reports
   USB4 Gen 3 TB4 class with no XID despite being sold with TB4 logos on
   both plugs. The cables may carry the advertised data rate, but there is
   no cert backing the claim.
2. **Genuinely unregistered VID with no XID.** #71 (UGOURD AliExpress) and
   #151 (AGFINEST / ULT-unite) both report 80 Gbps USB4 Gen 4 from an
   unregistered VID and zero XID. Plausibly real silicon, but unverifiable
   from the e-marker alone.
3. **Zeroed identity fields.** Now a common pattern across budget and even
   major-brand cables. First seen in #61 (CUKTECH No.6) with no VDO at all,
   then in many cables that report a power-class Cable VDO but zeroed
   VID/PID (#91, #92, #108, #116, #126, #132, #134, #136, #156, #158, #166,
   #170). Worth distinguishing the truly identity-less subset (no VDO at
   all) from the cables that publish power data but not vendor identity.
4. **Shared ODM silicon across brands.** Multiple cables with different
   brand labels report the same VID + Cable VDO, indicating they share
   e-marker silicon from a common ODM. Examples so far: Chengdu
   Convenientpower (`0x315C`) across acasis #45, PX #144, and the
   AliExpress TB4 cable in #169; Shenzhen Injoinic (`0x2E87`) across
   Baseus Pudding 100 W (#167) and CUKTECH PB200N powerbank built-in
   cable (#168). Same silicon, same VDO, different brand labels. Trust
   signals should treat these as one supplier's hardware, not as
   independent vendor diversity.
5. **One product ID, two capability tiers.** A vendor's PID can identify
   the e-marker chip rather than the cable model, so cables of different
   capability ship under one VID + PID and are told apart only by the
   Cable VDO. Sumitomo (`0x20C2`) PID `0x0714` appears as both 40 Gbps
   (`0x460A2643`, four probe-corpus machines) and 80 Gbps (`0x460A2644`,
   #405); PID `0x0A14` does the same. Chant Sincere (`0x0C62`) PID
   `0xC8F1` appears as both 3 A (#402) and 5 A. Ruled out as a read
   artefact: on 40 Gbps-only hosts the 80 Gbps e-marker still reads 80,
   so macOS is not clamping the reported speed to the negotiated link.
   **Fixed.** `whatcable.db` used to enforce `UNIQUE(vid, pid)` and skip
   the later row as a duplicate identity, so only the first-seen tier
   shipped. The identity rework (see #505 below) keys the db on the full
   `(vid, pid, cable_vdo, brand)` row instead, so both tiers ship and
   `CableReport`'s lookup discriminates on Cable VDO within a VID+PID
   match.
6. **Same OEM silicon, sold under different retail brands, identical
   fingerprint.** #505: a UGREEN Thunderbolt 5 cable and the existing
   Anker Prime Thunderbolt 5 cable (ACON `0x0522`/`0x0A33`) report the
   *exact same* VID + PID + Cable VDO. This is a step beyond pattern 4
   (shared silicon, different VDO): here two brands sell the identical
   e-marker fingerprint, so a VID+PID+VDO match alone cannot tell them
   apart. The db now returns every curated row for a matching fingerprint
   rather than picking one; `PortSummary` still shows the first brand
   (multi-brand wording is a follow-up), but the data no longer silently
   drops the second brand's identity.
7. **Port controller contradicts the e-marker's own self-report.** #111
   (CalDigit 2 m TB4) declares itself a passive cable in its ID Header,
   while the port controller reports `ActiveCable = true` for that same
   fingerprint on all four corpus submissions that report it. The
   `Type` cell for that row is therefore the port controller's reading,
   not the e-marker's: it is the only row in the table above whose type
   does not come from the e-marker. `CableClassification` resolves the
   two readings the same way, promoting a passive self-report when the
   controller disagrees and never demoting an active one.

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
