#!/usr/bin/env bash
# Spike: VRR, 10-bit and HDR on the real internal panel (eDP-1).
# Safety: a detached watchdog runs `hyprctl reload` after $WATCHDOG seconds no
# matter what happens to this script. Reload drops every eval-applied rule and
# restores monitors.lua (verified in headless.sh).
set -u
OUT=${OUT:-eDP-1}
WATCHDOG=${WATCHDOG:-90}
shots=${1:-.}

setsid bash -c "sleep $WATCHDOG; hyprctl reload >/dev/null" >/dev/null 2>&1 &
echo "watchdog armed: reload in ${WATCHDOG}s"

snap() {
  hyprctl -j monitors all | jq -c --arg n "$OUT" '.[] | select(.name == $n) |
    {mode: "\(.width)x\(.height)@\(.refreshRate)", scale, vrr, fmt: .currentFormat,
     cm: .colorManagementPreset, sdrB: .sdrBrightness, sdrS: .sdrSaturation,
     sdrMin: .sdrMinLuminance, sdrMax: .sdrMaxLuminance}'
}

ev() {
  echo "## $1"
  local start=$(date +%s%N)
  hyprctl eval "$1" 2>&1 | sed 's/^/   /'
  echo "   eval took $(( ($(date +%s%N) - start) / 1000000 )) ms"
  sleep 1.5
  echo "   => $(snap)"
}

B="output = \"$OUT\", mode = \"2560x1600@165\", position = \"0x0\", scale = 1.6"

echo "initial => $(snap)"

echo; echo "### baseline (same as current)"
ev "hl.monitor({ $B })"

echo; echo "### VRR"
ev "hl.monitor({ $B, vrr = 1 })"
hyprctl -j monitors | jq -c '.[] | {name, vrr, activelyTearing}'
ev "hl.monitor({ $B, vrr = 2 })"
ev "hl.monitor({ $B, vrr = 0 })"

echo; echo "### 10-bit"
ev "hl.monitor({ $B, vrr = 0, bitdepth = 10 })"

echo; echo "### color presets"
for cm in wide edid dcip3; do
  ev "hl.monitor({ $B, vrr = 0, bitdepth = 10, cm = \"$cm\" })"
done

echo; echo "### HDR"
ev "hl.monitor({ $B, vrr = 0, bitdepth = 10, cm = \"hdr\" })"
grim -o "$OUT" "$shots/edp-hdr.png" 2>&1
ev "hl.monitor({ $B, vrr = 0, bitdepth = 10, cm = \"hdredid\" })"
ev "hl.monitor({ $B, vrr = 0, bitdepth = 10, cm = \"hdr\", sdrbrightness = 1.4, sdrsaturation = 1.2 })"
ev "hl.monitor({ $B, vrr = 0, bitdepth = 10, cm = \"hdr\", sdrbrightness = 1.0, sdrsaturation = 1.0, sdr_eotf = \"gamma22\" })"

echo; echo "### back to SDR"
ev "hl.monitor({ $B, vrr = 0, bitdepth = 8, cm = \"srgb\", sdr_eotf = \"default\" })"

echo; echo "### reload restores monitors.lua"
hyprctl reload >/dev/null
sleep 2
echo "after reload => $(snap)"
hyprctl configerrors
pkill -f "sleep $WATCHDOG; hyprctl reload" 2>/dev/null && echo "watchdog disarmed"
