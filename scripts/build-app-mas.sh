#!/usr/bin/env bash
# Build, sign, and package WhatCable.app for the Mac App Store.
#
# This is the App Store sibling of scripts/smoke-test.sh. The OSS pipeline
# stays the canonical path for the GitHub + Homebrew release. This script
# never touches the OSS build, the Homebrew tap, or notarisation.
#
# What it does, in order:
#   1. Builds release binaries with the WHATCABLE_MAS Swift define.
#   2. Assembles dist-mas/WhatCable.app (same layout as smoke-test.sh).
#   3. Embeds the Mac App Store provisioning profile inside the bundle.
#   4. Signs the inner CLI + outer app with the App Store identities and
#      the sandbox-only entitlements file.
#   5. Productbuilds a signed .pkg ready to upload via Transporter or
#      `xcrun altool --upload-app`.
#
# What it does NOT do:
#   - Notarisation. App Store submissions go through App Review, which
#     is a separate pipeline.
#   - Tag, commit, or push anything. release-mas.sh handles submission;
#     this script only produces the artefact.
#
# Prerequisites (script fails fast if any are missing):
#   - 3rd Party Mac Developer Application: <Team Name> (<TEAM_ID>) in keychain.
#   - 3rd Party Mac Developer Installer:   <Team Name> (<TEAM_ID>) in keychain.
#   - Mac App Store provisioning profile for uk.whatcable.whatcable at
#     the path given by MAS_PROVISIONING_PROFILE.
#   - .env (or environment) provides:
#       MAS_APP_IDENTITY     "3rd Party Mac Developer Application: ..."
#       MAS_INSTALLER_IDENTITY "3rd Party Mac Developer Installer: ..."
#       MAS_PROVISIONING_PROFILE  /path/to/WhatCable_MAS.provisionprofile
#
# Version constants are read from scripts/smoke-test.sh so OSS and MAS
# builds always ship the same version + build number per release.

set -euo pipefail

cd "$(dirname "$0")/.."

# Load .env if present
if [[ -f ".env" ]]; then
    # shellcheck disable=SC1091
    set -a; source .env; set +a
fi

APP_NAME="WhatCable"
BUNDLE_ID="uk.whatcable.whatcable"
MIN_OS="14.0"
CLI_PRODUCT="whatcable-cli"
CLI_BIN_NAME="whatcable"

# Pull VERSION + BUILD_NUMBER from the OSS smoke-test.sh so both pipelines
# stay anchored to the same release. release.sh patches those constants
# during a release; release-mas.sh re-reads them here.
VERSION=$(grep -E '^VERSION=' scripts/smoke-test.sh | head -1 | sed -E 's/VERSION="(.*)"/\1/')
BUILD_NUMBER=$(grep -E '^BUILD_NUMBER=' scripts/smoke-test.sh | head -1 | sed -E 's/BUILD_NUMBER="(.*)"/\1/')

if [[ -z "${VERSION}" || -z "${BUILD_NUMBER}" ]]; then
    echo "ERROR: failed to read VERSION/BUILD_NUMBER from scripts/smoke-test.sh" >&2
    exit 1
fi

# Required env. Documented at top of script.
: "${MAS_APP_IDENTITY:?MAS_APP_IDENTITY not set (3rd Party Mac Developer Application: ...)}"
: "${MAS_INSTALLER_IDENTITY:?MAS_INSTALLER_IDENTITY not set (3rd Party Mac Developer Installer: ...)}"
: "${MAS_PROVISIONING_PROFILE:?MAS_PROVISIONING_PROFILE not set (path to .provisionprofile)}"

if [[ ! -f "${MAS_PROVISIONING_PROFILE}" ]]; then
    echo "ERROR: provisioning profile not found at ${MAS_PROVISIONING_PROFILE}" >&2
    exit 1
fi

# Confirm the App Store identities are actually in the keychain. Fast-fail
# beats letting codesign emit an opaque error 30 seconds in.
if ! security find-identity -v -p codesigning | grep -q "${MAS_APP_IDENTITY}"; then
    echo "ERROR: app identity not found in keychain: ${MAS_APP_IDENTITY}" >&2
    exit 1
fi
if ! security find-identity -v -p basic | grep -q "${MAS_INSTALLER_IDENTITY}"; then
    echo "ERROR: installer identity not found in keychain: ${MAS_INSTALLER_IDENTITY}" >&2
    exit 1
fi

DIST_DIR="dist-mas"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
HELPERS_DIR="${CONTENTS_DIR}/Helpers"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ENTITLEMENTS="scripts/${APP_NAME}.MAS.entitlements"
PKG_PATH="${DIST_DIR}/${APP_NAME}.pkg"

echo "==> Running tests"
swift test

echo "==> Cleaning previous MAS build"
rm -rf "${DIST_DIR}"
mkdir -p "${MACOS_DIR}" "${HELPERS_DIR}" "${RESOURCES_DIR}"

echo "==> Building MAS release binaries (WHATCABLE_MAS=1, arm64 + x86_64)"
WHATCABLE_MAS=1 swift build -c release --product "${APP_NAME}" \
    --arch arm64 --arch x86_64
WHATCABLE_MAS=1 swift build -c release --product "${CLI_PRODUCT}" \
    --arch arm64 --arch x86_64

BIN_PATH=$(WHATCABLE_MAS=1 swift build -c release --product "${APP_NAME}" \
    --arch arm64 --arch x86_64 --show-bin-path)
cp "${BIN_PATH}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
cp "${BIN_PATH}/${CLI_PRODUCT}" "${HELPERS_DIR}/${CLI_BIN_NAME}"

# Bundled WhatCableCore resources (USB-IF vendor list, etc.). Same layout
# as smoke-test.sh.
SPM_BUNDLE_NAME="WhatCable_WhatCableCore.bundle"
SPM_RESOURCES_SRC="Sources/WhatCableCore/Resources"
if [[ -d "${SPM_RESOURCES_SRC}" ]]; then
    bundle_path="${RESOURCES_DIR}/${SPM_BUNDLE_NAME}"
    rm -rf "${bundle_path}"
    mkdir -p "${bundle_path}"
    cp -R "${SPM_RESOURCES_SRC}/." "${bundle_path}/"
fi

echo "==> Verifying universal binaries"
lipo -archs "${MACOS_DIR}/${APP_NAME}" | sed 's/^/    app: /'
lipo -archs "${HELPERS_DIR}/${CLI_BIN_NAME}" | sed 's/^/    cli: /'

echo "==> Copying app icon"
if [[ ! -f "scripts/AppIcon.icns" ]]; then
    ./scripts/make-icon.sh
fi
cp "scripts/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"

echo "==> Writing Info.plist"
cat > "${CONTENTS_DIR}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_OS}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© $(date +%Y) Darryl Morley</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

printf "APPL????" > "${CONTENTS_DIR}/PkgInfo"

echo "==> Embedding Mac App Store provisioning profile"
cp "${MAS_PROVISIONING_PROFILE}" "${CONTENTS_DIR}/embedded.provisionprofile"

echo "==> Signing CLI binary (inner) with App Store identity + sandbox entitlements"
# Helper executables in a sandboxed bundle must themselves carry the
# sandbox entitlement, otherwise App Store validation rejects the package
# with "helper tools must be sandboxed". Same entitlements file as the
# outer app.
codesign --force --options runtime --timestamp \
    --entitlements "${ENTITLEMENTS}" \
    --sign "${MAS_APP_IDENTITY}" \
    "${HELPERS_DIR}/${CLI_BIN_NAME}"

echo "==> Signing app bundle (outer) with App Store identity + sandbox entitlements"
echo "    Identity: ${MAS_APP_IDENTITY}"
codesign --force --options runtime --timestamp \
    --entitlements "${ENTITLEMENTS}" \
    --sign "${MAS_APP_IDENTITY}" \
    "${APP_DIR}"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "${APP_DIR}" 2>&1 | sed 's/^/    /'

echo "==> Producing signed installer .pkg"
productbuild \
    --component "${APP_DIR}" /Applications \
    --sign "${MAS_INSTALLER_IDENTITY}" \
    "${PKG_PATH}"

echo
echo "Done."
echo "  App:  ${APP_DIR}"
echo "  Pkg:  ${PKG_PATH}"
echo
echo "Upload via Transporter.app or:"
echo "  xcrun altool --upload-app -f ${PKG_PATH} -t macos \\"
echo "    --apple-id <APPLE_ID> --password <APP_SPECIFIC_PASSWORD>"
