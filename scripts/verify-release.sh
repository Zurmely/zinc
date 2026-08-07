#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${APP:-$ROOT/Zinc.app}"
BIN="$APP/Contents/MacOS/Zinc"
VERIFY_BROWSER=0

for arg in "$@"; do
  case "$arg" in
    --browser) VERIFY_BROWSER=1 ;;
    "$ROOT/Zinc.app"|./*Zinc.app|*/Zinc.app)
      APP="$arg"
      BIN="$APP/Contents/MacOS/Zinc"
      ;;
  esac
done

if [[ "${VERIFY_BROWSER_CAPTURE:-}" == "1" ]]; then
  VERIFY_BROWSER=1
fi

if [[ ! -d "$APP" ]]; then
  echo "error: app bundle not found at $APP" >&2
  exit 1
fi

if [[ ! -x "$BIN" ]]; then
  echo "error: executable not found at $BIN" >&2
  exit 1
fi

echo "Verifying Apple Events entitlement on $APP..."
ENTITLEMENTS_OUTPUT="$(codesign -d --entitlements - "$APP" 2>&1)" || {
  echo "error: failed to read entitlements from $APP" >&2
  echo "$ENTITLEMENTS_OUTPUT" >&2
  exit 1
}

if ! grep -q 'com.apple.security.automation.apple-events' <<< "$ENTITLEMENTS_OUTPUT"; then
  echo "error: $APP is missing com.apple.security.automation.apple-events" >&2
  echo "$ENTITLEMENTS_OUTPUT" >&2
  exit 1
fi

echo "OK: com.apple.security.automation.apple-events is present"
echo "$ENTITLEMENTS_OUTPUT"

if [[ "$VERIFY_BROWSER" -eq 0 ]]; then
  exit 0
fi

echo "Verifying browser URL capture from signed binary..."
if ! pgrep -xq Safari; then
  echo "error: Safari must be running with a page open" >&2
  exit 1
fi

osascript -e 'tell application "Safari" to activate' >/dev/null 2>&1 || true
sleep 0.5

OUTPUT=""
if ! OUTPUT="$(ZINC_VERIFY_BROWSER_CONTEXT=1 "$BIN" 2>&1)"; then
  echo "error: browser context verification failed" >&2
  echo "$OUTPUT" >&2
  exit 1
fi

if ! grep -Eq '^url: https?://' <<< "$OUTPUT"; then
  echo "error: expected a page URL in verification output" >&2
  echo "$OUTPUT" >&2
  exit 1
fi

echo "OK: browser URL captured from signed build"
echo "$OUTPUT"
