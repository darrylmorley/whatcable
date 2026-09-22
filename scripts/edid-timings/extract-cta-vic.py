#!/usr/bin/env python3
"""Extract CTA-861-H Table 1 (Video Format Timings) into a CSV of VIC timings.

Source of record: ANSI/CTA-861-H, Table 1 "Video Format Timings, Detailed
Timing Information", pages 41 to 43 in the published PDF
(https://archive.org/download/ansi-cta-861-h-final/ANSI-CTA-861-H-Final.pdf).
Table 1 is split across several vertical-frequency sections (Low, 50Hz,
60Hz, 100Hz, 120Hz, 200Hz, 240Hz); each section header is followed by rows of
the shape:

    VIC[, VIC]  Hactive Vactive I/P  Htotal Hblank Vtotal Vblank  HFreq VFreq PixelFreq

Two footnote quirks in the extracted text, both handled here without ever
hand-editing the output:

1. Hactive and Htotal occasionally carry a glued-on footnote "2" (no space),
   e.g. "14402" for Hactive 1440 (CTA-861-H footnote 2: some SD formats are
   double-clocked, so Hactive is shown doubled). Detected and stripped using
   the one column NOT subject to a footnote in this table, Hblank: it always
   equals Htotal - Hactive exactly, so whichever reading (raw or footnote-
   stripped) satisfies that arithmetic is the real value.
2. V Freq occasionally carries a glued-on footnote "3" (CTA-861-H footnote 3:
   a vertical frequency that is an integer multiple of 6.00 Hz is considered
   the same Video Timing as its 1000/1001-scaled NTSC-compatible sibling).
   Every V Freq value in this table is printed to either 2 or 3 decimal
   places; a footnoted value has one extra trailing digit, so any value with
   more than 2 decimal places has its last character (the footnote) dropped.

VICs 0 and 128 to 192 are reserved (CTA-861-H defines no Video Format Timing
for them, and SVD values 128-192 are explicitly Forbidden); the output CSV
has no rows for them.

A handful of VICs (8, 9, 12, 13, 23, 24, 27, 28) list two or three row
variants that differ only in Vtotal/V Freq by a scan line or two: CTA-861-H's
own footnote on this ("these frame formats differ only by one or two scan
lines... treated as the same Video Format") says they are the same timing.
edid-decode's own tables (cross-checked by check-edid-timings.py) resolve
each of these to its first-listed variant, so this script does the same:
first occurrence wins, and a later variant is accepted silently only when it
agrees on everything except Vtotal/V Freq.
"""

from __future__ import annotations

import argparse
import csv
import re
import sys

ROW_RE = re.compile(
    r"(?P<vics>\d+(?:,\s*\d+)?)\s+"
    r"(?P<hact>\d+)\s+"
    r"(?P<vact>\d+)\s+"
    r"(?P<ip>Int|Prog)\s+"
    r"(?P<htot>\d+)\s+"
    r"(?P<hblank>\d+)\s+"
    r"(?P<vtot>\d+)\s+"
    r"(?P<vblank>[\d.]+)\s+"
    r"(?P<hfreq>[\d.]+)\s+"
    r"(?P<vfreq>[\d.]+)\s+"
    r"(?P<pclk>[\d.]+)\s*$"
)

EXPECTED_VICS = sorted(set(range(1, 128)) | set(range(193, 220)))


def strip_h_footnote(hact_raw: str, htot_raw: str, hblank: int) -> tuple[int, int]:
    """Hblank = Htotal - Hactive always holds in this table (it is never
    itself footnoted). Try the raw reading first; if it does not balance,
    strip a trailing '2' footnote from both Hactive and Htotal and retry."""
    hact, htot = int(hact_raw), int(htot_raw)
    if htot - hact == hblank:
        return hact, htot
    if hact_raw.endswith("2") and htot_raw.endswith("2"):
        hact2, htot2 = int(hact_raw[:-1]), int(htot_raw[:-1])
        if htot2 - hact2 == hblank:
            return hact2, htot2
    raise ValueError(
        f"Hblank invariant failed: Htotal({htot_raw}) - Hactive({hact_raw}) != Hblank({hblank}), "
        "and stripping a trailing footnote '2' from both did not fix it either"
    )


def strip_v_footnote(token: str) -> float:
    """V Freq values print to 2 or 3 decimal places. A footnoted value (CTA
    footnote 3) has one extra trailing digit glued on with no separator."""
    if "." in token:
        decimals = len(token.split(".", 1)[1])
        if decimals > 2:
            token = token[:-1]
    return float(token)


def parse_table1(text: str, page_num: int, rows: dict) -> None:
    for raw_line in text.split("\n"):
        line = raw_line.strip()
        if not line:
            continue
        m = ROW_RE.search(line)
        if not m:
            continue
        vics = [int(v.strip()) for v in m.group("vics").split(",")]
        interlaced = m.group("ip") == "Int"
        vact = int(m.group("vact"))
        vtot = int(m.group("vtot"))
        hblank = int(m.group("hblank"))
        try:
            hact, htot = strip_h_footnote(m.group("hact"), m.group("htot"), hblank)
        except ValueError as e:
            raise ValueError(f"page {page_num}, line {line!r}: {e}") from e
        vfreq = strip_v_footnote(m.group("vfreq"))
        pclk_mhz = float(m.group("pclk"))
        pixel_clock_khz = round(pclk_mhz * 1000)
        for vic in vics:
            row = {
                "vic": vic,
                "width": hact,
                "height": vact,
                "interlaced": interlaced,
                "h_total": htot,
                "v_total": vtot,
                "pixel_clock_khz": pixel_clock_khz,
                "v_freq_hz": vfreq,
                "source_page": page_num,
            }
            if vic in rows:
                prior = rows[vic]
                differs_only_in_vtotal = (
                    prior["width"] == row["width"]
                    and prior["height"] == row["height"]
                    and prior["interlaced"] == row["interlaced"]
                    and prior["h_total"] == row["h_total"]
                    and prior["pixel_clock_khz"] == row["pixel_clock_khz"]
                )
                if not differs_only_in_vtotal:
                    raise ValueError(
                        f"VIC {vic} defined twice with different values: {prior} vs {row}"
                    )
                continue  # first-listed variant wins; see module docstring
            rows[vic] = row


def main() -> int:
    p = argparse.ArgumentParser(
        description="Extract CTA-861-H Table 1 (Video Format Timings) into a VIC timing CSV.",
        epilog=(
            "The source PDF is ANSI/CTA-861-H, downloadable from "
            "https://archive.org/download/ansi-cta-861-h-final/ANSI-CTA-861-H-Final.pdf . "
            "This script never downloads it: pass a local copy with --pdf."
        ),
    )
    p.add_argument("--pdf", required=True, help="Path to a local CTA-861-H PDF (never downloaded by this script)")
    p.add_argument("--out", required=True, help="Path to write the output CSV")
    args = p.parse_args()

    from pypdf import PdfReader

    reader = PdfReader(args.pdf)
    rows: dict = {}
    errors = []
    for i, page in enumerate(reader.pages):
        text = page.extract_text() or ""
        if "Table 1" not in text and i > 0:
            # Table 1 spans a contiguous run of pages; skip everything else,
            # but always look at the first page too in case of an off-by-one.
            continue
        try:
            parse_table1(text, i + 1, rows)
        except ValueError as e:
            errors.append(str(e))

    if errors:
        print("FAILED to parse CTA-861-H Table 1:", file=sys.stderr)
        for e in errors:
            print(f"  {e}", file=sys.stderr)
        return 1

    found = sorted(rows.keys())
    missing = sorted(set(EXPECTED_VICS) - set(found))
    extra = sorted(set(found) - set(EXPECTED_VICS))
    if missing or extra:
        print("FAILED: VIC set does not match CTA-861-H Table 1 (VIC 1-127, 193-219; 128-192 reserved):", file=sys.stderr)
        if missing:
            print(f"  missing: {missing}", file=sys.stderr)
        if extra:
            print(f"  unexpected: {extra}", file=sys.stderr)
        return 1

    with open(args.out, "w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["vic", "width", "height", "interlaced", "h_total", "v_total", "pixel_clock_khz", "v_freq_hz", "source_page"])
        for vic in found:
            r = rows[vic]
            w.writerow([
                r["vic"], r["width"], r["height"], "true" if r["interlaced"] else "false",
                r["h_total"], r["v_total"], r["pixel_clock_khz"], r["v_freq_hz"], r["source_page"],
            ])

    print(f"OK: wrote {len(found)} VIC rows to {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
