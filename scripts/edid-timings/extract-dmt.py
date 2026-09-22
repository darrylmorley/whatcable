#!/usr/bin/env python3
"""Extract VESA DMT 1.13's DMT timing table into a CSV.

Source of record: VESA Display Monitor Timing Standard, Version 1.0, Rev. 13
(https://glenwing.github.io/docs/VESA-DMT-1.13.pdf).

Two things inside the PDF feed this script:

  - Table 2-1 "Summary of DMT ID, Std. 2 Byte & CVT 3 Byte Codes" (pages 10
    to 12) gives the DMT ID plus its EDID standard-timing 2-byte code and
    CVT 3-byte code, where they exist.
  - Section 4 "DMT Timing Specifications" (pages 18 onward), one physical
    page per DMT, gives the actual timing numbers ("EDID ID: DMT ID: XXh;
    Std. 2 Byte Code: ...; CVT 3 Byte Code: ...", "Resolution: W x H at
    R Hz (interlaced|non-interlaced)[ REDUCED BLANKING[ v2]]", "Pixel Clock
    =M;", "Hor Total Time =...= NPixels", "Ver Total Time =...= Nlines").

Both sources name the DMT ID and its Std./CVT codes; this script asserts
they agree rather than trusting either one alone.

Reduced blanking has two independent tells, one on each source, and this
script requires both to agree: the detail page's "Resolution:" line says
"REDUCED BLANKING" (with or without a trailing "v2"); Table 2-1's Refresh
Rate column says "(RB)" for the same DMT ID. The detail page's own "Method:"
line was tried first and rejected: it reads "*** NOT CVT COMPLIANT ***" for
some genuinely reduced-blanking, non-CVT modes (e.g. DMT 56h, 1366x768@60
RB) and "CVT Compliant" with no mention of blanking style at all for at
least one CVT reduced-blanking mode (DMT 4Ch, 2560x1600@60 RB) - it is not a
reliable second signal.
"""

from __future__ import annotations

import argparse
import csv
import re
import sys

TABLE21_ROW_RE = re.compile(
    r"(?P<rb>\(RB\)\s+)?"
    r"(?P<id>[0-9A-Fa-f]{2})h\s+"
    r"(?P<std>\([0-9A-Fa-f]{2},\s*[0-9A-Fa-f]{2}\)h|n/a)\s+"
    r"(?P<cvt>\([0-9A-Fa-f]{2},\s*[0-9A-Fa-f]{2},\s*[0-9A-Fa-f]{2}\)h|n/a)"
)

RESOLUTION_RE = re.compile(
    r"Resolution:\s*(?P<w>\d+)\s*x\s*(?P<h>\d+)\s*at\s*(?P<refresh>[\d.]+)\s*Hz\s*"
    r"\((?P<scan>interlaced|non-interlaced)\)(?P<rb>\s*REDUCED BLANKING(?:\s*v2)?)?",
    re.IGNORECASE,
)
# Std. 2 Byte Code is printed as "(XX, YY)h" almost everywhere, but three
# detail pages (DMT 53h, 54h, 55h) print it as "XXh, YYh" instead. Both are
# accepted here; parse_code_bytes handles either shape.
STD_CODE_ALT = r"(?:\([0-9A-Fa-f]{2},\s*[0-9A-Fa-f]{2}\)h|[0-9A-Fa-f]{2}h,\s*[0-9A-Fa-f]{2}h|n/a)"
CVT_CODE_ALT = r"(?:\([0-9A-Fa-f]{2},\s*[0-9A-Fa-f]{2},\s*[0-9A-Fa-f]{2}\)h|n/a)"
EDID_ID_RE = re.compile(
    rf"DMT ID:\s*(?P<id>[0-9A-Fa-f]{{2}})h;\s*Std\.\s*2 Byte Code:\s*(?P<std>{STD_CODE_ALT})\s*;\s*"
    rf"CVT 3 Byte Code:\s*(?P<cvt>{CVT_CODE_ALT})"
)
PIXEL_CLOCK_RE = re.compile(r"Pixel Clock\s*=\s*([\d.]+)\s*;")
HOR_TOTAL_RE = re.compile(r"Hor Total Time.*?(\d+)\s*Pixels")
VER_TOTAL_RE = re.compile(r"Ver Total Time.*?(\d+)\s*lines")
SCAN_TYPE_RE = re.compile(r"Scan Type\s*=\s*(NONINTERLACED|INTERLACED)")

EXPECTED_IDS = list(range(0x01, 0x59))  # 0x01..0x58 inclusive, no gaps


def parse_code_bytes(text: str) -> int | None:
    if text.strip().lower() == "n/a":
        return None
    hexbytes = re.findall(r"[0-9A-Fa-f]{2}", text)
    value = 0
    for b in hexbytes:
        value = (value << 8) | int(b, 16)
    return value


def parse_table21(text: str, page_num: int, codes: dict) -> None:
    for m in TABLE21_ROW_RE.finditer(text):
        dmt_id = int(m.group("id"), 16)
        std = parse_code_bytes(m.group("std"))
        cvt = parse_code_bytes(m.group("cvt"))
        rb = m.group("rb") is not None
        if dmt_id in codes:
            prior = codes[dmt_id]
            if prior[:3] != (std, cvt, rb):
                raise ValueError(
                    f"Table 2-1: DMT ID {dmt_id:#04x} listed twice with different codes: {prior[:3]} vs {(std, cvt, rb)}"
                )
            continue
        codes[dmt_id] = (std, cvt, rb, page_num)


def parse_detail_page(text: str, page_num: int) -> dict | None:
    edid_m = EDID_ID_RE.search(text)
    if not edid_m:
        return None
    dmt_id = int(edid_m.group("id"), 16)
    std = parse_code_bytes(edid_m.group("std"))
    cvt = parse_code_bytes(edid_m.group("cvt"))

    res_m = RESOLUTION_RE.search(text)
    if not res_m:
        raise ValueError(f"page {page_num}: found EDID ID for DMT {dmt_id:#04x} but no Resolution: line")
    width = int(res_m.group("w"))
    height = int(res_m.group("h"))
    resolution_rb = res_m.group("rb") is not None
    interlaced_from_resolution = res_m.group("scan").lower() == "interlaced"

    scan_m = SCAN_TYPE_RE.search(text)
    if not scan_m:
        raise ValueError(f"page {page_num}: DMT {dmt_id:#04x} has no Scan Type line")
    interlaced_from_scan_type = scan_m.group(1) == "INTERLACED"
    if interlaced_from_resolution != interlaced_from_scan_type:
        raise ValueError(
            f"page {page_num}: DMT {dmt_id:#04x} Resolution: line and Scan Type: line disagree on interlacing"
        )
    interlaced = interlaced_from_resolution

    reduced_blanking = resolution_rb

    pclk_m = PIXEL_CLOCK_RE.search(text)
    if not pclk_m:
        raise ValueError(f"page {page_num}: DMT {dmt_id:#04x} has no Pixel Clock line")
    pixel_clock_khz = round(float(pclk_m.group(1)) * 1000)

    htot_m = HOR_TOTAL_RE.search(text)
    if not htot_m:
        raise ValueError(f"page {page_num}: DMT {dmt_id:#04x} has no parseable Hor Total Time line")
    h_total = int(htot_m.group(1))

    vtot_m = VER_TOTAL_RE.search(text)
    if not vtot_m:
        raise ValueError(f"page {page_num}: DMT {dmt_id:#04x} has no parseable Ver Total Time line")
    v_total = int(vtot_m.group(1))

    return {
        "dmt_id": dmt_id,
        "width": width,
        "height": height,
        "refresh_hz": res_m.group("refresh"),
        "interlaced": interlaced,
        "reduced_blanking": reduced_blanking,
        "h_total": h_total,
        "v_total": v_total,
        "pixel_clock_khz": pixel_clock_khz,
        "std_code": std,
        "cvt_code": cvt,
        "source_page": page_num,
    }


def main() -> int:
    p = argparse.ArgumentParser(
        description="Extract the VESA DMT 1.13 timing table (Table 2-1 + Section 4 detail pages) into a CSV.",
        epilog=(
            "The source PDF is the VESA Display Monitor Timing Standard v1.0 Rev 13, downloadable from "
            "https://glenwing.github.io/docs/VESA-DMT-1.13.pdf . "
            "This script never downloads it: pass a local copy with --pdf."
        ),
    )
    p.add_argument("--pdf", required=True, help="Path to a local VESA DMT 1.13 PDF (never downloaded by this script)")
    p.add_argument("--out", required=True, help="Path to write the output CSV")
    args = p.parse_args()

    from pypdf import PdfReader

    reader = PdfReader(args.pdf)
    codes: dict = {}
    details: dict = {}
    errors = []

    for i, page in enumerate(reader.pages):
        text = page.extract_text() or ""
        page_num = i + 1
        if "Table 2-1" in text or (10 <= page_num <= 12):
            try:
                parse_table21(text, page_num, codes)
            except ValueError as e:
                errors.append(str(e))
        try:
            row = parse_detail_page(text, page_num)
        except ValueError as e:
            errors.append(str(e))
            row = None
        if row is not None:
            if row["dmt_id"] in details:
                raise ValueError(f"DMT ID {row['dmt_id']:#04x} has a detail page on both "
                                  f"{details[row['dmt_id']]['source_page']} and {page_num}")
            details[row["dmt_id"]] = row

    if errors:
        print("FAILED to parse VESA DMT 1.13:", file=sys.stderr)
        for e in errors:
            print(f"  {e}", file=sys.stderr)
        return 1

    found_detail = sorted(details.keys())
    missing = sorted(set(EXPECTED_IDS) - set(found_detail))
    extra = sorted(set(found_detail) - set(EXPECTED_IDS))
    if missing or extra:
        print("FAILED: DMT ID set from detail pages does not match the expected 0x01-0x58:", file=sys.stderr)
        if missing:
            print(f"  missing: {[hex(x) for x in missing]}", file=sys.stderr)
        if extra:
            print(f"  unexpected: {[hex(x) for x in extra]}", file=sys.stderr)
        return 1

    found_table21 = sorted(codes.keys())
    missing_t21 = sorted(set(EXPECTED_IDS) - set(found_table21))
    extra_t21 = sorted(set(found_table21) - set(EXPECTED_IDS))
    if missing_t21 or extra_t21:
        print("FAILED: DMT ID set from Table 2-1 does not match the expected 0x01-0x58:", file=sys.stderr)
        if missing_t21:
            print(f"  missing: {[hex(x) for x in missing_t21]}", file=sys.stderr)
        if extra_t21:
            print(f"  unexpected: {[hex(x) for x in extra_t21]}", file=sys.stderr)
        return 1

    code_mismatches = []
    for dmt_id in found_detail:
        std21, cvt21, rb21, _ = codes[dmt_id]
        d = details[dmt_id]
        if std21 != d["std_code"] or cvt21 != d["cvt_code"]:
            code_mismatches.append(
                f"DMT {dmt_id:#04x}: Table 2-1 says std={std21!r} cvt={cvt21!r}, "
                f"detail page {d['source_page']} says std={d['std_code']!r} cvt={d['cvt_code']!r}"
            )
        if rb21 != d["reduced_blanking"]:
            code_mismatches.append(
                f"DMT {dmt_id:#04x}: Table 2-1 Refresh Rate column says (RB)={rb21}, "
                f"detail page {d['source_page']} Resolution: line says REDUCED BLANKING={d['reduced_blanking']}"
            )
    if code_mismatches:
        print("FAILED: Table 2-1 and detail pages disagree on Std./CVT codes:", file=sys.stderr)
        for m in code_mismatches:
            print(f"  {m}", file=sys.stderr)
        return 1

    with open(args.out, "w", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow([
            "dmt_id", "width", "height", "refresh_hz", "interlaced", "reduced_blanking",
            "h_total", "v_total", "pixel_clock_khz", "std_code", "cvt_code", "source_page",
        ])
        for dmt_id in found_detail:
            d = details[dmt_id]
            w.writerow([
                f"0x{dmt_id:02X}", d["width"], d["height"], d["refresh_hz"],
                "true" if d["interlaced"] else "false", "true" if d["reduced_blanking"] else "false",
                d["h_total"], d["v_total"], d["pixel_clock_khz"],
                f"0x{d['std_code']:04X}" if d["std_code"] is not None else "",
                f"0x{d['cvt_code']:06X}" if d["cvt_code"] is not None else "",
                d["source_page"],
            ])

    print(f"OK: wrote {len(found_detail)} DMT rows to {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
