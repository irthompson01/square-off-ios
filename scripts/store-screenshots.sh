#!/bin/zsh
# App Store screenshots from the simulators: one 6.9" iPhone set (the largest iPhone in the runtime, 1320×2868)
# and one 13" iPad set (iPad Pro 13-inch, 2064×2752), eight screens each, captured from a Debug
# build on the in-app mock with the demo account (the launch arguments only exist in Debug).
#
#   scripts/store-screenshots.sh                 # both families → build-screenshots/{iphone-6.9,ipad-13}/
#   FAMILIES=iphone scripts/store-screenshots.sh # one family
#   RUNTIME="iOS 27.0" IPHONE_NAME="iPhone 18 Pro Max" IPAD_NAME="iPad Pro 13-inch (M5)" …
#
# No framing or captions: Apple accepts raw device captures. Check each PNG shows no "mock",
# "Developer" or "local" text before uploading.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

RUNTIME=${RUNTIME:-}
IPHONE_NAME=${IPHONE_NAME:-iPhone 18 Pro Max}
IPAD_NAME=${IPAD_NAME:-iPad Pro 13-inch (M5)}
FAMILIES=${FAMILIES:-iphone ipad}
BUNDLE=com.novastrada.squareoff
OUT=build-screenshots
DERIVED=$OUT/derived
APP=$DERIVED/Build/Products/Debug-iphonesimulator/SquareOff.app

# The first simctl call after an Xcode update can take a couple of minutes (CoreSimulator
# reinstalls its service); do it once before any timed step.
xcrun simctl list devices >/dev/null

# Newest runtime unless RUNTIME says otherwise.
if [ -z "$RUNTIME" ]; then
  RUNTIME=$(xcrun simctl list runtimes available | sed -nE 's/^(iOS [0-9.]+) .*/\1/p' | sort -V | tail -1)
fi
echo "Runtime: $RUNTIME"

udid_for() {   # device name → UDID in that runtime (empty when absent; `set -e` must not trip on grep)
  # Names like "iPad Pro 13-inch (M5)" carry regex metacharacters, so escape them and insist the
  # UDID follows the name directly (keeps "(M5) (16GB)" variants from matching).
  local escaped; escaped=$(printf '%s' "$1" | sed -E 's/[][(){}.*+?^$|\\]/\\&/g')
  { xcrun simctl list devices available "$RUNTIME" | grep -E "^\s+$escaped \([0-9A-F-]{36}\)" || true; } | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
}

shots=(
  "01-home|"
  "02-game|-demoGame busy"
  "03-pass-and-play|-demoGame local4"
  "04-game-over|-demoGame over"
  "05-setup|-demoScreen setup"
  "06-online-room|-demoOnline host"
  "07-rules|-demoScreen rules"
  "08-stats|-demoScreen stats"
)

capture() {   # family dir, device name
  local dir=$1 name=$2
  local udid; udid=$(udid_for "$name")
  if [ -z "$udid" ]; then
    echo "No '$name' simulator in $RUNTIME. Create one: xcrun simctl create \"$name\" \"$name\" \"$RUNTIME\"" >&2
    exit 1
  fi
  echo "== $name ($udid) → $OUT/$dir"
  mkdir -p "$OUT/$dir"
  # A failed build must stop the run, or the shots silently come from a stale product.
  if ! xcodebuild -project SquareOff.xcodeproj -scheme SquareOff -configuration Debug \
      -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$DERIVED" build -quiet > "$OUT/build-$dir.log" 2>&1; then
    grep -E "error:|BUILD FAILED" "$OUT/build-$dir.log" | head -20 >&2
    echo "Build failed; see $OUT/build-$dir.log" >&2
    exit 1
  fi
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl uninstall "$udid" $BUNDLE 2>/dev/null || true     # clean defaults: no stale Continue game
  xcrun simctl install "$udid" "$APP"
  xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4
  for shot in "${shots[@]}"; do
    local file=${shot%%|*} args=${shot#*|}
    xcrun simctl terminate "$udid" $BUNDLE 2>/dev/null || true
    sleep 5                                     # a relaunch under ~5 s shows stale state
    xcrun simctl launch "$udid" $BUNDLE -backend mock -demoSignedIn YES ${=args} >/dev/null
    if [[ $args == *busy* ]]; then sleep 12; else sleep 10; fi
    xcrun simctl io "$udid" screenshot --type png "$OUT/$dir/$file.png" >/dev/null 2>&1
    echo "   $file.png  $(sips -g pixelWidth -g pixelHeight "$OUT/$dir/$file.png" | awk '/pixel/ {printf "%s ", $2}')"
  done
  xcrun simctl terminate "$udid" $BUNDLE 2>/dev/null || true
  xcrun simctl status_bar "$udid" clear
}

for family in ${=FAMILIES}; do
  case $family in
    iphone) capture iphone-6.9 "$IPHONE_NAME" ;;
    ipad)   capture ipad-13 "$IPAD_NAME" ;;
    *) echo "unknown family $family" >&2; exit 1 ;;
  esac
done
echo "done: $OUT"
