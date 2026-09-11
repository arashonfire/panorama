#!/usr/bin/env bash
# End-to-end check of the keyboard move (Alt+arrows → Draft.nudge), driven over
# IPC against a headless output. Nothing is applied: it only inspects the draft.
# Needs a running Panorama (bin/panorama). Leaves no headless output behind.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
OUT=PANO-NUDGE
pass=0
fail=0

ipc() { qs -p "$root" ipc call panorama "$@"; }
state() { ipc state; }
# Draft position of the headless output, relative to the other display, which
# normalize() may shift too.
pos() {
  state | jq -r --arg n "$OUT" --arg o "$other" '
    (.draft[] | select(.name == $n)) as $a
    | (.draft[] | select(.name == $o)) as $b
    | "\($a.x - $b.x),\($a.y - $b.y)"'
}
live() { hyprctl -j monitors all | jq -r --arg n "$1" ".[] | select(.name == \$n) | $2"; }
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

cleanup() {
  ipc reset >/dev/null 2>&1
  hyprctl output remove "$OUT" >/dev/null 2>&1
  hyprctl reload >/dev/null
  sleep 1
  focus_ws "$home_ws"
}

ipc state >/dev/null 2>&1 || { echo "Panorama isn't running (start it with bin/panorama)"; exit 1; }
[[ $(state | jq -r .phase) == idle ]] || { echo "Panorama is busy; finish that first"; exit 1; }
[[ $(state | jq -r '.changes | length') == 0 ]] || { echo "Panorama has unapplied edits; reset them first"; exit 1; }

home_ws=$(focused_ws)
other=$(hyprctl -j monitors | jq -r '[.[] | select(.name != "'"$OUT"'")][0].name')
hyprctl output create headless "$OUT" >/dev/null
sleep 1.5
focus_ws "$home_ws"
trap cleanup EXIT

# Put the headless output right of the other display, top-aligned, as a draft.
ow=$(hyprctl -j monitors | jq -r --arg o "$other" '.[] | select(.name == $o) | (if .transform % 2 == 1 then .height else .width end) / .scale | floor')
ox=$(live "$other" .x)
oy=$(live "$other" .y)
ipc move "$OUT" $((ox + ow)) "$oy"
sleep 0.3
start=$(pos)
echo "headless $OUT next to $other (width $ow); draft offset $start"
check "starts flush right, top-aligned" "$start" "$ow,0"

echo "1. sliding along the shared edge"
ipc nudge "$OUT" 0 100
sleep 0.2
check "moved down 100" "$(pos)" "$ow,100"
ipc nudge "$OUT" 0 -10
sleep 0.2
check "fine step up 10" "$(pos)" "$ow,90"

echo "2. moving away snaps back flush"
ipc nudge "$OUT" 100 0
sleep 0.2
check "still flush" "$(pos)" "$ow,90"

echo "3. moving into the other display is refused"
ipc nudge "$OUT" -100 0
sleep 0.2
check "still flush" "$(pos)" "$ow,90"

echo "4. nothing is applied"
check "phase idle" "$(state | jq -r .phase)" idle

echo
echo "$pass passed, $fail failed"
((fail == 0))
