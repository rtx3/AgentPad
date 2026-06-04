#!/bin/bash

# Codesign and build a dmg file

if [ $# -lt 1 ]; then
  echo "usage: $0 <app_path>"
  exit 1
fi

SRC_APP_PATH="${1}"
APP_NAME=`basename "${SRC_APP_PATH}"`
if [ "${APP_NAME}" != "AgentPad.app" ]; then
  echo "error: App name must be 'AgentPad.app'"
  exit 2
fi

VERSION=`git describe --tags --abbrev=0 --match "v*.*.*"`
if [ "${VERSION}" == "" ]; then
  echo "error: version tag not found"
  exit 3
fi

echo "Source app path: ${SRC_APP_PATH}"

PROJECT_ROOT="`dirname $0`/.."
TMP_DIR="${PROJECT_ROOT}/dmg"
APP_PATH="${TMP_DIR}/AgentPad.app"
LAUNCHER_ENTITLEMENTS="${PROJECT_ROOT}/AgentPadLauncher/AgentPadLauncher.entitlements"
APP_ENTITLEMENTS="${PROJECT_ROOT}/AgentPad/AgentPad.entitlements"
DMG_PATH="${TMP_DIR}/AgentPad-${VERSION}.dmg"
BUNDLE_ID="com.rtx3.agentpad"

if [ "${APP_API_ISSUER}" == "" ]; then
  read -p "App Store Connect Issuer ID: " APP_API_ISSUER
fi

if [ "${APP_API_KEY_ID}" == "" ]; then
  read -p "App Store Connect Key ID: " APP_API_KEY_ID
fi

if [ "${APP_API_KEY_PATH}" == "" ]; then
  read -p "App Store Connect Key Path (.p8 file): " APP_API_KEY_PATH
fi

if [ ! -f "${APP_API_KEY_PATH}" ]; then
  echo "error: API key file not found: ${APP_API_KEY_PATH}"
  exit 3
fi

# Copy App
echo "Copying app..."
rm -rf "${TMP_DIR}"
mkdir "${TMP_DIR}"
cp -Rp "${SRC_APP_PATH}" "${APP_PATH}"

# Verify
echo "Verifying..."
codesign -dv --verbose=4 "${APP_PATH}"
if [ $? -ne 0 ]; then
  echo "error: The app is not correctly signed"
  exit 4
fi

# Create a dmg file
echo "Creating a dmg file at ${DMG_PATH}"
dmgbuild -s "${PROJECT_ROOT}/scripts/dmg_settings.py" AgentPad "${DMG_PATH}"
if [ $? -ne 0 ]; then
  echo "error: Failed to build a dmg file"
  exit 5
fi

echo "Code signing to the dmg file..."
codesign -f -o runtime --timestamp -s "Developer ID Application" "${DMG_PATH}"
if [ $? -ne 0 ]; then
  echo "error: Failed to sign to the dmg file"
  exit 6
fi

# Notarize the dmg file (synchronous: --wait blocks until Apple finishes)
echo "Notarizing the dmg file..."
xcrun notarytool submit "${DMG_PATH}" \
  --key "${APP_API_KEY_PATH}" \
  --key-id "${APP_API_KEY_ID}" \
  --issuer "${APP_API_ISSUER}" \
  --wait
if [ $? -ne 0 ]; then
  echo "error: Notarization failed"
  exit 7
fi

# Staple a ticket to the dmg file
xcrun stapler staple "${DMG_PATH}"
if [ $? -ne 0 ]; then
  echo "error: Failed to staple a ticket"
  exit 10
fi

echo "Done."
