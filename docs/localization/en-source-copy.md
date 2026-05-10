# English Source Copy and Translation Notes

This document is the translation source of truth for the first WhatCable
localization pass. It records what each English string means in product
context before the Simplified Chinese catalog is authored.

## Translation Rules

- Default language remains English (`en`). Simplified Chinese uses `zh-Hans`.
- Keep technical product/protocol terms in English when they are names or
  common technical labels: USB-C, USB4, Thunderbolt, Power Delivery, e-marker,
  IOKit, DisplayPort, SuperSpeed, VDO, PDO, MagSafe.
- Translate explanatory prose into natural Simplified Chinese, but preserve
  units and symbols such as W, V, A, Gb/s, mW, uW, `x`, and `@`.
- Keep GitHub cable report Markdown and JSON payload display text in English
  because they are maintainer-facing and script-facing stable outputs.
- Buttons and menu items should be short. Diagnostics should prioritize causal
  accuracy over literal English order.

## Ambiguous Terms

| English | Meaning in WhatCable | Simplified Chinese guidance |
|---|---|---|
| `Active` | In connection state rows, means the port/link is active or currently enabled. | `活跃` or `已启用`, depending on row context. |
| `Active cable` | A cable with active signal-conditioning electronics, not "currently active". | `有源线缆`; keep "active" meaning electronics-assisted. |
| `active` | Badge next to the currently selected charging profile/PDO. | `当前`; not "active cable". |
| `profiles` | USB-PD/MagSafe power profiles/PDO options exposed by a power source. | `供电档位`. |
| `source` | A power source/charger object, not source code. | `供电源` or `充电器`. |
| `smart cable` | A cable with an e-marker chip that can advertise capabilities. | `带 e-marker 的线缆`. |
| `basic cable` | A cable that does not advertise an e-marker. It may still work for basic USB/charging. | `基础线缆`; avoid implying it is broken. |
| `trust signals` | Hedged warning signals from e-marker data. Not a final fake-cable verdict. | `可信度信号`; keep wording cautious. |
| `raw` | Low-level IOKit or VDO data for technical users. | `原始`; do not translate as "生". |

## App UI and Menus

| English source | Product context | Placeholder notes | Suggested zh-Hans | Status |
|---|---|---|---|---|
| `Settings` | Header and gear tooltip for the settings panel. | none | `设置` | reviewed |
| `Settings...` / `Settings…` | macOS menu item that opens settings. | none | `设置...` / `设置…` | reviewed |
| `Done` | Closes embedded settings panel. | none | `完成` | reviewed |
| `Behavior` | Settings section for launch/window behavior. | none | `行为` | reviewed |
| `Launch at login` | Toggle for SMAppService login item. | none | `登录时启动` | reviewed |
| `Show in menu bar` | Toggle for menu-bar-only mode. | none | `显示在菜单栏` | reviewed |
| `Lives in the menu bar with no Dock icon.` | Explanation when menu bar mode is enabled. | none | `驻留在菜单栏，不显示 Dock 图标。` | reviewed |
| `Runs as a regular Dock app with a window.` | Explanation when window mode is enabled. | none | `作为普通 Dock 应用运行并显示窗口。` | reviewed |
| `Display` | Settings section for visual preferences. | none | `显示` | reviewed |
| `Language` | Settings picker label for app language. | none | `语言` | reviewed |
| `English` | Language picker option for selecting the English UI. | none | `英语` | reviewed |
| `Simplified Chinese` | Language picker option. | none | `简体中文` | reviewed |
| `Show technical details` | Toggle for advanced IOKit/VDO details. | none | `显示技术详情` | reviewed |
| `Hide empty ports` | Toggle hiding ports with no live signal. | none | `隐藏空端口` | reviewed |
| `Font size` | Settings slider label. | none | `字体大小` | reviewed |
| `Notifications` | Settings section for user notifications. | none | `通知` | reviewed |
| `Notify on cable changes` | Toggle for USB/power change notifications. | none | `线缆变化时通知` | reviewed |
| `Refresh` | Refresh button/menu item. | none | `刷新` | reviewed |
| `Quit` / `Quit %@` | Footer and app menu quit action. | app name | `退出` / `退出 %@` | reviewed |
| `About %@` | App menu about item. | app name | `关于 %@` | reviewed |
| `Check for Updates...` / `Check for Updates…` | OSS build updater menu item. | none | `检查更新...` / `检查更新…` | reviewed |
| `WhatCable on GitHub` | Help menu opens repository. | none | `GitHub 上的 WhatCable` | reviewed |
| `Keep window open` | Status-menu pin toggle. | none | `保持窗口打开` | reviewed |
| `WhatCable %@ is available` | Update banner headline. | version | `WhatCable %@ 可用` | reviewed |
| `You're on %@` | Update banner current version status. | version | `当前版本 %@` | reviewed |
| `Downloading...` / `Downloading…` | Installer state. | none | `正在下载...` / `正在下载…` | reviewed |
| `Verifying signature...` / `Verifying signature…` | Installer state. | none | `正在验证签名...` / `正在验证签名…` | reviewed |
| `Installing, WhatCable will relaunch` | Installer state. | none | `正在安装，WhatCable 将重新启动` | reviewed |
| `Install failed: %@` | Installer error. | error message | `安装失败：%@` | reviewed |
| `View release` | Button opens GitHub release. | none | `查看发布页` | reviewed |
| `Install update` | Button starts installer. | none | `安装更新` | reviewed |

## Main Popover and Port Details

| English source | Product context | Placeholder notes | Suggested zh-Hans | Status |
|---|---|---|---|---|
| `No USB-C ports detected` | Empty state when no port-controller services are exposed. | none | `未检测到 USB-C 端口` | reviewed |
| `This Mac doesn't seem to expose its port-controller services. Hit refresh, or check System Information > USB.` | Explanation for no ports. | none | `这台 Mac 似乎没有暴露端口控制器服务。请点按刷新，或检查“系统信息”>“USB”。` | reviewed |
| `Nothing connected` | Empty state or per-port headline when no live connection exists. | none | `未连接任何设备` | reviewed |
| `%lld USB-C ports detected, but nothing is currently plugged in. Turn off "Hide empty ports" in Settings to see them.` | Empty state when ports exist but are hidden because empty. | count | `检测到 %lld 个 USB-C 端口，但当前没有接入设备。可在“设置”中关闭“隐藏空端口”查看它们。` | reviewed |
| `%lld USB devices` | Footer USB device count. | count | `%lld 个 USB 设备` | reviewed |
| `Connected devices` | Section listing matched USB devices on a port. | none | `已连接设备` | reviewed |
| `Unknown` | Fallback device name. | none | `未知` | reviewed |
| `Connection` | Advanced section for live connection flags. | none | `连接` | reviewed |
| `Active` | Row label in advanced connection/transports sections. | none | `活跃` | reviewed |
| `Active cable electronics` | Advanced row for port active-cable flag. | none | `有源线缆电子组件` | reviewed |
| `Optical` | Advanced row/label for optical media. | none | `光纤` | reviewed |
| `USB active` | Advanced row for USB transport activity. | none | `USB 活跃` | reviewed |
| `SuperSpeed` | Advanced row for SuperSpeed flag. | none | `SuperSpeed` | reviewed |
| `Plug events` | Advanced row showing plug-event count. | count value elsewhere | `插拔事件` | reviewed |
| `Transports` | Advanced section for supported/provisioned/active transports. | none | `传输` | reviewed |
| `Supported` | Transport capabilities supported by port. | none | `支持` | reviewed |
| `Provisioned` | Transports provisioned/configured by controller. | none | `已配置` | reviewed |
| `All raw IOKit properties (%lld)` | Disclosure group for raw properties. | property count | `全部原始 IOKit 属性（%lld）` | reviewed |
| `Active cable (VDO 2)` / `Active cable (VDO 2):` | Deep active-cable VDO section. | none | `有源线缆（VDO 2）` / `有源线缆（VDO 2）：` | reviewed |
| `Physical connection` | Active Cable VDO 2 field label for copper/optical medium. | none | `物理连接` | reviewed |
| `Active element` | Active Cable VDO 2 field label for re-driver/re-timer. | none | `有源元件` | reviewed |
| `Optically isolated` | Active Cable VDO 2 boolean field label. | none | `光隔离` | reviewed |
| `USB lanes` | Active Cable VDO 2 lane-count field label. | none | `USB 通道数` | reviewed |
| `Two` / `One` | Active Cable VDO 2 lane-count values. | none | `双通道` / `单通道` | reviewed |
| `USB Gen` | Active Cable VDO 2 USB generation field label. | none | `USB 代际` | reviewed |
| `Gen 2 or higher` / `Gen 1` | Active Cable VDO 2 USB generation values. | none | `Gen 2 或更高` / `Gen 1` | reviewed |
| `USB4 supported` / `USB 3.2 supported` / `USB 2.0 supported` | Active Cable VDO 2 protocol support booleans. | none | `USB4 支持` / `USB 3.2 支持` / `USB 2.0 支持` | reviewed |
| `USB 2.0 hub hops` | Active Cable VDO 2 hub-hop count field label. | none | `USB 2.0 hub 跳数` | reviewed |
| `USB4 asymmetric` | Active Cable VDO 2 asymmetric-mode field label. | none | `USB4 非对称模式` | reviewed |
| `U3 to U0 transition` | Active Cable VDO 2 power-state transition field label. | none | `U3 到 U0 转换` | reviewed |
| `Through U3S` / `Direct` | Active Cable VDO 2 transition values. | none | `经由 U3S` / `直接` | reviewed |
| `Idle power (U3/CLd)` | Active Cable VDO 2 idle power field label. | none | `空闲功耗（U3/CLd）` | reviewed |
| `Max operating temp` / `Shutdown temp` | Active Cable VDO 2 temperature field labels. | none | `最高工作温度` / `关断温度` | reviewed |
| `Thunderbolt fabric` | Advanced Thunderbolt topology section. | none | `Thunderbolt 拓扑` | reviewed |
| `Host (%@)` | Thunderbolt host switch row. | class name | `主机（%@）` | reviewed |
| `no active link` | Fallback when no TB lane link is active. | none | `无活跃链路` | reviewed |
| `Cable trust signals` / `Cable trust signals:` | Trust warning section/card title. | none | `线缆可信度信号` / `线缆可信度信号：` | reviewed |

## Core Summaries and Diagnostics

| English source | Product context | Placeholder notes | Suggested zh-Hans | Status |
|---|---|---|---|---|
| `Plug a cable into %@ to see what it can do.` | Per-port empty subtitle. | port label | `将线缆接入 %@，即可查看它能做什么。` | reviewed |
| `Thunderbolt / USB4 link active` | Generic TB/USB4 link bullet. | none | `Thunderbolt / USB4 链路活跃` | reviewed |
| `SuperSpeed USB (5 Gbps or faster)` | USB3+ data bullet. | none | `SuperSpeed USB（5 Gbps 或更快）` | reviewed |
| `USB 2.0 only (480 Mbps), no high-speed data` | Slow USB bullet. | none | `仅 USB 2.0（480 Mbps），无高速数据` | reviewed |
| `Carrying DisplayPort video` | DisplayPort alt-mode bullet. | none | `正在传输 DisplayPort 视频` | reviewed |
| `Connected device: %@, %@` | Partner identity bullet. | device kind, vendor | `已连接设备：%@，%@` | reviewed |
| `Cable has an e-marker chip (advertises its capabilities)` | Cable e-marker detected. | none | `线缆带有 e-marker 芯片（会声明自身能力）` | reviewed |
| `Cable does not advertise an e-marker (basic cable)` | PD-capable port did not find cable e-marker. | none | `线缆未声明 e-marker（基础线缆）` | reviewed |
| `This port can't read cable details (USB-only port, no Power Delivery)` | USB-only port cannot query e-marker. | none | `此端口无法读取线缆详情（仅 USB，无 Power Delivery）` | reviewed |
| `Cable speed: %@` | Cable VDO speed bullet. | speed label | `线缆速度：%@` | reviewed |
| `Cable rated for %@ at up to %lldV (~%lldW)` | Cable current/voltage/wattage bullet. | current, volts, watts | `线缆额定 %@，最高 %lldV（约 %lldW）` | reviewed |
| `Active %@ cable, %@` | Active cable medium and element. | medium, element | `有源%@线缆，%@` | reviewed |
| `Optical fibres are electrically isolated end-to-end` | Optical isolation bullet. | none | `光纤端到端电气隔离` | reviewed |
| `Optical cable, not electrically isolated (carries copper alongside the fibres)` | Optical but not isolated. | none | `光纤线缆，但未电气隔离（光纤旁仍带有铜线）` | reviewed |
| `Active cable (contains signal-conditioning electronics)` | Active cable fallback. | none | `有源线缆（包含信号调理电子组件）` | reviewed |
| `Optical cable` | Port-level optical flag. | none | `光纤线缆` | reviewed |
| `Cable made by %@` | Cable vendor bullet. | vendor name | `线缆制造商：%@` | reviewed |
| `Charger advertises up to %lldW` | Charger advertised max power. | watts | `充电器声明最高 %lldW` | reviewed |
| `Currently negotiated: %@ @ %@ (%@)` | Winning PDO bullet. | volts, amps, watts | `当前协商：%@ @ %@（%@）` | reviewed |
| `Thunderbolt / USB4` | Headline. | optional suffix elsewhere | `Thunderbolt / USB4` | reviewed |
| `USB-C with video` | Headline for USB data + DP. | none | `带视频的 USB-C` | reviewed |
| `Display connected` | Headline for DP-only/display. | none | `已连接显示器` | reviewed |
| `USB device` | Headline for data device. | none | `USB 设备` | reviewed |
| `Slow USB device or charge-only cable` | Headline for USB2-only. | none | `慢速 USB 设备或仅充电线缆` | reviewed |
| `Charging` / `Charging only` | Headline for power-only states. | optional wattage suffix | `正在充电` / `仅充电` | reviewed |
| `Connected` | Unknown connected state. | none | `已连接` | reviewed |
| `Supports %@.` | Subtitle with joined capabilities. | capability list | `支持 %@。` | reviewed |
| `high-speed data` | Capability phrase. | none | `高速数据` | reviewed |
| `video` | Capability phrase. | none | `视频` | reviewed |
| `smart cable` | Capability phrase meaning e-marker present. | none | `带 e-marker 的线缆` | reviewed |
| `Cable is limiting charging speed` | Diagnostic summary. | none | `线缆限制了充电速度` | reviewed |
| `Charging at %lldW (charger can do up to %lldW)` | Diagnostic summary. | negotiated, charger max | `正在以 %lldW 充电（充电器最高可达 %lldW）` | reviewed |
| `Charging well at %lldW` | Diagnostic summary. | watts | `正在以 %lldW 正常充电` | reviewed |
| `Charger and cable are well-matched.` | Diagnostic detail. | none | `充电器和线缆匹配良好。` | reviewed |

## Widget, Notifications, and CLI

| English source | Product context | Placeholder notes | Suggested zh-Hans | Status |
|---|---|---|---|---|
| `Cable Status` | Widget configuration name. | none | `线缆状态` | reviewed |
| `See what your USB-C cables can do at a glance.` | Widget gallery description. | none | `快速查看你的 USB-C 线缆能做什么。` | reviewed |
| `No cable data` | Widget empty state. | none | `无线缆数据` | reviewed |
| `Open WhatCable to start monitoring.` | Widget empty state detail. | none | `打开 WhatCable 开始监测。` | reviewed |
| `Connected: %@` | Notification title for USB device added. | device name | `已连接：%@` | reviewed |
| `Low Speed (1.5 Mbps)` / `Full Speed (12 Mbps)` / `High Speed (480 Mbps)` | USB device negotiated speed labels. | none | `低速（1.5 Mbps）` / `全速（12 Mbps）` / `高速（480 Mbps）` | reviewed |
| `Super Speed (5 Gbps)` / `Super Speed+ (10 Gbps)` / `Super Speed+ Gen 2x2 (20 Gbps)` | USB device negotiated speed labels. | none | `SuperSpeed（5 Gbps）` / `SuperSpeed+（10 Gbps）` / `SuperSpeed+ Gen 2x2（20 Gbps）` | reviewed |
| `Unknown speed` | USB device speed fallback. | none | `未知速度` | reviewed |
| `USB device disconnected` | Notification title for device removal. | none | `USB 设备已断开` | reviewed |
| `%lld devices removed` | Notification body for removals. | count | `已移除 %lld 个设备` | reviewed |
| `%@ negotiated` | Notification body for negotiated watts. | watts label | `已协商 %@` | reviewed |
| `PD source` | Notification fallback for power source. | none | `PD 供电源` | reviewed |
| `Charger connected` | Notification title. | none | `充电器已连接` | reviewed |
| `Charger disconnected` | Notification title. | none | `充电器已断开` | reviewed |
| `whatcable [options]` help text | CLI human-readable help. | version and tagline | Translate prose; keep flag names. | reviewed |
| `whatcable: unknown option %@` | CLI unknown flag error. | flag | `whatcable：未知选项 %@` | reviewed |
| `whatcable: --language requires one of: en, zh-Hans` | CLI language flag missing value. | none | `whatcable：--language 需要以下之一：en、zh-Hans` | reviewed |
| `whatcable: unsupported language %@. Use one of: en, zh-Hans` | CLI invalid language code. | invalid code | `whatcable：不支持语言 %@。请使用以下之一：en、zh-Hans` | reviewed |
| `No cable e-markers detected...` | CLI report mode user-facing precondition. | none | `未检测到线缆 e-marker...` | reviewed |
| `Cable %lld of %lld` | CLI report wrapper when multiple cable e-markers are found. | current index, total count | `第 %lld / %lld 条线缆` | reviewed |
| `Open in GitHub to file a report:` | CLI report mode instruction. | none | `在 GitHub 中打开以提交报告：` | reviewed |

## Stable English Outputs

The following remain English even when the UI language is Simplified Chinese:

- JSON display fields (`headline`, `subtitle`, `bullets`, diagnostic `summary`
  and `detail`, trust flag titles/details).
- Cable report Markdown table headings, field names, issue title, and URL query
  payload. These are maintainer-facing and kept stable for future parsing.
