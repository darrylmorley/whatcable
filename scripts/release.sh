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
#   9.  Close public issues referenced by closing keywords in commits since
#       the previous tag, commenting "Fixed in v<version>.".
#
# Anything in steps 5-9 can be re-run idempotently if the script is interrupted
# (gh release create is the one place that errors loudly on re-run; you can
# `gh release delete` and try again). Step 9 skips issues that are already
# closed, so a re-run is a no-op.
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

# BUILD_NUMBER gets sed-spliced into smoke-test.sh, which is then executed, so it must be a plain integer.
if [[ ! "${BUILD_NUMBER}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: build number '${BUILD_NUMBER}' is not a plain integer." >&2
    exit 1
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

# Release notes must exist.
NOTES_FILE="release-notes/v${VERSION}.md"
if [[ ! -f "${NOTES_FILE}" ]]; then
    echo "ERROR: ${NOTES_FILE} not found. Write the release notes first." >&2
    exit 1
fi

# Anything still pending at release time blocks the release.
#
# This exists because "remember at release" items were living in PR bodies and
# in Darryl's head, which is not a system. The gate fires at the moment it
# matters (running this script) rather than hoping somebody checks a board, and
# it clears itself: folding the items into the notes file above is normally how
# they get done.
PENDING_FILE="planning/RELEASE-PENDING.md"
# The file is tracked, so it is always meant to be here. A missing or unreadable
# one is a broken checkout or a bad merge, not permission to ship: a gate whose
# whole job is to stop a release must not disappear quietly when its input does.
if [[ ! -f "${PENDING_FILE}" ]]; then
    echo "ERROR: ${PENDING_FILE} is missing. It is tracked, so this is a broken" >&2
    echo "checkout or a bad merge. Restore it (git checkout -- ${PENDING_FILE})" >&2
    echo "before releasing; an empty list is fine, an absent one is not." >&2
    exit 1
fi
if [[ ! -r "${PENDING_FILE}" ]]; then
    echo "ERROR: ${PENDING_FILE} exists but is not readable, so its contents" >&2
    echo "cannot be checked. Fix the permissions before releasing." >&2
    exit 1
fi
# An unticked item is a task-list line whose box is empty. Deliberately loose
# about the bullet and the leading space: "-", "*" and "+" are all valid
# Markdown bullets, and an item indented under a heading is the obvious thing
# someone will write. A strict '^- \[ \]' would let any of those through
# silently, which for this gate means shipping while the list still has work in
# it. Ticked boxes ("[x]") and the prose around them do not match.
PENDING_RE='^[[:space:]]*([-*+]|[0-9]{1,9}[.)])[[:space:]]+\[[[:space:]]\]'
# grep exits 0 when it matches, 1 when it does not, and 2 on a real error.
# Only 1 is an all-clear; 2 must not be swallowed into one.
set +e
PENDING_ITEMS=$(grep -nE "${PENDING_RE}" "${PENDING_FILE}")
PENDING_STATUS=$?
set -e
if [[ ${PENDING_STATUS} -gt 1 ]]; then
    echo "ERROR: could not read ${PENDING_FILE} (grep exit ${PENDING_STATUS})." >&2
    echo "Not proceeding: an unchecked list is not an empty one." >&2
    exit 1
fi
if [[ -n "${PENDING_ITEMS}" ]]; then
    echo "ERROR: ${PENDING_FILE} still has unticked items, so this release is blocked." >&2
    echo >&2
    echo "${PENDING_ITEMS}" >&2
    echo >&2
    echo "Do each one, tick it, then remove the ticked lines. Items that are" >&2
    echo "release-note text belong in ${NOTES_FILE}." >&2
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
    echo "==> Tagging v${VERSION} and pushing main + tag to private"
    git tag -a "v${VERSION}" -m "v${VERSION}"
    git push origin main
    git push origin "v${VERSION}"

    # Wait for the mirror action to push the tag to public.
    # gh release create will fail if the tag doesn't exist on public yet.
    echo "==> Waiting for mirror to push tag to public..."
    for i in $(seq 1 30); do
        if gh api "repos/darrylmorley/whatcable/git/refs/tags/v${VERSION}" \
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

# ---- 6. Create the GitHub release on PUBLIC repo -------------------------

RELEASE_TITLE_FIRST_LINE=$(head -1 "${NOTES_FILE}" | sed -E 's/^#+[[:space:]]*//')
if [[ -z "${RELEASE_TITLE_FIRST_LINE}" ]]; then
    RELEASE_TITLE="v${VERSION}"
else
    RELEASE_TITLE="v${VERSION}: ${RELEASE_TITLE_FIRST_LINE}"
fi

if [[ "${DRY_RUN}" == "0" ]]; then
    echo "==> gh release create v${VERSION} on darrylmorley/whatcable"
    gh release create "v${VERSION}" \
        dist/WhatCable.zip \
        "dist/whatcable-cli-${VERSION}.zip" \
        --repo darrylmorley/whatcable \
        --title "${RELEASE_TITLE}" \
        --notes-file "${NOTES_FILE}"
else
    echo "==> Would create release: ${RELEASE_TITLE}"
fi

# ---- 7. Verify uploaded asset matches local zip --------------------------

if [[ "${DRY_RUN}" == "0" && -n "${TAP_DIR:-}" ]]; then
    echo "==> Verifying remote asset shas match local"
    CASK_VERIFY_REMOTE=1 CASK_VERIFY_STRICT=1 \
        ./scripts/bump-cask.sh "${VERSION}" "dist/WhatCable.zip"
    CASK_VERIFY_REMOTE=1 CASK_VERIFY_STRICT=1 \
        ./scripts/bump-formula.sh "${VERSION}" "dist/whatcable-cli-${VERSION}.zip"
fi

# ---- 8. Sync release notes into tap and push -----------------------------

if [[ "${DRY_RUN}" == "0" && -n "${TAP_DIR:-}" ]]; then
    echo "==> Syncing release notes into tap and pushing"
    cp "${NOTES_FILE}" "${TAP_DIR}/release-notes/v${VERSION}.md"
    # NOTE: this amends HEAD, which is whichever bump script ran last in
    # build-app.sh (currently bump-formula.sh, after bump-cask.sh). If the
    # order of those bumps changes, the release notes will land on the
    # other commit. That's cosmetic, but worth being aware of.
    if ! git -C "${TAP_DIR}" diff --quiet -- "release-notes/v${VERSION}.md"; then
        git -C "${TAP_DIR}" add "release-notes/v${VERSION}.md"
        git -C "${TAP_DIR}" commit --amend --no-edit
    elif git -C "${TAP_DIR}" status --porcelain | grep -q "release-notes/v${VERSION}.md"; then
        git -C "${TAP_DIR}" add "release-notes/v${VERSION}.md"
        git -C "${TAP_DIR}" commit --amend --no-edit
    fi
    git -C "${TAP_DIR}" push --force-with-lease
fi

# ---- 9. Close fixed issues on the public repo ----------------------------

# Issues live on the public repo (darrylmorley/whatcable), but the fix
# commits land here via PRs whose messages use closing keywords. The mirror
# flattens history into a single "Mirror from private" commit, so GitHub
# never sees the keyword on public and can't auto-close. Do it explicitly
# here, once the release is actually live, referencing the version. Only
# closing keywords ("Closes/Fixes/Resolves #N") match, so a bare "(#NN)" PR
# suffix is ignored.
# `|| true` keeps a no-match grep (exit 1) from aborting the whole release
# under `set -euo pipefail`; the empty result then trips the guards below.
# Beta tags (e.g. v1.2.0-beta.1) sort ahead of the stable they precede, so
# the previous tag must be the last STABLE release: positively select
# dotted-triple tags rather than excluding known pre-release spellings, so
# the issue scan can't be fooled by a future pre-release naming scheme.
PREV_TAG=$(git tag --list 'v*' --sort=-version:refname | grep -vxF "v${VERSION}" | grep -Ex 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
if [[ -z "${PREV_TAG}" ]]; then
    echo "==> No previous tag found; skipping issue auto-close"
else
    # Bind the range to the published tag, not HEAD, so the issue set is
    # frozen to what shipped and a re-run stays a no-op even if new commits
    # have landed since the tag.
    FIXED_ISSUES=$(git log "${PREV_TAG}..v${VERSION}" --pretty=%B \
        | grep -ioE '(close[sd]?|fix(es|ed)?|resolve[sd]?) +#[0-9]+' \
        | grep -oE '[0-9]+' \
        | sort -un || true)
    if [[ -z "${FIXED_ISSUES}" ]]; then
        echo "==> No issues referenced with closing keywords since ${PREV_TAG}"
    elif [[ "${DRY_RUN}" == "1" ]]; then
        echo "==> Would close on darrylmorley/whatcable (since ${PREV_TAG}):"
        for n in ${FIXED_ISSUES}; do echo "      #${n}"; done
    else
        echo "==> Closing fixed issues on darrylmorley/whatcable (since ${PREV_TAG})"
        for n in ${FIXED_ISSUES}; do
            STATE=$(gh issue view "${n}" --repo darrylmorley/whatcable \
                --json state --jq .state 2>/dev/null) || {
                echo "    #${n} is not an issue (or not found), skipping"
                continue
            }
            if [[ "${STATE}" == "OPEN" ]]; then
                if gh issue close "${n}" --repo darrylmorley/whatcable \
                       --comment "Fixed in v${VERSION}." >/dev/null 2>&1; then
                    echo "    closed #${n}"
                else
                    echo "    failed to close #${n} (left open)" >&2
                fi
            else
                echo "    #${n} already ${STATE}, skipping"
            fi
        done
    fi
fi

echo
if [[ "${DRY_RUN}" == "1" ]]; then
    echo "Dry run complete. Re-run without --dry-run to ship v${VERSION}."
else
    echo "v${VERSION} shipped."
    echo "  GitHub:   https://github.com/darrylmorley/whatcable/releases/tag/v${VERSION}"
    echo "  Homebrew: brew upgrade --cask whatcable"
fi
