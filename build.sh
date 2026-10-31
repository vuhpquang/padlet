#!/usr/bin/env bash
# build.sh
# Builds Padlet as a proper macOS .app bundle, signs it, packages into a DMG,
# and optionally notarizes.
#
# USAGE:
#   ./build.sh                  # Build + DMG (ad-hoc signed, local use only)
#   TEAM_ID="Developer ID Application: Name (ID)" ./build.sh   # Developer ID signed
#   NOTARIZE=1 TEAM_ID="..." ./build.sh                         # Signed + notarized

set -euo pipefail

BINARY_NAME="Padlet"
APP_NAME="Padlet"
APP_BUNDLE="${APP_NAME}.app"
BUILD_DIR="$(pwd)/build"
APP_PATH="${BUILD_DIR}/${APP_BUNDLE}"
DMG_PATH="${BUILD_DIR}/${BINARY_NAME}.dmg"
TEAM_ID="${TEAM_ID:--}"          # "-" = ad-hoc signing (works locally)
NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-Padlet}"
NOTARIZE="${NOTARIZE:-0}"

# ── STEP 0: Clean ──────────────────────────────────────────
echo "==> Preparing build directory…"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# ── STEP 1: Compile universal binary ───────────────────────
echo "==> Building universal release binary (arm64 + x86_64)…"
swift build -c release --arch arm64 --arch x86_64
# Ask SwiftPM where it put the binary — the output folder differs between toolchains
# (.build/apple/… on older ones, .build/out/… on newer), and a hardcoded path silently
# packaged a stale binary.
BINARY_PATH="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/${BINARY_NAME}"

if [[ ! -f "${BINARY_PATH}" ]]; then
    echo "ERROR: Binary not found at ${BINARY_PATH}" >&2
    exit 1
fi
echo "==> Build succeeded."

# ── STEP 2: Assemble .app bundle ───────────────────────────
# A proper macOS .app bundle has this layout:
#   Padlet.app/
#     Contents/
#       MacOS/
#         Padlet       ← the compiled binary
#       Info.plist           ← tells macOS about the app (name, bundle ID, LSUIElement, etc.)
#
# Without this structure macOS treats the binary as a Unix tool and opens it in Terminal.
echo "==> Assembling ${APP_BUNDLE}…"
mkdir -p "${APP_PATH}/Contents/MacOS"

# Copy the compiled binary into the bundle.
cp "${BINARY_PATH}" "${APP_PATH}/Contents/MacOS/${BINARY_NAME}"

# Copy Info.plist into the bundle root (Contents/).
cp "Sources/Padlet/Resources/Info.plist" "${APP_PATH}/Contents/Info.plist"

# Build AppIcon.icns from the 1024px master (regenerate it with scripts/make-icon.swift).
echo "==> Building AppIcon.icns…"
mkdir -p "${APP_PATH}/Contents/Resources"
ICONSET="${BUILD_DIR}/AppIcon.iconset"
ICON_SRC="Sources/Padlet/Resources/AppIcon.png"
mkdir -p "${ICONSET}"
for s in 16 32 128 256 512; do
    sips -z $s $s             "${ICON_SRC}" --out "${ICONSET}/icon_${s}x${s}.png"    >/dev/null
    sips -z $((s*2)) $((s*2)) "${ICON_SRC}" --out "${ICONSET}/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "${ICONSET}" -o "${APP_PATH}/Contents/Resources/AppIcon.icns"
rm -rf "${ICONSET}"

# ── STEP 3: Code-sign the .app bundle ──────────────────────
# Sign the whole bundle (not just the binary) so Gatekeeper is satisfied.
# With TEAM_ID="-" this is an ad-hoc signature — works on your own Mac only.
# With a real Developer ID certificate it passes Gatekeeper on any Mac.
echo "==> Code-signing ${APP_BUNDLE} with: ${TEAM_ID}"
codesign \
    --deep \
    --force \
    --sign "${TEAM_ID}" \
    "${APP_PATH}"

echo "==> Verifying signature…"
codesign --verify --deep --strict "${APP_PATH}"
echo "==> Signature OK."

# ── STEP 4: Create DMG ─────────────────────────────────────
# The DMG contains the signed .app and a symlink to /Applications so users can
# drag-and-drop to install.
echo "==> Creating DMG…"
STAGING="${BUILD_DIR}/dmg_staging"
mkdir -p "${STAGING}"
cp -R "${APP_PATH}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"

hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${STAGING}" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "${DMG_PATH}"

rm -rf "${STAGING}"
echo "==> DMG created: ${DMG_PATH}"

# ── STEP 5 (optional): Notarize ────────────────────────────
if [[ "${NOTARIZE}" == "1" ]]; then
    echo "==> Submitting for notarization (this may take a few minutes)…"
    xcrun notarytool submit "${DMG_PATH}" \
        --keychain-profile "${NOTARYTOOL_PROFILE}" \
        --wait
    echo "==> Stapling notarization ticket…"
    xcrun stapler staple "${DMG_PATH}"
    echo "==> Notarization complete."
else
    echo "==> Notarization skipped (set NOTARIZE=1 to enable)."
fi

echo ""
echo "======================================================"
echo "  Done!  →  ${DMG_PATH}"
echo "======================================================"
