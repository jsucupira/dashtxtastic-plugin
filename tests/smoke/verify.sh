#!/usr/bin/env bash
# Checks that a published share link serves the expected marker text.
# Usage: verify.sh <share-url> <marker> [expect-badge]
set -euo pipefail

SHARE_URL="${1:?share url required}"
MARKER="${2:?marker required}"
EXPECT_BADGE="${3:-}"
BADGE_TEXT="Made with Dashtxtastic"

[[ "$SHARE_URL" =~ ^https://[^/]+/s/[a-z0-9-]+$ ]] || { echo "::error::Unexpected share URL: ${SHARE_URL}"; exit 1; }

page="$(curl -fsS "${SHARE_URL}/_raw")"
grep -qF "$MARKER" <<<"$page" || { echo "::error::Marker '${MARKER}' not found at ${SHARE_URL}"; exit 1; }
if [[ "$EXPECT_BADGE" == "expect-badge" ]]; then
  grep -qF "$BADGE_TEXT" <<<"$page" || { echo "::error::Free-plan badge missing at ${SHARE_URL}"; exit 1; }
fi
echo "OK: ${SHARE_URL} serves '${MARKER}'"
