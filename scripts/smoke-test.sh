#!/usr/bin/env bash
# Build, sign, notarise, and smoke-test WhatCable.app.
#
# This is the day-to-day verification script. It does NOT touch the Homebrew
# tap. For a full release build (including the cask bump), use build-app.sh
# via scripts/release.sh.
#
# Modes:
#   - No DEVELOPER_ID set: ad-hoc signed (works locally, Gatekeeper warns elsewhere).
#   - DEVELOPER_ID set:   Developer ID signed + hardened runtime.
#   - Plus NOTARY_PROFILE: also notarises and staples (full distribution).
#
# Configure via .env (see .env.example).
set -euo pipefail

cd "$(dirname "$0")/.."

# Load .env if present
if [[ -f ".env" ]]; then
    # shellcheck disable=SC1091
    set -a; source .env; set +a
fi

APP_NAME="WhatCable"
BUNDLE_ID="uk.whatcable.whatcable"
VERSION="0.8.0"
BUILD_NUMBER="33"
MIN_OS="14.0"
CLI_PRODUCT="whatcable-cli"
CLI_BIN_NAME="whatcable"

DEVELOPER_ID="${DEVELOPER_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

DIST_DIR="dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
HELPERS_DIR="${CONTENTS_DIR}/Helpers"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ENTITLEMENTS="scripts/${APP_NAME}.entitlements"

echo "==> Running tests"
swift test

echo "==> Cleaning previous build"
rm -rf "${DIST_DIR}"
mkdir -p "${MACOS_DIR}" "${HELPERS_DIR}" "${RESOURCES_DIR}"

echo "==> Building universal release binaries (arm64 + x86_64)"
swift build -c release --product "${APP_NAME}" \
    --arch arm64 --arch x86_64
swift build -c release --product "${CLI_PRODUCT}" \
    --arch arm64 --arch x86_64

BIN_PATH=$(swift build -c release --product "${APP_NAME}" \
    --arch arm64 --arch x86_64 --show-bin-path)
cp "${BIN_PATH}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
# CLI lives in Helpers/, not MacOS/, because macOS filesystems are case-insensitive
# by default. Putting "whatcable" next to "WhatCable" silently overwrote the
# main binary in v0.5.0. Helpers/ avoids the collision and is also where Apple
# expects bundled non-launch executables to live.
cp "${BIN_PATH}/${CLI_PRODUCT}" "${HELPERS_DIR}/${CLI_BIN_NAME}"

# WhatCableCore ships the bundled USB-IF vendor list as a `.process`
# resource. SPM wraps `Sources/WhatCableCore/Resources/` in a bundle
# named `WhatCable_WhatCableCore.bundle`. Put it in Contents/Resources
# so Bundle.main.resourceURL (which Bundle.module's lookup chain
# checks first) resolves it for both the GUI binary and the CLI when
# launched from inside the .app. We do not ship the bundle into
# Contents/Helpers because codesign rejects non-bundle directories
# placed there.
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
    echo "    AppIcon.icns missing — regenerating via make-icon.sh"
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

if [[ -n "${DEVELOPER_ID}" ]]; then
    echo "==> Signing CLI binary (inner) with Developer ID + hardened runtime"
    codesign --force --options runtime --timestamp \
        --sign "${DEVELOPER_ID}" \
        "${HELPERS_DIR}/${CLI_BIN_NAME}"

    echo "==> Signing app bundle (outer) with Developer ID + hardened runtime"
    echo "    Identity: ${DEVELOPER_ID}"
    codesign --force --options runtime --timestamp \
        --entitlements "${ENTITLEMENTS}" \
        --sign "${DEVELOPER_ID}" \
        "${APP_DIR}"
else
    echo "==> Ad-hoc signing (no DEVELOPER_ID set)"
    codesign --force --deep --sign - "${APP_DIR}"
fi

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "${APP_DIR}" 2>&1 | sed 's/^/    /'

echo "==> Smoke-testing main binary (must stay alive as a GUI app, not exit immediately)"
"${MACOS_DIR}/${APP_NAME}" >/dev/null 2>&1 &
SMOKE_PID=$!
sleep 2
if kill -0 "${SMOKE_PID}" 2>/dev/null; then
    echo "    main binary alive after 2s — looks like a GUI app"
    kill "${SMOKE_PID}" 2>/dev/null || true
    wait "${SMOKE_PID}" 2>/dev/null || true
else
    echo "    ERROR: ${MACOS_DIR}/${APP_NAME} exited within 2s. The menu bar binary"
    echo "    should stay running. Check whether it was overwritten by another"
    echo "    executable during build (case-insensitive FS collision, etc.)." >&2
    exit 1
fi

echo "==> Smoke-testing CLI binary (--version must match build VERSION)"
CLI_VERSION_OUTPUT=$("${HELPERS_DIR}/${CLI_BIN_NAME}" --version 2>&1 | tr -d '[:space:]')
if [[ "${CLI_VERSION_OUTPUT}" != "${VERSION}" ]]; then
    echo "    ERROR: CLI --version reported '${CLI_VERSION_OUTPUT}', expected '${VERSION}'." >&2
    echo "    The CLI binary may not be reading the bundle Info.plist correctly." >&2
    exit 1
fi
echo "    CLI reports ${CLI_VERSION_OUTPUT}"

# Exercise the JSON output path so we hit VendorDB / CableTrustReport
# / ChargingDiagnostic, not just the Info.plist read. Catches regressions
# where bundled resources (like the USB-IF vendor list) fail to load
# in the deployed .app and crash on first use. Output goes to /dev/null;
# we only care that the process exits 0.
if ! "${HELPERS_DIR}/${CLI_BIN_NAME}" --json >/dev/null 2>&1; then
    echo "    ERROR: CLI --json exited non-zero. A bundled resource may not be" >&2
    echo "    loadable in the deployed .app context." >&2
    exit 1
fi
echo "    CLI --json runs cleanly"

echo "==> Creating zip"
( cd "${DIST_DIR}" && ditto -c -k --keepParent "${APP_NAME}.app" "${APP_NAME}.zip" )

if [[ -n "${DEVELOPER_ID}" && -n "${NOTARY_PROFILE}" ]]; then
    echo "==> Submitting to Apple notarisation (this can take a few minutes)"
    xcrun notarytool submit "${DIST_DIR}/${APP_NAME}.zip" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait

    echo "==> Stapling notarisation ticket"
    xcrun stapler staple "${APP_DIR}"

    echo "==> Re-creating zip with stapled ticket"
    rm -f "${DIST_DIR}/${APP_NAME}.zip"
    ( cd "${DIST_DIR}" && ditto -c -k --keepParent "${APP_NAME}.app" "${APP_NAME}.zip" )

    echo "==> Verifying Gatekeeper acceptance"
    spctl --assess --type execute --verbose "${APP_DIR}" 2>&1 | sed 's/^/    /'
elif [[ -n "${DEVELOPER_ID}" ]]; then
    echo "==> NOTARY_PROFILE not set — skipping notarisation"
    echo "    Set it in .env once you've run:"
    echo "      xcrun notarytool store-credentials \"WhatCable-notary\" --apple-id ... --team-id ... --password ..."
fi

echo
echo "Done."
echo "  App:  ${APP_DIR}"
echo "  CLI:  ${HELPERS_DIR}/${CLI_BIN_NAME} (inside the bundle)"
echo "  Zip:  ${DIST_DIR}/${APP_NAME}.zip"
