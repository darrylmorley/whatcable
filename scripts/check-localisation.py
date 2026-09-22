#!/usr/bin/env python3
"""Localisation coverage gate.

Two blind spots let three user-facing strings ship untranslated in v1.3.0-beta.3
(reported by @jimmyorz on discussion #489):

  1. The parity check I had been running compared `.strings` files only.
     `.stringsdict` holds the plural forms and was never in the comparison, so
     `Show %lld hubs` and `via %lld hubs` sat in English alone.

  2. Parity compares every language against English. A key missing from English
     TOO is not a discrepancy, so the check passes. `String(localized:)` falls
     back to the literal, so it renders correctly in English and silently ships
     untranslated everywhere else. That is how `Hide hubs` reached users without
     existing in any `.strings` file at all.

So this script checks two different things:

  A. EXTRACTION. Every `String(localized: "...")` literal in the Swift sources
     resolves in the catalogue its `bundle:` argument points at. Catches a
     string nobody ever added, which parity cannot.

  B. PARITY. Every language has exactly the keys English has, in BOTH file
     types, per catalogue, with values that are actually translated (not
     just present).

A second review pass (before this file shipped) found six more ways the
first version of this gate could go green while something was genuinely
broken. Each is noted at the point in the code that closes it:

  1. Only two source directories were scanned, but WhatCablePlugins and
     WhatCableWidget also call String(localized:) against the same two
     catalogues. Fixed by scanning every .swift file under Sources/ and
     classifying each call by its `bundle:` argument rather than by which
     directory the file happens to live in.
  2. A literal the scanner could not read (raw strings, triple-quoted
     strings) was silently dropped instead of failing. Fixed by supporting
     both forms and failing loudly on anything still unparseable.
  3. Parity only checked keys that existed in both catalogues; deleting an
     entire language directory left the rest agreeing and nothing failed.
     Fixed by asserting the expected locale set explicitly.
  4. Parity compared keys only, never values, so a translation could be
     wrong, untranslated, or a malformed stringsdict entry and still pass.
     Fixed with structural stringsdict validation plus a byte-identical-
     to-English value check.
  5. `%@` and `%lld` were treated as interchangeable when matching an
     interpolated literal against the catalogue, so a String argument could
     be silently satisfied by an Int-only catalogue entry. Fixed with a
     narrow, explicitly-scoped specifier inference plus an ambiguity check.
  6. The baseline ratchet was keyed on (target, key) alone, so a second,
     unrelated occurrence of an already-baselined string was silently
     covered too. Fixed by keying on (target, path, key) with an expected
     occurrence count.

A third review pass found two more:

  7. SPECIFIER_RE, used to validate a stringsdict category's format text
     against its declared NSStringFormatValueTypeKey, had no `%@`
     alternative. Changing a plural category's text from an integer
     specifier to `%@` while the declared value type stayed numeric passed
     clean, which is a real runtime mismatch (the format text and the
     declared type disagree). Fixed by recognising `%@` as a found
     specifier too.
  8. The identical-to-English amnesty (ALLOWED_IDENTICAL) was keyed on
     (target, value) only, so a legitimate loanword in one language (say,
     French keeping "Diagnostics") silently exempted every other language
     from the same check, including one that regressed to the English text.
     Fixed by keying on (target, language, value), reseeded per language
     from the current catalogues.

A fourth finding from the same pass (a nested local function can shadow its
parent's name during bundle resolution) is dormant with no code path that
triggers it today, and is tracked separately rather than fixed here.

Run directly, or via scripts/ci.sh.
"""

import os
import plistlib
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BASE_LANG = "en"

# The two catalogues that exist in this repo, and the global bundle constant
# that every literal's `bundle:` argument ultimately resolves to. This is not
# "which source directory is the file in": WhatCablePlugins and WhatCableWidget
# have no catalogue of their own, they call into Core's via _coreLocalizedBundle
# (see finding 1 above), and two Core functions take a `bundle: Bundle`
# parameter and get called with EITHER global depending on caller (see
# resolve_bundle below), so a literal can legitimately need to exist in both.
CATALOGUES = {
    "_coreLocalizedBundle": ("WhatCableCore", "Sources/WhatCableCore/Resources"),
    "_appLocalizedBundle": ("WhatCable (app)", "Sources/WhatCable/Resources"),
    "_notificationsLocalizedBundle": ("WhatCableNotifications", "Sources/WhatCableNotifications/Resources"),
}

# The locale directories every catalogue is expected to carry, asserted
# explicitly rather than derived from whatever .lproj directories happen to
# exist on disk (finding 3: derived-only meant deleting a whole language
# still passed parity, because the remaining languages still agreed with
# each other).
EXPECTED_LANGUAGES = [
    "de", "en", "es", "fr", "hi", "hy", "it", "ja", "ko", "lv", "nb", "nl",
    "pl", "pt-BR", "ru", "tr", "uk", "zh-Hans", "zh-Hant",
]

# CLDR cardinal-plural categories each language requires at minimum. A
# language may carry MORE categories than this (harmless: NSStringDictionary
# just never selects the unused one, e.g. several of our files keep a "one"
# entry for languages like zh/tr/ja/ko whose grammar doesn't need it) but
# must not carry FEWER, because a missing required category is a runtime
# crash-or-fallback for that count. This table is a static fact about each
# language's grammar, not something this repo's data can drift out of sync
# with, so unlike the ratchets below it's not expected to change.
REQUIRED_PLURAL_CATEGORIES = {
    "en": {"one", "other"},
    "de": {"one", "other"},
    "es": {"one", "other"},
    "fr": {"one", "other"},
    "hi": {"one", "other"},
    "hy": {"one", "other"},
    "it": {"one", "other"},
    "ja": {"other"},
    "ko": {"other"},
    "lv": {"zero", "one", "other"},
    "nb": {"one", "other"},
    "nl": {"one", "other"},
    "pl": {"few", "many", "one", "other"},
    "pt-BR": {"one", "other"},
    "ru": {"few", "many", "one", "other"},
    "tr": {"other"},
    "uk": {"few", "many", "one", "other"},
    "zh-Hans": {"other"},
    "zh-Hant": {"other"},
}

# Placeholder standing in for one `\(...)` interpolation while we compare.
HOLE = "\x00"

CALL_RE = re.compile(r"String\(\s*localized:\s*")


# --- Known-missing baseline (a ratchet, not an amnesty) -----------------------
#
# These strings were already missing from a catalogue when this check learned
# to see them, so failing on them would block every push. They are listed here
# so the gate can go green on the backlog while blocking anything NEW, exactly
# like the pro-boundary ratchet.
#
# Keyed on (repo-relative source path, catalogue key), not key alone (finding
# 6): a bare-key baseline silently covers a SECOND, unrelated occurrence of the
# same string anywhere else in the target, and still passes if the original
# occurrence moves. The value is the number of times that exact occurrence is
# expected at that exact call site (almost always 1). If the actual count at
# that (path, key) differs, in either direction, the check fails: fewer means
# it was fixed and the line must be deleted; more means a new or moved
# occurrence needs its own line, not a free ride on this one.
#
# The list may only SHRINK. Fixing one and leaving it here is also an error:
# the check fails if a baseline entry has been resolved, which forces the line
# to be deleted and stops the list quietly becoming permanent.
#
# Tracked in the maintainer's backlog.
KNOWN_MISSING = {
    "WhatCableCore": {
        # billboardPresenceLabel(bundle:) is defined in Core but called from
        # both TextFormatter (Core) and ContentView (app) with different
        # bundles, so this literal (physically in USBDevice.swift) has to
        # resolve in both catalogues. See the matching entry under
        # "WhatCable (app)" below.
        ("Sources/WhatCableCore/USB/USBDevice.swift", "Billboard device: \x00"): 1,
        # The rest of this target's baseline is WhatCablePlugins and
        # WhatCableWidget: both call String(localized:, bundle:
        # _coreLocalizedBundle), so they're checked against this catalogue,
        # but neither was in scope before this check learned to classify by
        # bundle argument instead of source directory (finding 1). This is
        # the "batch of new baseline entries" that fix predicted.
        ("Sources/WhatCablePlugins/Diagnostics/CableDiagnosticView.swift",
         "A Billboard device reports the Alt Modes a USB-C device supports. On a healthy dock it's normal."): 1,
        ("Sources/WhatCablePlugins/Diagnostics/CableDiagnosticView.swift", "Advertised Alt Modes"): 1,
        ("Sources/WhatCablePlugins/Diagnostics/CableDiagnosticView.swift", "Alt Mode \x00"): 1,
        ("Sources/WhatCablePlugins/Diagnostics/CableDiagnosticView.swift", "Configured"): 1,
        ("Sources/WhatCablePlugins/Diagnostics/CableDiagnosticView.swift", "Device class"): 1,
        ("Sources/WhatCablePlugins/Diagnostics/CableDiagnosticView.swift", "Didn't come up"): 2,
        ("Sources/WhatCablePlugins/Diagnostics/CableDiagnosticView.swift", "Location ID"): 1,
        ("Sources/WhatCablePlugins/Diagnostics/CableDiagnosticView.swift", "No active power request"): 1,
        ("Sources/WhatCablePlugins/Diagnostics/CableDiagnosticView.swift", "Not attempted"): 1,
        ("Sources/WhatCablePlugins/Diagnostics/CableDiagnosticView.swift",
         "One advertised Alt Mode didn't come up. That can be normal right after plugging in, or a sign the cable or port can't carry it."): 1,
        ("Sources/WhatCablePlugins/Diagnostics/CableDiagnosticView.swift", "Power available"): 1,
        ("Sources/WhatCablePlugins/Diagnostics/CableDiagnosticView.swift", "Power requested"): 1,
        ("Sources/WhatCablePlugins/Diagnostics/CableDiagnosticView.swift", "Raw properties"): 1,
        ("Sources/WhatCablePlugins/Diagnostics/CableDiagnosticView.swift", "Serial number"): 1,
        ("Sources/WhatCablePlugins/Diagnostics/CableDiagnosticView.swift", "Status"): 3,
        ("Sources/WhatCablePlugins/Diagnostics/CableDiagnosticView.swift", "USB version"): 1,
        ("Sources/WhatCablePlugins/Diagnostics/CableDiagnosticView.swift", "Unregistered cable (vendor ID not set)"): 1,
        ("Sources/WhatCablePlugins/Diagnostics/CableDiagnosticView.swift", "Yes, available power below Mac's max draw"): 1,
        ("Sources/WhatCablePlugins/History/SavedCablesScreen.swift",
         'Open WhatCable, find a connected cable, and choose "Add this cable" on its port to start tracking it.'): 1,
        ("Sources/WhatCablePlugins/Power/PowerMonitorWindow.swift",
         "Could be damage, debris, or a marginal cable. Try reseating it, or a known-good cable."): 1,
        ("Sources/WhatCablePlugins/Power/PowerMonitorWindow.swift", "Worth keeping an eye on"): 1,
        ("Sources/WhatCableWidget/Power/PowerWidgetViews.swift", "%@W draw"): 1,
        ("Sources/WhatCableWidget/Power/PowerWidgetViews.swift", "Battery and charging at a glance."): 1,
        ("Sources/WhatCableWidget/Power/PowerWidgetViews.swift", "No power data"): 1,
    },
    "WhatCable (app)": {
        ("Sources/WhatCable/Support/UnsupportedArchitectureNotice.swift",
         "This Mac has an Intel processor. WhatCable gets its cable and port data from Apple Silicon's port controller, and Intel Macs don't expose it, so the app will show nothing useful.\n\nIt'll stay open if you want to look around, but there's nothing behind it."): 1,
        ("Sources/WhatCable/Views/SettingsView.swift", "Upgrade to WhatCable Pro"): 1,
        ("Sources/WhatCable/Services/DetachedProWindowManager.swift", "WhatCable Pro"): 1,
        ("Sources/WhatCable/Views/ContentView.swift",
         "\x00 USB-C ports and 1 MagSafe port detected, but nothing is currently plugged in. Turn off \"Hide empty ports\" in Settings to see them."): 1,
        ("Sources/WhatCable/Views/ContentView.swift",
         "\x00 USB-C ports detected, but nothing is currently plugged in. Turn off \"Hide empty ports\" in Settings to see them."): 1,
        ("Sources/WhatCable/Views/TestKitSettingsSection.swift", "Last run: v\x00"): 1,
        ("Sources/WhatCable/Views/TestKitSettingsSection.swift", "No output: \x00"): 1,
        ("Sources/WhatCable/Views/TestKitSettingsSection.swift", "\x00 submitted, \x00 failed, \x00 no output"): 1,
        ("Sources/WhatCable/Views/TestKitSettingsSection.swift", "\x00 submitted, \x00 failed"): 1,
        ("Sources/WhatCable/Views/TestKitSettingsSection.swift", "\x00 submitted, \x00 no output"): 1,
        ("Sources/WhatCable/Views/TestKitSettingsSection.swift", "\x00 probes submitted"): 1,
        # See the matching comment under WhatCableCore above.
        ("Sources/WhatCableCore/USB/USBDevice.swift", "Billboard device: \x00"): 1,
    },
}

# Same idea for a language carrying a key English does not.
KNOWN_EXTRA = {
    ("WhatCable (app)", "uk", ".stringsdict"): {"%lld displays connected"},
    ("WhatCable (app)", "lv", ".stringsdict"): {
        "%lld displays connected",
        "%lld USB-C ports and 1 MagSafe port detected, but nothing is currently plugged in. Turn off \"Hide empty ports\" in Settings to see them.",
        "%lld USB-C ports detected, but nothing is currently plugged in. Turn off \"Hide empty ports\" in Settings to see them.",
    },
    ("WhatCableCore", "lv", ".stringsdict"): {"%lld displays connected"},
}

# Values that are byte-identical to English on purpose: loanwords, unit
# symbols, and product names that don't take a local form ("USB",
# "Thunderbolt", "WhatCable Pro", amperage figures like "3 A", and so on).
# Finding 4(b): a value identical to English is exactly what an untranslated
# or half-translated string looks like, so it needs to be flagged, but a huge
# share of the real corpus is legitimately identical for the reasons above.
#
# Finding 8: this used to be keyed on (target, value) alone, so one entry
# applied to every language regardless of which language it was actually
# legitimate in. "Diagnostics" is a genuine loanword in French, but the same
# flat entry also silently exempted German, so German regressing to the
# English word for "Diagnostics" passed clean with no mention of it anywhere.
# Now keyed on (target, language, value): an entry only covers the one
# language it was seeded from, so a loanword in one language can't mask a
# regression in another.
#
# This is a SNAPSHOT of every (target, language, key) triple that was
# already identical to English when this check learned to compare values,
# reseeded the same way after the re-key, not a hand-vetted "these are
# definitely fine" list. Unlike KNOWN_MISSING, a translation that stops
# matching English does not force deletion here: many of these keys are
# permanently, correctly identical in that language (a unit symbol has no
# translation to give), so this ratchet is allowed to sit at its current
# size rather than trend to zero. It can still shrink by hand when a
# genuinely untranslated entry in here gets a real translation.
#
# "via %lld hubs" (WhatCableCore .stringsdict) shows up under fr/nl/pt-BR
# and nb: "via" and "hub"/"hubs" are kept as loanwords in those languages
# (see "Hide hubs" and "Through U3S" -> "Via U3S" in the same catalogues),
# so this is a coincidentally correct match in each of them rather than an
# untranslated string.
ALLOWED_IDENTICAL = {
    "WhatCableCore": {
        "de": {
            "OK",
            "%lld displays connected", "%lld × %lld", "1-5 mW", "3 A", "5 A", "5-10 mW",
            "50-200 µW", "< 50 µW", "> 10 mW", "Battery full, not drawing power",
            "Battery, %@ to %@, %@", "Built-in %1$@ port %2$lld",
            "Cable rated to %lldV / %@, delivers up to %lldW (USB-PD caps at 48V)",
            "DisplayPort Alt Mode",
            "E-marker reports passive, but carries active-cable structure (may be a mis-programmed e-marker)",
            "EPR AVS, %@ to %@, %@",
            "High-resolution displays often use compression (DSC) to fit their top mode through a link like this, so selecting the higher mode in Display settings may reach it normally.",
            "Host", "Isn't performing as expected", "Lanes", "Live", "MagSafe 3", "Monitor",
            "Name", "No problems seen while watching this cable.",
            "Not performing as expected", "PPS, %@ to %@ @ %@, %@ max",
            "Performing as expected", "Rate", "Rate %lld", "Requested max operating power",
            "Requested operating power", "Requested output voltage",
            "SPR AVS, %@ at 15V / %@ at 20V",
            "Saw a brief drop or a single high reading. Not conclusive; still watching.",
            "Thunderbolt", "Thunderbolt / USB4", "Variable, %@ to %@ @ %@", "Video",
            "WhatCable Pro",
        },
        "es": {
            "OK",
            "experimental",
            "%lld displays connected", "%lld × %lld", "1-5 mW", "3 A", "5 A", "5-10 mW",
            "50-200 µW", "< 50 µW", "> 10 mW", "Battery full, not drawing power",
            "Battery, %@ to %@, %@", "Built-in %1$@ port %2$lld", "Cable",
            "Cable rated to %lldV / %@, delivers up to %lldW (USB-PD caps at 48V)",
            "E-marker reports passive, but carries active-cable structure (may be a mis-programmed e-marker)",
            "EPR AVS, %@ to %@, %@",
            "High-resolution displays often use compression (DSC) to fit their top mode through a link like this, so selecting the higher mode in Display settings may reach it normally.",
            "Host", "Isn't performing as expected", "MagSafe 3", "Marginal", "Monitor", "No",
            "No problems seen while watching this cable.", "Not performing as expected",
            "PPS, %@ to %@ @ %@, %@ max", "Performing as expected", "Re-driver", "Re-timer",
            "Requested max operating power", "Requested operating power",
            "Requested output voltage", "SPR AVS, %@ at 15V / %@ at 20V",
            "Saw a brief drop or a single high reading. Not conclusive; still watching.",
            "Thunderbolt", "Thunderbolt / USB4", "USB 2.0 (480 Mbps)",
            "USB 3.2 Gen 1 (5 Gbps)", "USB 3.2 Gen 2 (10 Gbps)", "USB4 Gen 3 (20 / 40 Gbps)",
            "USB4 Gen 4 (80 Gbps)", "Variable, %@ to %@ @ %@", "WhatCable Pro",
        },
        "fr": {
            "OK",
            "%@ Port %lld", "%@ port %lld", "%lld displays connected", "%lld × %lld", "1-5 mW",
            "3 A", "5 A", "5-10 mW", "50-200 µW", "< 50 µW", "> 10 mW",
            "Battery full, not drawing power", "Battery, %@ to %@, %@",
            "Built-in %1$@ port %2$lld",
            "Cable rated to %lldV / %@, delivers up to %lldW (USB-PD caps at 48V)",
            "Diagnostics",
            "E-marker reports passive, but carries active-cable structure (may be a mis-programmed e-marker)",
            "EPR AVS, %@ to %@, %@",
            "High-resolution displays often use compression (DSC) to fit their top mode through a link like this, so selecting the higher mode in Display settings may reach it normally.",
            "Isn't performing as expected", "Licence…", "MagSafe 3", "Mode",
            "No problems seen while watching this cable.", "Not performing as expected",
            "PPS, %@ to %@ @ %@, %@ max", "Performing as expected", "Port", "Re-driver",
            "Re-timer", "Requested max operating power", "Requested operating power",
            "Requested output voltage", "SPR AVS, %@ at 15V / %@ at 20V",
            "Saw a brief drop or a single high reading. Not conclusive; still watching.",
            "Source", "Thunderbolt", "Thunderbolt / USB4", "Type %lld",
            "Variable, %@ minimum @ %@, %@ minimum", "Variable, %@ to %@ @ %@",
            "WhatCable Pro", "via %lld hubs",
        },
        "hi": {
            "%lld displays connected", "%lld × %lld", "0.2-0.5 mW", "0.5-1 mW", "1-5 mW",
            "3 A", "5 A", "5-10 mW", "50-200 µW", "< 50 µW", "> 10 mW",
            "Battery full, not drawing power", "Battery, %@ to %@, %@",
            "Built-in %1$@ port %2$lld",
            "Cable rated to %lldV / %@, delivers up to %lldW (USB-PD caps at 48V)",
            "E-marker reports passive, but carries active-cable structure (may be a mis-programmed e-marker)",
            "EPR AVS, %@ to %@, %@",
            "High-resolution displays often use compression (DSC) to fit their top mode through a link like this, so selecting the higher mode in Display settings may reach it normally.",
            "Isn't performing as expected", "MagSafe 3",
            "No problems seen while watching this cable.", "Not performing as expected",
            "PPS, %@ to %@ @ %@, %@ max", "Performing as expected",
            "Requested max operating power", "Requested operating power",
            "Requested output voltage", "SPR AVS, %@ at 15V / %@ at 20V",
            "Saw a brief drop or a single high reading. Not conclusive; still watching.",
            "Thunderbolt", "Thunderbolt / USB4", "USB 2.0 (480 Mbps)",
            "USB 3.2 Gen 1 (5 Gbps)", "USB 3.2 Gen 2 (10 Gbps)", "USB4 Gen 3 (20 / 40 Gbps)",
            "USB4 Gen 4 (80 Gbps)", "Variable, %@ to %@ @ %@", "WhatCable Pro",
        },
        "hy": {
            "%lld displays connected", "%lld × %lld", "Battery full, not drawing power",
            "Battery, %@ to %@, %@", "Built-in %1$@ port %2$lld",
            "Cable rated to %lldV / %@, delivers up to %lldW (USB-PD caps at 48V)",
            "E-marker reports passive, but carries active-cable structure (may be a mis-programmed e-marker)",
            "EPR AVS, %@ to %@, %@",
            "High-resolution displays often use compression (DSC) to fit their top mode through a link like this, so selecting the higher mode in Display settings may reach it normally.",
            "Isn't performing as expected", "MagSafe 3",
            "No problems seen while watching this cable.", "Not performing as expected",
            "PPS, %@ to %@ @ %@, %@ max", "Performing as expected", "Re-driver", "Re-timer",
            "Requested max operating power", "Requested operating power",
            "Requested output voltage", "SPR AVS, %@ at 15V / %@ at 20V",
            "Saw a brief drop or a single high reading. Not conclusive; still watching.",
            "Thunderbolt", "Thunderbolt / USB4", "Variable, %@ to %@ @ %@", "WhatCable Pro",
        },
        "it": {
            "OK",
            "%lld × %lld", "1-5 mW", "3 A", "5 A", "5-10 mW", "50-200 µW", "< 50 µW",
            "> 10 mW", "Host", "MagSafe 3", "Monitor", "No", "Re-driver", "Re-timer",
            "Thunderbolt", "Thunderbolt / USB4", "USB 2.0 (480 Mbps)",
            "USB 3.2 Gen 1 (5 Gbps)", "USB 3.2 Gen 2 (10 Gbps)", "USB4 Gen 4 (80 Gbps)",
            "Video", "WhatCable Pro", "video",
        },
        "ja": {
            "OK",
            "%lld displays connected", "%lld × %lld", "0.2-0.5 mW", "0.5-1 mW", "1-5 mW",
            "3 A", "5 A", "5-10 mW", "50-200 µW", "< 50 µW", "> 10 mW",
            "Battery full, not drawing power", "Battery, %@ to %@, %@",
            "Built-in %1$@ port %2$lld",
            "Cable rated to %lldV / %@, delivers up to %lldW (USB-PD caps at 48V)",
            "E-marker reports passive, but carries active-cable structure (may be a mis-programmed e-marker)",
            "EPR AVS, %@ to %@, %@",
            "High-resolution displays often use compression (DSC) to fit their top mode through a link like this, so selecting the higher mode in Display settings may reach it normally.",
            "Isn't performing as expected", "MagSafe 3",
            "No problems seen while watching this cable.", "Not performing as expected",
            "PPS, %@ to %@ @ %@, %@ max", "Performing as expected",
            "Requested max operating power", "Requested operating power",
            "Requested output voltage", "SPR AVS, %@ at 15V / %@ at 20V",
            "Saw a brief drop or a single high reading. Not conclusive; still watching.",
            "Thunderbolt", "Thunderbolt / USB4", "USB 2.0 (480 Mbps)",
            "USB 3.2 Gen 1 (5 Gbps)", "USB 3.2 Gen 2 (10 Gbps)", "USB4 Gen 3 (20 / 40 Gbps)",
            "USB4 Gen 4 (80 Gbps)", "Variable, %@ to %@ @ %@", "WhatCable Pro",
        },
        "ko": {
            "%lld displays connected", "%lld × %lld", "0.2-0.5 mW", "0.5-1 mW", "1-5 mW",
            "3 A", "5 A", "5-10 mW", "50-200 µW", "< 50 µW", "> 10 mW",
            "Battery full, not drawing power", "Battery, %@ to %@, %@",
            "Built-in %1$@ port %2$lld",
            "DisplayPort Alt Mode",
            "E-marker reports passive, but carries active-cable structure (may be a mis-programmed e-marker)",
            "EPR AVS, %@ to %@, %@",
            "High-resolution displays often use compression (DSC) to fit their top mode through a link like this, so selecting the higher mode in Display settings may reach it normally.",
            "Isn't performing as expected", "MagSafe 3",
            "No problems seen while watching this cable.", "Not performing as expected",
            "PPS, %@ to %@ @ %@, %@ max", "Performing as expected",
            "Requested max operating power", "Requested operating power",
            "Requested output voltage", "SPR AVS, %@ at 15V / %@ at 20V",
            "Saw a brief drop or a single high reading. Not conclusive; still watching.",
            "Thunderbolt", "Thunderbolt / USB4", "USB 2.0 (480 Mbps)",
            "USB 3.2 Gen 1 (5 Gbps)", "USB 3.2 Gen 2 (10 Gbps)", "USB4 Gen 3 (20 / 40 Gbps)",
            "USB4 Gen 4 (80 Gbps)", "Variable, %@ to %@ @ %@", "WhatCable Pro",
        },
        "lv": {
            "%lld displays connected", "%lld × %lld", "1-5 mW", "3 A", "5 A", "5-10 mW",
            "50-200 µW", "< 50 µW", "> 10 mW", "Battery full, not drawing power",
            "Built-in %1$@ port %2$lld",
            "High-resolution displays often use compression (DSC) to fit their top mode through a link like this, so selecting the higher mode in Display settings may reach it normally.",
            "CC Advertisement", "Isn't performing as expected", "Licence…", "MagSafe 3",
            "Raw VDOs", "Raw cable VDOs", "Re-driver", "Re-timer",
            "No problems seen while watching this cable.", "Not performing as expected",
            "Performing as expected",
            "Saw a brief drop or a single high reading. Not conclusive; still watching.",
            "Thunderbolt", "Thunderbolt / USB4", "USB 2.0 (480 Mbps)",
            "USB 3.2 Gen 1 (5 Gbps)", "USB 3.2 Gen 2 (10 Gbps)", "USB4 Gen 3 (20 / 40 Gbps)",
            "USB4 Gen 4 (80 Gbps)", "Video", "WhatCable Pro", "video",
        },
        "nb": {
            "OK",
            "%@ Port %lld", "%@ port %lld", "%lld displays connected", "%lld × %lld", "3 A",
            "5 A", "< 50 µW", "> 10 mW", "Battery full, not drawing power",
            "Battery, %@ to %@, %@", "Built-in %1$@ port %2$lld",
            "Cable rated to %lldV / %@, delivers up to %lldW (USB-PD caps at 48V)", "Data",
            "E-marker reports passive, but carries active-cable structure (may be a mis-programmed e-marker)",
            "EPR AVS, %@ to %@, %@",
            "High-resolution displays often use compression (DSC) to fit their top mode through a link like this, so selecting the higher mode in Display settings may reach it normally.",
            "Isn't performing as expected", "MagSafe 3", "Marginal",
            "No problems seen while watching this cable.", "Not performing as expected",
            "PPS, %@ to %@ @ %@, %@ max", "Performing as expected", "Port", "Re-driver",
            "Re-timer", "Requested max operating power", "Requested operating power",
            "Requested output voltage", "SPR AVS, %@ at 15V / %@ at 20V",
            "Saw a brief drop or a single high reading. Not conclusive; still watching.",
            "Thunderbolt", "Thunderbolt / USB4", "Type %lld", "Variable, %@ to %@ @ %@",
            "Video", "WhatCable Pro", "adapter %lld", "via %lld hubs", "video",
        },
        "nl": {
            "OK",
            "%lld displays connected", "%lld × %lld", "1-5 mW", "3 A", "5 A", "5-10 mW",
            "50-200 µW", "< 50 µW", "> 10 mW", "Battery full, not drawing power",
            "Battery, %@ to %@, %@", "Built-in %1$@ port %2$lld", "Connector", "Data",
            "DisplayPort Alt Mode",
            "E-marker reports passive, but carries active-cable structure (may be a mis-programmed e-marker)",
            "EPR AVS, %@ to %@, %@",
            "High-resolution displays often use compression (DSC) to fit their top mode through a link like this, so selecting the higher mode in Display settings may reach it normally.",
            "Host", "Isn't performing as expected", "Lanes", "Live", "MagSafe 3", "Monitor",
            "No problems seen while watching this cable.", "Not performing as expected",
            "PPS, %@ to %@ @ %@, %@ max", "Performing as expected", "Power Monitor",
            "Re-driver", "Re-timer", "Requested max operating power",
            "Requested operating power", "Requested output voltage",
            "SPR AVS, %@ at 15V / %@ at 20V",
            "Saw a brief drop or a single high reading. Not conclusive; still watching.",
            "Thunderbolt", "Thunderbolt / USB4", "Type %lld", "USB 2.0 (480 Mbps)",
            "USB 3.2 Gen 1 (5 Gbps)", "USB 3.2 Gen 2 (10 Gbps)", "USB Hub",
            "USB4 Gen 3 (20 / 40 Gbps)", "USB4 Gen 4 (80 Gbps)", "Variable, %@ to %@ @ %@",
            "Video", "WhatCable Pro", "adapter %lld", "via %lld hubs", "video",
        },
        "pl": {
            "OK",
            "%@ Port %lld", "%@ port %lld", "%lld displays connected", "%lld × %lld", "1-5 mW",
            "3 A", "5 A", "5-10 mW", "50-200 µW", "< 50 µW", "> 10 mW", "Alert",
            "Battery full, not drawing power", "Battery, %@ to %@, %@",
            "Built-in %1$@ port %2$lld",
            "Cable rated to %lldV / %@, delivers up to %lldW (USB-PD caps at 48V)",
            "E-marker reports passive, but carries active-cable structure (may be a mis-programmed e-marker)",
            "EPR AVS, %@ to %@, %@",
            "High-resolution displays often use compression (DSC) to fit their top mode through a link like this, so selecting the higher mode in Display settings may reach it normally.",
            "Host", "Isn't performing as expected", "MagSafe 3", "Monitor",
            "No problems seen while watching this cable.", "Not performing as expected",
            "PPS, %@ to %@ @ %@, %@ max", "Performing as expected", "Port", "Re-driver",
            "Re-timer", "Requested max operating power", "Requested operating power",
            "Requested output voltage", "SPR AVS, %@ at 15V / %@ at 20V",
            "Saw a brief drop or a single high reading. Not conclusive; still watching.",
            "Thunderbolt", "Thunderbolt / USB4", "USB 2.0 (480 Mbps)",
            "USB 3.2 Gen 1 (5 Gbps)", "USB 3.2 Gen 2 (10 Gbps)", "USB4 Gen 3 (20 / 40 Gbps)",
            "USB4 Gen 4 (80 Gbps)", "Variable, %@ to %@ @ %@", "WhatCable Pro", "adapter %lld",
        },
        "pt-BR": {
            "OK",
            "experimental",
            "%lld displays connected", "%lld × %lld", "1-5 mW", "3 A", "5 A", "5-10 mW",
            "50-200 µW", "< 50 µW", "> 10 mW", "Battery full, not drawing power",
            "Battery, %@ to %@, %@", "Built-in %1$@ port %2$lld",
            "Cable rated to %lldV / %@, delivers up to %lldW (USB-PD caps at 48V)",
            "E-marker reports passive, but carries active-cable structure (may be a mis-programmed e-marker)",
            "EPR AVS, %@ to %@, %@",
            "High-resolution displays often use compression (DSC) to fit their top mode through a link like this, so selecting the higher mode in Display settings may reach it normally.",
            "Host", "Isn't performing as expected", "MagSafe 3", "Monitor",
            "No problems seen while watching this cable.", "Not performing as expected",
            "PPS, %@ to %@ @ %@, %@ max", "Performing as expected", "Re-driver", "Re-timer",
            "Requested max operating power", "Requested operating power",
            "Requested output voltage", "SPR AVS, %@ at 15V / %@ at 20V",
            "Saw a brief drop or a single high reading. Not conclusive; still watching.",
            "Thunderbolt", "Thunderbolt / USB4", "USB 2.0 (480 Mbps)",
            "USB 3.2 Gen 1 (5 Gbps)", "USB 3.2 Gen 2 (10 Gbps)", "USB4 Gen 3 (20 / 40 Gbps)",
            "USB4 Gen 4 (80 Gbps)", "Variable, %@ to %@ @ %@", "WhatCable Pro",
            "via %lld hubs",
        },
        "ru": {
            "%lld displays connected", "%lld × %lld", "Built-in %1$@ port %2$lld",
            "High-resolution displays often use compression (DSC) to fit their top mode through a link like this, so selecting the higher mode in Display settings may reach it normally.",
            "MagSafe 3", "Thunderbolt", "Thunderbolt / USB4", "WhatCable Pro",
        },
        "tr": {
            "%@ Port %lld", "%lld displays connected", "%lld × %lld", "1-5 mW", "3 A", "5 A",
            "5-10 mW", "50-200 µW", "< 50 µW", "> 10 mW", "Battery full, not drawing power",
            "Battery, %@ to %@, %@", "Built-in %1$@ port %2$lld",
            "DisplayPort Alt Mode",
            "E-marker reports passive, but carries active-cable structure (may be a mis-programmed e-marker)",
            "EPR AVS, %@ to %@, %@",
            "High-resolution displays often use compression (DSC) to fit their top mode through a link like this, so selecting the higher mode in Display settings may reach it normally.",
            "Isn't performing as expected", "MagSafe 3",
            "No problems seen while watching this cable.", "Not performing as expected",
            "PPS, %@ to %@ @ %@, %@ max", "Performing as expected", "Port", "Re-driver",
            "Re-timer", "Requested max operating power", "Requested operating power",
            "Requested output voltage", "SPR AVS, %@ at 15V / %@ at 20V",
            "Saw a brief drop or a single high reading. Not conclusive; still watching.",
            "Thunderbolt", "Thunderbolt / USB4", "USB 2.0 (480 Mbps)",
            "USB 3.2 Gen 1 (5 Gbps)", "USB 3.2 Gen 2 (10 Gbps)", "USB Hub",
            "USB4 Gen 3 (20 / 40 Gbps)", "USB4 Gen 4 (80 Gbps)", "Variable, %@ to %@ @ %@",
            "Video", "WhatCable Pro", "video",
        },
        "uk": {
            "%lld displays connected", "%lld × %lld", "1-5 mW", "3 A", "5 A", "5-10 mW",
            "50-200 µW", "< 50 µW", "> 10 mW", "Battery full, not drawing power",
            "Battery, %@ to %@, %@", "Built-in %1$@ port %2$lld",
            "DisplayPort Alt Mode",
            "E-marker reports passive, but carries active-cable structure (may be a mis-programmed e-marker)",
            "EPR AVS, %@ to %@, %@",
            "High-resolution displays often use compression (DSC) to fit their top mode through a link like this, so selecting the higher mode in Display settings may reach it normally.",
            "Isn't performing as expected", "MagSafe 3",
            "No problems seen while watching this cable.", "Not performing as expected",
            "PPS, %@ to %@ @ %@, %@ max", "Performing as expected", "Power Monitor",
            "Re-driver", "Re-timer", "Requested max operating power",
            "Requested operating power", "Requested output voltage",
            "SPR AVS, %@ at 15V / %@ at 20V",
            "Saw a brief drop or a single high reading. Not conclusive; still watching.",
            "Thunderbolt", "Thunderbolt / USB4", "USB 2.0 (480 Mbps)",
            "USB 3.2 Gen 1 (5 Gbps)", "USB 3.2 Gen 2 (10 Gbps)", "USB Hub",
            "USB4 Gen 3 (20 / 40 Gbps)", "USB4 Gen 4 (80 Gbps)", "Variable, %@ to %@ @ %@",
            "WhatCable Pro",
        },
        "zh-Hans": {
            "%lld × %lld", "0.2-0.5 mW", "0.5-1 mW", "1-5 mW", "3 A", "5 A", "5-10 mW",
            "50-200 µW", "< 50 µW", "> 10 mW",
            "High-resolution displays often use compression (DSC) to fit their top mode through a link like this, so selecting the higher mode in Display settings may reach it normally.",
            "MagSafe 3", "Re-driver", "Re-timer", "Thunderbolt", "Thunderbolt / USB4",
            "WhatCable Pro",
        },
        "zh-Hant": {
            "%lld × %lld", "0.2-0.5 mW", "0.5-1 mW", "1-5 mW", "3 A", "5 A", "5-10 mW",
            "50-200 µW", "< 50 µW", "> 10 mW", "CC Advertisement", "DisplayPort Alt Mode",
            "Live", "MagSafe 3", "Product ID", "Product Type", "Raw VDOs", "Raw cable VDOs",
            "Re-driver", "Re-timer", "Source PDOs",
            "Thunderbolt", "Thunderbolt / USB4", "USB 2.0 (480 Mbps)",
            "USB 3.2 Gen 1 (5 Gbps)", "USB 3.2 Gen 2 (10 Gbps)", "USB Hub",
            "USB4 Gen 3 (20 / 40 Gbps)", "USB4 Gen 4 (80 Gbps)", "Vendor ID", "WhatCable Pro",
        },
    },
    "WhatCable (app)": {
        "de": {
            "Updates", "%lld displays connected", "Built-in %1$@ port %2$lld", "COMMUNITY",
            "Display connected", "Gen 1", "Host (%@)", "OK", "Pro", "SuperSpeed", "USB",
        },
        "es": {
            "%lld displays connected", "Built-in %1$@ port %2$lld", "Cable",
            "Cable, horizontal", "Display connected", "Gen 1", "Host (%@)", "No", "OK", "Pro",
            "SuperSpeed", "USB",
        },
        "fr": {
            "%lld displays connected", "Built-in %1$@ port %2$lld", "Direct",
            "Display connected", "Gen 1", "Notifications", "OK", "Pro", "SuperSpeed",
            "Transports", "USB",
        },
        "hi": {
            "%lld displays connected", "Built-in %1$@ port %2$lld", "Display connected",
            "Gen 1", "Pro", "SuperSpeed", "USB",
        },
        "hy": {
            "%lld displays connected", "Built-in %1$@ port %2$lld", "Display connected", "Pro",
            "SuperSpeed", "USB",
        },
        "it": {
            "Gen 1", "Host (%@)", "No", "OK", "Privacy", "Pro", "SuperSpeed", "USB",
        },
        "ja": {
            "%lld displays connected", "Built-in %1$@ port %2$lld", "Display connected",
            "Gen 1", "OK", "Pro", "SuperSpeed", "USB",
        },
        "ko": {
            "%lld displays connected", "Built-in %1$@ port %2$lld", "Display connected",
            "Gen 1", "Pro", "SuperSpeed", "USB",
        },
        "lv": {
            "%lld displays connected", "Built-in %1$@ port %2$lld", "Display connected", "Pro",
            "SuperSpeed", "USB",
        },
        "nb": {
            "%lld displays connected", "Built-in %1$@ port %2$lld", "Display connected",
            "Gen 1", "OK", "Pro", "SuperSpeed", "USB",
        },
        "nl": {
            "Updates", "%lld displays connected", "Built-in %1$@ port %2$lld", "COMMUNITY", "Direct",
            "Display connected", "Gen 1", "Host (%@)", "OK", "Privacy", "Pro", "SuperSpeed",
            "Thunderbolt fabric", "USB",
        },
        "pl": {
            "%lld displays connected", "Built-in %1$@ port %2$lld", "Display connected",
            "Gen 1", "Host (%@)", "OK", "Pro", "SuperSpeed", "USB", "USB Gen",
        },
        "pt-BR": {
            "%lld displays connected", "Built-in %1$@ port %2$lld", "Display connected",
            "Gen 1", "Host (%@)", "OK", "Pro", "SuperSpeed", "USB",
        },
        "ru": {
            "%lld displays connected", "Built-in %1$@ port %2$lld", "Display connected",
            "Gen 1", "Pro", "SuperSpeed", "USB",
        },
        "tr": {
            "%lld displays connected", "Built-in %1$@ port %2$lld", "Display connected", "Pro",
            "SuperSpeed", "Thunderbolt fabric", "USB",
        },
        "uk": {
            "Dock app", "Gen 1", "Pro", "SuperSpeed", "Thunderbolt fabric", "USB",
        },
        "zh-Hans": {
            "Pro", "SuperSpeed", "USB",
        },
        "zh-Hant": {
            "Gen 1", "Pro", "SuperSpeed", "USB", "USB Gen",
        },
    },
}


def scan_literal(text: str, start: int):
    """Read one plain Swift string literal beginning at `start` (just past
    the opening quote).

    Returns (normalised_key, index_after_closing_quote, hole_exprs), or
    (None, index, None) if the literal cannot be read reliably. `hole_exprs`
    is the raw Swift source text of every `\\(...)` interpolation in source
    order, kept so the specifier-inference pass (see infer_specifier) has
    something to look at.

    A regex cannot do this. Interpolations nest: `\\(label(for: x))` has
    balanced parentheses, and `\\(a.joined(separator: ", "))` contains a quote
    that is NOT the end of the literal. The first version of this script used
    a regex and mis-parsed 8 of the 30 strings it flagged, which is exactly
    the kind of noise that makes a check untrustworthy.
    """
    out = []
    holes = []
    i = start
    n = len(text)
    while i < n:
        c = text[i]
        if c == "\\":
            if i + 1 < n and text[i + 1] == "(":
                # Interpolation: skip to the matching close paren, respecting
                # nested parens and nested string literals.
                expr_start = i + 2
                depth = 0
                i += 1
                while i < n:
                    ch = text[i]
                    if ch == '"':
                        i += 1
                        while i < n and text[i] != '"':
                            i += 2 if text[i] == "\\" else 1
                    elif ch == "(":
                        depth += 1
                    elif ch == ")":
                        depth -= 1
                        if depth == 0:
                            break
                    i += 1
                if i >= n:
                    return None, i, None
                holes.append(text[expr_start:i])
                out.append(HOLE)
                i += 1
                continue
            # Unicode escape: \u{00B7} is the character it denotes, and the
            # catalogue key contains that character, not the escape text.
            if text.startswith("\\u{", i):
                close = text.find("}", i)
                if close == -1:
                    return None, i, None
                try:
                    out.append(chr(int(text[i + 3:close], 16)))
                except ValueError:
                    return None, i, None
                i = close + 1
                continue
            # Ordinary escape.
            if i + 1 >= n:
                return None, i, None
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(text[i + 1], text[i + 1]))
            i += 2
            continue
        if c == '"':
            return "".join(out), i + 1, holes
        out.append(c)
        i += 1
    return None, i, None


def scan_raw_literal(text: str, start: int, hashes: int):
    """Read a raw string literal's body: `#"..."#` or `##"..."##`.

    Raw strings turn escaping off: a bare backslash is just a backslash, and
    the only way to interpolate is `\\#(...)` with the SAME number of `#` as
    the delimiter. The terminator is `"` followed by that many `#`. Without
    this, `String(localized: #"Uncatalogued"#)` doesn't match CALL_RE's old
    "quote right after localized:" assumption at all and is skipped in
    silence, which is finding 2: an unparseable literal should fail loudly,
    not vanish.
    """
    out = []
    holes = []
    i = start
    n = len(text)
    interp_prefix = "\\" + "#" * hashes + "("
    close_seq = '"' + "#" * hashes
    while i < n:
        if text.startswith(interp_prefix, i):
            expr_start = i + len(interp_prefix)
            depth = 0
            i += len(interp_prefix) - 1
            while i < n:
                ch = text[i]
                if ch == '"':
                    i += 1
                    while i < n and text[i] != '"':
                        i += 2 if text[i] == "\\" else 1
                elif ch == "(":
                    depth += 1
                elif ch == ")":
                    depth -= 1
                    if depth == 0:
                        break
                i += 1
            if i >= n:
                return None, i, None
            holes.append(text[expr_start:i])
            out.append(HOLE)
            i += 1
            continue
        if text.startswith(close_seq, i):
            return "".join(out), i + len(close_seq), holes
        out.append(text[i])
        i += 1
    return None, i, None


def scan_triple_quoted_literal(text: str, start: int):
    """Read a Swift multi-line string literal's body: `\"\"\"...\"\"\"`.

    Escapes and interpolation work the same as a plain literal; only the
    terminator changes (three quotes, and a bare `"` inside is legal text).
    Swift also applies two source-level rules before any escape processing:
    a newline immediately after the opening delimiter and one immediately
    before the closing delimiter are both dropped, and if the line holding
    the closing `\"\"\"` is pure whitespace, that whitespace is stripped from
    the start of every other line (so the literal can be indented to match
    the surrounding code without that indentation ending up in the string).

    This only needs to be right for existence-checking against the
    catalogue, not for exact runtime reproduction, so it does not attempt
    every corner of the Swift grammar (an escaped literal `\"\"\"` inside an
    interpolation's own nested string literal is one gap); anything it can't
    place a matching terminator for is reported as unparseable, per finding
    2, rather than guessed at.
    """
    i = start
    n = len(text)
    end = None
    while i < n:
        c = text[i]
        if c == "\\" and i + 1 < n and text[i + 1] == "(":
            depth = 0
            i += 1
            while i < n:
                ch = text[i]
                if ch == '"':
                    i += 1
                    while i < n and text[i] != '"':
                        i += 2 if text[i] == "\\" else 1
                elif ch == "(":
                    depth += 1
                elif ch == ")":
                    depth -= 1
                    if depth == 0:
                        break
                i += 1
            i += 1
            continue
        if c == "\\" and i + 1 < n:
            i += 2
            continue
        if text[i:i + 3] == '"""':
            end = i
            break
        i += 1
    if end is None:
        return None, i, None

    raw = text[start:end]

    # Dedent: only if the line holding the closing delimiter is pure
    # whitespace (that's Swift's own rule for when indentation is "part of
    # the literal's formatting" rather than "part of the string").
    line_start = text.rfind("\n", 0, end) + 1
    indent = text[line_start:end]
    if indent.strip() == "" and indent:
        lines = raw.split("\n")
        if len(lines) > 1:
            lines = [lines[0]] + [
                ln[len(indent):] if ln.startswith(indent) else ln for ln in lines[1:]
            ]
            raw = "\n".join(lines)

    if raw.startswith("\r\n"):
        raw = raw[2:]
    elif raw.startswith("\n"):
        raw = raw[1:]
    if raw.endswith("\n"):
        raw = raw[:-1]

    # Process escapes/interpolation on the dedented body. A bare `"` is legal
    # text here (unlike scan_literal, it is not a terminator), so this walks
    # to the end of `raw` rather than stopping at the first quote.
    out = []
    holes = []
    i = 0
    m = len(raw)
    while i < m:
        c = raw[i]
        if c == "\\":
            if i + 1 < m and raw[i + 1] == "(":
                expr_start = i + 2
                depth = 0
                i += 1
                while i < m:
                    ch = raw[i]
                    if ch == '"':
                        i += 1
                        while i < m and raw[i] != '"':
                            i += 2 if raw[i] == "\\" else 1
                    elif ch == "(":
                        depth += 1
                    elif ch == ")":
                        depth -= 1
                        if depth == 0:
                            break
                    i += 1
                if i >= m:
                    return None, end + 3, None
                holes.append(raw[expr_start:i])
                out.append(HOLE)
                i += 1
                continue
            if raw.startswith("\\u{", i):
                close = raw.find("}", i)
                if close == -1:
                    return None, end + 3, None
                try:
                    out.append(chr(int(raw[i + 3:close], 16)))
                except ValueError:
                    return None, end + 3, None
                i = close + 1
                continue
            if i + 1 >= m:
                return None, end + 3, None
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(raw[i + 1], raw[i + 1]))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out), end + 3, holes


def scan_call_literal(content: str, pos: int):
    """Detect and read whichever literal form follows `localized:` at `pos`:
    plain (`"..."`), raw (`#"..."#`, `##"..."##`, ...), or triple-quoted
    (`\"\"\"...\"\"\"`).

    Returns (key, end_index, holes). If `pos` isn't the start of any
    recognised literal (e.g. a variable was passed instead of a literal,
    which is a legitimate, different usage this check has no opinion on),
    returns (None, pos, "not-a-literal") so the caller can tell "nothing to
    check here" apart from "found a literal but couldn't read it".
    """
    i = pos
    n = len(content)
    while i < n and content[i] in " \t":
        i += 1
    hashes = 0
    while i + hashes < n and content[i + hashes] == "#":
        hashes += 1
    j = i + hashes
    if hashes == 0 and content[j:j + 3] == '"""':
        key, end, holes = scan_triple_quoted_literal(content, j + 3)
        return (key, end, holes) if key is not None else (None, end, None)
    if content[j:j + 1] == '"':
        if hashes == 0:
            key, end, holes = scan_literal(content, j + 1)
        else:
            key, end, holes = scan_raw_literal(content, j + 1, hashes)
        return (key, end, holes) if key is not None else (None, end, None)
    return None, pos, "not-a-literal"


def find_call_bundle(content: str, start: int):
    """From just after a literal closes, walk to the end of the enclosing
    `String(...)` call (we're inside one open paren already) and return
    (bundle_expr_or_None, index_after_close_paren). Only looks at the
    top-level argument list, so it can't be fooled by a `bundle:`-shaped
    substring buried inside some other argument's own parentheses.
    """
    n = len(content)
    depth = 1
    bundle_expr = None
    i = start
    while i < n and depth > 0:
        c = content[i]
        if c == '"':
            i += 1
            while i < n and content[i] != '"':
                i += 2 if content[i] == "\\" else 1
            i += 1
            continue
        if c == "(":
            depth += 1
            i += 1
            continue
        if c == ")":
            depth -= 1
            i += 1
            continue
        if depth == 1 and bundle_expr is None and content.startswith("bundle:", i):
            j = i + len("bundle:")
            while j < n and content[j] in " \t\n":
                j += 1
            m = re.match(r"[A-Za-z_][\w.]*", content[j:])
            if m:
                bundle_expr = m.group(0)
            i = j
            continue
        i += 1
    return bundle_expr, i


FUNC_RE = re.compile(r"\bfunc\s+([A-Za-z_]\w*)\s*[<(]")


def enclosing_func_name(content: str, idx: int):
    """Best-effort "which function is this call inside" by taking the last
    `func` declaration found before `idx`. Good enough for this codebase's
    shape (no closures that redeclare `func`); if it's ever wrong the
    downstream passthrough resolution just fails to find a match and this
    check fails loudly asking for a human look, rather than guessing.
    """
    name = None
    for m in FUNC_RE.finditer(content, 0, idx):
        name = m.group(1)
    return name


GLOBAL_BUNDLES = {expr: target for expr, (target, _resources) in CATALOGUES.items()}


def resolve_bundle(expr, content, idx, all_contents, depth=0):
    """Which catalogue target(s) does this `bundle:` argument ultimately
    point at?

    Most calls pass one of the two global bundle constants directly. Two
    functions in Core (ActiveTunnelPresentation.lines and
    USBDevice.billboardPresenceLabel) take a `bundle: Bundle` parameter
    instead and forward it, and are called with EITHER global depending on
    the caller (billboardPresenceLabel is called from Core's own
    TextFormatter with _coreLocalizedBundle AND from the app's ContentView
    with _appLocalizedBundle), so a literal defined inside one of those
    functions can legitimately need to exist in both catalogues.

    This resolves a passthrough by finding the enclosing function and
    tracing ITS callers for their own `bundle:` argument, recursively, up to
    a small depth. If it can't find a caller, or the chain is deeper than
    that, it returns an error string instead of guessing: silently treating
    an unresolvable bundle as "must be one specific catalogue" is exactly
    the kind of guess that hid the original bugs.
    """
    if expr in GLOBAL_BUNDLES:
        return {GLOBAL_BUNDLES[expr]}, None
    if depth >= 3:
        return None, f"bundle argument '{expr}' is passed through more levels than this check follows"
    func_name = enclosing_func_name(content, idx)
    if not func_name:
        return None, f"bundle argument '{expr}' is not one of the known globals, and no enclosing function was found to trace its callers"

    call_pattern = re.compile(r"\b" + re.escape(func_name) + r"\s*\(")
    resolved = set()
    found_caller = False
    for other_path, other_content in all_contents.items():
        for m in call_pattern.finditer(other_content):
            line_start = other_content.rfind("\n", 0, m.start()) + 1
            prefix = other_content[line_start:m.start()]
            if re.search(r"\bfunc\s*$", prefix):
                continue  # this is the declaration, not a call
            bundle_expr, _ = find_call_bundle(other_content, m.end())
            if bundle_expr is None:
                continue
            found_caller = True
            sub, err = resolve_bundle(bundle_expr, other_content, m.end(), all_contents, depth + 1)
            if err:
                return None, err
            resolved |= sub
    if not found_caller:
        return None, f"could not find any caller of '{func_name}(...)' that passes bundle:, so the target catalogue for this literal can't be determined"
    return resolved, None


def localized_calls(path, content, all_contents, failures):
    """Yield (target, key, holes) for every String(localized:) call in
    `content` that resolves cleanly. Anything that can't be read or
    classified is appended to `failures` with the file and line, per
    finding 2: a call this script can't understand is a defect in the
    check, not something to skip past.
    """
    rel = os.path.relpath(path, REPO)
    for m in CALL_RE.finditer(content):
        key, end, holes = scan_call_literal(content, m.end())
        if holes == "not-a-literal":
            continue  # a variable was passed, not a literal; nothing to check
        if key is None:
            line = content.count("\n", 0, m.start()) + 1
            failures.append(
                f"{rel}:{line}: a String(localized:) literal here could not be parsed "
                "(unterminated string, or a form this scanner doesn't support). "
                "Fix the literal, or extend scan_call_literal if it's valid Swift."
            )
            continue
        bundle_expr, call_end = find_call_bundle(content, end)
        if bundle_expr is None:
            line = content.count("\n", 0, m.start()) + 1
            failures.append(
                f"{rel}:{line}: String(localized: \"...\") has no bundle: argument this "
                "check can read, so it can't tell which catalogue must contain it."
            )
            continue
        targets, err = resolve_bundle(bundle_expr, content, end, all_contents)
        if err:
            line = content.count("\n", 0, m.start()) + 1
            failures.append(f"{rel}:{line}: {err}")
            continue
        for target in targets:
            yield target, key, holes


# --- Finding 5: %@ vs %lld are not interchangeable ---------------------------
#
# The old key_pattern accepted ANY of %@ / %lld / positional forms in every
# hole, so a String argument was silently satisfied by a catalogue entry that
# only had %lld. String(localized:) resolves that at runtime by matching the
# INTERPOLATED ARGUMENT'S TYPE against the catalogue's format specifiers; a
# mismatch means the lookup misses and the English literal shows, which is
# the exact failure mode this whole script exists to catch.
#
# This does not attempt full type inference (that needs the Swift compiler,
# not a text scanner). It only recognises a few shapes where the type is
# obvious from the source text alone:
#   - an integer literal, or a `.count` property access          -> Int
#   - a string literal, or `.joined(separator:` (always String)  -> String
#   - a call to a function this repo declares as `-> String`     -> String
# Anything else falls back to the old permissive pattern (accept either),
# same as before this fix, so this can't introduce a false failure on an
# expression it has no way to classify. What it does add, unconditionally: if
# a literal's pattern matches MORE THAN ONE catalogue key, that's reported as
# an ambiguity regardless of whether inference fired, because two catalogue
# entries only differing by specifier for the same shape is itself a defect.
SPEC_PATTERNS = {
    "int": r"(?:%lld|%\d+\$lld)",
    "string": r"(?:%@|%\d+\$@)",
}
GENERIC_HOLE_PATTERN = r"(?:%lld|%@|%\d+\$@|%\d+\$lld)"

STRING_LITERAL_RE = re.compile(r'^"(?:[^"\\]|\\.)*"$')
INT_LITERAL_RE = re.compile(r"^-?\d+$")
FUNC_RETURN_STRING_RE = re.compile(r"\bfunc\s+([A-Za-z_]\w*)\s*\([^()]*\)\s*->\s*String\b")
CALL_HEAD_RE = re.compile(r"^(?:[A-Za-z_]\w*\.)*([A-Za-z_]\w*)\(")


def build_string_returning_funcs(all_contents):
    names = set()
    for content in all_contents.values():
        for m in FUNC_RETURN_STRING_RE.finditer(content):
            names.add(m.group(1))
    return names


def infer_specifier(expr: str, string_returning_funcs):
    """Return "int", "string", or None (can't tell) for one interpolation's
    Swift source text. See the module comment above this for what this is
    and isn't allowed to guess.
    """
    e = expr.strip()
    if INT_LITERAL_RE.match(e):
        return "int"
    if STRING_LITERAL_RE.match(e):
        return "string"
    if e.endswith(".count"):
        return "int"
    if ".joined(" in e:
        return "string"
    m = CALL_HEAD_RE.match(e)
    if m and m.group(1) in string_returning_funcs:
        return "string"
    return None


def key_pattern(normalised: str, holes, string_returning_funcs) -> re.Pattern:
    parts = [re.escape(p) for p in normalised.split(HOLE)]
    pattern = parts[0]
    for expr, part in zip(holes, parts[1:]):
        spec = infer_specifier(expr, string_returning_funcs)
        pattern += SPEC_PATTERNS.get(spec, GENERIC_HOLE_PATTERN) + part
    return re.compile("^" + pattern + "$")


def strings_kv(path: str) -> dict:
    """Key -> value for a .strings file (finding 4 needs values, not just
    keys, to catch a translation that's present but wrong)."""
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as f:
        text = f.read()
    return {
        m.group(1): m.group(2)
        for m in re.finditer(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', text, re.M)
    }


def strings_keys(path: str) -> set:
    return set(strings_kv(path).keys())


def stringsdict_dict(path: str) -> dict:
    if not os.path.exists(path):
        return {}
    with open(path, "rb") as f:
        return plistlib.load(f)


def stringsdict_keys(path: str) -> set:
    return set(stringsdict_dict(path).keys())


def languages(resources: str) -> list:
    root = os.path.join(REPO, resources)
    if not os.path.isdir(root):
        return []
    return sorted(d[:-6] for d in os.listdir(root) if d.endswith(".lproj"))


def swift_files_all():
    root = os.path.join(REPO, "Sources")
    for dirpath, dirnames, filenames in os.walk(root):
        # Don't descend into a catalogue's own resources.
        dirnames[:] = [d for d in dirnames if d != "Resources"]
        for name in filenames:
            if name.endswith(".swift"):
                yield os.path.join(dirpath, name)


VAR_REF_RE = re.compile(r"%#@(\w+)@")

# Finding 7: the numeric alternatives all need a `\b` after them so `%d`
# doesn't also match the start of some longer identifier-looking text, but
# `%@` isn't a word character on either side, so a trailing `\b` after it
# would fail to match the common case of `%@` followed by a space or the end
# of the string. The two shapes are kept as separate alternatives (each with
# the boundary check that's actually correct for it) rather than forcing one
# `\b` rule onto both.
SPECIFIER_RE = re.compile(r"%(?:\d+\$)?(?:(lld|llu|ld|lu|d|u|f)\b|(@))")


def check_stringsdict_structure(target, lang, path, failures):
    """Finding 4(a): a .stringsdict entry that exists (so the key-parity
    check above is happy) can still be structurally broken in a way that
    shows the raw key at runtime for that one language: a plural variable
    referenced in the format key but never defined, a value type that
    doesn't match what the plural strings actually use, or a language
    missing one of the plural categories its own grammar requires. None of
    that shows up by comparing key sets, which is all the old parity loop
    did.
    """
    d = stringsdict_dict(path)
    required = REQUIRED_PLURAL_CATEGORIES.get(lang)
    for key, entry in d.items():
        if not isinstance(entry, dict):
            failures.append(f"{target}: {lang}.stringsdict entry '{key}' is not a dictionary")
            continue
        fmt = entry.get("NSStringLocalizedFormatKey")
        if not fmt:
            failures.append(f"{target}: {lang}.stringsdict entry '{key}' has no NSStringLocalizedFormatKey")
            continue
        varnames = VAR_REF_RE.findall(fmt)
        if not varnames:
            failures.append(
                f"{target}: {lang}.stringsdict entry '{key}' has a format key "
                f"'{fmt}' that references no %#@variable@, so it can't be a plural entry"
            )
            continue
        for varname in varnames:
            vardict = entry.get(varname)
            if not isinstance(vardict, dict):
                failures.append(
                    f"{target}: {lang}.stringsdict entry '{key}' references variable "
                    f"'{varname}' in its format key but has no matching sub-dictionary"
                )
                continue
            spec_type = vardict.get("NSStringFormatSpecTypeKey")
            if spec_type != "NSStringPluralRuleType":
                failures.append(
                    f"{target}: {lang}.stringsdict entry '{key}' variable '{varname}' has "
                    f"NSStringFormatSpecTypeKey={spec_type!r}, expected 'NSStringPluralRuleType'"
                )
            vt = vardict.get("NSStringFormatValueTypeKey")
            if not vt:
                failures.append(
                    f"{target}: {lang}.stringsdict entry '{key}' variable '{varname}' has no "
                    "NSStringFormatValueTypeKey"
                )

            cats = {
                k: v for k, v in vardict.items()
                if k not in ("NSStringFormatSpecTypeKey", "NSStringFormatValueTypeKey")
            }
            if vt:
                for cat, val in cats.items():
                    if not isinstance(val, str):
                        continue
                    # SPECIFIER_RE has two capture groups (letter specifiers,
                    # then `@`); exactly one is populated per match, so flatten
                    # them into one set of found specifiers.
                    specs_found = {a or b for a, b in SPECIFIER_RE.findall(val)}
                    if specs_found and vt not in specs_found:
                        failures.append(
                            f"{target}: {lang}.stringsdict entry '{key}' variable '{varname}' "
                            f"category '{cat}' uses %{sorted(specs_found)[0]} but "
                            f"NSStringFormatValueTypeKey says '{vt}'"
                        )

            if required is not None:
                missing_cats = required - set(cats.keys())
                if missing_cats:
                    failures.append(
                        f"{target}: {lang}.stringsdict entry '{key}' variable '{varname}' is "
                        f"missing required plural categor{'y' if len(missing_cats) == 1 else 'ies'} "
                        f"{sorted(missing_cats)} for '{lang}'"
                    )


def main() -> int:
    failures = []
    checked_strings = 0
    baseline_counts = {target: {} for target in KNOWN_MISSING}
    identical_flagged = {target: set() for target in ALLOWED_IDENTICAL}

    # --- 0. Read every Swift source file once. Extraction now spans all of
    # Sources/, not just two hand-picked directories (finding 1), because
    # classification is by `bundle:` argument, not by source location.
    all_contents = {}
    for path in swift_files_all():
        with open(path, encoding="utf-8") as f:
            all_contents[path] = f.read()

    string_returning_funcs = build_string_returning_funcs(all_contents)

    # --- A. every literal resolves in the catalogue(s) its bundle points at
    per_target_calls = {target: [] for target, _res in CATALOGUES.values()}
    for path, content in all_contents.items():
        for target, key, holes in localized_calls(path, content, all_contents, failures):
            per_target_calls[target].append((path, key, holes))

    for bundle_const, (target, resources) in CATALOGUES.items():
        # --- Finding 3: assert the expected locale set explicitly, rather
        # than trusting whatever .lproj directories happen to exist. A
        # deleted language leaves the rest agreeing with each other, and the
        # old languages()-only approach called that a pass.
        found_langs = set(languages(resources))
        missing_langs = set(EXPECTED_LANGUAGES) - found_langs
        extra_langs = found_langs - set(EXPECTED_LANGUAGES)
        if missing_langs or extra_langs:
            detail = []
            if missing_langs:
                detail.append(f"missing {sorted(missing_langs)}")
            if extra_langs:
                detail.append(f"unexpected {sorted(extra_langs)} (add to EXPECTED_LANGUAGES if intentional)")
            failures.append(f"{target}: locale set under {resources} does not match EXPECTED_LANGUAGES: " + "; ".join(detail))

        langs = languages(resources)
        if not langs:
            failures.append(f"{target}: no .lproj directories found under {resources}")
            continue
        if BASE_LANG not in langs:
            failures.append(f"{target}: no {BASE_LANG}.lproj")
            continue

        def catalogue(lang, resources=resources):
            base = os.path.join(REPO, resources, f"{lang}.lproj")
            return (
                strings_kv(os.path.join(base, "Localizable.strings")),
                stringsdict_dict(os.path.join(base, "Localizable.stringsdict")),
            )

        en_strings_kv, en_dict = catalogue(BASE_LANG)
        en_strings = set(en_strings_kv.keys())
        en_all = en_strings | set(en_dict.keys())

        for path, norm, holes in per_target_calls[target]:
            checked_strings += 1
            rel = os.path.relpath(path, REPO)
            resolved = False
            if HOLE in norm:
                pattern = key_pattern(norm, holes, string_returning_funcs)
                matches = [k for k in en_all if pattern.match(k)]
                if len(matches) > 1:
                    display = norm.replace(HOLE, "\\(...)")
                    failures.append(
                        f'{target}: "{display}" used in {rel} matches '
                        f"{len(matches)} different catalogue keys ({sorted(matches)}), which is "
                        f"ambiguous, not a pass"
                    )
                    resolved = True  # already reported; don't also report as missing
                elif len(matches) == 1:
                    resolved = True
            elif norm in en_all:
                resolved = True

            if resolved:
                continue

            baseline_key = (rel, norm)
            expected = KNOWN_MISSING.get(target, {}).get(baseline_key)
            if expected is not None:
                seen = baseline_counts[target].get(baseline_key, 0) + 1
                baseline_counts[target][baseline_key] = seen
                if seen <= expected:
                    continue  # within the ratchet's expected count, suppressed
                # finding 6: an occurrence beyond what the baseline expects
                # (moved, duplicated, or newly added) does not inherit the
                # exemption, and fails on its own.
                shown = norm.replace(HOLE, "\\(...)")
                failures.append(
                    f'{target}: "{shown}" in {rel} occurs {seen} times but KNOWN_MISSING only '
                    f"expects {expected}; update the baseline count if this is a genuine new occurrence"
                )
                continue

            shown = norm.replace(HOLE, "\\(...)")
            failures.append(
                f'{target}: "{shown}" used in {rel} but missing from '
                f"{BASE_LANG}.lproj (this is how an untranslated string ships: "
                f"String(localized:) falls back to the literal, so English looks fine)"
            )

        # --- B. every language matches English, in both file types, with
        # translated (not just present) values.
        for lang in langs:
            if lang == BASE_LANG:
                continue
            lang_strings_kv, lang_dict = catalogue(lang)
            lang_strings = set(lang_strings_kv.keys())

            for kind, en_keys, lang_keys in (
                (".strings", en_strings, lang_strings),
                (".stringsdict", set(en_dict.keys()), set(lang_dict.keys())),
            ):
                missing = en_keys - lang_keys
                extra = lang_keys - en_keys
                if missing:
                    failures.append(
                        f"{target}: {lang}{kind} missing {len(missing)} key(s): "
                        + ", ".join(f'"{k}"' for k in sorted(missing)[:4])
                        + (" ..." if len(missing) > 4 else "")
                    )
                extra -= KNOWN_EXTRA.get((target, lang, kind), set())
                if extra:
                    failures.append(
                        f"{target}: {lang}{kind} has {len(extra)} key(s) not in {BASE_LANG}: "
                        + ", ".join(f'"{k}"' for k in sorted(extra)[:4])
                        + (" ..." if len(extra) > 4 else "")
                    )

            # Finding 4(b): a key that exists in both languages but has the
            # exact same value as English is what an untranslated (or
            # half-translated) string looks like. Ratcheted (see
            # ALLOWED_IDENTICAL above) because a large, legitimate share of
            # the corpus is unit symbols, loanwords, and product names.
            # Finding 8: fetched per (target, lang), not just target, so an
            # amnesty seeded for one language's loanword can't cover a
            # regression in a different language.
            allowed = ALLOWED_IDENTICAL.get(target, {}).get(lang, set())
            for k in en_strings & lang_strings:
                if en_strings_kv.get(k) == lang_strings_kv.get(k):
                    if k in allowed:
                        identical_flagged.setdefault(target, set()).add(k)
                        continue
                    failures.append(
                        f'{target}: {lang}.strings "{k}" has the same value as English '
                        f'("{en_strings_kv[k]}"), which looks untranslated'
                    )

            # Same check for stringsdict leaf plural values.
            for k in set(en_dict.keys()) & set(lang_dict.keys()):
                en_entry = en_dict.get(k, {})
                lang_entry = lang_dict.get(k, {})
                if not isinstance(en_entry, dict) or not isinstance(lang_entry, dict):
                    continue
                for varname, en_vardict in en_entry.items():
                    if varname == "NSStringLocalizedFormatKey" or not isinstance(en_vardict, dict):
                        continue
                    lang_vardict = lang_entry.get(varname, {})
                    if not isinstance(lang_vardict, dict):
                        continue
                    for cat, en_val in en_vardict.items():
                        if cat in ("NSStringFormatSpecTypeKey", "NSStringFormatValueTypeKey"):
                            continue
                        lang_val = lang_vardict.get(cat)
                        if lang_val is not None and lang_val == en_val:
                            if k in allowed:
                                identical_flagged.setdefault(target, set()).add(k)
                                continue
                            failures.append(
                                f'{target}: {lang}.stringsdict "{k}" category "{cat}" has the '
                                f'same value as English ("{en_val}"), which looks untranslated'
                            )

            # Finding 4(a): structural validation, independent of parity.
            dict_path = os.path.join(REPO, resources, f"{lang}.lproj", "Localizable.stringsdict")
            check_stringsdict_structure(target, lang, dict_path, failures)

        en_dict_path = os.path.join(REPO, resources, f"{BASE_LANG}.lproj", "Localizable.stringsdict")
        check_stringsdict_structure(target, BASE_LANG, en_dict_path, failures)

    # Ratchet: anything in the baseline that no longer reproduces (at all, or
    # at its expected count) must be deleted or corrected, or the backlog
    # silently becomes permanent.
    for target, entries in KNOWN_MISSING.items():
        for baseline_key, expected in entries.items():
            seen = baseline_counts.get(target, {}).get(baseline_key, 0)
            if seen < expected:
                rel, key = baseline_key
                shown = key.replace(HOLE, "\\(...)")
                failures.append(
                    f'{target}: "{shown}" in {rel} is in KNOWN_MISSING expecting {expected} '
                    f"occurrence(s) but only {seen} still reproduce(s). Delete or correct the "
                    f"entry in {os.path.basename(__file__)}."
                )

    if failures:
        print("  localisation coverage FAILED\n")
        for f in failures:
            print(f"    - {f}")
        print(f"\n  ({checked_strings} String(localized:) literals checked)")
        return 1

    baseline_total = sum(len(v) for v in KNOWN_MISSING.values())
    print(
        f"  {checked_strings} localised literals resolve; all languages at parity"
        f" ({baseline_total} known gaps held in the baseline)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
