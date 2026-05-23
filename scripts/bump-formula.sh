#!/usr/bin/env bash
# Bump the whatcable-cli formula in the homebrew-whatcable tap to point at a
# new release. Parallel to bump-cask.sh, but for Formula/whatcable-cli.rb.
#
# Usage:
#   scripts/bump-formula.sh <version> <cli-zip-path>
#
# Configuration (via env or .env):
#   TAP_DIR              Path to the homebrew-whatcable repo. Required.
#   CASK_AUTOPUSH        If "1", run `git push` after committing. Default: 0.
#   CASK_VERIFY_REMOTE   If "1", download the asset from the GitHub release URL
#                        the formula points at and verify its sha256 matches
#                        the local zip before committing. Default: 0.
#   CASK_VERIFY_STRICT   If "1" and CASK_VERIFY_REMOTE=1, treat a 404 as a hard
#                        error rather than a warning.
#
# Skipped silently if TAP_DIR is unset, so build-app.sh can call it unconditionally.
set -euo pipefail

VERSION="${1:-}"
ZIP_PATH="${2:-}"

if [[ -z "${VERSION}" || -z "${ZIP_PATH}" ]]; then
    echo "usage: $0 <version> <cli-zip-path>" >&2
    exit 1
fi

if [[ -z "${TAP_DIR:-}" ]]; then
    echo "==> TAP_DIR not set, skipping whatcable-cli formula bump"
    exit 0
fi

if [[ ! -d "${TAP_DIR}" ]]; then
    echo "==> TAP_DIR=${TAP_DIR} does not exist, skipping whatcable-cli bump" >&2
    exit 0
fi

FORMULA_FILE="${TAP_DIR}/Formula/whatcable-cli.rb"
if [[ ! -f "${FORMULA_FILE}" ]]; then
    echo "==> Formula file ${FORMULA_FILE} not found, skipping whatcable-cli bump" >&2
    exit 0
fi

if [[ ! -f "${ZIP_PATH}" ]]; then
    echo "==> Zip ${ZIP_PATH} not found, cannot compute sha256" >&2
    exit 1
fi

NEW_SHA=$(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')

echo "==> Bumping whatcable-cli to ${VERSION}"
echo "    sha256: ${NEW_SHA}"

if [[ "${CASK_VERIFY_REMOTE:-0}" == "1" ]]; then
    REMOTE_URL="https://github.com/darrylmorley/whatcable/releases/download/v${VERSION}/whatcable-cli-${VERSION}.zip"
    echo "==> Verifying remote asset at ${REMOTE_URL}"

    HTTP_CODE=$(curl -sLI -o /dev/null -w "%{http_code}" "${REMOTE_URL}" || echo "000")
    if [[ "${HTTP_CODE}" != "200" ]]; then
        if [[ "${CASK_VERIFY_STRICT:-0}" == "1" ]]; then
            echo "    ERROR: remote asset returned HTTP ${HTTP_CODE}" >&2
            echo "    Publish the GitHub release first, or unset CASK_VERIFY_STRICT." >&2
            exit 1
        fi
        echo "    Remote returned HTTP ${HTTP_CODE}, release likely not published yet."
        echo "    Skipping remote verify."
    else
        TMP_ZIP=$(mktemp -t whatcable-cli-verify.XXXXXX).zip
        trap 'rm -f "${TMP_ZIP}"' EXIT
        curl -sL -o "${TMP_ZIP}" "${REMOTE_URL}"
        REMOTE_SHA=$(shasum -a 256 "${TMP_ZIP}" | awk '{print $1}')
        if [[ "${REMOTE_SHA}" != "${NEW_SHA}" ]]; then
            echo "    ERROR: sha mismatch between local zip and uploaded release asset" >&2
            echo "      local:  ${NEW_SHA}" >&2
            echo "      remote: ${REMOTE_SHA}" >&2
            exit 1
        fi
        echo "    Remote sha matches local. Proceeding."
    fi
fi

# BSD sed (-i '') vs GNU sed (-i)
if sed --version >/dev/null 2>&1; then
    SED_INPLACE=(sed -i)
else
    SED_INPLACE=(sed -i '')
fi

# The formula has no explicit `version` field; Homebrew parses the version
# from the URL automatically. We rewrite both occurrences of the version
# in the URL (v<ver>/whatcable-cli-<ver>.zip) in a single substitution.
"${SED_INPLACE[@]}" -E \
    "s|/download/v[0-9]+\.[0-9]+\.[0-9]+/whatcable-cli-[0-9]+\.[0-9]+\.[0-9]+\.zip|/download/v${VERSION}/whatcable-cli-${VERSION}.zip|" \
    "${FORMULA_FILE}"
"${SED_INPLACE[@]}" -E "s/^  sha256 \".*\"/  sha256 \"${NEW_SHA}\"/" "${FORMULA_FILE}"

cd "${TAP_DIR}"

if git diff --quiet -- Formula/whatcable-cli.rb; then
    echo "==> whatcable-cli formula already at ${VERSION} with this sha256, nothing to commit"
    exit 0
fi

git add Formula/whatcable-cli.rb
git commit -m "WhatCable CLI ${VERSION}"
echo "==> Committed whatcable-cli formula bump in ${TAP_DIR}"

if [[ "${CASK_AUTOPUSH:-0}" == "1" ]]; then
    echo "==> Pushing tap"
    git push
else
    echo "    (set CASK_AUTOPUSH=1 in .env to push automatically)"
fi
