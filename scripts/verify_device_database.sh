#!/usr/bin/env bash
set -euo pipefail

serial="${1:-}"
if [[ -z "$serial" ]]; then
  serial="$(adb devices | awk 'NR > 1 && $2 == "device" { print $1; exit }')"
fi
if [[ -z "$serial" ]]; then
  echo "No authorized Android device found" >&2
  exit 2
fi

package="dev.rahul.ntfy_flutter"
launch() {
  adb -s "$serial" shell monkey \
    -p "$package" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
}

adb -s "$serial" shell am force-stop "$package"
launch
sleep 4
adb -s "$serial" shell input keyevent KEYCODE_HOME
sleep 1
launch
sleep 4

focus="$(adb -s "$serial" shell dumpsys window | grep -m1 'mCurrentFocus=' || true)"
if [[ "$focus" != *"$package"* ]]; then
  echo "App is not visible; unlock the device and rerun" >&2
  exit 2
fi

MSYS_NO_PATHCONV=1 adb -s "$serial" shell \
  uiautomator dump /sdcard/ntfy-window.xml >/dev/null
ui="$(MSYS_NO_PATHCONV=1 adb -s "$serial" shell cat /sdcard/ntfy-window.xml)"

if grep -q "database_closed" <<<"$ui"; then
  echo "FAIL: database_closed appeared after foreground-service restart" >&2
  exit 1
fi

echo "PASS: database stayed open after app background/resume"
