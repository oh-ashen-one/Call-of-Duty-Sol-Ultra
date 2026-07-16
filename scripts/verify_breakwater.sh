#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GODOT_BIN=${GODOT_BIN:-godot}
LOG_DIR=${TMPDIR:-/tmp}/project-breakwater-verify
BUILD_DIR="$PROJECT_DIR/build"
APP_PATH="$BUILD_DIR/Project Breakwater.app"
APP_BINARY="$APP_PATH/Contents/MacOS/Project Breakwater"
APP_PACK="$APP_PATH/Contents/Resources/Project Breakwater.pck"
PACK_PROJECT="$LOG_DIR/pack-project"
SIGNED_APP="$LOG_DIR/Project Breakwater.app"
SIGNED_BINARY="$SIGNED_APP/Contents/MacOS/Project Breakwater"
ARCHIVE_PATH="$BUILD_DIR/Project Breakwater-macOS.zip"
ARCHIVE_CHECK="$LOG_DIR/archive-check"
ARCHIVED_BINARY="$ARCHIVE_CHECK/Project Breakwater.app/Contents/MacOS/Project Breakwater"

mkdir -p "$LOG_DIR" "$BUILD_DIR"

if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
  echo "Godot was not found. Install Godot 4.7 with: brew install --cask godot" >&2
  exit 1
fi

cd "$PROJECT_DIR"

run_and_log() {
  name=$1
  shift
  echo "[Breakwater] $name"
  if "$@" >"$LOG_DIR/$name.log" 2>&1; then
    cat "$LOG_DIR/$name.log"
  else
    status=$?
    cat "$LOG_DIR/$name.log" >&2
    return "$status"
  fi
}

assert_log_contains() {
  name=$1
  expected=$2
  if ! grep -F "$expected" "$LOG_DIR/$name.log" >/dev/null 2>&1; then
    echo "Expected output was not found in $LOG_DIR/$name.log: $expected" >&2
    exit 1
  fi
}

assert_no_script_errors() {
  name=$1
  if grep -E "SCRIPT ERROR|Parse Error|ERROR:|Invalid call|Assertion failed|CRASH" "$LOG_DIR/$name.log" >/dev/null 2>&1; then
    echo "Godot reported a script error in $LOG_DIR/$name.log" >&2
    exit 1
  fi
}

assert_bot_activity() {
  name=$1
  kills=$(sed -n 's/.*bot_kills=\([0-9][0-9]*\).*/\1/p' "$LOG_DIR/$name.log" | tail -1)
  bot_vs_bot=$(sed -n 's/.*bot_vs_bot=\([0-9][0-9]*\).*/\1/p' "$LOG_DIR/$name.log" | tail -1)
  if [ -z "$kills" ] || [ "$kills" -le 0 ]; then
    echo "No autonomous bot scoring was reported in $LOG_DIR/$name.log" >&2
    exit 1
  fi
  if [ -z "$bot_vs_bot" ] || [ "$bot_vs_bot" -le 0 ]; then
    echo "No bot-versus-bot eliminations were reported in $LOG_DIR/$name.log" >&2
    exit 1
  fi
}

assert_bot_systems() {
  name=$1
  grenades=$(sed -n 's/.*bot_grenades=\([0-9][0-9]*\).*/\1/p' "$LOG_DIR/$name.log" | tail -1)
  pickups=$(sed -n 's/.*bot_pickups=\([0-9][0-9]*\).*/\1/p' "$LOG_DIR/$name.log" | tail -1)
  if [ -z "$grenades" ] || [ "$grenades" -le 0 ]; then
    echo "No autonomous bot grenade use was reported in $LOG_DIR/$name.log" >&2
    exit 1
  fi
  if [ -z "$pickups" ] || [ "$pickups" -le 0 ]; then
    echo "No autonomous bot pickup collection was reported in $LOG_DIR/$name.log" >&2
    exit 1
  fi
}

run_and_log import "$GODOT_BIN" --headless --path . --editor --quit
assert_no_script_errors import

run_and_log gameplay "$GODOT_BIN" --headless --fixed-fps 60 --path . --script tests/gameplay/run_tests.gd
assert_log_contains gameplay "GAMEPLAY TESTS PASS"
assert_no_script_errors gameplay

run_and_log integration "$GODOT_BIN" --headless --fixed-fps 60 --path . --script tests/integration/run_tests.gd
assert_log_contains integration "INTEGRATION TESTS PASS"
assert_no_script_errors integration

run_and_log bot_benchmark "$GODOT_BIN" --headless --fixed-fps 60 --path . -- --bot-benchmark=300 --time-scale=12
assert_log_contains bot_benchmark "BOT_BENCHMARK simulated=300.0s"
assert_bot_activity bot_benchmark
assert_bot_systems bot_benchmark
assert_no_script_errors bot_benchmark

run_and_log export "$GODOT_BIN" --headless --path . --export-debug "macOS" "$APP_PATH"
assert_no_script_errors export

if [ ! -x "$APP_BINARY" ]; then
  echo "Export did not produce the expected executable: $APP_BINARY" >&2
  exit 1
fi

if [ ! -f "$APP_PACK" ]; then
  echo "Export did not produce the expected resource pack: $APP_PACK" >&2
  exit 1
fi

mkdir -p "$PACK_PROJECT"
printf '[application]\nconfig/name="Pack Verification"\n' >"$PACK_PROJECT/project.godot"
run_and_log pack_manifest "$GODOT_BIN" --headless --path "$PACK_PROJECT" --script "$PROJECT_DIR/scripts/verify_export_pack.gd" -- "$APP_PACK"
assert_log_contains pack_manifest "PACK_MANIFEST_OK"
assert_no_script_errors pack_manifest

rm -rf "$SIGNED_APP" "$ARCHIVE_CHECK"
run_and_log stage_signed_bundle ditto "$APP_PATH" "$SIGNED_APP"
run_and_log clear_bundle_metadata xattr -cr "$SIGNED_APP"
run_and_log codesign codesign --force --deep --sign - --timestamp=none "$SIGNED_APP"
run_and_log codesign_verify codesign --verify --deep --strict --verbose=4 "$SIGNED_APP"

run_and_log architecture lipo -info "$SIGNED_BINARY"
assert_log_contains architecture "x86_64"
assert_log_contains architecture "arm64"

rm -f "$ARCHIVE_PATH"
run_and_log archive ditto -c -k --keepParent "$SIGNED_APP" "$ARCHIVE_PATH"
mkdir -p "$ARCHIVE_CHECK"
run_and_log archive_extract ditto -x -k "$ARCHIVE_PATH" "$ARCHIVE_CHECK"
run_and_log archive_signature codesign --verify --deep --strict --verbose=4 "$ARCHIVE_CHECK/Project Breakwater.app"
run_and_log archive_architecture lipo -info "$ARCHIVED_BINARY"
assert_log_contains archive_architecture "x86_64"
assert_log_contains archive_architecture "arm64"

run_and_log exported_gameplay "$ARCHIVED_BINARY" --headless --fixed-fps 60 -- --bot-benchmark=60 --time-scale=12
assert_log_contains exported_gameplay "BOT_BENCHMARK simulated=60.0s"
assert_bot_activity exported_gameplay
assert_no_script_errors exported_gameplay

gameplay_assertions=$(sed -n 's/.*PASS.* \([0-9][0-9]*\) assertions.*/\1/p' "$LOG_DIR/gameplay.log" | tail -1)
integration_assertions=$(sed -n 's/.*PASS.* \([0-9][0-9]*\) assertions.*/\1/p' "$LOG_DIR/integration.log" | tail -1)
if [ -z "$gameplay_assertions" ] || [ -z "$integration_assertions" ]; then
  echo "Unable to read assertion totals from the test logs" >&2
  exit 1
fi
total_assertions=$((gameplay_assertions + integration_assertions))
echo "[Breakwater] PASS — $total_assertions automated assertions, five-minute bot combat/equipment simulation, verified ad-hoc-signed macOS archive, and exported-app gameplay test"
echo "[Breakwater] Logs: $LOG_DIR"
