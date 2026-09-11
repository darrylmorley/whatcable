#!/usr/bin/env python3
"""Fail when an IOKit class name is read from more than one file without a reason.

WHY NOT A BLANKET RULE. The obvious invariant, "one file per IOKit class name",
is the wrong one. It has two ways to be satisfied and only one of them is
progress: either you merge two lists that differ on purpose (deciding a
behaviour question by fiat to shut a script up), or you carve out an exception
and the rule stops meaning anything. `AppleHPMInterfaceWatcher` matching the
`IOPort` superclass while the telemetry reader does not is exactly that case:
a real, deliberate, undecided difference.

So this gates the SPECIFIC duplicates that exist today, each with a written
reason, and refuses to let the set grow. It is a ratchet, not a rule.

Two ways to fail, both loud:

  NEW      a class name appears in more than one file and is not in ALLOWED.
           Someone added a second reader for something already read elsewhere.

  STALE    an ALLOWED entry no longer matches what is on disk. The duplicate
           was resolved (good) but the exemption was left behind (not good),
           so the next one to appear would be waved through by a stale entry.
           The script names the exact line to delete. Same mechanic
           `check-localisation.py` already uses for its known-missing list.

Scope note: the class-name check looks for IOKit-class-SHAPED string literals
(`IO...` / `Apple...`) anywhere in Sources, not just inside
`IOServiceMatching(...)`. That is on purpose and was measured: several watchers
hold their class names in an array and pass them to `IOServiceMatching` in a
loop, so a scan anchored on the call site finds 7 classes and 0 duplicates,
while the literal scan finds 58 and 17. The narrow version looked clean and was
simply not looking.

A literal scan has its own blind spot, and it was demonstrated rather than
imagined: a reviewer added a file containing

    let cls = "Apple" + "SmartBattery"
    return IOServiceMatching(cls)

which is a genuine second reader of a class this very script was written to
keep singular, and the first version of the script did not notice the file
existed. Neither fragment matches the pattern on its own. That is not a
contrived example either: this codebase already numbers its classes
(`AppleHPMInterfaceType10/11/12/18`), so `"AppleHPMInterfaceType" + String(n)`
is a plausible way to write the next one.

So there is a second check. Every argument passed to `IOServiceMatching` /
`IOServiceNameMatching` that is NOT a bare string literal is a computed
matcher, and the (file, expression) pairs are ratcheted the same way. A new
file that matches services dynamically fails until someone writes down why.

What neither check covers, stated so a green run is not read as more than it
is:

  - Two readers of the same class inside ONE file. A per-file ratchet cannot
    see that by construction.
  - A matcher argument written as a Swift multi-line string literal (three
    consecutive quote characters). The scanner toggles its in-string state per
    quote character and treats those three as three separate delimiters, so an
    odd number of embedded quotes desyncs it and the captured text is wrong. It
    still FAILS LOUDLY in that case, because the argument is not a bare literal
    and the file gets flagged either way, which is the safe direction; it just
    reports the wrong text in the message. No IOKit class name would ever be
    written that way, and Sources contains no such call today.
"""

import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = os.path.join(ROOT, "Sources")

# An IOKit class name as a string literal. Three or more trailing characters so
# short unrelated strings like "IO" or "Apple" do not qualify.
LITERAL = re.compile(r'"((?:IO|Apple)[A-Za-z0-9_]{3,})"')

# Where a service-matcher call starts. The argument itself is read by
# `matcher_argument` below rather than by this pattern, because a regex cannot
# balance parentheses and the first attempt here stopped at the first comma or
# close paren. That was not merely imprecise: an argument CONTAINING a comma,
# such as any two-parameter class-name builder, failed to match the call at all,
# so the whole file went unseen rather than being flagged as unrecognised. A
# reviewer proved it with `IOServiceMatching(buildClassName("Apple", "SmartBattery"))`,
# which is a real second reader and produced a completely clean run.
MATCHER_CALL_START = re.compile(r'IOService(?:Name)?Matching\(')
BARE_LITERAL_ARG = re.compile(r'^"(?:IO|Apple)[A-Za-z0-9_]{3,}"$')

# Files that pass something other than a bare string literal to a service
# matcher, with the expression they pass and why it is fine.
#
# Every one of these is a loop over a named class list, which is the shape this
# consolidation was aiming for. A NEW entry means someone is computing a class
# name, and that needs a human to look at it.
DYNAMIC_MATCHERS = {
    "WhatCableDarwinBackend/Reading/AppleSmartBatteryReader.swift": (
        {"serviceClassName"},
        "The one owner of the AppleSmartBattery class name, held as a private constant.",
    ),
    "WhatCableDarwinBackend/Watchers/AppleHPMInterfaceWatcher.swift": (
        {"cls"},
        "Loops over candidateClasses (the shared named list plus the IOPort catch-all).",
    ),
    "WhatCableDarwinBackend/Services/PowerService.swift": (
        {"cls"},
        "Loops over HPMPortControllerClasses.named. Was "
        "Watchers/PowerTelemetryWatcher.swift until it was renamed to what it "
        "always was; the ratchet fired on both halves of that move, which is "
        "the intended cost of keying exemptions to a path.",
    ),
    "WhatCableDarwinBackend/Watchers/AppleTypeCPhyWatcher.swift": (
        {"cls"},
        "Loops over its own candidate class list.",
    ),
    "WhatCableDarwinBackend/Watchers/TRMTransportWatcher.swift": (
        {"cls"},
        "Loops over the four transport-state classes. Splitting this watcher is step 4 of the layering refactor.",
    ),
    "WhatCableDarwinBackend/Watchers/USBPDSOPWatcher.swift": (
        {"className", "Self.stateCCClassName"},
        "Loops over the SOP class list (className). Merging with VDMIdentityWatcher "
        "is step 5. `Self.stateCCClassName` (issue #573 part 2) is IOPortTransportStateCC, "
        "the class carrying a MagSafe cable's chip VID/PID -- a held constant, not a "
        "loop, and no other reader in Sources matches this class (checked 2026-08-31).",
    ),
    "WhatCableDarwinBackend/Watchers/VDMIdentityWatcher.swift": (
        {"className"},
        "Loops over the SOP class list. Merging with USBPDSOPWatcher is step 5.",
    ),
    "WhatCableDarwinBackend/Watchers/IOThunderboltSwitchWatcher.swift": (
        {"className", "matchClassName"},
        "Walks the IOThunderboltSwitch class hierarchy, whose concrete name varies by silicon generation.",
    ),
    "WhatCableDarwinBackend/Debug/ThunderboltProbe.swift": (
        {"matchClassName"},
        "The --tb-debug contributor dump, deliberately independent of the watcher.",
    ),
    "WhatCableDarwinBackend/Watchers/AppleUVDMWatcher.swift": (
        {"Self.watchedClass"},
        "A single held constant rather than a loop, IOPortTransportProtocolAppleUVDM, "
        "the node carrying an Apple accessory's own name. No other reader in Sources "
        "matches this class (checked 2026-09-10).",
    ),
}

# Every duplicate that exists today, with the reason it is allowed to.
#
# Each value is (reason, {files}). The file set is part of the key, not
# decoration: if a duplicate moves to a different pair of files that is a new
# duplicate and deserves a fresh look, not silent inheritance of an old excuse.
#
# TO ADD AN ENTRY: don't, unless the duplication is genuinely intended. The
# point of this file is that the list only ever gets shorter.
ALLOWED = {
    # --- Deliberate, decided, not going away -------------------------------
    "AppleUSBHostBillboardDevice": (
        "Core names the class to classify a device it was handed; the watcher "
        "names it to find one. Different jobs, and Core cannot import IOKit to "
        "share a matcher.",
        {"WhatCableCore/USB/USBDevice.swift", "WhatCableDarwinBackend/Watchers/USBWatcher.swift"},
    ),
    "IOUSBHostDevice": (
        "Same split as AppleUSBHostBillboardDevice: a Core classifier and a "
        "backend finder.",
        {"WhatCableCore/USB/USBDevice.swift", "WhatCableDarwinBackend/Watchers/USBWatcher.swift"},
    ),
    "IOPortTransportStateDisplayPort": (
        "Core names it in the model type of the same name; two watchers read "
        "it. The watcher half is the transport-watcher split, step 4 of the "
        "layering refactor.",
        {
            "WhatCableCore/Display/IOPortTransportStateDisplayPort.swift",
            "WhatCableDarwinBackend/Watchers/DisplayPortTransportWatcher.swift",
            "WhatCableDarwinBackend/Watchers/TRMTransportWatcher.swift",
        },
    ),
    "IOPowerManagement": (
        "A registry plane name, not a service class. Matched only because it "
        "is IO-prefixed.",
        {
            "WhatCableCore/Thunderbolt/IOThunderboltLink.swift",
            "WhatCableDarwinBackend/Debug/ThunderboltProbe.swift",
        },
    ),
    "IOPlatformUUID": (
        "A property key, not a service class. Three readers of the machine id, "
        "all doing different things with it.",
        {
            "WhatCable/Services/TestKitRunner.swift",
            "WhatCablePlugins/Core/LicenceManager.swift",
            "WhatCablePlugins/TestKit/TestKitCommand.swift",
        },
    ),
    "IOPlatformExpertDevice": (
        "Reads the machine id for the test kit, once in the app and once in "
        "the CLI command. The CLI runs as a separate process with no app to "
        "call into.",
        {"WhatCable/Services/TestKitRunner.swift", "WhatCablePlugins/TestKit/TestKitCommand.swift"},
    ),
    "AppleHPMInterfaceType10": (
        "The two readers now share HPMPortControllerClasses.named, so the only "
        "remaining second mention is Core using the name as a default class "
        "string when building a model from data it was handed. Core cannot "
        "import the backend, so it cannot reference the shared list. This "
        "entry started out listing the watcher too, and the script failed on "
        "its very first run because the watcher no longer names it: the "
        "MOVED check earning its place immediately.",
        {
            "WhatCableCore/Port/AppleHPMInterface.swift",
            "WhatCableDarwinBackend/Watchers/HPMPortControllerClasses.swift",
        },
    ),
    # --- Known duplicates owned by a later slice ---------------------------
    "IOThunderboltSwitch": (
        "The debug probe behind --tb-debug duplicates the watcher's matching "
        "on purpose: it is a contributor diagnostic that must keep working "
        "even when the watcher's own logic is what is being diagnosed.",
        {
            "WhatCableDarwinBackend/Debug/ThunderboltProbe.swift",
            "WhatCableDarwinBackend/Watchers/IOThunderboltSwitchWatcher.swift",
        },
    ),
    "IOIOThunderboltSwitch": (
        "Same as IOThunderboltSwitch. The doubled IO is a known naming wart, "
        "not a typo, and the rename is step 2 of the layering refactor.",
        {
            "WhatCableDarwinBackend/Debug/ThunderboltProbe.swift",
            "WhatCableDarwinBackend/Watchers/IOThunderboltSwitchWatcher.swift",
        },
    ),
    "IOPortTransportComponentCCUSBPDSOP": (
        "USBPDSOPWatcher and VDMIdentityWatcher read the same SOP class. "
        "Merging them into one reader is step 5 of the layering refactor, and "
        "moves the VDM parse into a service.",
        {
            "WhatCableDarwinBackend/Watchers/USBPDSOPWatcher.swift",
            "WhatCableDarwinBackend/Watchers/VDMIdentityWatcher.swift",
        },
    ),
    "IOPortTransportComponentCCUSBPDSOPp": (
        "Same pair as IOPortTransportComponentCCUSBPDSOP, step 5.",
        {
            "WhatCableDarwinBackend/Watchers/USBPDSOPWatcher.swift",
            "WhatCableDarwinBackend/Watchers/VDMIdentityWatcher.swift",
        },
    ),
    "IOPortTransportStateUSB3": (
        "TRMTransportWatcher and USB3TransportWatcher read the same transport "
        "class. Splitting TRM into base watchers plus a service is step 4.",
        {
            "WhatCableDarwinBackend/Watchers/TRMTransportWatcher.swift",
            "WhatCableDarwinBackend/Watchers/USB3TransportWatcher.swift",
        },
    ),
}


def matcher_argument(text, open_paren_index):
    """The full first argument of a matcher call, however many parens or commas
    it contains.

    Walks forward from the opening paren tracking nesting depth and string
    literals, and stops at the comma or close paren that belongs to THIS call.
    Returns None when the call is unterminated (a truncated or unparseable
    file), which the caller treats as unrecognised rather than absent: failing
    loudly on something we cannot read beats reporting it clean.
    """
    depth = 0
    index = open_paren_index
    start = open_paren_index + 1
    in_string = False
    while index < len(text):
        char = text[index]
        if in_string:
            if char == "\\":
                index += 2
                continue
            if char == '"':
                in_string = False
        elif char == '"':
            in_string = True
        elif char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return text[start:index].strip()
        elif char == "," and depth == 1:
            return text[start:index].strip()
        index += 1
    return None


def scan():
    """(class name -> files naming it, file -> computed matcher expressions)."""
    by_class = defaultdict(set)
    dynamic = defaultdict(set)
    for dirpath, _, filenames in os.walk(SOURCES):
        for name in filenames:
            if not name.endswith(".swift"):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, SOURCES)
            try:
                text = open(path, encoding="utf-8").read()
            except OSError as exc:
                print(f"  cannot read {rel}: {exc}", file=sys.stderr)
                return None, None
            for match in LITERAL.finditer(text):
                by_class[match.group(1)].add(rel)
            for match in MATCHER_CALL_START.finditer(text):
                arg = matcher_argument(text, match.end() - 1)
                if arg is None:
                    dynamic[rel].add("<unparseable matcher call>")
                elif not BARE_LITERAL_ARG.match(arg):
                    dynamic[rel].add(arg)
    return by_class, dynamic


def main():
    by_class, dynamic = scan()
    if by_class is None:
        return 2

    # Non-vacuity. A regex that matched nothing would report a clean run, which
    # is the failure mode this project has hit repeatedly with new scanners.
    # Measured 58 class-shaped literals when this landed.
    if len(by_class) < 40:
        print(f"FAIL: only {len(by_class)} IOKit class literals found in Sources/.")
        print("      The scanner has stopped matching. Fix it before trusting a green run.")
        return 1

    duplicates = {cls: files for cls, files in by_class.items() if len(files) > 1}

    failures = []

    for cls in sorted(duplicates):
        files = duplicates[cls]
        if cls not in ALLOWED:
            listing = "\n".join(f"        {f}" for f in sorted(files))
            failures.append(
                f"NEW duplicate reader: \"{cls}\" is named in {len(files)} files:\n{listing}\n"
                "      Give it one owner, or add it to ALLOWED in this script with the reason."
            )
            continue
        _, expected = ALLOWED[cls]
        if files != expected:
            added = sorted(files - expected)
            removed = sorted(expected - files)
            detail = ""
            if added:
                detail += "\n        now also in: " + ", ".join(added)
            if removed:
                detail += "\n        no longer in: " + ", ".join(removed)
            failures.append(
                f"MOVED duplicate reader: \"{cls}\" is in a different set of files "
                f"than its exemption records.{detail}\n"
                "      A duplicate that moved is a new duplicate. Re-check the reason, then update ALLOWED."
            )

    for rel in sorted(dynamic):
        expressions = dynamic[rel]
        if rel not in DYNAMIC_MATCHERS:
            failures.append(
                f"COMPUTED matcher in a file with no reason on record: {rel}\n"
                f"        passes: {', '.join(sorted(expressions))}\n"
                "      A matcher argument that is not a bare string literal hides which class is being\n"
                "      read, so the duplicate check above cannot see it. Say why here in DYNAMIC_MATCHERS."
            )
            continue
        expected, _ = DYNAMIC_MATCHERS[rel]
        if expressions != expected:
            added = sorted(expressions - expected)
            removed = sorted(expected - expressions)
            detail = ""
            if added:
                detail += "\n        now also passes: " + ", ".join(added)
            if removed:
                detail += "\n        no longer passes: " + ", ".join(removed)
            failures.append(
                f"COMPUTED matcher changed in {rel}.{detail}\n"
                "      Re-check what class it resolves to, then update DYNAMIC_MATCHERS."
            )

    for rel in sorted(DYNAMIC_MATCHERS):
        if rel not in dynamic:
            failures.append(
                f"STALE computed-matcher entry: {rel} no longer passes a computed matcher. "
                f"Delete its entry from DYNAMIC_MATCHERS in {os.path.relpath(__file__, ROOT)}."
            )

    for cls in sorted(ALLOWED):
        if cls not in duplicates:
            failures.append(
                f"STALE exemption: \"{cls}\" is no longer duplicated. "
                f"Delete its entry from ALLOWED in {os.path.relpath(__file__, ROOT)}."
            )

    if failures:
        print(f"FAIL: {len(failures)} duplicate-reader problem(s).")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    print(f"  {len(by_class)} IOKit class literals, {len(duplicates)} shared, "
          f"{len(dynamic)} files with computed matchers, all accounted for.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
