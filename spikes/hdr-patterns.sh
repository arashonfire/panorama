#!/usr/bin/env bash
# Spike: exact-nit HDR test patterns, for a manual HDR calibration.
#
# Shows one of three patterns full screen through mpv, each a row of tiles
# labelled in nits. You read off where the panel stops telling tiles apart:
#
#   peak   A square at N nits inside a 10000-nit frame, tiles covering ~9% of
#          the screen (the 10% window peaks are quoted for). The panel clips
#          everything above its peak alike, so the first square that vanishes
#          into its frame ≈ `max_luminance`.
#   black  Near-black squares on black. The first square you can see ≈
#          `min_luminance`. View it in a dark room, after a minute or so.
#   full   The same clipping test with the whole screen at 10000 nits ≈
#          `max_avg_luminance`. Closes by itself after 30 s. If it gives the
#          same answer as `peak`, the panel dims a bright full screen as a whole
#          (ABL) rather than clipping, which an eye test can't measure; keep
#          the EDID value then.
#
# mpv writes PQ / BT.2020 with a hard clip at PEAK (default: the EDID's
# desired content max, which Hyprland uses without a max_luminance override)
# and no black-point lift. In `peak` and `full` the last tile sits at PEAK
# and always vanishes: that's the control.
#
# Hyprland (0.56.2, getCMSettings) doesn't take the content's peak from the
# mastering luminance or MaxCLL mpv sends, only from `luminances`, which mpv
# leaves unset, so for PQ it's 10000 nits and Hyprland tone-maps 0–10000
# into the panel's range, squeezing every tile together. A window rule,
# `tonemap = 0`, for mpv's app id alone turns that off. It lasts until the
# next config reload; nothing else is changed. TONEMAP=1 keeps Hyprland's
# tone mapping, to compare. Unchecked: whether Hyprland's PQ-to-PQ conversion
# maps the protocol's default PQ black (0.005 nits) to the panel's, which
# could shift `black` by a few thousandths of a nit.
#
# Run it yourself, with the monitor in HDR (cm = hdr / hdredid). q quits.
#   spikes/hdr-patterns.sh [peak|black|full] [MONITOR]   # default: peak, focused monitor
#   NITS="300 500 700" PEAK=1000 spikes/hdr-patterns.sh peak eDP-1
set -euo pipefail

MODE=${1:-peak}
case $MODE in peak | black | full) ;; *) echo "usage: $0 [peak|black|full] [MONITOR]" >&2; exit 2 ;; esac
MON=${2:-$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')}
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
case $MODE in
  peak) NITS=${NITS:-"200 400 600 800 900 1000 1100"} ;;
  black) NITS=${NITS:-"0.001 0.002 0.005 0.01 0.02 0.05 0.1 0.2"} ;;
  full) NITS=${NITS:-"200 300 400 500 600 800 1000"} ;;
esac

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
img="$dir/$MODE.png"

# Draw the tiles with ImageMagick at 16 bits, as PQ code values (SMPTE ST 2084).
font=$(fc-match -f '%{file}' sans-serif)
python3 - "$MODE" "$W" "$H" "$PEAK" "$img" "$font" $NITS <<'PY' >"$dir/draw.sh"
import sys, shlex
mode, W, H, peak, out, font = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), sys.argv[5], sys.argv[6]
values = [float(n) for n in sys.argv[7:]]

def pq(y):  # nits → PQ signal, 0..1
    m1, m2 = 2610 / 16384, 2523 / 4096 * 128
    c1, c2, c3 = 3424 / 4096, 2413 / 4096 * 32, 2392 / 4096 * 32
    p = (y / 10000) ** m1
    return ((c1 + c2 * p) / (1 + c3 * p)) ** m2

def gray(y):
    return "gray(%.4f%%)" % (100 * pq(y))

def fmt(y):
    return "%g" % y

if mode == "black":
    nits = sorted({y for y in values if y > 0})
    background, label = gray(0), gray(10)   # dim labels keep the eye dark-adapted
    title = "Which squares can you see? The first visible one is about the panel's black level (nits). q quits."
else:
    # Clipping tests: tiles below PEAK, plus PEAK itself as the control.
    nits = sorted({y for y in values if 0 < y < peak} | {float(peak)})
    background = gray(0) if mode == "peak" else gray(10000)
    label = gray(100)
    title = "Which squares can you still see? The first one that vanishes is about the panel's %s (nits). %s" % (
        ("peak", "q quits.") if mode == "peak" else ("full-screen peak", "Closes in 30 s; q quits."))

n = len(nits)
side = W // 12                      # tile edge
gap = (W - n * side) // (n + 1)
top = (H - side) // 2
q = side // 4                       # frame width in `peak`
args = ["magick", "-size", "%dx%d" % (W, H), "xc:" + background, "-depth", "16", "-font", font]
for i, y in enumerate(nits):
    x = gap + i * (side + gap)
    if mode == "peak":
        args += ["-fill", gray(10000), "-draw", "rectangle %d,%d %d,%d" % (x, top, x + side - 1, top + side - 1)]
        args += ["-fill", gray(y), "-draw", "rectangle %d,%d %d,%d" % (x + q, top + q, x + side - q - 1, top + side - q - 1)]
    else:
        args += ["-fill", gray(y), "-draw", "rectangle %d,%d %d,%d" % (x, top, x + side - 1, top + side - 1)]
    text = fmt(y) + (" (control)" if mode != "black" and y == peak else "")
    args += ["-fill", label, "-pointsize", str(side // 7), "-gravity", "NorthWest",
             "-annotate", "+%d+%d" % (x, top + side + side // 8), text]
args += ["-fill", label, "-pointsize", str(side // 7), "-gravity", "North", "-annotate", "+0+%d" % (H // 8), title]
args += ["-strip", "PNG48:" + out]
print(" ".join(shlex.quote(a) for a in args))
PY
bash "$dir/draw.sh"

echo "$MON: ${W}x${H}, $cm, $MODE pattern, clipping at PEAK=$PEAK nits; tiles: $NITS"
# LOG=file keeps mpv's log (which GPU, swapchain format, target colorspace);
# MPV_ARGS adds options, e.g. "--gpu-context=wayland" to skip Vulkan.
extra=()
[ -n "${LOG:-}" ] && extra+=(--log-file="$LOG")
read -r -a more <<<"${MPV_ARGS:-}" && extra+=("${more[@]}")
# A full screen at peak for long is hard on an OLED; let that one close itself.
duration=inf
[ "$MODE" = full ] && duration=30
hyprctl eval "hl.window_rule({ match = { class = \"^panorama-hdr-test\$\" }, tonemap = ${TONEMAP:-0} })" >/dev/null
mpv --no-config --really-quiet --osd-level=0 "${extra[@]}" --wayland-app-id=panorama-hdr-test \
  --fs --fs-screen-name="$MON" --image-display-duration="$duration" \
  --vo=gpu-next --target-colorspace-hint=yes \
  --vf=format=gamma=pq:primaries=bt.2020 \
  --target-trc=pq --target-prim=bt.2020 --target-peak="$PEAK" --target-contrast=inf \
  --tone-mapping=clip --gamut-mapping-mode=clip --hdr-compute-peak=no \
  "$img"
