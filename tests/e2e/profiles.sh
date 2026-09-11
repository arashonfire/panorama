#!/usr/bin/env bash
# Live check of the profile handler Panorama writes into monitors.lua, without
# touching the file: the same Lua (lib/profiles.js) is registered at runtime
# with `hyprctl eval`, then a headless output is plugged in and out. A config
# reload at the end drops the handler and its rules again.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
out=PROF-1
home_ws=$(hyprctl -j monitors | jq -r '.[] | select(.focused) | .activeWorkspace.name')
pass=0
fail=0

check() {
  if [[ $2 == "$3" ]]; then
    echo "  ✔ $1"
    ((pass++))
  else
    echo "  ✖ $1: got '$2', want '$3'"
    ((fail++))
  fi
}

pos() { hyprctl -j monitors | jq -r --arg n "$1" '.[] | select(.name == $n) | "\(.x),\(.y)"'; }

cleanup() {
  hyprctl eval "hl.monitor({ output = \"$out\", disabled = false })" >/dev/null 2>&1
  hyprctl output remove "$out" >/dev/null 2>&1
  hyprctl reload >/dev/null
  sleep 1.5
  hyprctl dispatch "hl.dsp.focus({ workspace = \"$home_ws\" })" >/dev/null
}
trap cleanup EXIT

edp=$(hyprctl -j monitors | jq -c '.[] | select(.name == "eDP-1") | {mode: "\(.width)x\(.height)@\(.refreshRate | round)", scale}')
[[ -n $edp ]] || { echo "needs eDP-1"; exit 1; }
mode=$(jq -r .mode <<<"$edp")
scale=$(jq -r .scale <<<"$edp")

# A profile for eDP-1 + the headless output: headless on the left, the panel
# to its right, and workspace 8 on the headless output. Base: the panel at 0,0.
script=$(cd "$root" && node -e '
  const load = require("./tests/load");
  const P = load("lib/profiles.js");
  const [out, mode, scale] = process.argv.slice(1);
  const edp = (position) => ({ output: "eDP-1", disabled: false, mode, position, scale: Number(scale), transform: 0, mirror: "" });
  const profile = {
    name: "Test",
    monitors: [{ match: "eDP-1", port: "eDP-1" }, { match: out, port: out }],
    rules: [edp("1920x0"), { output: out, disabled: false, mode: "1920x1080@60", position: "0x0", scale: 1, transform: 0, mirror: "" }],
    workspaces: [{ workspace: "8", monitor: out }]
  };
  process.stdout.write(P.render([profile], [edp("0x0")]).join("\n"));
' "$out" "$mode" "$scale")

echo "1. register the handler (as loading monitors.lua would)"
# The generated Lua starts with a `--` comment, which hyprctl would take for a
# flag; a leading newline keeps it an argument.
check "eval accepted" "$(hyprctl eval $'\n'"$script")" ok
sleep 1
check "no profile matches eDP-1 alone: base layout" "$(pos eDP-1)" "0,0"

echo "2. plug in the profile's other monitor"
hyprctl output create headless "$out" >/dev/null
sleep 2.5
check "headless placed by the profile" "$(pos "$out")" "0,0"
check "panel moved by the profile" "$(pos eDP-1)" "1920,0"
check "workspace 8 rule on the headless output" "$(hyprctl -j workspacerules | jq -r '.[] | select(.workspaceString == "8") | .monitor')" "$out"

echo "3. unplug it"
hyprctl output remove "$out" >/dev/null
sleep 2
check "back to the base layout" "$(pos eDP-1)" "0,0"

echo "4. plug in again"
hyprctl output create headless "$out" >/dev/null
sleep 2.5
check "profile again" "$(pos eDP-1)" "1920,0"

echo
echo "$pass passed, $fail failed"
((fail == 0))
