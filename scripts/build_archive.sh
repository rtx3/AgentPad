#!/bin/bash
set -e

PROJECT_ROOT="`dirname $0`/.."
ARCHIVE_PATH="${PROJECT_ROOT}/build/AgentPad.xcarchive"
EXPORT_PATH="${PROJECT_ROOT}/build/Export"
EXPORT_OPTIONS="${PROJECT_ROOT}/scripts/ExportOptions.plist"

rm -rf "${PROJECT_ROOT}/build"

echo "Archiving..."
xcodebuild \
  -workspace "${PROJECT_ROOT}/AgentPad.xcworkspace" \
  -scheme AgentPad \
  -configuration Release \
  -archivePath "${ARCHIVE_PATH}" \
  archive

echo "Exporting..."
xcodebuild \
  -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_PATH}" \
  -exportOptionsPlist "${EXPORT_OPTIONS}"

echo "Done. App at ${EXPORT_PATH}/AgentPad.app"
