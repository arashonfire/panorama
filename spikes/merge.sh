#!/usr/bin/env bash
# Spike: rule merge semantics on a headless output. How do we clear a mirror or
# re-enable a disabled output when hl.monitor merges into the existing rule?
set -u

snap() {
  hyprctl -j monitors all | jq -c --arg n "$1" '.[] | select(.name == $n) |
    {mode: "\(.width)x\(.height)@\(.refreshRate)", x, y, scale, disabled, mirrorOf}'
}

ev() {
  echo "## $1"
  hyprctl eval "$1" 2>&1 | sed 's/^/   /'
  sleep 0.6
  echo "   => $(snap "$OUT")"
}

before=$(hyprctl -j monitors all | jq -r '.[].name' | sort)
hyprctl output create headless PANO-2 >/dev/null
sleep 1
OUT=$(comm -13 <(echo "$before") <(hyprctl -j monitors all | jq -r '.[].name' | sort) | head -1)
M="output = \"$OUT\", mode = \"1920x1080@60\", position = \"4000x0\", scale = 1"
echo "headless: $OUT"

echo; echo "### clearing a mirror"
ev "hl.monitor({ $M, mirror = \"eDP-1\" })"
ev "hl.monitor({ $M, mirror = \"\" })"
ev "hl.monitor({ $M, mirror = \"eDP-1\" })"
ev "hl.monitor({ $M, mirror = \"none\" })"

echo; echo "### re-enabling"
ev "hl.monitor({ $M, disabled = true })"
ev "hl.monitor({ $M, disabled = false })"

echo; echo "### clearing vrr back to 'unset' (-1)"
ev "hl.monitor({ $M, vrr = 1 })"
ev "hl.monitor({ $M, vrr = -1 })"

echo; echo "### eval timing for a no-op full rule"
start=$(date +%s%N)
hyprctl eval "hl.monitor({ $M })" >/dev/null
echo "   $(( ($(date +%s%N) - start) / 1000000 )) ms"

hyprctl output remove "$OUT"
sleep 0.5
hyprctl reload >/dev/null
hyprctl configerrors
