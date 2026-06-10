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

# Notarize the dmg file.
# notarytool is unstable on macOS 26 (Tahoe): both `--wait` and bare `submit`
# can crash with "Bus error: 10" *after* the upload has already succeeded and
# the submission ID has been printed. So: never use --wait, ignore submit's
# exit code, and instead trust the parsed submission ID and poll info ourselves.
echo "Notarizing the dmg file..."
SUBMIT_OUTPUT=$(xcrun notarytool submit "${DMG_PATH}" \
  --key "${APP_API_KEY_PATH}" \
  --key-id "${APP_API_KEY_ID}" \
  --issuer "${APP_API_ISSUER}" 2>&1)
echo "${SUBMIT_OUTPUT}"

SUBMISSION_ID=$(echo "${SUBMIT_OUTPUT}" | grep -E '^[[:space:]]*id:' | head -1 | awk '{print $2}')
if [ -z "${SUBMISSION_ID}" ]; then
  echo "error: notarytool submit produced no submission ID"
  exit 7
fi
echo "Submission ID: ${SUBMISSION_ID}"

echo "Waiting for notarization to complete..."
NOTARIZE_STATUS=""
# 240 * 15s = 60 minutes. Apple notary normally finishes in <15 min, but
# occasional backend backlog has been observed to stretch past 30 min.
for i in $(seq 1 240); do
  sleep 15
  INFO_OUTPUT=$(xcrun notarytool info "${SUBMISSION_ID}" \
    --key "${APP_API_KEY_PATH}" \
    --key-id "${APP_API_KEY_ID}" \
    --issuer "${APP_API_ISSUER}" 2>&1)
  NOTARIZE_STATUS=$(echo "${INFO_OUTPUT}" | grep -E '^[[:space:]]*status:' | head -1 | sed 's/.*status:[[:space:]]*//')
  echo "  [${i}/240] status: ${NOTARIZE_STATUS}"
  if [ -n "${NOTARIZE_STATUS}" ] && [ "${NOTARIZE_STATUS}" != "In Progress" ]; then
    break
  fi
done

if [ "${NOTARIZE_STATUS}" != "Accepted" ]; then
  echo "error: Notarization not accepted (status: ${NOTARIZE_STATUS})"
  echo "Fetching notarization log..."
  xcrun notarytool log "${SUBMISSION_ID}" \
    --key "${APP_API_KEY_PATH}" \
    --key-id "${APP_API_KEY_ID}" \
    --issuer "${APP_API_ISSUER}"
  exit 7
fi
echo "Notarization accepted."

# Staple a ticket to the dmg file
xcrun stapler staple "${DMG_PATH}"
if [ $? -ne 0 ]; then
  echo "error: Failed to staple a ticket"
  exit 10
fi

echo "Done."
