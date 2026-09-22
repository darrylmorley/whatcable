#!/usr/bin/env python3
"""Three-way cross-check for data/edid-timings/{vesa-dmt,cta-861-vic}.csv.

Every row in both CSVs (produced by extract-dmt.py and extract-cta-vic.py,
which read the VESA DMT and CTA-861-H spec PDFs) must agree on width,
height, hTotal, vTotal, pixelClockKHz and interlacing with BOTH:

  1. edid-decode's own tables (MIT, commit see edid-decode-src/COMMIT):
     dmt_timings[] in parse-base-block.cpp, edid_cta_modes1[] /
     edid_cta_modes2[] in parse-cta-block.cpp.
  2. The Linux kernel's drm_edid.c (GPL-2.0, numeric cross-check only,
     nothing copied): drm_dmt_modes[], edid_cea_modes_1[], edid_cea_modes_193[].

Any row present in the CSV and absent from a reference, or vice versa, is a
failure, as is any row where a compared field disagrees. Exits non-zero and
prints every disagreement found (never stops at the first one), so a CSV
regenerate only has to be run once to see the whole list.

Known, deliberate exclusion: edid-decode's established_timings12[] (base
block "Established Timings I & II", IBM/Apple legacy signals with
dmt_id 0x00) is not a DMT table and is out of scope for this script; it is
Task 4's concern.
"""

from __future__ import annotations

import argparse
import csv
import re
import sys

# --- generic C struct-array-literal parsing -------------------------------


def extract_array_body(text: str, var_name: str) -> str:
    """Return the text strictly between the '{' that opens `var_name[] = {`
    and the matching top-level '}' that closes the array, via brace-depth
    counting (comments and quoted strings are not brace-aware, but neither
    contains a literal '{' or '}' anywhere in these two files)."""
    m = re.search(re.escape(var_name) + r"\s*\[\s*\]\s*=\s*{", text)
    if not m:
        raise ValueError(f"array {var_name}[] not found")
    start = m.end()  # just after the opening '{'
    depth = 1
    i = start
    while depth > 0:
        if i >= len(text):
            raise ValueError(f"array {var_name}[] never closes")
        c = text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        i += 1
    return text[start:i - 1]


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.DOTALL)
    text = re.sub(r"//[^\n]*", " ", text)
    return text


def split_top_level_entries(body: str) -> list[str]:
    """Split an array body into its top-level '{ ... }' entries. Each
    returned string is the entry's content with the outer braces stripped."""
    entries = []
    depth = 0
    start = None
    for i, c in enumerate(body):
        if c == "{":
            if depth == 0:
                start = i + 1
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                entries.append(body[start:i])
    return entries


def split_top_level_args(s: str) -> list[str]:
    """Split a comma-separated argument list on top-level commas only,
    respecting nested {}/() and double-quoted strings."""
    args = []
    depth = 0
    in_quotes = False
    current = []
    for c in s:
        if in_quotes:
            current.append(c)
            if c == '"':
                in_quotes = False
            continue
        if c == '"':
            in_quotes = True
            current.append(c)
        elif c in "{(":
            depth += 1
            current.append(c)
        elif c in ")}":
            depth -= 1
            current.append(c)
        elif c == "," and depth == 0:
            args.append("".join(current).strip())
            current = []
        else:
            current.append(c)
    if "".join(current).strip():
        args.append("".join(current).strip())
    return args


def to_bool_or_int(tok: str):
    tok = tok.strip()
    if tok == "true":
        return True
    if tok == "false":
        return False
    return int(tok, 0)  # handles 0x-prefixed hex and plain decimal


# --- edid-decode `struct timings` parsing ----------------------------------

# Field order per edid-decode.h `struct timings` (positional aggregate init;
# trailing fields default to 0/false when the literal is shorter).
TIMINGS_FIELDS = [
    "hact", "vact", "hratio", "vratio", "pixclk_khz", "rb", "interlaced",
    "hfp", "hsync", "hbp", "pos_pol_hsync", "vfp", "vsync", "vbp",
    "pos_pol_vsync", "hborder", "vborder", "even_vtotal", "no_pol_vsync",
    "hsize_mm", "vsize_mm", "ycbcr420",
]
TIMINGS_DEFAULTS = {
    "hborder": 0, "vborder": 0, "even_vtotal": False, "no_pol_vsync": False,
    "hsize_mm": 0, "vsize_mm": 0, "ycbcr420": False,
}


def parse_timings_struct(fields_str: str) -> dict:
    tokens = split_top_level_args(fields_str)
    t = dict(TIMINGS_DEFAULTS)
    for name, tok in zip(TIMINGS_FIELDS, tokens):
        t[name] = to_bool_or_int(tok)
    return t


def timings_to_row(t: dict) -> dict:
    """Derive (width, height, hTotal, vTotal, pixelClockKHz, interlaced) the
    same way DMTTiming/VICTiming will: hTotal always sums the horizontal
    fields; vTotal for a progressive timing sums the vertical fields; for an
    interlaced timing (see edid-decode.h: vact is the FULL FRAME height, so
    the per-field height is vact/2) the frame vTotal is
    2 * (vact/2 + vfp + vsync + vbp) + (0 if even_vtotal else 1) -- verified
    against DMT 0x0F (817 lines) and CTA VIC 5 (1125 lines), both stated
    directly in the spec PDFs."""
    h_total = t["hact"] + t["hfp"] + t["hsync"] + t["hbp"] + 2 * t["hborder"]
    if t["interlaced"]:
        field_vact = t["vact"] // 2
        v_total = 2 * (field_vact + t["vfp"] + t["vsync"] + t["vbp"]) + (0 if t["even_vtotal"] else 1)
    else:
        v_total = t["vact"] + t["vfp"] + t["vsync"] + t["vbp"] + 2 * t["vborder"]
    return {
        "width": t["hact"],
        "height": t["vact"],
        "h_total": h_total,
        "v_total": v_total,
        "pixel_clock_khz": t["pixclk_khz"],
        "interlaced": t["interlaced"],
    }


def parse_edid_decode_dmt(edid_decode_dir: str) -> dict:
    path = f"{edid_decode_dir}/parse-base-block.cpp"
    with open(path) as f:
        text = strip_comments(f.read())
    body = extract_array_body(text, "dmt_timings")
    result = {}
    for entry in split_top_level_entries(body):
        args = split_top_level_args(entry)
        if len(args) != 4:
            raise ValueError(f"dmt_timings entry has {len(args)} top-level fields, expected 4: {entry!r}")
        dmt_id = to_bool_or_int(args[0])
        inner = args[3].strip()
        if inner.startswith("{") and inner.endswith("}"):
            inner = inner[1:-1]
        t = parse_timings_struct(inner)
        result[dmt_id] = timings_to_row(t)
    return result


def parse_edid_decode_cta(edid_decode_dir: str) -> dict:
    path = f"{edid_decode_dir}/parse-cta-block.cpp"
    with open(path) as f:
        text = strip_comments(f.read())
    result = {}
    for var_name, start_vic in [("edid_cta_modes1", 1), ("edid_cta_modes2", 193)]:
        body = extract_array_body(text, var_name)
        entries = split_top_level_entries(body)
        for i, entry in enumerate(entries):
            t = parse_timings_struct(entry)
            result[start_vic + i] = timings_to_row(t)
    return result


# --- Linux kernel drm_edid.c DRM_MODE(...) parsing -------------------------

# DRM_MODE(name, type, clock_khz, hdisplay, hsync_start, hsync_end, htotal,
#          hskew, vdisplay, vsync_start, vsync_end, vtotal, vscan, flags)
DRM_MODE_FIELDS = [
    "name", "type", "clock", "hdisplay", "hsync_start", "hsync_end", "htotal",
    "hskew", "vdisplay", "vsync_start", "vsync_end", "vtotal", "vscan", "flags",
]


def parse_drm_mode_call(text: str, start: int) -> tuple[dict, int]:
    """Parse one `DRM_MODE(...)` call starting at the index of its '(' in
    `text`. Returns the parsed field dict and the index just past the
    matching ')'."""
    depth = 1
    i = start + 1
    while depth > 0:
        c = text[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        i += 1
    args_str = text[start + 1:i - 1]
    tokens = split_top_level_args(args_str)
    if len(tokens) != len(DRM_MODE_FIELDS):
        raise ValueError(f"DRM_MODE call has {len(tokens)} args, expected {len(DRM_MODE_FIELDS)}: {args_str!r}")
    fields = dict(zip(DRM_MODE_FIELDS, tokens))
    return fields, i


def drm_fields_to_row(fields: dict) -> dict:
    interlaced = "DRM_MODE_FLAG_INTERLACE" in fields["flags"]
    # DRM_MODE_FLAG_DBLCLK marks the legacy SD "720(1440)xN" formats: the
    # kernel stores the native, undoubled per-pixel clock and horizontal
    # timing (720/13500kHz/858) and communicates the pixel repetition via
    # this flag, rather than baking it into the numbers. CTA-861-H's own
    # Table 1 text and edid-decode's tables both use the EDID-facing
    # doubled convention instead (1440/27000kHz/1716, footnote 2: "H active
    # is shown as 1440, instead of 720"), which is what our CSVs and Swift
    # tables carry, so DBLCLK rows are doubled here (horizontal fields and
    # pixel clock only; vertical fields are unaffected) before comparison.
    dblclk = "DRM_MODE_FLAG_DBLCLK" in fields["flags"]
    mult = 2 if dblclk else 1
    return {
        "width": int(fields["hdisplay"]) * mult,
        "height": int(fields["vdisplay"]),
        "h_total": int(fields["htotal"]) * mult,
        "v_total": int(fields["vtotal"]),
        "pixel_clock_khz": int(fields["clock"]) * mult,
        "interlaced": interlaced,
    }


def parse_drm_array(text: str, var_name: str, start_index: int) -> dict:
    body = extract_array_body(strip_comments(text), var_name)
    result = {}
    idx = start_index
    pos = 0
    while True:
        m = re.search(r"DRM_MODE\s*\(", body[pos:])
        if not m:
            break
        open_paren = pos + m.end() - 1
        fields, end = parse_drm_mode_call(body, open_paren)
        result[idx] = drm_fields_to_row(fields)
        idx += 1
        pos = end
    return result


def parse_drm_edid(drm_edid_path: str) -> tuple[dict, dict]:
    with open(drm_edid_path) as f:
        text = f.read()
    # drm_dmt_modes[] is NOT indexed by DMT ID (it is a driver-internal
    # array); the DMT ID is only recoverable from its "/* 0xXX - ... */"
    # comment, so it is parsed by comment tracking rather than position.
    dmt = parse_drm_dmt_with_ids(text)
    vic1 = parse_drm_array(text, "edid_cea_modes_1", 1)
    vic193 = parse_drm_array(text, "edid_cea_modes_193", 193)
    vic = {**vic1, **vic193}
    return dmt, vic


def parse_drm_dmt_with_ids(text: str) -> dict:
    body_raw = extract_array_body(text, "drm_dmt_modes")  # comments intact, for the /* 0xXX */ markers
    result = {}
    pos = 0
    current_id = None
    while True:
        comment_m = re.search(r"/\*\s*(0x[0-9A-Fa-f]{2})\s*-", body_raw[pos:])
        mode_m = re.search(r"DRM_MODE\s*\(", body_raw[pos:])
        if not mode_m:
            break
        mode_start = pos + mode_m.start()
        if comment_m and pos + comment_m.start() < mode_start:
            current_id = int(comment_m.group(1), 16)
            pos = pos + comment_m.end()
            continue
        open_paren = pos + mode_m.end() - 1
        fields, end = parse_drm_mode_call(body_raw, open_paren)
        if current_id is None:
            raise ValueError("drm_dmt_modes entry has no preceding /* 0xXX - ... */ id comment")
        result[current_id] = drm_fields_to_row(fields)
        current_id = None
        pos = end
    return result


# --- CSV loading ------------------------------------------------------------


def load_dmt_csv(path: str) -> dict:
    rows = {}
    with open(path, newline="") as f:
        for r in csv.DictReader(f):
            dmt_id = int(r["dmt_id"], 16)
            rows[dmt_id] = {
                "width": int(r["width"]),
                "height": int(r["height"]),
                "h_total": int(r["h_total"]),
                "v_total": int(r["v_total"]),
                "pixel_clock_khz": int(r["pixel_clock_khz"]),
                "interlaced": r["interlaced"] == "true",
            }
    return rows


def load_vic_csv(path: str) -> dict:
    rows = {}
    with open(path, newline="") as f:
        for r in csv.DictReader(f):
            vic = int(r["vic"])
            rows[vic] = {
                "width": int(r["width"]),
                "height": int(r["height"]),
                "h_total": int(r["h_total"]),
                "v_total": int(r["v_total"]),
                "pixel_clock_khz": int(r["pixel_clock_khz"]),
                "interlaced": r["interlaced"] == "true",
            }
    return rows


COMPARE_FIELDS = ["width", "height", "h_total", "v_total", "pixel_clock_khz", "interlaced"]


def compare(label: str, csv_rows: dict, edid_decode_rows: dict, drm_rows: dict) -> list[str]:
    errors = []
    all_keys = sorted(set(csv_rows) | set(edid_decode_rows) | set(drm_rows))
    for key in all_keys:
        in_csv = key in csv_rows
        in_ed = key in edid_decode_rows
        in_drm = key in drm_rows
        if not (in_csv and in_ed and in_drm):
            where = []
            if not in_csv:
                where.append("missing from CSV")
            if not in_ed:
                where.append("missing from edid-decode")
            if not in_drm:
                where.append("missing from drm_edid.c")
            errors.append(f"{label} {key}: {', '.join(where)}")
            continue
        csv_row, ed_row, drm_row = csv_rows[key], edid_decode_rows[key], drm_rows[key]
        for field in COMPARE_FIELDS:
            if csv_row[field] != ed_row[field]:
                errors.append(
                    f"{label} {key}: CSV {field}={csv_row[field]!r} != edid-decode {field}={ed_row[field]!r}"
                )
            if csv_row[field] != drm_row[field]:
                errors.append(
                    f"{label} {key}: CSV {field}={csv_row[field]!r} != drm_edid.c {field}={drm_row[field]!r}"
                )
    return errors


def main() -> int:
    p = argparse.ArgumentParser(
        description="Cross-check data/edid-timings/*.csv against edid-decode and the Linux kernel's drm_edid.c.",
    )
    p.add_argument("--dmt-csv", default="data/edid-timings/vesa-dmt.csv")
    p.add_argument("--vic-csv", default="data/edid-timings/cta-861-vic.csv")
    p.add_argument("--edid-decode-dir", required=True, help="Path to edid-decode's utils/edid-decode/ sources (pinned commit)")
    p.add_argument("--drm-edid", required=True, help="Path to a local copy of the Linux kernel's drivers/gpu/drm/drm_edid.c "
                                                       "(https://raw.githubusercontent.com/torvalds/linux/master/drivers/gpu/drm/drm_edid.c)")
    args = p.parse_args()

    dmt_csv = load_dmt_csv(args.dmt_csv)
    vic_csv = load_vic_csv(args.vic_csv)

    dmt_ed = parse_edid_decode_dmt(args.edid_decode_dir)
    vic_ed = parse_edid_decode_cta(args.edid_decode_dir)

    dmt_drm, vic_drm = parse_drm_edid(args.drm_edid)

    errors = []
    errors += compare("DMT", dmt_csv, dmt_ed, dmt_drm)
    errors += compare("VIC", vic_csv, vic_ed, vic_drm)

    if errors:
        print(f"FAILED: {len(errors)} disagreement(s):", file=sys.stderr)
        for e in errors:
            print(f"  {e}", file=sys.stderr)
        return 1

    print(f"OK: {len(dmt_csv)} DMT rows and {len(vic_csv)} VIC rows agree with edid-decode and drm_edid.c")
    return 0


if __name__ == "__main__":
    sys.exit(main())
