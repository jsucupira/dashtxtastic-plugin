#!/usr/bin/env bash
# Publishes one markdown file to Dashtxtastic and keeps its share link alive.
# Reads its inputs from DTX_* environment variables (set by action.yml) and writes
# project-id and share-url to $GITHUB_OUTPUT when running inside GitHub Actions.
set -euo pipefail

BASE_URL="${DTX_BASE_URL:-https://dashtxtastic.com}"
BASE_URL="${BASE_URL%/}"
RENDER_MODE="${DTX_RENDER_MODE:-prose}"
TARGET_PATH="${DTX_TARGET_PATH:-main.md}"
SHARE="${DTX_SHARE:-true}"
SHARE_SLUG="${DTX_SHARE_SLUG:-}"
SHARE_DAYS="${DTX_SHARE_DAYS:-90}"
PROJECT_NAME="${DTX_PROJECT_NAME:-}"
FILE="${DTX_FILE:-}"

MAX_FILE_BYTES=1048576
MIN_SHARE_DAYS=1
MAX_SHARE_DAYS=365
LIST_PAGE_SIZE=100

RESPONSE_BODY="$(mktemp)"
trap 'rm -f "$RESPONSE_BODY"' EXIT

fail() {
  echo "::error::$1" >&2
  exit 1
}

# Prints the HTTP status code; the response body lands in $RESPONSE_BODY.
api() {
  local method="$1" path="$2"
  shift 2
  curl -sS -o "$RESPONSE_BODY" -w '%{http_code}' -X "$method" \
    -H "Authorization: Bearer ${DTX_API_KEY}" \
    -H "Accept: application/json" \
    "$@" "${BASE_URL}${path}"
}

# Fails the step with the API's own error message.
fail_with_response() {
  local action="$1" status="$2" message
  message="$(jq -r '.message // .error // empty' "$RESPONSE_BODY" 2>/dev/null || true)"
  fail "${action} failed with HTTP ${status}: ${message:-no error message returned}"
}

new_idempotency_key() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen
  else
    cat /proc/sys/kernel/random/uuid
  fi
}

# ---- validate inputs ----
command -v jq >/dev/null 2>&1 || fail "jq is required on the runner."
[[ -n "${DTX_API_KEY:-}" ]] || fail "api-key is empty. Pass it from a repository secret."
[[ -n "$FILE" ]] || fail "file is required."
[[ -f "$FILE" ]] || fail "file '${FILE}' does not exist."
[[ -n "$PROJECT_NAME" ]] || fail "project-name is empty."
[[ "$TARGET_PATH" =~ ^[a-z0-9][a-z0-9._/-]{0,250}\.md$ && "$TARGET_PATH" != *..* ]] \
  || fail "target-path '${TARGET_PATH}' must be lowercase ASCII, end in .md, and not contain '..'."
if ! [[ "$SHARE_DAYS" =~ ^[0-9]+$ ]] || (( SHARE_DAYS < MIN_SHARE_DAYS || SHARE_DAYS > MAX_SHARE_DAYS )); then
  fail "share-days must be a whole number from ${MIN_SHARE_DAYS} to ${MAX_SHARE_DAYS}."
fi
file_bytes="$(wc -c < "$FILE" | tr -d ' ')"
(( file_bytes <= MAX_FILE_BYTES )) || fail "file '${FILE}' is ${file_bytes} bytes; the limit is ${MAX_FILE_BYTES}."

# ---- find or create the project ----
encoded_name="$(jq -rn --arg v "$PROJECT_NAME" '$v | @uri')"
status="$(api GET "/api/v1/projects?q=${encoded_name}&pageSize=${LIST_PAGE_SIZE}")"
[[ "$status" == "200" ]] || fail_with_response "Listing projects" "$status"
project_id="$(jq -r --arg n "$PROJECT_NAME" \
  '[.data.items[] | select(.name == $n)] | first | .id // empty' "$RESPONSE_BODY")"

if [[ -z "$project_id" ]]; then
  echo "Creating project '${PROJECT_NAME}' (${RENDER_MODE})."
  payload="$(jq -n --arg name "$PROJECT_NAME" --arg mode "$RENDER_MODE" --arg src "$FILE" \
    '{name: $name, renderMode: $mode, description: ("source: " + $src)}')"
  status="$(api POST "/api/v1/projects" -H "Content-Type: application/json" \
    -H "Idempotency-Key: $(new_idempotency_key)" --data "$payload")"
  [[ "$status" == "201" ]] || fail_with_response "Creating the project" "$status"
  project_id="$(jq -r '.data.id // empty' "$RESPONSE_BODY")"
  [[ -n "$project_id" ]] || fail "Creating the project returned no id."
else
  echo "Reusing project '${PROJECT_NAME}' (${project_id})."
fi

# ---- upload: renders and publishes in one call ----
encoded_mode="$(jq -rn --arg v "$RENDER_MODE" '$v | @uri')"
status="$(api PUT "/api/v1/projects/${project_id}/files/${TARGET_PATH}?renderMode=${encoded_mode}" \
  -H "Content-Type: text/markdown" -H "Idempotency-Key: $(new_idempotency_key)" \
  --data-binary "@${FILE}")"
[[ "$status" =~ ^20[01]$ ]] || fail_with_response "Uploading ${TARGET_PATH}" "$status"
echo "Published ${FILE} as ${TARGET_PATH}."

# ---- share link: extend keeps the URL stable; create only when none exists ----
share_url=""
if [[ "$SHARE" != "false" ]]; then
  extend_payload="$(jq -n --argjson days "$SHARE_DAYS" '{expiresInDays: $days}')"
  status="$(api POST "/api/v1/projects/${project_id}/share-links/extend" \
    -H "Content-Type: application/json" --data "$extend_payload")"
  if [[ "$status" == "404" ]]; then
    create_payload="$(jq -n --arg slug "$SHARE_SLUG" --argjson days "$SHARE_DAYS" \
      '{expiresInDays: $days} + (if $slug == "" then {} else {slugBase: $slug} end)')"
    status="$(api POST "/api/v1/projects/${project_id}/share-links" \
      -H "Content-Type: application/json" --data "$create_payload")"
    [[ "$status" =~ ^20[01]$ ]] || fail_with_response "Creating the share link" "$status"
  elif [[ "$status" != "200" ]]; then
    fail_with_response "Extending the share link" "$status"
  fi
  share_url="$(jq -r '.data.url // empty' "$RESPONSE_BODY")"
  [[ -n "$share_url" ]] || fail "The share-link response carried no url."
  echo "Share link: ${share_url}"
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "project-id=${project_id}"
    echo "share-url=${share_url}"
  } >> "$GITHUB_OUTPUT"
fi
if [[ -n "${GITHUB_STEP_SUMMARY:-}" && -n "$share_url" ]]; then
  echo "Dashboard published: ${share_url}" >> "$GITHUB_STEP_SUMMARY"
fi
