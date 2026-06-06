#!/bin/bash
#
# Sparkle: sign the freshly built DMG with the Keychain-stored EdDSA private
# key (matching SUPublicEDKey in Info.plist), then append a new <item> entry
# to page/appcast.xml.
#
# Usage:
#   scripts/update_appcast.sh <version-tag> <dmg-path>
#
# Arguments:
#   <version-tag>  Git tag like "v1.0.3". Used in <title>, download URL,
#                  and release notes URL.
#   <dmg-path>     Path to the DMG to sign (already codesign + notarize +
#                  staple by build_dmg.sh).
#
# Idempotent: if page/appcast.xml already contains an item titled
# "Version <X.Y.Z>", the script logs and exits 0 without modifying.
set -e

VERSION="$1"
DMG="$2"

if [ -z "${VERSION}" ] || [ -z "${DMG}" ]; then
  echo "Usage: $0 <version-tag> <dmg-path>"
  exit 1
fi

PROJECT_ROOT="`dirname $0`/.."
cd "${PROJECT_ROOT}"

SIGN_UPDATE="./Pods/Sparkle/bin/sign_update"
if [ ! -x "${SIGN_UPDATE}" ]; then
  echo "error: ${SIGN_UPDATE} not found. Run 'pod install'."
  exit 1
fi

if [ ! -f "${DMG}" ]; then
  echo "error: DMG not found at ${DMG}"
  exit 1
fi

# sign_update prints to stdout: sparkle:edSignature="..." length="..."
SPARKLE_SIG_LINE=$("${SIGN_UPDATE}" "${DMG}")
if [ -z "${SPARKLE_SIG_LINE}" ]; then
  echo "error: sign_update produced no output"
  exit 1
fi
echo "[appcast] Signed ${DMG}: ${SPARKLE_SIG_LINE}"

# Build number is read from the exported .app to match what users will run.
APP="./build/Export/AgentPad.app"
if [ ! -d "${APP}" ]; then
  echo "error: ${APP} not found (build_archive.sh must have run first)"
  exit 1
fi
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${APP}/Contents/Info.plist")
SHORT_VERSION="${VERSION#v}"
PUB_DATE=$(LC_TIME=en_US date -u "+%a, %d %b %Y %H:%M:%S +0000")
DOWNLOAD_URL="https://github.com/rtx3/AgentPad/releases/download/${VERSION}/AgentPad-${VERSION}.dmg"
RELEASE_NOTES_URL="https://github.com/rtx3/AgentPad/releases/tag/${VERSION}"
MIN_SYSTEM_VERSION="10.14"

export VERSION SHORT_VERSION BUILD_NUMBER PUB_DATE
export DOWNLOAD_URL RELEASE_NOTES_URL MIN_SYSTEM_VERSION SPARKLE_SIG_LINE

python3 - <<'PYTHON'
import os
from pathlib import Path

appcast_path = Path("page/appcast.xml")
content = appcast_path.read_text()

short = os.environ["SHORT_VERSION"]
title_marker = f"<title>Version {short}</title>"
if title_marker in content:
    print(f"[appcast] already contains version {short}, skipping injection")
    raise SystemExit(0)

new_item = (
    "    <item>\n"
    f"      <title>Version {short}</title>\n"
    f"      <pubDate>{os.environ['PUB_DATE']}</pubDate>\n"
    f"      <sparkle:version>{os.environ['BUILD_NUMBER']}</sparkle:version>\n"
    f"      <sparkle:shortVersionString>{short}</sparkle:shortVersionString>\n"
    f"      <sparkle:minimumSystemVersion>{os.environ['MIN_SYSTEM_VERSION']}</sparkle:minimumSystemVersion>\n"
    f"      <sparkle:releaseNotesLink>{os.environ['RELEASE_NOTES_URL']}</sparkle:releaseNotesLink>\n"
    "      <enclosure\n"
    f"        url=\"{os.environ['DOWNLOAD_URL']}\"\n"
    f"        {os.environ['SPARKLE_SIG_LINE']}\n"
    "        type=\"application/octet-stream\" />\n"
    "    </item>\n"
)

# Insert just before </channel>; channel-level metadata stays at the top,
# new item goes at the bottom of the items list (chronological).
needle = "  </channel>"
if needle not in content:
    raise SystemExit("error: </channel> not found in page/appcast.xml")

new_content = content.replace(needle, new_item + needle, 1)
appcast_path.write_text(new_content)
print(f"[appcast] injected version {short} into page/appcast.xml")
PYTHON
