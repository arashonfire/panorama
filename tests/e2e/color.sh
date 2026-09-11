#!/usr/bin/env bash
# End-to-end check of color, HDR and VRR on a real monitor, driven over IPC
# through Panorama's own apply path. Every change is reverted (or dropped with
# a config reload), and nothing is saved. Needs a running Panorama and an
# HDR-capable monitor; the screen flickers and briefly switches to HDR.
# Usage: tests/e2e/color.sh [MONITOR]   (default: the focused monitor)
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
mon=${1:-$(hyprctl -j monitors | jq -r '.[] | select(.focused) | .name')}
pass=0
fail=0

ipc() { qs -p "$root" ipc call panorama "$@"; }
state() { ipc state; }
phase() { state | jq -r .phase; }
live() { hyprctl -j monitors all | jq -r --arg n "$mon" ".[] | select(.name == \$n) | $1"; }

check() {
  if [[ $2 == "$3" ]]; then
    echo "  ✔ $1"
    ((pass++))
  else
    echo "  ✖ $1: got '$2', want '$3'"
    ((fail++))
  fi
}

wait_phase() {
  for _ in $(seq 1 40); do
    [[ $(phase) == "$1" ]] && return 0
    sleep 0.25
  done
  return 1
}

apply_and_settle() {
  ipc apply
  wait_phase confirming
  sleep 2.5
}

revert() {
  ipc revert
  wait_phase idle
  sleep 1.5
  ipc reset
}

set_color() {
  local key value
  while (($#)); do
    key=$1 value=$2
    shift 2
    ipc setColor "$mon" "$key" "$value"
  done
}

state >/dev/null 2>&1 || { echo "Panorama isn't running (start it with bin/panorama)"; exit 1; }
[[ $(phase) == idle ]] || { echo "Panorama is busy ($(phase)); finish that first"; exit 1; }
[[ $(state | jq '.changes | length') == 0 ]] || { echo "Panorama has pending edits; reset or apply them first"; exit 1; }
[[ $(state | jq -r .liveUnsaved) == false ]] || { echo "Panorama has unsaved live changes; save or reload first"; exit 1; }

cm0=$(live .colorManagementPreset)
fmt0=$(live .currentFormat)
echo "testing $mon (now $cm0, $fmt0)"

echo "1. 10-bit"
set_color bitdepth 10
apply_and_settle
check "10-bit format" "$(live '.currentFormat | test("2101010")')" true
revert
check "back to $fmt0" "$(live .currentFormat)" "$fmt0"

echo "2. HDR with forced support"
set_color cm hdr bitdepth 10 supports_hdr 1 supports_wide_color 1 sdrbrightness 1.3
apply_and_settle
check "HDR active" "$(live .colorManagementPreset)" hdr
check "SDR brightness applied" "$(live .sdrBrightness)" 1.3
check "no issues reported" "$(state | jq '.issues | length')" 0
revert
check "back to $cm0" "$(live .colorManagementPreset)" "$cm0"

echo "3. VRR through the nudge"
vrr_global=$(hyprctl -j getoption misc:vrr | jq .int)
set_color vrr 1
apply_and_settle
check "Hyprland reports VRR active" "$(live .vrr)" true
check "no VRR refusal in the log" "$(state | jq '[.issues[] | select(test("refused VRR"))] | length')" 0
revert
[[ $vrr_global == 0 ]] && check "VRR off again" "$(live .vrr)" false

echo "4. a kept HDR change is what a save would write"
set_color cm hdr bitdepth 10 supports_hdr 1 supports_wide_color 1
apply_and_settle
ipc keep
wait_phase idle
preview=$(ipc preview)
check "section asks for HDR" "$(grep -c "\"$mon\".*cm = \"hdr\"" <<<"$preview")" 1
check "section forces HDR + wide color" "$(grep -c 'supports_hdr = 1.*supports_wide_color = 1' <<<"$preview")" 1
check "live but unsaved" "$(state | jq -r .liveUnsaved)" true
# Drop the unsaved live change: Hyprland goes back to the saved file.
hyprctl reload >/dev/null
sleep 2
check "reload restored $cm0" "$(live .colorManagementPreset)" "$cm0"
check "applied rules forgotten" "$(state | jq '.appliedRules | length')" 0

echo
echo "$pass passed, $fail failed"
((fail == 0))
