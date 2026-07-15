#!/usr/bin/env bash
#
# Builds FridaLauncher.ipa for a jailbroken device.
#
# An .ipa is simply a zip containing Payload/<App>.app. This script:
#   1. generates the Xcode project (XcodeGen)
#   2. builds an unsigned Release .app against the iOS SDK
#   3. pseudo-signs it with the jailbreak entitlements (ldid)
#   4. wraps it in Payload/ and zips it to FridaLauncher.ipa
#
# REQUIREMENTS (this cannot run with Command Line Tools alone):
#   - Full Xcode installed and selected:
#       sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
#   - brew install xcodegen ldid
#
# Usage:  cd ios && ./build-ipa.sh
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="FridaLauncher"
CONFIG="Release"
BUILD_DIR="build"
IPA_OUT="${APP_NAME}.ipa"

# --- sanity checks --------------------------------------------------------
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "error: full Xcode is required (Command Line Tools cannot build iOS apps)." >&2
  echo "       Install Xcode, then: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi
command -v xcodegen >/dev/null || { echo "error: xcodegen not found (brew install xcodegen)"; exit 1; }
command -v ldid     >/dev/null || { echo "error: ldid not found (brew install ldid)"; exit 1; }

# --- 1. project -----------------------------------------------------------
echo "==> generating Xcode project"
xcodegen generate

# --- 2. build unsigned .app ----------------------------------------------
echo "==> building ${CONFIG} .app"
xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "${APP_NAME}" \
  -configuration "${CONFIG}" \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "${BUILD_DIR}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

APP_PATH="${BUILD_DIR}/Build/Products/${CONFIG}-iphoneos/${APP_NAME}.app"
[ -d "${APP_PATH}" ] || { echo "error: build did not produce ${APP_PATH}"; exit 1; }

# --- 3. pseudo-sign with jailbreak entitlements ---------------------------
echo "==> ldid-signing with entitlements.plist"
ldid -Sentitlements.plist "${APP_PATH}/${APP_NAME}"

# --- 4. package into .ipa -------------------------------------------------
echo "==> packaging ${IPA_OUT}"
rm -rf Payload "${IPA_OUT}"
mkdir -p Payload
cp -R "${APP_PATH}" Payload/
zip -qry "${IPA_OUT}" Payload
rm -rf Payload

echo "==> done: $(pwd)/${IPA_OUT}"
echo "    Install with TrollStore (open the .ipa), or sideload with your tool of choice."
