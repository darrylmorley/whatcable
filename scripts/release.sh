#!/usr/bin/env bash
# Release WhatCable end to end.
#
# Usage:
#   scripts/release.sh <version> [build-number]
#   scripts/release.sh --dry-run <version> [build-number]
#
# Steps, in order:
#   1.  Sanity checks: clean tree, on main, tag doesn't exist, gh CLI present,
#       release-notes/v<version>.md exists.
#   2.  Patch VERSION and BUILD_NUMBER in scripts/smoke-test.sh.
#   3.  Commit the version bump.
#   4.  Run scripts/build-app.sh (calls smoke-test.sh for build/sign/notarise/
#       smoke-test, then bumps the cask locally -- commit only, no push).
#   5.  Tag v<version>, push main, push tag.
#   6.  gh release create with the zip + release-notes/v<version>.md.
#   7.  Re-run bump-cask.sh with CASK_VERIFY_REMOTE=1 CASK_VERIFY_STRICT=1 to
#       prove the uploaded asset matches the locally built one.
#   8.  Copy release-notes/v<version>.md into the tap and amend the cask
#       commit with it, then push the tap.
#
# Anything in steps 5-8 can be re-run idempotently if the script is interrupted
# (gh release create is the one place that errors loudly on re-run; you can
# `gh release delete` and try again).
#
# --dry-run prints what each step would do but skips: commits, tag push, the
# notarised build, gh release create, cask push. It still runs the sanity
# checks so you can validate state.

set -euo pipefail

cd "$(dirname "$0")/.."

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
    shift
fi

VERSION="${1:-}"
BUILD_NUMBER="${2:-}"

if [[ -z "${VERSION}" ]]; then
    echo "usage: $0 [--dry-run] <version> [build-number]" >&2
    echo "  e.g. $0 0.5.3 17" >&2
    exit 1
fi

# If build-number not given, infer it: current BUILD_NUMBER + 1.
if [[ -z "${BUILD_NUMBER}" ]]; then
    CURRENT_BUILD=$(grep -E '^BUILD_NUMBER=' scripts/smoke-test.sh | head -1 | sed -E 's/.*"([0-9]+)".*/\1/')
    BUILD_NUMBER=$((CURRENT_BUILD + 1))
fi

# Validate version looks semver-ish.
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: version '${VERSION}' is not a dotted triple (e.g. 0.5.3)." >&2
    exit 1
fi

echo "==> Releasing WhatCable v${VERSION} (build ${BUILD_NUMBER})"
[[ "${DRY_RUN}" == "1" ]] && echo "    DRY RUN — no commits, tags, builds, or pushes will be made"

# ---- 1. Sanity checks ----------------------------------------------------

echo "==> Sanity checks"

if [[ -f ".env" ]]; then
    # shellcheck disable=SC1091
    set -a; source .env; set +a
fi

# Must be in a git checkout.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: not inside a git checkout." >&2
    exit 1
fi

# Must be on main.
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "${BRANCH}" != "main" ]]; then
    echo "ERROR: on branch '${BRANCH}', expected 'main'." >&2
    exit 1
fi

# Working tree must be clean.
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "ERROR: working tree has uncommitted changes." >&2
    git status --short >&2
    exit 1
fi

# Tag must not already exist locally or remotely.
if git rev-parse "v${VERSION}" >/dev/null 2>&1; then
    echo "ERROR: tag v${VERSION} already exists locally." >&2
    exit 1
fi
if git ls-remote --tags origin "v${VERSION}" | grep -q "v${VERSION}"; then
    echo "ERROR: tag v${VERSION} already exists on origin." >&2
    exit 1
fi

# gh CLI required for release creation.
if ! command -v gh >/dev/null 2>&1; then
    echo "ERROR: gh CLI not found. Install it: brew install gh" >&2
    exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
    echo "ERROR: gh not authenticated. Run: gh auth login" >&2
    exit 1
fi

# Release notes must exist.
NOTES_FILE="release-notes/v${VERSION}.md"
if [[ ! -f "${NOTES_FILE}" ]]; then
    echo "ERROR: ${NOTES_FILE} not found. Write the release notes first." >&2
    exit 1
fi

# Tap dir, if configured, must exist and be clean.
if [[ -n "${TAP_DIR:-}" ]]; then
    if [[ ! -d "${TAP_DIR}" ]]; then
        echo "ERROR: TAP_DIR=${TAP_DIR} does not exist." >&2
        exit 1
    fi
    if ! git -C "${TAP_DIR}" diff --quiet || ! git -C "${TAP_DIR}" diff --cached --quiet; then
        echo "ERROR: tap repo at ${TAP_DIR} has uncommitted changes." >&2
        git -C "${TAP_DIR}" status --short >&2
        exit 1
    fi
    TAP_BRANCH=$(git -C "${TAP_DIR}" rev-parse --abbrev-ref HEAD)
    if [[ "${TAP_BRANCH}" != "main" ]]; then
        echo "ERROR: tap on branch '${TAP_BRANCH}', expected 'main'." >&2
        exit 1
    fi
fi

echo "    all checks passed"

# ---- 2. Patch smoke-test.sh ----------------------------------------------

echo "==> Updating VERSION=${VERSION} BUILD_NUMBER=${BUILD_NUMBER} in scripts/smoke-test.sh"

# BSD sed (-i '') vs GNU sed (-i)
if sed --version >/dev/null 2>&1; then
    SED_INPLACE=(sed -i)
else
    SED_INPLACE=(sed -i '')
fi

if [[ "${DRY_RUN}" == "0" ]]; then
    "${SED_INPLACE[@]}" -E "s/^VERSION=\".*\"/VERSION=\"${VERSION}\"/" scripts/smoke-test.sh
    "${SED_INPLACE[@]}" -E "s/^BUILD_NUMBER=\".*\"/BUILD_NUMBER=\"${BUILD_NUMBER}\"/" scripts/smoke-test.sh
fi

# ---- 3. Commit the bump --------------------------------------------------

if [[ "${DRY_RUN}" == "0" ]]; then
    if ! git diff --quiet scripts/smoke-test.sh; then
        git add scripts/smoke-test.sh
        git commit -m "Bump version to ${VERSION} (build ${BUILD_NUMBER})"
    else
        echo "    (smoke-test.sh already at this version, no commit needed)"
    fi
fi

# ---- 4. Build, sign, notarise, smoke-test, local cask bump ---------------

if [[ "${DRY_RUN}" == "0" ]]; then
    echo "==> Running scripts/build-app.sh"
    ./scripts/build-app.sh
else
    echo "==> Would run scripts/build-app.sh (skipped in dry run)"
fi

# ---- 5. Tag and push -----------------------------------------------------

if [[ "${DRY_RUN}" == "0" ]]; then
    echo "==> Tagging v${VERSION} and pushing main + tag"
    git tag -a "v${VERSION}" -m "v${VERSION}"
    git push origin main
    git push origin "v${VERSION}"
fi

# ---- 6. Create the GitHub release ----------------------------------------

RELEASE_TITLE_FIRST_LINE=$(head -1 "${NOTES_FILE}" | sed -E 's/^#+\s*//')
if [[ -z "${RELEASE_TITLE_FIRST_LINE}" ]]; then
    RELEASE_TITLE="v${VERSION}"
else
    RELEASE_TITLE="v${VERSION}: ${RELEASE_TITLE_FIRST_LINE}"
fi

if [[ "${DRY_RUN}" == "0" ]]; then
    echo "==> gh release create v${VERSION}"
    gh release create "v${VERSION}" dist/WhatCable.zip \
        --title "${RELEASE_TITLE}" \
        --notes-file "${NOTES_FILE}"
else
    echo "==> Would create release: ${RELEASE_TITLE}"
fi

# ---- 7. Verify uploaded asset matches local zip --------------------------

if [[ "${DRY_RUN}" == "0" && -n "${TAP_DIR:-}" ]]; then
    echo "==> Verifying remote asset sha matches local"
    CASK_VERIFY_REMOTE=1 CASK_VERIFY_STRICT=1 \
        ./scripts/bump-cask.sh "${VERSION}" "dist/WhatCable.zip"
fi

# ---- 8. Sync release notes into tap and push -----------------------------

if [[ "${DRY_RUN}" == "0" && -n "${TAP_DIR:-}" ]]; then
    echo "==> Syncing release notes into tap and pushing"
    cp "${NOTES_FILE}" "${TAP_DIR}/release-notes/v${VERSION}.md"
    if ! git -C "${TAP_DIR}" diff --quiet -- "release-notes/v${VERSION}.md"; then
        # Amend the cask commit with the release notes so the tap has one
        # commit per release rather than two.
        git -C "${TAP_DIR}" add "release-notes/v${VERSION}.md"
        git -C "${TAP_DIR}" commit --amend --no-edit
    elif git -C "${TAP_DIR}" status --porcelain | grep -q "release-notes/v${VERSION}.md"; then
        git -C "${TAP_DIR}" add "release-notes/v${VERSION}.md"
        git -C "${TAP_DIR}" commit --amend --no-edit
    fi
    git -C "${TAP_DIR}" push --force-with-lease
fi

echo
if [[ "${DRY_RUN}" == "1" ]]; then
    echo "Dry run complete. Re-run without --dry-run to ship v${VERSION}."
else
    echo "v${VERSION} shipped."
    echo "  GitHub:   https://github.com/darrylmorley/whatcable/releases/tag/v${VERSION}"
    echo "  Homebrew: brew upgrade --cask whatcable"
fi
