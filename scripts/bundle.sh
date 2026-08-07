#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_PATH="${BUILD_PATH:-$ROOT/.build}"

# Prefer full Xcode so actool can compile Icon Composer (.icon) assets.
if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fi

echo "Building Zinc (release)..."
swift build -c release --build-path "$BUILD_PATH"

BIN=""
for candidate in \
  "$BUILD_PATH/release/Zinc" \
  "$BUILD_PATH/arm64-apple-macosx/release/Zinc" \
  "$BUILD_PATH/x86_64-apple-macosx/release/Zinc"; do
  if [[ -f "$candidate" ]]; then
    BIN="$candidate"
    break
  fi
done

if [[ -z "$BIN" ]]; then
  echo "error: could not find Zinc binary under $BUILD_PATH" >&2
  exit 1
fi

APP="$ROOT/Zinc.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BIN" "$MACOS/Zinc"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/MenubarIcon.svg" "$RESOURCES/MenubarIcon.svg"

ICON_SOURCE="$ROOT/Resources/zincIcon.icon"
if [[ -d "$ICON_SOURCE" ]]; then
  echo "Compiling app icon..."
  ICON_OUT="$(mktemp -d)"
  trap 'rm -rf "$ICON_OUT"' EXIT
  xcrun actool "$ICON_SOURCE" \
    --compile "$ICON_OUT" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon zincIcon \
    --output-partial-info-plist "$ICON_OUT/partial.plist" \
    --errors --warnings \
    --output-format human-readable-text
  cp "$ICON_OUT/Assets.car" "$RESOURCES/Assets.car"
  cp "$ICON_OUT/zincIcon.icns" "$RESOURCES/zincIcon.icns"
else
  echo "warning: missing $ICON_SOURCE — app icon not bundled" >&2
fi

# Prefer a real Apple Development identity so Accessibility TCC grants stick.
# Ad-hoc (-s -) changes CDHash every rebuild and macOS ignores the toggle.
IDENTITY="${CODE_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
    | head -n 1 || true)"
fi
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
    | head -n 1 || true)"
fi

ENTITLEMENTS="$ROOT/Resources/Zinc.entitlements"
if [[ ! -f "$ENTITLEMENTS" ]]; then
  echo "error: missing entitlements file at $ENTITLEMENTS" >&2
  exit 1
fi

if [[ -n "$IDENTITY" ]]; then
  echo "Signing with: $IDENTITY"
  codesign -s "$IDENTITY" --force --options runtime --entitlements "$ENTITLEMENTS" "$MACOS/Zinc"
  codesign -s "$IDENTITY" --force --options runtime --entitlements "$ENTITLEMENTS" "$APP"
else
  echo "warning: no Apple Development identity found — falling back to ad-hoc" >&2
  codesign -s - --force --identifier "com.zurmely.zinc" --entitlements "$ENTITLEMENTS" "$MACOS/Zinc"
  codesign -s - --force --identifier "com.zurmely.zinc" --entitlements "$ENTITLEMENTS" "$APP"
fi

"$ROOT/scripts/verify-release.sh" "$APP"
if [[ "${VERIFY_BROWSER_CAPTURE:-}" == "1" ]]; then
  "$ROOT/scripts/verify-release.sh" --browser "$APP"
fi

codesign -dv "$APP" 2>&1 | sed -n '1,12p' || true

echo "Built $APP"
echo "Run: open $APP"
