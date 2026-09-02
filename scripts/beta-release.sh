#!/usr/bin/env bash
# Ship a WhatCable beta build.
#
# Usage:
#   scripts/beta-release.sh <version> [build-number]
#   scripts/beta-release.sh --dry-run <version> [build-number]
#
# <version> must look like a beta version, e.g. 1.2.0-beta.1
# (a plain stable version like 1.2.0 is rejected).
#
# Beta builds ship as GitHub PRE-releases on the public repo
# (darrylmorley/whatcable). GitHub's `releases/latest` API excludes
# pre-releases, so the in-app updater and Homebrew never see a beta:
# only testers who go to the release page manually will find it.
#
# Differences from scripts/release.sh (the stable release script):
#   - No Homebrew cask/formula bump. Runs smoke-test.sh directly, never
#     build-app.sh (build-app.sh is the one that touches the tap).
#   - No TAP_DIR checks, no tap push.
#   - No issue auto-close: a beta isn't "the fix is out", so issues stay
#     open until the matching stable release ships.
#   - release-notes/v<version>.md is optional. If missing, a stock beta
#     blurb is used instead.
#
# Steps, in order:
#   1.  Sanity checks: clean tree, on main, tag doesn't exist, gh CLI
#       present.
#   2.  Patch VERSION and BUILD_NUMBER in scripts/smoke-test.sh.
#   3.  Commit the version bump.
#   4.  Run scripts/smoke-test.sh (build, sign, notarise, smoke-test).
#   5.  Tag v<version>, push main, push tag, wait for the mirror to push
#       the tag to public.
#   6.  gh release create --prerelease with the zips.
#   7.  Verify the uploaded assets byte-match the local zips.
#
# --dry-run prints what each step would do but skips: commits, tag push,
# the notarised build, gh release create, asset verification. It still
# runs the sanity checks so you can validate state.
#
# Resuming a beta that failed mid-flight:
# If the script dies after the tag push (mirror wait timeout, gh release
# create failure), do NOT re-run the whole script: the tag-exists sanity
# check will refuse, since the tag is already on private origin. Instead
# finish by hand:
#
#   gh release create "v<version>" dist/WhatCable.zip \
#       "dist/whatcable-cli-<version>.zip" \
#       --repo darrylmorley/whatcable \
#       --prerelease \
#       --title "v<version> (beta)" \
#       --notes "<blurb or notes file>"
#
# Then re-run the asset verification manually (gh release download + shasum
# compare against dist/). gh release create errors loudly if the release
# already exists; run `gh release delete v<version>` first to redo it.

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
    echo "  e.g. $0 1.2.0-beta.1 118" >&2
    exit 1
fi

# Validate version looks like a beta version. This is the guard that stops
# a stable version being shipped as a pre-release through this script.
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+$ ]]; then
    echo "ERROR: version '${VERSION}' is not a beta version (e.g. 1.2.0-beta.1)." >&2
    echo "       Use scripts/release.sh for a stable release." >&2
    exit 1
fi

# If build-number not given, infer it: current BUILD_NUMBER + 1.
if [[ -z "${BUILD_NUMBER}" ]]; then
    CURRENT_BUILD=$(grep -E '^BUILD_NUMBER=' scripts/smoke-test.sh | head -1 | sed -E 's/.*"([0-9]+)".*/\1/')
    BUILD_NUMBER=$((CURRENT_BUILD + 1))
fi

# BUILD_NUMBER gets sed-spliced into smoke-test.sh, which is then executed, so it must be a plain integer.
if [[ ! "${BUILD_NUMBER}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: build number '${BUILD_NUMBER}' is not a plain integer." >&2
    exit 1
fi

echo "==> Releasing WhatCable v${VERSION} (build ${BUILD_NUMBER}) as a BETA pre-release"
[[ "${DRY_RUN}" == "1" ]] && echo "    DRY RUN: no commits, tags, builds, or pushes will be made"

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
ORIGIN_TAGS=$(git ls-remote --tags origin "v${VERSION}") || {
    echo "ERROR: could not check tags on origin." >&2
    exit 1
}
if echo "${ORIGIN_TAGS}" | grep -q "refs/tags/v${VERSION}$"; then
    echo "ERROR: tag v${VERSION} already exists on private origin." >&2
    exit 1
fi
if git remote get-url public >/dev/null 2>&1; then
    PUBLIC_TAGS=$(git ls-remote --tags public "v${VERSION}") || {
        echo "ERROR: could not check tags on public." >&2
        exit 1
    }
    if echo "${PUBLIC_TAGS}" | grep -q "refs/tags/v${VERSION}$"; then
        echo "ERROR: tag v${VERSION} already exists on public repo." >&2
        exit 1
    fi
else
    echo "    no 'public' remote configured, skipping public tag check (the mirror-wait step later still guards against collisions)"
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

echo "    all checks passed"

# Pending-at-release items WARN here rather than blocking, unlike release.sh.
# A pending item is usually not relevant until the stable ships, and blocking
# beta builds on it would push people to clear the list early, which defeats
# the point of the gate. Printed so nobody is surprised by it at stable time.
PENDING_FILE="planning/RELEASE-PENDING.md"
# Same matcher as release.sh: loose about bullet and indentation, because a
# strict pattern would let ordinary Markdown variants through unseen.
PENDING_RE='^[[:space:]]*([-*+]|[0-9]{1,9}[.)])[[:space:]]+\[[[:space:]]\]'
if [[ -r "${PENDING_FILE}" ]]; then
    set +e
    PENDING_ITEMS=$(grep -nE "${PENDING_RE}" "${PENDING_FILE}")
    PENDING_STATUS=$?
    set -e
    if [[ ${PENDING_STATUS} -gt 1 ]]; then
        echo
        echo "    NOTE: could not read ${PENDING_FILE} (grep exit ${PENDING_STATUS})."
        echo "    Betas are not blocked by it, but check it before the next stable."
        echo
    fi
    if [[ -n "${PENDING_ITEMS}" ]]; then
        echo
        echo "    NOTE: ${PENDING_FILE} has unticked items. Betas are not blocked"
        echo "    by them, but the next STABLE release will be:"
        echo "${PENDING_ITEMS}" | sed 's/^/      /'
        echo
    fi
else
    # Absent or unreadable warns here rather than blocking; release.sh is where
    # that becomes an error.
    echo
    echo "    NOTE: ${PENDING_FILE} is missing or unreadable. It is tracked, so"
    echo "    that is probably a broken checkout. The next stable release will"
    echo "    refuse to run until it is back."
    echo
fi

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

# ---- 4. Build, sign, notarise, smoke-test --------------------------------

# Deliberately run smoke-test.sh directly, not build-app.sh: build-app.sh
# also bumps the Homebrew cask/formula, which must never happen for a beta.
#
# --require-distributable has to be passed explicitly here for that same
# reason. Skipping build-app.sh skips the flag it adds, so without this line a
# beta is the one release path with no signature gate on it, and a beta is
# precisely a build handed to real people to run.
if [[ "${DRY_RUN}" == "0" ]]; then
    echo "==> Running scripts/smoke-test.sh"
    ./scripts/smoke-test.sh --require-distributable
else
    echo "==> Would run scripts/smoke-test.sh --require-distributable (skipped in dry run)"
fi

# ---- 5. Tag and push -----------------------------------------------------

if [[ "${DRY_RUN}" == "0" ]]; then
    echo "==> Tagging v${VERSION} and pushing main + tag to private"
    git tag -a "v${VERSION}" -m "v${VERSION}"
    git push origin main
    git push origin "v${VERSION}"

    # Wait for the mirror action to push the tag to public.
    # gh release create will fail if the tag doesn't exist on public yet.
    # Use the singular "ref" exact-match endpoint, not the plural "refs"
    # prefix-match one, so e.g. v1.2.0-beta.1 doesn't false-match on a
    # pre-existing v1.2.0-beta.10.
    echo "==> Waiting for mirror to push tag to public..."
    for i in $(seq 1 30); do
        if gh api "repos/darrylmorley/whatcable/git/ref/tags/v${VERSION}" \
           --jq '.ref' 2>/dev/null; then
            echo "    Tag v${VERSION} found on public."
            break
        fi
        if [ "$i" -eq 30 ]; then
            echo "ERROR: tag not found on public after 5 minutes." >&2
            echo "Check the mirror action in the upstream repository's Actions tab." >&2
            exit 1
        fi
        sleep 10
    done
fi

# ---- 6. Create the GitHub PRE-release on PUBLIC repo ----------------------

NOTES_FILE="release-notes/v${VERSION}.md"
STOCK_NOTES="Beta build for testers. Not recommended for general use.

Install by downloading WhatCable.zip below, unzipping, and dragging
WhatCable.app into /Applications over your existing copy.

Please report anything odd on the issue tracker:
https://github.com/darrylmorley/whatcable/issues"

if [[ -f "${NOTES_FILE}" ]]; then
    RELEASE_TITLE_FIRST_LINE=$(head -1 "${NOTES_FILE}" | sed -E 's/^#+[[:space:]]*//')
    if [[ -z "${RELEASE_TITLE_FIRST_LINE}" ]]; then
        RELEASE_TITLE="v${VERSION} (beta)"
    else
        RELEASE_TITLE="v${VERSION}: ${RELEASE_TITLE_FIRST_LINE}"
    fi
else
    RELEASE_TITLE="v${VERSION} (beta)"
fi

if [[ "${DRY_RUN}" == "0" ]]; then
    echo "==> gh release create v${VERSION} (pre-release) on darrylmorley/whatcable"
    if [[ -f "${NOTES_FILE}" ]]; then
        gh release create "v${VERSION}" \
            dist/WhatCable.zip \
            "dist/whatcable-cli-${VERSION}.zip" \
            --repo darrylmorley/whatcable \
            --prerelease \
            --title "${RELEASE_TITLE}" \
            --notes-file "${NOTES_FILE}"
    else
        gh release create "v${VERSION}" \
            dist/WhatCable.zip \
            "dist/whatcable-cli-${VERSION}.zip" \
            --repo darrylmorley/whatcable \
            --prerelease \
            --title "${RELEASE_TITLE}" \
            --notes "${STOCK_NOTES}"
    fi
else
    echo "==> Would create pre-release: ${RELEASE_TITLE}"
    if [[ -f "${NOTES_FILE}" ]]; then
        echo "    notes from: ${NOTES_FILE}"
    else
        echo "    notes: stock beta blurb (${NOTES_FILE} not found)"
    fi
fi

# ---- 7. Verify uploaded assets match local zips ---------------------------

if [[ "${DRY_RUN}" == "0" ]]; then
    echo "==> Verifying remote assets match local"

    VERIFY_DIR=$(mktemp -d)
    trap 'rm -rf "${VERIFY_DIR}"' EXIT

    APP_ASSET="WhatCable.zip"
    CLI_ASSET="whatcable-cli-${VERSION}.zip"

    gh release download "v${VERSION}" --repo darrylmorley/whatcable \
        --pattern "${APP_ASSET}" --dir "${VERIFY_DIR}"
    gh release download "v${VERSION}" --repo darrylmorley/whatcable \
        --pattern "${CLI_ASSET}" --dir "${VERIFY_DIR}"

    LOCAL_APP_SHA=$(shasum -a 256 "dist/${APP_ASSET}" | awk '{print $1}')
    REMOTE_APP_SHA=$(shasum -a 256 "${VERIFY_DIR}/${APP_ASSET}" | awk '{print $1}')
    LOCAL_CLI_SHA=$(shasum -a 256 "dist/${CLI_ASSET}" | awk '{print $1}')
    REMOTE_CLI_SHA=$(shasum -a 256 "${VERIFY_DIR}/${CLI_ASSET}" | awk '{print $1}')

    if [[ "${LOCAL_APP_SHA}" != "${REMOTE_APP_SHA}" ]]; then
        echo "ERROR: uploaded ${APP_ASSET} does not match local dist/${APP_ASSET}." >&2
        echo "  local:  ${LOCAL_APP_SHA}" >&2
        echo "  remote: ${REMOTE_APP_SHA}" >&2
        exit 1
    fi
    if [[ "${LOCAL_CLI_SHA}" != "${REMOTE_CLI_SHA}" ]]; then
        echo "ERROR: uploaded ${CLI_ASSET} does not match local dist/${CLI_ASSET}." >&2
        echo "  local:  ${LOCAL_CLI_SHA}" >&2
        echo "  remote: ${REMOTE_CLI_SHA}" >&2
        exit 1
    fi
    echo "    both assets verified byte-identical to local build."
fi

echo
if [[ "${DRY_RUN}" == "1" ]]; then
    echo "Dry run complete. Re-run without --dry-run to ship v${VERSION} as a beta."
else
    echo "v${VERSION} shipped as a beta pre-release."
    echo "  Release: https://github.com/darrylmorley/whatcable/releases/tag/v${VERSION}"
    echo "  This will NOT show up as an update for normal users or Homebrew:"
    echo "  pre-releases are excluded from the releases/latest API."
    echo "  Testers install manually from the release page above."
fi
