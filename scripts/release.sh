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

# Auto commit + push of page/appcast.xml at the end requires being on master,
# otherwise the appcast publish step would push to the wrong ref.
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "${CURRENT_BRANCH}" != "master" ]; then
  echo "error: release must run on master (current: ${CURRENT_BRANCH})"
  exit 1
fi

VERSION=`git describe --tags --abbrev=0 --match "v*.*.*"`
if [ "${VERSION}" == "" ]; then
  echo "error: version tag not found"
  exit 1
fi

# Refuse to start if page/appcast.xml is dirty — we'll auto-commit it at the
# end, and we don't want unrelated edits riding along on that commit.
if ! git ls-files --error-unmatch page/appcast.xml >/dev/null 2>&1; then
  echo "error: page/appcast.xml is not tracked by git. Commit the template first."
  exit 1
fi
if ! git diff --quiet HEAD -- page/appcast.xml; then
  echo "error: page/appcast.xml has uncommitted changes; commit or stash before releasing."
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

# Past this point, GitHub already has the release. If anything below fails,
# the user has to finish the appcast publish manually — print a recovery hint
# so they know exactly what to do.
recovery_hint() {
  echo ""
  echo "================================================================"
  echo "WARN: GitHub release ${VERSION} is published, but the appcast step"
  echo "      did not complete. Sparkle clients will not see the update"
  echo "      until page/appcast.xml is signed, committed, and pushed."
  echo ""
  echo "      Recover with:"
  echo "        ./scripts/update_appcast.sh \"${VERSION}\" \"${DMG}\""
  echo "        git add page/appcast.xml"
  echo "        git commit -m \"chore(appcast): publish ${VERSION}\""
  echo "        git push origin master"
  echo "================================================================"
}

# 5. EdDSA-sign DMG and inject the new <item> into page/appcast.xml
if ! ./scripts/update_appcast.sh "${VERSION}" "${DMG}"; then
  recovery_hint
  exit 1
fi

# 6. Commit + push the updated appcast (GitHub Pages auto-rebuilds the site)
if git diff --quiet HEAD -- page/appcast.xml; then
  echo "page/appcast.xml unchanged (idempotent rerun); nothing to commit."
else
  if ! git add page/appcast.xml \
     || ! git commit -m "chore(appcast): publish ${VERSION}" \
     || ! git push origin master; then
    recovery_hint
    exit 1
  fi
fi

echo "Released ${VERSION}"
