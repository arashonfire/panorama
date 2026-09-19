#!/usr/bin/env bash
# Checks bin/panorama-hdr-pattern without a display: the PNGs it draws hold
# the exact PQ code values, and `show` asks Hyprland and mpv for the right
# things (both stubbed here, so nothing is shown and no rule is added).
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pattern=$root/bin/panorama-hdr-pattern
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

# 16-bit value of pixel (x, y), and the PQ code a luminance should have.
px() { magick "$1" -format "%[fx:round(65535*p{$2,$3}.r)]" info:; }
code() {
  awk -v y="$1" 'BEGIN {
    m1 = 2610 / 16384; m2 = 2523 / 4096 * 128; c1 = 3424 / 4096; c2 = 2413 / 4096 * 32; c3 = 2392 / 4096 * 32
    p = (y / 10000) ^ m1; printf "%d", 65535 * ((c1 + c2 * p) / (1 + c3 * p)) ^ m2 + 0.5 }'
}

# Tile i's left edge, as the helper lays them out.
W=1920 H=1080
left() { local n=$1 i=$2 side=$((W / 12)); echo $(( (W - n * side) / (n + 1) + i * (side + (W - n * side) / (n + 1)) )); }
mid_y=$((H / 2))

echo "1. peak: squares in frames at the clip level, plus the control"
"$pattern" draw peak $W $H 1107 "$tmp/peak.png" 200 800
check "16-bit PNG, monitor size" "$(magick identify -format '%wx%h %z' "$tmp/peak.png")" "${W}x${H} 16"
check "background black" "$(px "$tmp/peak.png" 3 3)" 0
check "200-nit square" "$(px "$tmp/peak.png" $(( $(left 3 0) + W / 24 )) $mid_y)" "$(code 200)"
check "its frame at 1107" "$(px "$tmp/peak.png" $(( $(left 3 0) + 2 )) $mid_y)" "$(code 1107)"
check "800-nit square" "$(px "$tmp/peak.png" $(( $(left 3 1) + W / 24 )) $mid_y)" "$(code 800)"
check "control square at 1107" "$(px "$tmp/peak.png" $(( $(left 3 2) + W / 24 )) $mid_y)" "$(code 1107)"

echo "2. full: squares on a whole screen at the clip level"
"$pattern" draw full $W $H 4000 "$tmp/full.png" 700
check "background at 4000" "$(px "$tmp/full.png" 3 3)" "$(code 4000)"
check "700-nit square" "$(px "$tmp/full.png" $(( $(left 2 0) + W / 24 )) $mid_y)" "$(code 700)"

echo "3. black: near-black squares, no control"
"$pattern" draw black $W $H 4000 "$tmp/black.png" 0.001 0.01
check "background black" "$(px "$tmp/black.png" 3 3)" 0
check "0.001-nit square" "$(px "$tmp/black.png" $(( $(left 2 0) + W / 24 )) $mid_y)" "$(code 0.001)"
check "0.01-nit square" "$(px "$tmp/black.png" $(( $(left 2 1) + W / 24 )) $mid_y)" "$(code 0.01)"

echo "4. bad arguments"
"$pattern" draw nope $W $H 1000 "$tmp/x.png" 1 2>/dev/null
check "unknown pattern refused" $? 2
"$pattern" show peak 2>/dev/null
check "short show refused" $? 2

echo "5. show: the tone-mapping rule, then mpv on that monitor"
mkdir -p "$tmp/bin"
cat >"$tmp/bin/hyprctl" <<STUB
#!/usr/bin/env bash
case \$1 in
  monitors) echo '[{"name":"HDMI-A-1","width":3840,"height":2160,"transform":0,"colorManagementPreset":"hdredid"},
                   {"name":"DP-2","width":1080,"height":1920,"transform":1,"colorManagementPreset":"hdr"},
                   {"name":"eDP-1","width":2560,"height":1600,"transform":0,"colorManagementPreset":"srgb"}]' ;;
  eval) echo "\$2" >>"$tmp/evals"; [[ -e "$tmp/reject" ]] && echo "error: unknown field 'tonemap'" || echo ok ;;
esac
STUB
cat >"$tmp/bin/mpv" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$@" >"$tmp/mpv-args"
magick identify -format '%wx%h' "\${@: -1}" >"$tmp/mpv-size"
STUB
chmod +x "$tmp/bin/"*
export PATH=$tmp/bin:$PATH
"$pattern" show peak HDMI-A-1 4000 600 800
check "exit" $? 0
check "rule for the pattern window only" "$(cat "$tmp/evals")" 'hl.window_rule({ match = { class = "^panorama-hdr-test$" }, tonemap = 0 })'
check "full screen on the monitor" "$(grep -c -e '^--fs$' -e '^--fs-screen-name=HDMI-A-1$' "$tmp/mpv-args")" 2
check "app id matches the rule" "$(grep -c '^--wayland-app-id=panorama-hdr-test$' "$tmp/mpv-args")" 1
check "clips at the limit" "$(grep -c -e '^--target-peak=4000$' -e '^--tone-mapping=clip$' "$tmp/mpv-args")" 2
check "stays up until closed" "$(grep -c '^--image-display-duration=inf$' "$tmp/mpv-args")" 1
check "drawn at the monitor's size" "$(cat "$tmp/mpv-size")" 3840x2160

"$pattern" show full DP-2 1000 500 >/dev/null
check "full closes itself" "$(grep -c '^--image-display-duration=30$' "$tmp/mpv-args")" 1
check "rotated monitor drawn upright" "$(cat "$tmp/mpv-size")" 1920x1080

msg=$("$pattern" show peak eDP-1 1000 500 2>&1)
check "refused when not in HDR" "$?:$msg" '1:panorama-hdr-pattern: eDP-1 is showing "srgb", not HDR'
touch "$tmp/reject"; rm -f "$tmp/mpv-args"
"$pattern" show peak HDMI-A-1 4000 600 2>/dev/null
check "refused when Hyprland rejects the rule" $? 3
check "mpv not started then" "$([[ -e $tmp/mpv-args ]] && echo started || echo no)" no

echo
echo "$pass passed, $fail failed"
((fail == 0))
