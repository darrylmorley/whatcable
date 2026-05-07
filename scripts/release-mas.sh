#!/usr/bin/env bash
# Mac App Store submission, downstream of scripts/release.sh.
#
# This script is non-mutating. It does not bump the version, commit,
# tag, push, or touch the Homebrew tap. The OSS release.sh has already
# done all of that. release-mas.sh just builds the same VERSION /
# BUILD_NUMBER as a signed App Store .pkg and uploads it to App Store
# Connect.
#
# Typical sequence:
#   1. scripts/release.sh 0.X.Y      # OSS release (bump, tag, push, GH)
#   2. scripts/release-mas.sh        # MAS submission, same version
#
# Re-running this on the same version is safe: App Store Connect handles
# build-number versioning of resubmissions on its side. If a build was
# rejected and a code change is needed, run release.sh first to ship a
# new OSS release with a new VERSION/BUILD_NUMBER, then re-run this.
#
# Required env (loaded from .env, see .env.example):
#   MAS_APP_IDENTITY
#   MAS_INSTALLER_IDENTITY
#   MAS_PROVISIONING_PROFILE
#   MAS_APPLE_ID                Apple ID email for altool upload
#   MAS_APP_PASSWORD            App-specific password (App Store Connect)
#
# Pass --no-upload to build the .pkg locally without uploading. Useful
# for verification before the first real submission.

set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -f ".env" ]]; then
    # shellcheck disable=SC1091
    set -a; source .env; set +a
fi

UPLOAD=1
if [[ "${1:-}" == "--no-upload" ]]; then
    UPLOAD=0
fi

# Sanity: working tree should be clean and tag should match smoke-test.sh.
# We don't enforce on-tag (caller might run from main right after release.sh),
# but a dirty tree is a footgun.
if ! git diff-index --quiet HEAD --; then
    echo "ERROR: working tree has uncommitted changes. Commit or stash first." >&2
    exit 1
fi

VERSION=$(grep -E '^VERSION=' scripts/smoke-test.sh | head -1 | sed -E 's/VERSION="(.*)"/\1/')
BUILD_NUMBER=$(grep -E '^BUILD_NUMBER=' scripts/smoke-test.sh | head -1 | sed -E 's/BUILD_NUMBER="(.*)"/\1/')

echo "==> MAS release: WhatCable ${VERSION} (build ${BUILD_NUMBER})"

./scripts/build-app-mas.sh

PKG_PATH="dist-mas/WhatCable.pkg"

if [[ "${UPLOAD}" -eq 0 ]]; then
    echo
    echo "Built ${PKG_PATH}. Skipping upload (--no-upload)."
    exit 0
fi

: "${MAS_APPLE_ID:?MAS_APPLE_ID not set}"
: "${MAS_APP_PASSWORD:?MAS_APP_PASSWORD not set (use an app-specific password)}"

echo "==> Uploading ${PKG_PATH} to App Store Connect"
xcrun altool --upload-app \
    --type macos \
    --file "${PKG_PATH}" \
    --apple-id "${MAS_APPLE_ID}" \
    --password "${MAS_APP_PASSWORD}"

echo
echo "Upload submitted. App Store Connect will process the build, then"
echo "you can submit it for review from https://appstoreconnect.apple.com."
