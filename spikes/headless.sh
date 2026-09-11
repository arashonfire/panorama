#!/usr/bin/env bash
# Spike: how runtime `hl.monitor` via `hyprctl eval` behaves, using a headless
# output so the real panel is never touched. Also probes hl.config and reload.
set -u

snap() {
  hyprctl -j monitors all | jq -c --arg n "$1" '.[] | select(.name == $n) |
    {mode: "\(.width)x\(.height)@\(.refreshRate)", x, y, scale, transform, vrr,
     disabled, mirrorOf, currentFormat, cm: .colorManagementPreset,
     sdrB: .sdrBrightness, sdrS: .sdrSaturation, sdrMin: .sdrMinLuminance,
     sdrMax: .sdrMaxLuminance}'
}

ev() {
  echo "## $1"
  hyprctl eval "$1" 2>&1 | sed 's/^/   /'
  echo "   rc=${PIPESTATUS[0]}"
  sleep 0.6
  echo "   => $(snap "$OUT")"
}

before=$(hyprctl -j monitors all | jq -r '.[].name' | sort)
hyprctl output create headless PANO-1 >/dev/null
sleep 1
after=$(hyprctl -j monitors all | jq -r '.[].name' | sort)
OUT=$(comm -13 <(echo "$before") <(echo "$after") | head -1)
[[ -n $OUT ]] || { echo "no headless output appeared"; exit 1; }

echo "headless output: $OUT"
hyprctl -j monitors all | jq --arg n "$OUT" '.[] | select(.name == $n) | {description, make, model, serial, availableModes}'
echo "   initial => $(snap "$OUT")"

M="output = \"$OUT\""

echo; echo "### full rule"
ev "hl.monitor({ $M, mode = \"1920x1080@60\", position = \"4000x0\", scale = 1 })"

echo; echo "### partial rule: does it merge with the previous rule or replace it?"
ev "hl.monitor({ $M, scale = 2 })"
ev "hl.monitor({ $M, mode = \"1920x1080@60\", position = \"4000x0\", scale = 1 })"

echo; echo "### scale validity"
ev "hl.monitor({ $M, mode = \"1920x1080@60\", position = \"4000x0\", scale = 1.5 })"
ev "hl.monitor({ $M, mode = \"1920x1080@60\", position = \"4000x0\", scale = 1.33 })"
ev "hl.monitor({ $M, mode = \"1920x1080@60\", position = \"4000x0\", scale = \"auto\" })"
ev "hl.monitor({ $M, mode = \"1920x1080@60\", position = \"4000x0\", scale = 1 })"

echo; echo "### modes"
ev "hl.monitor({ $M, mode = \"1280x720@30\", position = \"4000x0\", scale = 1 })"
ev "hl.monitor({ $M, mode = \"preferred\", position = \"4000x0\", scale = 1 })"
ev "hl.monitor({ $M, mode = \"bogus\", position = \"4000x0\", scale = 1 })"

echo; echo "### transform"
ev "hl.monitor({ $M, mode = \"1920x1080@60\", position = \"4000x0\", scale = 1, transform = 1 })"
ev "hl.monitor({ $M, mode = \"1920x1080@60\", position = \"4000x0\", scale = 1, transform = 7 })"
ev "hl.monitor({ $M, mode = \"1920x1080@60\", position = \"4000x0\", scale = 1, transform = 9 })"

echo; echo "### vrr"
for v in 1 2 3 0 true 5; do
  ev "hl.monitor({ $M, mode = \"1920x1080@60\", position = \"4000x0\", scale = 1, vrr = $v })"
done

echo; echo "### bitdepth"
ev "hl.monitor({ $M, mode = \"1920x1080@60\", position = \"4000x0\", scale = 1, bitdepth = 10 })"
ev "hl.monitor({ $M, mode = \"1920x1080@60\", position = \"4000x0\", scale = 1, bitdepth = 16 })"

echo; echo "### color management presets"
for cm in auto srgb dcip3 dp3 adobe wide edid hdr hdredid bogus; do
  ev "hl.monitor({ $M, mode = \"1920x1080@60\", position = \"4000x0\", scale = 1, cm = \"$cm\" })"
done

echo; echo "### sdr tuning (with cm = hdr)"
ev "hl.monitor({ $M, mode = \"1920x1080@60\", position = \"4000x0\", scale = 1, cm = \"hdr\", sdrbrightness = 1.3, sdrsaturation = 1.1, sdr_min_luminance = 0.005, sdr_max_luminance = 250 })"
for eotf in default srgb gamma22 bogus; do
  ev "hl.monitor({ $M, mode = \"1920x1080@60\", position = \"4000x0\", scale = 1, cm = \"hdr\", sdr_eotf = \"$eotf\" })"
done
ev "hl.monitor({ $M, mode = \"1920x1080@60\", position = \"4000x0\", scale = 1, cm = \"hdr\", min_luminance = 0.001, max_luminance = 1000, max_avg_luminance = 500, supports_hdr = 1, supports_wide_color = 1 })"

echo; echo "### unknown field"
ev "hl.monitor({ $M, mode = \"1920x1080@60\", position = \"4000x0\", scale = 1, bogus_field = 1 })"

echo; echo "### mirror, disable, re-enable"
ev "hl.monitor({ $M, mode = \"1920x1080@60\", position = \"4000x0\", scale = 1, mirror = \"eDP-1\" })"
ev "hl.monitor({ $M, mode = \"1920x1080@60\", position = \"4000x0\", scale = 1 })"
ev "hl.monitor({ $M, disabled = true })"
ev "hl.monitor({ $M, mode = \"1920x1080@60\", position = \"4000x0\", scale = 1 })"

echo; echo "### desc: selector"
desc=$(hyprctl -j monitors all | jq -r --arg n "$OUT" '.[] | select(.name == $n) | .description')
echo "description: '$desc'"
ev "hl.monitor({ output = \"desc:$desc\", mode = \"1280x720@60\", position = \"4000x0\", scale = 1 })"

echo; echo "### does reload discard eval-applied rules?"
ev "hl.monitor({ $M, mode = \"1920x1080@60\", position = \"5000x100\", scale = 2 })"
hyprctl reload >/dev/null; sleep 1.5
echo "   after reload => $(snap "$OUT")"

echo; echo "### hl.config at runtime (cursor.no_break_fs_vrr, restored afterwards)"
orig=$(hyprctl getoption cursor:no_break_fs_vrr -j | jq -r '.int')
echo "original: $orig"
hyprctl eval 'hl.config({ cursor = { no_break_fs_vrr = 0 } })'; echo "   rc=$?"
echo "   nested  => $(hyprctl getoption cursor:no_break_fs_vrr -j | jq -c '{int, set}')"
hyprctl eval 'hl.config({ ["cursor.no_break_fs_vrr"] = 1 })' 2>&1; echo "   rc=$?"
echo "   dotted  => $(hyprctl getoption cursor:no_break_fs_vrr -j | jq -c '{int, set}')"
hyprctl repl 'return tostring(hl.get_config("cursor.no_break_fs_vrr"))'; echo
hyprctl eval 'hl.config({ cursor = { bogus_option = 1 } })' 2>&1; echo "   rc(bogus)=$?"
hyprctl reload >/dev/null; sleep 1
echo "   after reload => $(hyprctl getoption cursor:no_break_fs_vrr -j | jq -c '{int, set}') (original $orig)"

echo; echo "### cleanup"
hyprctl output remove "$OUT"
sleep 0.5
hyprctl reload >/dev/null
echo "configerrors:"; hyprctl configerrors
hyprctl -j monitors all | jq -c '.[] | {name, mode: "\(.width)x\(.height)@\(.refreshRate)", scale, cm: .colorManagementPreset}'
