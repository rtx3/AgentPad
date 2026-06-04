#!/bin/bash
set -e

# Notarization credentials (ENV vars override these defaults)
# Key ID and Issuer ID are identifiers, not secrets — safe to commit.
# The actual secret is the .p8 private key file; keep it out of git.
export APP_API_KEY_ID="${APP_API_KEY_ID:-R8B8CXR92P}"
export APP_API_ISSUER="${APP_API_ISSUER:-5bd3d59d-14f1-4af7-ae22-8e3db694ecbf}"
export APP_API_KEY_PATH="${APP_API_KEY_PATH:-$HOME/.release/AuthKey_R8B8CXR92P.p8}"

PROJECT_ROOT="`dirname $0`/.."
cd "${PROJECT_ROOT}"

VERSION=`git describe --tags --abbrev=0 --match "v*.*.*"`
if [ "${VERSION}" == "" ]; then
  echo "error: version tag not found"
  exit 1
fi

# 1. Archive + Export
./scripts/build_archive.sh

# 2. Build DMG (codesign + notarize + staple)
./scripts/build_dmg.sh "./build/Export/AgentPad.app"

# 3. Compute sha256
DMG="./dmg/AgentPad-${VERSION}.dmg"
shasum -a 256 "${DMG}" > "${DMG}.sha256"

# 4. Create GitHub release
gh release create "${VERSION}" "${DMG}" "${DMG}.sha256" \
  --title "AgentPad ${VERSION}" \
  --notes "Download the DMG and drag AgentPad to /Applications. On first launch: right-click → Open. Grant Accessibility permission when prompted."

echo "Released ${VERSION}"
