#!/usr/bin/env bash
# End-to-end check of brightness: the shared backend, the app following
# changes made outside it, the app setting it, the key command, and (with an
# HDR-capable panel) brightness in HDR: SDR brightness from the Settings path
# and from the keys, with and without Panorama's help. Needs a running
# Panorama. Restores the brightness and drops the live HDR change.
# Usage: tests/e2e/brightness.sh [MONITOR]   (default: the focused monitor)
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
mon=${1:-$(hyprctl -j monitors | jq -r '.[] | select(.focused) | .name')}
helper=$root/bin/panorama-brightness
pass=0
fail=0

ipc() { qs -p "$root" ipc call panorama "$@"; }
state() { ipc state; }
phase() { state | jq -r .phase; }
app_percent() { state | jq -r --arg m "$mon" '.brightness[$m].percent'; }
sdr() { hyprctl -j monitors | jq -r --arg m "$mon" '.[] | select(.name == $m) | .sdrBrightness'; }
cm() { hyprctl -j monitors | jq -r --arg m "$mon" '.[] | select(.name == $m) | .colorManagementPreset'; }
actual() { "$helper" get "$mon"; }

check() {
  if [[ $2 == "$3" ]]; then
    echo "  ✔ $1"
    ((pass++))
  else
    echo "  ✖ $1: got '$2', want '$3'"
    ((fail++))
  fi
}

# Poll until the app shows the expected value (it polls every 1.5 s).
wait_app() {
  for _ in $(seq 1 20); do
    [[ $(app_percent) == "$1" ]] && return 0
    sleep 0.25
  done
  return 1
}

wait_phase() {
  for _ in $(seq 1 40); do
    [[ $(phase) == "$1" ]] && return 0
    sleep 0.25
  done
  return 1
}

state >/dev/null 2>&1 || { echo "Panorama isn't running (start it with bin/panorama)"; exit 1; }
original=$("$helper" get "$mon") || { echo "$mon has no adjustable brightness"; exit 1; }
trap '"$helper" set "$mon" "$original%" >/dev/null' EXIT
echo "testing $mon (brightness $original%)"

echo "1. the shared backend"
check "absolute set" "$("$helper" set "$mon" 40%)" 40
check "relative step up" "$("$helper" set "$mon" +5%)" 45
check "relative step down" "$("$helper" set "$mon" 5%-)" 40
check "never below 1 %" "$("$helper" set "$mon" 0%)" 1
"$helper" set "$mon" 40% >/dev/null

echo "2. the app follows changes made outside it"
"$helper" set "$mon" 30% >/dev/null
wait_app 30
check "app shows 30 %" "$(app_percent)" 30

echo "3. the app sets it"
ipc setBrightness "$mon" 55
sleep 0.8
check "applied: 55 %" "$(actual)" 55
sleep 1.8
check "a later poll keeps 55 %" "$(app_percent)" 55

echo "4. the key command"
"$root/bin/panorama" --brightness +5%
check "key step up" "$(actual)" 60
"$root/bin/panorama" --brightness --hdr 5%-
check "--hdr on an SDR monitor changes the backlight" "$(actual)" 55

if [[ ${SKIP_HDR:-} != 1 ]]; then
  echo "5. brightness in HDR is SDR brightness"
  for kv in "cm hdr" "bitdepth 10" "supports_hdr 1" "supports_wide_color 1"; do ipc setColor "$mon" $kv; done
  ipc apply
  wait_phase confirming
  sleep 2
  ipc keep
  wait_phase idle
  if [[ $(cm) == hdr ]]; then
    before=$(actual)
    "$root/bin/panorama" --brightness --hdr +5%
    sleep 0.8
    check "key through Panorama: SDR brightness 1 → 1.05" "$(sdr)" 1.05
    check "backlight untouched" "$(actual)" "$before"
    ipc setSdrBrightness "$mon" 1.5
    sleep 0.8
    check "app slider path: 1.5" "$(sdr)" 1.5
    # Without Panorama's IPC: a partial rule merged into the saved same-name
    # rule. Simulated by calling the helper's fallback directly.
    value=$(PATH="$root/tests/e2e/no-qs:$PATH" "$helper" sdr "$mon" 5%-)
    sleep 0.8
    check "key without Panorama: 1.5 → 1.45" "$(sdr)" 1.45
    check "…and HDR stays on" "$(cm)" hdr
  else
    echo "  (HDR didn't engage on $mon; skipped)"
  fi
  # Drop the live HDR change: Hyprland goes back to the saved file.
  hyprctl reload >/dev/null
  sleep 2
fi

echo
echo "$pass passed, $fail failed"
((fail == 0))
