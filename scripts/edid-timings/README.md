# EDID timing tables

`Sources/WhatCableCore/Display/EDIDTimingTables.generated.swift` is generated
from `data/edid-timings/vesa-dmt.csv` and `data/edid-timings/cta-861-vic.csv`.
Nothing in that file is hand-edited; the CSVs are also script output, never
hand-edited.

## Sources

The two CSVs are transcribed from the specs, which are the source of record:

- **VESA DMT Standard v1.0 Rev 13**:
  <https://glenwing.github.io/docs/VESA-DMT-1.13.pdf>
- **ANSI/CTA-861-H**:
  <https://archive.org/download/ansi-cta-861-h-final/ANSI-CTA-861-H-Final.pdf>

Both CSVs are cross-checked (numbers only, never structure or text) against
two independent references, at pinned versions:

- **edid-decode**, MIT licence, commit `f341ed8e3742118a86619e5f499017db2de30d94`
  (`utils/edid-decode/parse-base-block.cpp`'s `dmt_timings[]` and
  `parse-cta-block.cpp`'s `edid_cta_modes1[]` / `edid_cta_modes2[]`).
- The Linux kernel's `drivers/gpu/drm/drm_edid.c`, GPL-2.0, numeric
  cross-check only: nothing is copied from it, only compared against.
  (<https://raw.githubusercontent.com/torvalds/linux/master/drivers/gpu/drm/drm_edid.c>)

## Licensing note

The generated Swift file and the CSVs it comes from carry no MIT or GPL
notice: their content is transcribed from the VESA and CTA specs (which this
project licenses timing data from as the source of record), not from
edid-decode or the kernel. edid-decode and drm_edid.c are used only to
verify the transcription is numerically correct; check-edid-timings.py does
that verification and is the only script that reads them.

## Regenerating

1. Extract the VIC table from CTA-861-H:

   ```sh
   python3 scripts/edid-timings/extract-cta-vic.py --pdf <path-to-CTA-861-H.pdf> --out data/edid-timings/cta-861-vic.csv
   ```

2. Extract the DMT table from VESA DMT 1.13:

   ```sh
   python3 scripts/edid-timings/extract-dmt.py --pdf <path-to-VESA-DMT-1.13.pdf> --out data/edid-timings/vesa-dmt.csv
   ```

3. Cross-check both CSVs against edid-decode and the kernel:

   ```sh
   python3 scripts/edid-timings/check-edid-timings.py \
       --edid-decode-dir <path-to-edid-decode>/utils/edid-decode \
       --drm-edid <path-to-drm_edid.c>
   ```

   This must print `OK: 88 DMT rows and 154 VIC rows agree with edid-decode
   and drm_edid.c` before continuing. Any disagreement is investigated
   against the PDF page named in the CSV's `source_page` column and fixed in
   the extractor; the CSV itself is never hand-edited.

4. Regenerate the Swift file:

   ```sh
   swift scripts/edid-timings/build-edid-timings.swift
   ```

   `scripts/ci.sh` runs step 4 in `--check` mode (regenerate to a temp file,
   diff against the committed one) so a CSV change without a regenerate, or
   a hand edit to the generated Swift, fails CI.

None of these scripts download the PDFs; `--pdf` (steps 1-2) always takes a
local path, and `--help` on each documents where to get one.

## Row count: why 154, not 219

VIC 219 is the highest Video Identification Code CTA-861-H defines, but it
is not the row count. VICs 0 and 128 to 192 are reserved: CTA-861-H's
Table 1 defines no Video Format Timing for them (128-192 are also
"Forbidden" as SVD values in the CTA-861 sense, a separate but related
rule). The real count is 127 (VIC 1-127) + 27 (VIC 193-219) = 154, verified
three independent ways: the PDF text itself, edid-decode's
`edid_cta_modes1[]` (127 entries) + `edid_cta_modes2[]` (27 entries), and the
kernel's `edid_cea_modes_1[]` + `edid_cea_modes_193[]` (same 127 + 27).

## Who else reads these tables

`EDIDDisplayIDTimingDecoders.typeIVorVIII` (DisplayID Types IV and VIII) looks
up a DMT id in `EDIDTimingTables.dmt` and a VIC in `EDIDTimingTables.vic`, the
same two dictionaries this file's regenerate steps produce. An id missing
from either table yields no mode, same as an unresolved HDMI VIC.

`check-edid-timings.py`'s comparison above is against edid-decode's and the
kernel's own tables, not real EDIDs. The cross-check against real EDIDs is
`Tests/WhatCableDarwinTests/EDIDOracleSweepTests.swift`, which parses every
corpus EDID with the tables in place and compares the declared mode list
against edid-decode's output for the same file.

## Known convention difference: double-clocked SD formats

The legacy "720(1440)xN" analogue-heritage formats (VIC 6, 7, 8, 9, 21, 22,
23, 24, 44, 45, 50, 51, 54, 55, 58, 59) are pixel-repeated: each pixel is
sent twice. CTA-861-H's own Table 1 text and edid-decode both report the
*doubled* horizontal numbers (e.g. VIC 6: width 1440, pixel clock 27 MHz,
Htotal 1716), which is what this project's CSVs and Swift tables carry. The
Linux kernel instead stores the *native, undoubled* numbers (width 720,
pixel clock 13.5 MHz, Htotal 858) and marks the row with
`DRM_MODE_FLAG_DBLCLK`. `check-edid-timings.py` knows about this and doubles
the kernel's horizontal fields and pixel clock before comparing rows flagged
`DRM_MODE_FLAG_DBLCLK`; it is not a parsing bug, and the two references
agree once the convention difference is accounted for.
