#!/usr/bin/env bash
# Spike: can we show exact-nit HDR test patterns, for a manual HDR calibration?
#
# Shows a peak-luminance clipping pattern full screen through mpv: a row of
# tiles, each a square at N nits inside a 10000-nit surround. The panel clips
# everything above its real peak to the same brightness, so a tile whose
# square has vanished is at or above the peak. The first vanished tile ≈ the
# value for `max_luminance`. Tiles cover ~9% of the screen together, the 10%
# window HDR peaks are quoted for.
#
# mpv writes PQ / BT.2020 with a hard clip at PEAK (default: the EDID's
# desired content max, which Hyprland uses without a max_luminance override).
# The last tile sits at PEAK and always vanishes: that's the control.
#
# Hyprland (0.56.2, getCMSettings) doesn't take the content's peak from the
# mastering luminance or MaxCLL mpv sends, only from `luminances`, which mpv
# leaves unset, so for PQ it's 10000 nits and Hyprland tone-maps 0–10000
# into the panel's range, squeezing every tile together. A window rule,
# `tonemap = 0`, for mpv's app id alone turns that off. It lasts until the
# next config reload; nothing else is changed. TONEMAP=1 keeps Hyprland's
# tone mapping, to compare.
#
# Run it yourself, with the monitor in HDR (cm = hdr / hdredid). q quits.
#   spikes/hdr-peak.sh [MONITOR]              # default: the focused monitor
#   NITS="300 500 700" PEAK=1000 spikes/hdr-peak.sh eDP-1
set -euo pipefail

MON=${1:-$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')}
info=$(hyprctl monitors -j | jq -c --arg n "$MON" '.[] | select(.name == $n)')
[ -n "$info" ] || { echo "no monitor $MON" >&2; exit 1; }
cm=$(jq -r .colorManagementPreset <<<"$info")
case $cm in hdr | hdredid) ;; *) echo "$MON is in \"$cm\", not HDR; switch it to HDR first." >&2; exit 1 ;; esac
W=$(jq -r .width <<<"$info")
H=$(jq -r .height <<<"$info")

if [ -z "${PEAK:-}" ]; then
  edid=$(ls /sys/class/drm/card*-"$MON"/edid 2>/dev/null | head -1 || true)
  PEAK=$( { [ -n "$edid" ] && edid-decode "$edid" 2>/dev/null; } |
    sed -n 's/.*Desired content max luminance: [0-9]* (\([0-9.]*\) cd\/m^2).*/\1/p' | head -1)
  PEAK=${PEAK:-1000}
fi
PEAK=$(printf '%.0f' "$PEAK")
NITS=${NITS:-"200 400 600 800 900 1000 1100"}

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
img="$dir/peak.png"

# Tile values below PEAK, plus PEAK itself; draw them with ImageMagick at
# 16 bits, as PQ code values (SMPTE ST 2084).
font=$(fc-match -f '%{file}' sans-serif)
python3 - "$W" "$H" "$PEAK" "$img" "$font" $NITS <<'PY' >"$dir/draw.sh"
import sys, shlex
W, H, peak, out, font = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5]
nits = sorted({float(n) for n in sys.argv[6:] if 0 < float(n) < peak} | {float(peak)})

def pq(y):  # nits → PQ signal, 0..1
    m1, m2 = 2610 / 16384, 2523 / 4096 * 128
    c1, c2, c3 = 3424 / 4096, 2413 / 4096 * 32, 2392 / 4096 * 32
    p = (y / 10000) ** m1
    return ((c1 + c2 * p) / (1 + c3 * p)) ** m2

def gray(y):
    return "gray(%.4f%%)" % (100 * pq(y))

n = len(nits)
side = W // 12                      # tile edge
gap = (W - n * side) // (n + 1)
top = (H - side) // 2
label = gray(100)                   # labels at 100 nits, clearly SDR
args = ["magick", "-size", "%dx%d" % (W, H), "xc:black", "-depth", "16", "-font", font]
for i, y in enumerate(nits):
    x = gap + i * (side + gap)
    q = side // 4
    args += ["-fill", gray(10000), "-draw", "rectangle %d,%d %d,%d" % (x, top, x + side - 1, top + side - 1)]
    args += ["-fill", gray(y), "-draw", "rectangle %d,%d %d,%d" % (x + q, top + q, x + side - q - 1, top + side - q - 1)]
    text = "%d" % y + (" (control)" if y == peak else "")
    args += ["-fill", label, "-pointsize", str(side // 7), "-gravity", "NorthWest",
             "-annotate", "+%d+%d" % (x, top + side + side // 8), text]
args += ["-fill", label, "-pointsize", str(side // 7), "-gravity", "North", "-annotate", "+0+%d" % (H // 8),
         "Which squares can you still see? The first one that vanishes is about the panel's peak (nits). q quits."]
args += ["-strip", "PNG48:" + out]
print(" ".join(shlex.quote(a) for a in args))
PY
bash "$dir/draw.sh"

echo "$MON: ${W}x${H}, $cm, clipping at PEAK=$PEAK nits; tiles: $NITS"
# LOG=file keeps mpv's log (which GPU, swapchain format, target colorspace);
# MPV_ARGS adds options, e.g. "--gpu-context=wayland" to skip Vulkan.
extra=()
[ -n "${LOG:-}" ] && extra+=(--log-file="$LOG")
read -r -a more <<<"${MPV_ARGS:-}" && extra+=("${more[@]}")
hyprctl eval "hl.window_rule({ match = { class = \"^panorama-hdr-test\$\" }, tonemap = ${TONEMAP:-0} })" >/dev/null
mpv --no-config --really-quiet --osd-level=0 "${extra[@]}" --wayland-app-id=panorama-hdr-test \
  --fs --fs-screen-name="$MON" --image-display-duration=inf \
  --vo=gpu-next --target-colorspace-hint=yes \
  --vf=format=gamma=pq:primaries=bt.2020 \
  --target-trc=pq --target-prim=bt.2020 --target-peak="$PEAK" \
  --tone-mapping=clip --gamut-mapping-mode=clip --hdr-compute-peak=no \
  "$img"
