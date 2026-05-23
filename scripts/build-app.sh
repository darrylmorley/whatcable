#!/usr/bin/env bash
# Full release build: smoke-test.sh + Homebrew cask bump.
#
# This script is called by scripts/release.sh. For day-to-day verification
# builds that should NOT touch the Homebrew tap, run scripts/smoke-test.sh
# directly instead.
#
# Flags:
#   --pro   Passed through to smoke-test.sh to include Pro features.
#
# Configure via .env (see .env.example).
set -euo pipefail

cd "$(dirname "$0")/.."

# Collect flags to forward to smoke-test.sh.
SMOKE_ARGS=()
for arg in "$@"; do
    case "${arg}" in
        --pro) SMOKE_ARGS+=("--pro") ;;
    esac
done

# smoke-test.sh handles: .env loading, tests, build, sign, notarise, staple,
# Gatekeeper verify, alive checks, and zip creation.
./scripts/smoke-test.sh "${SMOKE_ARGS[@]+"${SMOKE_ARGS[@]}"}"

# Load .env again so we have TAP_DIR and other vars in this shell.
if [[ -f ".env" ]]; then
    # shellcheck disable=SC1091
    set -a; source .env; set +a
fi

# Source version constants so the cask bump gets the right version.
# These are set at the top of smoke-test.sh (and patched by release.sh).
VERSION=$(grep -E '^VERSION=' scripts/smoke-test.sh | head -1 | sed -E 's/VERSION="(.*)"/\1/')

if [[ -x "scripts/bump-cask.sh" ]]; then
    echo "==> Bumping Homebrew cask (no-op unless TAP_DIR is set)"
    ./scripts/bump-cask.sh "${VERSION}" "dist/WhatCable.zip" || \
        echo "    cask bump failed (non-fatal)"
fi

if [[ -x "scripts/bump-formula.sh" ]]; then
    echo "==> Bumping whatcable-cli formula (no-op unless TAP_DIR is set)"
    ./scripts/bump-formula.sh "${VERSION}" "dist/whatcable-cli-${VERSION}.zip" || \
        echo "    whatcable-cli formula bump failed (non-fatal)"
fi
