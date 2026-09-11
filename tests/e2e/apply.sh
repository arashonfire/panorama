#!/usr/bin/env bash
# End-to-end check of the apply → confirm → keep/revert flow, driven over IPC
# against a headless output, so the real panel is never reconfigured.
# Needs a running Panorama (bin/panorama). Takes about a minute: one step waits
# out the 15 s confirmation timeout. Leaves no headless output behind.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
OUT=PANO-E2E
pass=0
fail=0

ipc() { qs -p "$root" ipc call panorama "$@"; }
state() { ipc state; }
phase() { state | jq -r .phase; }
field() { hyprctl -j monitors all | jq -r --arg n "$OUT" ".[] | select(.name == \$n) | $1"; }
focused_ws() { hyprctl -j monitors | jq -r '.[] | select(.focused) | .activeWorkspace.name'; }
focus_ws() { hyprctl dispatch "hl.dsp.focus({ workspace = \"$1\" })" >/dev/null; }

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

cleanup() {
  ipc reset >/dev/null 2>&1
  [[ $(phase) == confirming ]] && ipc revert >/dev/null && wait_phase idle
  # A disabled headless output can't be removed, so make sure it's on first.
  hyprctl eval "hl.monitor({ output = \"$OUT\", disabled = false })" >/dev/null 2>&1
  sleep 0.5
  hyprctl output remove "$OUT" >/dev/null 2>&1
  hyprctl reload >/dev/null
  sleep 1
  focus_ws "$home_ws"
}

ipc state >/dev/null 2>&1 || { echo "Panorama isn't running (start it with bin/panorama)"; exit 1; }
[[ $(phase) == idle ]] || { echo "Panorama is busy ($(phase)); finish that first"; exit 1; }

home_ws=$(focused_ws)
hyprctl output create headless "$OUT" >/dev/null
sleep 1.5
focus_ws "$home_ws"
trap cleanup EXIT
initial_scale=$(field .scale)
others() { hyprctl -j monitors all | jq -c --arg n "$OUT" '[.[] | select(.name != $n) | {name, x, y}]'; }
others_before=$(others)
echo "headless $OUT at scale $initial_scale; home workspace $home_ws"

echo "1. apply, then revert"
ipc setScale "$OUT" 1.5
sleep 0.3
check "draft shows one changed display" "$(state | jq -r '.changes | length')" 1
ipc apply
wait_phase confirming
check "waiting for confirmation" "$(phase)" confirming
check "scale applied live" "$(field .scale)" 1.5
sleep 0.8
check "other displays stay put" "$(others)" "$others_before"
sleep 1.8
check "verification found no issues" "$(state | jq -r '.issues | length')" 0
ipc revert
wait_phase idle
sleep 0.5
check "scale restored" "$(field .scale)" "$initial_scale"
check "draft kept for another try" "$(state | jq -r '.changes | length')" 1
ipc reset

echo "2. apply, then keep"
ipc setTransform "$OUT" 1
ipc apply
wait_phase confirming
ipc keep
wait_phase idle
check "transform kept" "$(field .transform)" 1
check "marked live but unsaved" "$(state | jq -r .liveUnsaved)" true
check "draft cleared" "$(state | jq -r '.changes | length')" 0

echo "3. no answer reverts after the timeout"
ipc setScale "$OUT" 1
ipc apply
wait_phase confirming
check "scale applied live" "$(field .scale)" 1
sleep 16.5
check "back to idle" "$(phase)" idle
check "scale restored" "$(field .scale)" "$initial_scale"
check "says why" "$(state | jq -r '.message | startswith("No answer")')" true
ipc reset

echo "4. turning an output off and on keeps the focused workspace"
ipc setEnabled "$OUT" false
ipc apply
wait_phase confirming
sleep 1.8
check "output off" "$(field .disabled)" true
check "workspace unchanged" "$(focused_ws)" "$home_ws"
ipc keep
wait_phase idle
ipc setEnabled "$OUT" true
ipc apply
wait_phase confirming
sleep 1.8
check "output on" "$(field .disabled)" false
check "workspace unchanged" "$(focused_ws)" "$home_ws"
ipc keep
wait_phase idle

echo "5. validation blocks an unclean scale"
ipc setScale "$OUT" 1.75
sleep 0.3
check "one error" "$(state | jq -r '.errors | length')" 1
ipc apply
sleep 0.5
check "nothing applied" "$(phase)" idle
check "scale unchanged" "$(field .scale)" "$initial_scale"
ipc reset

echo "6. a config reload during the countdown"
ipc setScale "$OUT" 1.25
ipc apply
wait_phase confirming
hyprctl reload >/dev/null
sleep 1
check "back to idle" "$(phase)" idle
check "says why" "$(state | jq -r '.message | contains("reloaded")')" true
ipc reset

echo
echo "$pass passed, $fail failed"
((fail == 0))
