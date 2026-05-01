#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ClarityMail"
SCHEME="ClarityMail"
PROJECT="ClarityMail.xcodeproj"
CONFIGURATION="Debug"
DERIVED_DATA="${DERIVED_DATA:-/tmp/claritymail-derived-data}"
APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"

cd "$(dirname "$0")/.."

if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
  pkill -x "${APP_NAME}" || true
fi

xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "platform=macOS" \
  -derivedDataPath "${DERIVED_DATA}" \
  build \
  CODE_SIGNING_ALLOWED=NO

/usr/bin/open -n "${APP_PATH}"

if [[ "${1:-}" == "--verify" ]]; then
  sleep 2
  pgrep -x "${APP_NAME}" >/dev/null
  echo "${APP_NAME} launched"
fi
