#!/usr/bin/env bash
# Refresh the bundled USB-IF Vendor ID list.
#
# Downloads USB-IF's official vendor ID PDF, parses it with pdftotext,
# and writes a tab-separated lookup file at:
#   Sources/WhatCableCore/Resources/usbif-vendors.tsv
#
# The output is committed to the repo. Re-run this script when USB-IF
# publishes a newer list. Override the source via:
#   USBIF_VID_URL="https://www.usb.org/.../vendor_ids_NEWER.pdf" \
#     scripts/update-vendor-db.sh
#
# Requires: pdftotext (brew install poppler).
set -euo pipefail

cd "$(dirname "$0")/.."

URL="${USBIF_VID_URL:-https://www.usb.org/sites/default/files/vendor_ids03102026_0.pdf}"
RESOURCE_DIR="Sources/WhatCableCore/Resources"
OUTPUT="${RESOURCE_DIR}/usbif-vendors.tsv"

if ! command -v pdftotext >/dev/null 2>&1; then
    echo "Error: pdftotext not found. Install with:" >&2
    echo "  brew install poppler" >&2
    exit 1
fi

mkdir -p "$RESOURCE_DIR"
TMP_PDF=$(mktemp -t usbif-vids-XXXXXX).pdf
TMP_TXT=$(mktemp -t usbif-vids-XXXXXX).txt
trap 'rm -f "$TMP_PDF" "$TMP_TXT"' EXIT

echo "==> Downloading $URL"
curl -fsSL "$URL" -o "$TMP_PDF"
SIZE=$(stat -f%z "$TMP_PDF" 2>/dev/null || stat -c%s "$TMP_PDF")
echo "    $SIZE bytes"

echo "==> Extracting text"
pdftotext -layout "$TMP_PDF" "$TMP_TXT"

echo "==> Parsing vendor entries"
# Each vendor row in the layout-preserved text looks like:
#   "<company name>     <2+ spaces>     <decimal vid>"
# Skip blank lines and the table header.
{
    echo "# USB-IF Vendor ID lookup"
    echo "# Source: $URL"
    echo "# Fetched: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "# Format: <decimal_vid>\t<vendor_name>"
    perl -ne '
        # pdftotext emits a form-feed (\x0C) at the start of each page,
        # which can land glued onto a vendor name. Strip any control
        # characters from the line before parsing.
        s/[\x00-\x08\x0B-\x1F\x7F]+//g;
        next if /^\s*$/;
        next if /^\s*(Company|Vendor ID|\(Decimal Format\))/;
        if (/^(.*?\S)\s{2,}(\d+)\s*$/) {
            my ($name, $vid) = ($1, $2);
            $name =~ s/^\s+|\s+$//g;
            print "$vid\t$name\n";
        }
    ' "$TMP_TXT" | sort -n -u
} > "$OUTPUT"

# Count vendor entries (non-comment lines)
COUNT=$(grep -cv '^#' "$OUTPUT" || true)
echo "==> Wrote $COUNT vendor entries to $OUTPUT"

# Sanity: a few well-known VIDs should resolve.
echo "==> Sanity check"
for entry in "1452:Apple" "11037:Lintes" "8341:CE LINK"; do
    dec="${entry%:*}"
    expect="${entry#*:}"
    line=$(grep -E "^${dec}	" "$OUTPUT" || true)
    if [[ -z "$line" ]]; then
        echo "    WARN: VID $dec not found in output (expected $expect)" >&2
    else
        echo "    $line"
    fi
done
