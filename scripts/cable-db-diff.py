#!/usr/bin/env python3
"""Diff the customer-probe corpus's cable fingerprints against
data/known-cables.md, to find cables people are actually plugging in that
aren't catalogued yet.

Intended to be re-run after every ingest batch (see the whatcable-process-
probe skill's end-of-batch step): it surfaces which uncatalogued cables are
showing up on more than one machine, which is the signal worth chasing for a
new known-cables.md row. New rows still go through the normal hand-edit
discipline (the "Brand / model context" column is never auto-imported; see
CLAUDE.md), this script only tells you where to look.

Two things worth knowing before reading the output:

- PID = 0x0000 rows can never resolve at runtime. CableDB.curatedCables(vid:
  pid:) requires both VID and PID to be nonzero (see
  Sources/WhatCableCore/Database/CableDB.swift); a zero PID means the app can
  never match that cable to a brand no matter how well it's catalogued. This
  is the DAR-39 structural finding: cheap/generic cable silicon overwhelmingly
  ships with PID=0, so a big chunk of "uncatalogued" fingerprints are
  unfixable under the current (VID,PID) identity schema, not a coverage gap.
  Still counted here for visibility, but don't spend curation effort on them.
- A zeroed VID (0x0000) is a trust signal (an e-marker that didn't report an
  identity at all), not an identifiable cable model. It says something about
  the cable's trustworthiness, not its brand. Don't try to name it.

Usage:
    scripts/cable-db-diff.py                 # headline numbers + ranked missing list, to stdout
    scripts/cable-db-diff.py --json           # full data as JSON, to stdout
    scripts/cable-db-diff.py --out DIR        # also write fingerprint-frequency.tsv,
                                               # missing-from-db.md, never-seen-in-corpus.md into DIR
    scripts/cable-db-diff.py --top N          # how many ranked absentees to print (default 15)
"""
import json
import os
import re
import sqlite3
import sys
from collections import Counter, defaultdict

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KNOWN_CABLES = os.path.join(REPO, "data", "known-cables.md")
WHATCABLE_DB = os.path.join(REPO, "Sources", "WhatCableCore", "Resources", "whatcable.db")
CORPUS = os.path.join(REPO, "research", "customer-probes", "corpus.jsonl")
INSPECTIONS_DIR = os.path.join(REPO, "research", "customer-probes")


def hx(s):
    """Parse "0xABCD" (optionally backtick/whitespace-wrapped) into an int.
    Returns None for anything that isn't valid hex, mirroring
    build-cable-db.swift's parseHex(_:) -> Int? (nil on a bad prefix or bad
    digits, never a crash). Never raises."""
    if s is None:
        return None
    s = s.strip().strip("`")
    if not (s.lower().startswith("0x")):
        return None
    try:
        return int(s, 16)
    except ValueError:
        return None


def hx16(v):
    return "0x{:04X}".format(v) if v is not None else "0x0000"


def hx32(v):
    return "0x{:08X}".format(v) if v is not None else None


# md-row field name for each cables-table column the unique index can name.
# Anything outside this map means the schema grew a column this script has
# never seen, which is a stop-and-look, not something to guess through.
_COL_TO_MD_FIELD = {
    "vid": "vid",
    "pid": "pid",
    "cable_vdo": "vdo",
    "brand": "brand_ctx",
}


def quote_ident(name):
    """SQLite identifier quoting for a PRAGMA argument."""
    return '"' + name.replace('"', '""') + '"'


def dedup_columns(con):
    """Read the cables table's UNIQUE INDEX out of the database and return the
    key columns it covers, so this script dedups on whatever identity the
    builder actually enforces.

    Deliberately NOT restated from build-cable-db.swift. It used to be, as a
    docstring describing a partial index ON cables(vid, pid) WHERE vid != 0
    AND pid != 0, and that stopped being the builder's index in d808786e
    (2026-06-02, "Identify cables by VID+PID, never the Cable VDO"). The
    restatement rotted silently and made this script under-count by 4 rows:
    four (vid, pid) pairs legitimately carry two rows each, differing in
    cable_vdo or brand, and the stale key folded them together.

    Read through PRAGMA index_list / index_xinfo rather than by pattern-matching
    sqlite_master.sql. The DDL text is prose: an ordinary index named "unique"
    or carrying a /* UNIQUE */ comment would pass a \bUNIQUE\b test, and a full
    unique index whose name happened to contain "where" would fail a partial-index
    test. The PRAGMAs report uniqueness, partialness and the key columns as
    structured fields, which is what we actually need to know.

    Raises on anything this script cannot model, rather than falling back to a
    guess: no unique index, more than one, a partial index, an expression key,
    a non-BINARY collation (which would change what counts as a duplicate), or
    a column outside _COL_TO_MD_FIELD.
    """
    indexes = con.execute("PRAGMA index_list('cables')").fetchall()
    # (seq, name, unique, origin, partial); older SQLite builds return 3 columns.
    unique = []
    for row in indexes:
        name, is_unique = row[1], row[2]
        partial = row[4] if len(row) > 4 else 0
        if is_unique:
            unique.append((name, partial))
    if len(unique) != 1:
        raise SystemExit(
            "cable-db-diff: expected exactly one UNIQUE INDEX on cables, found "
            f"{len(unique)}: {[n for n, _ in unique]}. Schema changed; update "
            "dedup_columns() rather than guessing."
        )
    name, partial = unique[0]
    if partial:
        raise SystemExit(
            f"cable-db-diff: {name} is a partial index. This script only models "
            "a full unique index; update dedup_columns()."
        )

    cols = []
    for row in con.execute(f"PRAGMA index_xinfo({quote_ident(name)})").fetchall():
        # (seqno, cid, name, desc, coll, key); key == 0 rows are the trailing
        # rowid/covering columns, not part of the enforced identity.
        _seqno, cid, col, _desc, coll, key = row[:6]
        if not key:
            continue
        if col is None or cid is not None and cid < 0:
            raise SystemExit(
                f"cable-db-diff: {name} has an expression key column this script "
                "cannot map to a known-cables.md field. Update dedup_columns()."
            )
        if coll and coll.upper() != "BINARY":
            raise SystemExit(
                f"cable-db-diff: {name} column {col} uses collation {coll}. "
                "Non-BINARY collation changes what counts as a duplicate; "
                "update dedup_columns()."
            )
        cols.append(col)
    if not cols:
        raise SystemExit(f"cable-db-diff: {name} reported no key columns.")
    unknown = [c for c in cols if c not in _COL_TO_MD_FIELD]
    if unknown:
        raise SystemExit(
            f"cable-db-diff: {name} covers column(s) this script cannot map to "
            f"a known-cables.md field: {unknown}. Update _COL_TO_MD_FIELD."
        )
    return cols


def expected_db_row_count(md_rows, dedup_cols):
    """Reproduce scripts/build-cable-db.swift's insert logic to predict how many
    rows whatcable.db's `cables` table SHOULD have from the current
    known-cables.md, so a raw row-count mismatch can be told apart from
    expected deduplication.

    The build script:
    1. Skips rows with brand "(needs review)" (no usable identity yet).
    2. Skips all-zero rows (vid==0 and pid==0 and cable_vdo==0): unmatchable,
       not worth storing.
    3. Inserts everything else via INSERT OR IGNORE against the table's UNIQUE
       INDEX, so the first row per identity in file order wins and later
       duplicates of that identity are skipped. `dedup_cols` comes from
       dedup_columns(), i.e. from the database itself.

    Note there is no carve-out for rows with a zero vid or pid. The index is
    full, not partial, so every row is deduplicated on the same key. 56 rows
    in the db currently have vid == 0 or pid == 0, and two of them sharing
    every indexed field would collapse to one row exactly like any other
    duplicate.

    A row whose vid or pid didn't parse as hex is dropped before this
    function ever sees it (parse_known_cables() already requires both to
    match `0x...`), matching the build script's `guard let ... else continue`.
    """
    fields = [_COL_TO_MD_FIELD[c] for c in dedup_cols]
    seen_identity = set()
    expected = 0
    for r in md_rows:
        if r["brand_ctx"] == "(needs review)":
            continue
        vid, pid, vdo = r["vid"] or 0, r["pid"] or 0, r["vdo"] or 0
        if vid == 0 and pid == 0 and vdo == 0:
            continue
        key = tuple(r[f] for f in fields)
        if key in seen_identity:
            continue
        seen_identity.add(key)
        expected += 1
    return expected


def parse_known_cables():
    """Mirrors build-cable-db.swift's known-cables.md parser (~line 508-544)
    exactly, so this script's row set matches what actually gets compiled
    into whatcable.db:

    - Only parses between a line starting with "## Table" and the next line
      starting with "## " after that (a table added under some other
      heading later in the file must not be picked up as cable data).
    - Only considers lines starting with "|" that don't contain "---" (skips
      the header separator row).
    - Requires exactly 10 pipe-delimited cells.
    - Skips the header row itself (VID cell not starting with "`0x").
    - A VID or PID that isn't valid hex drops the row entirely (guard let
      ... else continue in the Swift source): a typo there can't silently
      become a wrong identity. Cable VDO, if unparseable, defaults to 0
      instead of dropping the row (`?? 0` in the Swift source) since VDO is
      capability data, not identity.
    """
    rows = []
    in_table = False
    with open(KNOWN_CABLES) as f:
        for line in f:
            line = line.rstrip("\n")
            if line.startswith("## Table"):
                in_table = True
                continue
            if in_table and line.startswith("## "):
                break
            if not in_table or not line.startswith("|") or "---" in line:
                continue
            cells = [c.strip() for c in line.strip("|").split("|")]
            if len(cells) != 10:
                continue
            brand_ctx, vid_s, pid_s, vdo_s, vendor, xid, speed, power, ctype, issue = cells
            if not vid_s.startswith("`0x"):
                continue  # header row
            vid, pid = hx(vid_s), hx(pid_s)
            if vid is None or pid is None:
                continue  # malformed identity: skip the row, don't guess
            vdo = hx(vdo_s)
            if vdo is None:
                vdo = 0
            rows.append({
                "brand_ctx": brand_ctx, "vid": vid, "pid": pid, "vdo": vdo,
                "vendor": vendor, "xid": xid, "speed": speed, "power": power,
                "type": ctype, "issue": issue,
            })
    return rows


def load_corpus():
    records = []
    with open(CORPUS) as f:
        for line in f:
            line = line.strip()
            if line:
                records.append(json.loads(line))
    return records


def get_inspection_text(folder):
    path = os.path.join(INSPECTIONS_DIR, folder, "inspection.md")
    if not os.path.exists(path):
        return ""
    with open(path) as f:
        return f.read()


def port_context_lines(folder, vid, pid, cache):
    """Grab the Ports section entry (Cable + adjacent Device lines) matching vid/pid."""
    text = cache.get(folder)
    if text is None:
        text = get_inspection_text(folder)
        cache[folder] = text
    if not text:
        return []
    vid_s, pid_s = hx16(vid), hx16(pid)
    hits = []
    for block in re.split(r"\n(?=### Port)", text):
        if f"VID={vid_s} PID={pid_s}" in block:
            lines = [l.strip() for l in block.splitlines()
                     if l.strip().startswith(("### Port", "- Cable:", "- Device:", "- PD:"))]
            hits.append(" | ".join(lines))
    return hits


def vendor_name(cur, vid):
    if vid is None:
        return None
    cur.execute("SELECT name, source FROM vendors WHERE vid=?", (vid,))
    row = cur.fetchone()
    return f"{row[0]} [{row[1]}]" if row else None


def main():
    args = sys.argv[1:]
    out_dir = args[args.index("--out") + 1] if "--out" in args else None
    want_json = "--json" in args
    top_n = int(args[args.index("--top") + 1]) if "--top" in args else 15

    md_rows = parse_known_cables()
    db_identity_nonzero = {(r["vid"], r["pid"]) for r in md_rows
                            if r["vid"] not in (None, 0) and r["pid"] not in (None, 0)}
    identity_to_rows = defaultdict(list)
    for r in md_rows:
        identity_to_rows[(r["vid"], r["pid"])].append(r)

    con = sqlite3.connect(WHATCABLE_DB)
    cur = con.cursor()
    cur.execute("SELECT count(*) FROM cables")
    db_row_count = cur.fetchone()[0]
    expected_row_count = expected_db_row_count(md_rows, dedup_columns(con))

    records = load_corpus()

    fp_machines = defaultdict(set)          # (vid,pid,vdo) -> folders
    pair_machines = defaultdict(set)        # nonzero (vid,pid) -> folders
    zeroed_fp_machines = defaultdict(set)   # zeroed-VID (vid,pid,vdo) -> folders
    pair_vdo_variants = defaultdict(Counter)

    total_cable_entries = 0
    machines_with_any_cable = set()

    for rec in records:
        folder = rec.get("folder")
        cables = rec.get("cables") or []
        if cables:
            machines_with_any_cable.add(folder)
        for c in cables:
            total_cable_entries += 1
            vid, pid, vdo = hx(c.get("vid")), hx(c.get("pid")), hx(c.get("cable_vdo"))
            fp = (vid, pid, vdo)
            fp_machines[fp].add(folder)
            if vid == 0:
                zeroed_fp_machines[fp].add(folder)
            else:
                pair_machines[(vid, pid)].add(folder)
                pair_vdo_variants[(vid, pid)][vdo] += 1

    absent_pairs = []
    machines_with_uncatalogued = set()
    for (vid, pid), folders in pair_machines.items():
        if (vid, pid) not in db_identity_nonzero:
            absent_pairs.append((vid, pid, sorted(folders)))
            machines_with_uncatalogued |= folders
    absent_pairs.sort(key=lambda t: -len(t[2]))

    never_seen = sorted(db_identity_nonzero - set(pair_machines.keys()))

    headline = {
        "corpus_records": len(records),
        "machines_with_any_cable": len(machines_with_any_cable),
        "total_cable_entries": total_cable_entries,
        "distinct_fingerprints_vid_pid_vdo": len(fp_machines),
        "distinct_nonzero_pairs": len(pair_machines),
        "distinct_zeroed_vid_fingerprints": len(zeroed_fp_machines),
        "known_cables_md_rows": len(md_rows),
        "whatcable_db_rows": db_row_count,
        "whatcable_db_expected_rows": expected_row_count,
        "db_stale": db_row_count != expected_row_count,
        "known_cables_nonzero_identities": len(db_identity_nonzero),
        "absent_nonzero_pairs": len(absent_pairs),
        "absent_pairs_pid_zero": sum(1 for v, p, _ in absent_pairs if p == 0),
        "machines_with_uncatalogued_nonzero_cable": len(machines_with_uncatalogued),
        "known_cables_never_seen_in_corpus": len(never_seen),
    }

    # ---- fingerprint frequency rows ----
    freq_rows = []
    for (vid, pid, vdo), folders in sorted(fp_machines.items(), key=lambda kv: -len(kv[1])):
        freq_rows.append({
            "vid": hx16(vid), "pid": hx16(pid), "vdo": hx32(vdo) or "",
            "machine_count": len(folders),
            "in_known_cables_db": (vid, pid) in db_identity_nonzero,
            "vendor_name": vendor_name(cur, vid) or "",
        })

    # ---- ranked missing rows (with hints) ----
    insp_cache = {}
    missing_rows = []
    for rank, (vid, pid, folders) in enumerate(absent_pairs, start=1):
        variants = pair_vdo_variants.get((vid, pid), {})
        vdo_str = ", ".join(f"{hx32(v)} (x{c})" for v, c in sorted(variants.items(), key=lambda kv: -kv[1]))
        hints = []
        for folder in folders[:3]:
            for h in port_context_lines(folder, vid, pid, insp_cache)[:1]:
                hints.append(f"{folder}: {h}")
        missing_rows.append({
            "rank": rank, "vid": hx16(vid), "pid": hx16(pid),
            "vendor": vendor_name(cur, vid) or "(unregistered / not in vendor list)",
            "machines": len(folders), "vdo_variants": vdo_str,
            "hints": hints, "pid_zero": pid == 0,
        })

    never_seen_rows = []
    for vid, pid in never_seen:
        for r in identity_to_rows.get((vid, pid), []):
            never_seen_rows.append({"vid": hx16(vid), "pid": hx16(pid),
                                     "brand_ctx": r["brand_ctx"], "issue": r["issue"]})

    con.close()

    # ---------------- Output ----------------
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
        with open(os.path.join(out_dir, "fingerprint-frequency.tsv"), "w") as f:
            f.write("vid_hex\tpid_hex\tvdo_hex\tmachine_count\tin_known_cables_db\tvendor_name\n")
            for r in freq_rows:
                f.write(f"{r['vid']}\t{r['pid']}\t{r['vdo']}\t{r['machine_count']}\t"
                        f"{r['in_known_cables_db']}\t{r['vendor_name']}\n")

        with open(os.path.join(out_dir, "missing-from-db.md"), "w") as f:
            f.write("# Corpus cable fingerprints not catalogued in known-cables.md\n\n")
            f.write(f"Nonzero (VID,PID) pairs seen in corpus but absent from known-cables.md: "
                    f"{len(missing_rows)}, of which {headline['absent_pairs_pid_zero']} have PID=0x0000 "
                    "and can never resolve at runtime (see the schema note at the top of this script).\n\n")
            f.write("| # | VID | PID | Vendor | Machines | Cable VDO variant(s) | Hints |\n")
            f.write("|---|---|---|---|---|---|---|\n")
            for r in missing_rows:
                hint_str = "<br>".join(r["hints"]) if r["hints"] else "(no inspection.md port match found)"
                f.write(f"| {r['rank']} | `{r['vid']}` | `{r['pid']}` | {r['vendor']} | "
                        f"{r['machines']} | {r['vdo_variants']} | {hint_str} |\n")

        with open(os.path.join(out_dir, "never-seen-in-corpus.md"), "w") as f:
            f.write("# known-cables.md (VID,PID) identities never seen in the customer-probe corpus\n\n")
            f.write(f"{len(never_seen_rows)} of {headline['known_cables_nonzero_identities']} "
                    f"nonzero-identity DB rows have zero matches across {headline['corpus_records']} "
                    "corpus machines. Expected: the corpus is a self-selected sample of test-kit "
                    "contributors, not every reported cable-report issue.\n\n")
            f.write("| VID | PID | Brand / model context | Issue |\n|---|---|---|---|\n")
            for r in never_seen_rows:
                f.write(f"| `{r['vid']}` | `{r['pid']}` | {r['brand_ctx']} | {r['issue']} |\n")

        print(f"wrote fingerprint-frequency.tsv, missing-from-db.md, never-seen-in-corpus.md to {out_dir}",
              file=sys.stderr)

    if want_json:
        print(json.dumps({
            "headline": headline,
            "fingerprint_frequency": freq_rows,
            "missing_from_db": missing_rows,
            "never_seen_in_corpus": never_seen_rows,
        }, indent=2))
        return

    print("# Cable fingerprint corpus vs known-cables.md\n")
    print(f"Corpus: {headline['corpus_records']} machine records, "
          f"{headline['machines_with_any_cable']} carrying >=1 cable, "
          f"{headline['total_cable_entries']} total cable entries.")
    print(f"Distinct (VID,PID,VDO) fingerprints: {headline['distinct_fingerprints_vid_pid_vdo']}. "
          f"Distinct nonzero (VID,PID) pairs: {headline['distinct_nonzero_pairs']}. "
          f"Distinct zeroed-VID fingerprints: {headline['distinct_zeroed_vid_fingerprints']}.")
    print(f"known-cables.md: {headline['known_cables_md_rows']} data rows, "
          f"{headline['known_cables_nonzero_identities']} distinct nonzero identities. "
          f"whatcable.db compiled cables table: {headline['whatcable_db_rows']} rows, "
          f"expected {headline['whatcable_db_expected_rows']} "
          "(the build script skips \"(needs review)\" and all-zero rows and dedups on the "
          "cables table's UNIQUE INDEX, so this is normally lower than the md row count, "
          "not a staleness signal by itself) "
          f"({'STALE vs expected, run swift scripts/build-cable-db.swift' if headline['db_stale'] else 'in sync with expected'}).")
    print(f"Nonzero corpus pairs absent from known-cables.md: {headline['absent_nonzero_pairs']} "
          f"({headline['absent_pairs_pid_zero']} of those have PID=0x0000, never resolvable at runtime). "
          f"Machines carrying >=1 uncatalogued nonzero cable: {headline['machines_with_uncatalogued_nonzero_cable']}.")
    print(f"known-cables.md identities never seen in corpus: {headline['known_cables_never_seen_in_corpus']} "
          f"of {headline['known_cables_nonzero_identities']}.")
    print()
    print(f"## Top {top_n} uncatalogued fingerprints worth chasing (ranked by machine count, PID != 0)\n")
    print("PID=0x0000 rows are excluded here since they can never resolve at runtime; "
          "they're still in missing-from-db.md (--out) for completeness.\n")
    print("| # | VID:PID | Vendor | Machines | VDO variant(s) | Hint |")
    print("|---|---|---|---|---|---|")
    shown = 0
    for r in missing_rows:
        if r["pid_zero"]:
            continue  # can never resolve; skip from the "worth chasing" list
        hint = r["hints"][0] if r["hints"] else ""
        shown += 1
        print(f"| {shown} | `{r['vid']}:{r['pid']}` | {r['vendor']} | {r['machines']} | "
              f"{r['vdo_variants']} | {hint} |")
        if shown >= top_n:
            break
    print()
    print("Pass --out DIR to write the full fingerprint-frequency.tsv, missing-from-db.md "
          "(all absentees incl. PID=0, with per-machine hints), and never-seen-in-corpus.md.")


if __name__ == "__main__":
    main()
