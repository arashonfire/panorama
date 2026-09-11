#!/usr/bin/env bash
# Runs the Quickshell probe, screenshots it, hot-plugs a headless output to see
# whether monitor events and per-screen Variants react, then prints the log.
# Usage: run.sh <screenshot-dir>
set -u
cd "$(dirname "$0")"
shots=${1:-.}
log=$XDG_RUNTIME_DIR/panorama-probe.log

timeout 25 qs -p . >"$log" 2>&1 &
pid=$!
sleep 4
grim -o eDP-1 "$shots/probe-1.png"
hyprctl clients -j | jq -c '.[] | select(.title == "panorama-probe") | {floating, size, at, monitor}'

before=$(hyprctl -j monitors all | jq -r '.[].name' | sort)
hyprctl output create headless PROBE-1 >/dev/null
sleep 2
out=$(comm -13 <(echo "$before") <(hyprctl -j monitors all | jq -r '.[].name' | sort) | head -1)
echo "headless: $out"
hyprctl layers -j | jq -c --arg n "$out" 'to_entries[] | select(.key == $n) | .value.levels | [.[][] | .namespace]'
hyprctl output remove "$out"
sleep 2
hyprctl reload >/dev/null
sleep 2

kill "$pid" 2>/dev/null
wait "$pid" 2>/dev/null
echo "----- qs log"
grep -vE '^\s*$' "$log"
echo "----- FileView output"
cat "$XDG_RUNTIME_DIR/panorama-probe.txt" 2>&1
