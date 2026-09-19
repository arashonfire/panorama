# HDR clients that don't set `luminances` are tone-mapped from 10000 nits

**Draft for hyprwm/Hyprland — not filed.**

## Environment

- Hyprland 0.56.2 (efb50993), Lua config
- Lenovo Legion Pro 5 16IAX10H, eDP-1 (Samsung ATNA60HS01 OLED, 2560×1600,
  EDID desired content max 1107 nits), `cm = hdr`, no `max_luminance` override
- mpv 0.41.0, `--vo=gpu-next`, Vulkan on the NVIDIA GB205M (open driver
  610.57.04), HDR10 swapchain (`VK_COLOR_SPACE_HDR10_ST2084_EXT`)

## What happens

A client shows PQ content already limited to the monitor's peak, and says so
with mastering luminance and MaxCLL. Hyprland still tone-maps it as if it
reached 10000 nits, which compresses everything toward the panel's peak.

mpv, asked to hard-clip at the preferred description's peak, sends
(`WAYLAND_DEBUG=1`):

```
wp_image_description_creator_params_v1.set_primaries_named(6)       # bt2020
wp_image_description_creator_params_v1.set_tf_named(11)             # st2084_pq
wp_image_description_creator_params_v1.set_max_cll(1107)
wp_image_description_creator_params_v1.set_max_fall(0)
wp_image_description_creator_params_v1.set_mastering_display_primaries(...)
wp_image_description_creator_params_v1.set_mastering_luminance(0, 1107)
wp_image_description_v1.ready(20)
```

and no `set_luminances`. The compositor's preferred description for the
surface was `target_luminance(10, 1107)`, `target_max_cll(1107)`.

A clipping pattern (squares at 200…1107 nits inside a 10000-nit surround)
then shows every square, barely darker at 200 than at 1100, and the 1100
square distinct from a surround one 10-bit step above it. With the window
rule `tonemap = 0` on the mpv window, the same pattern behaves as the signal
says: 200 is clearly mid-gray, 1000 is barely visible, 1100 is gone.

## Repro

```sh
# spikes/hdr-patterns.sh in Panorama draws the pattern and runs mpv like this:
mpv --fs --image-display-duration=inf --vo=gpu-next --target-colorspace-hint=yes \
  --vf=format=gamma=pq:primaries=bt.2020 --target-trc=pq --target-prim=bt.2020 \
  --target-peak=1107 --tone-mapping=clip --hdr-compute-peak=no pattern.png
# squeezed. Then, before starting mpv again:
hyprctl eval 'hl.window_rule({ match = { class = "^mpv$" }, tonemap = 0 })'
# correct.
```

## Cause

`getCMSettings()` (`src/render/Renderer.cpp`) takes the source peak from
`luminances` only:

```cpp
const float maxLuminance = needsHDRmod ?
    imageDescription->value().getTFMaxLuminance(-1) :
    (imageDescription->value().luminances.max > 0 ?
     imageDescription->value().luminances.max :
     imageDescription->value().luminances.reference);
const auto dstMaxLuminance = targetImageDescription->value().luminances.max > 0 ?
    targetImageDescription->value().luminances.max : 10000;
const bool needsTonemap = maxLuminance >= dstMaxLuminance * 1.01;
```

Without `set_luminances`, the protocol's defaults for PQ apply: max 10000.
So `needsTonemap` is true (10000 ≥ 1107 × 1.01), and the mastering
luminance and MaxCLL the client did send are never consulted.

## Suggested fix

When the client gives target color volume metadata, use it to bound the
source peak, as the protocol intends for `set_mastering_luminance` /
`set_max_cll` (a sketch: the field names are unchecked):

```cpp
float srcPeak = /* as today */;
const auto& d = imageDescription->value();
if (d.maxCLL > 0)
    srcPeak = std::min(srcPeak, (float)d.maxCLL);
else if (d.masteringLuminances.max > 0)
    srcPeak = std::min(srcPeak, (float)d.masteringLuminances.max);
```

Content mastered for (or clipped to) the monitor's peak then passes through
untouched, and genuinely brighter content is still tone-mapped.
