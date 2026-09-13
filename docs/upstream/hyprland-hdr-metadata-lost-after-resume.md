# HDR output looks washed out after suspend/resume until `cm` is toggled

**Draft for hyprwm/Hyprland (possibly hyprwm/aquamarine) — not filed.
Related: hyprwm/Hyprland#9724 (hibernation, closed by aquamarine#163, which
restores HDR metadata after a VT switch only).**

## Environment

- Hyprland 0.56.2 (efb50993), aquamarine 0.15.0
- Lenovo Legion Pro 5 16IAX10H, Samsung ATNA60HS01-0 OLED (eDP-1), NVIDIA
- Rule: `cm = "hdredid", bitdepth = 10, supports_hdr = 1, supports_wide_color = 1`
- `debug:disable_logs = true` (Omarchy default), so only aquamarine's lines
  are in the log

## What happens

After a suspend/resume the panel shows every colour washed out and greyish,
as PQ-encoded frames look on a panel that is back in SDR mode. `hyprctl
monitors` still reports `colorManagementPreset: hdredid` and
`currentFormat: XBGR2101010`, so from Hyprland's point of view nothing
changed.

Switching the monitor's `cm` to `srgb` and back to `hdredid` (both at runtime,
via `hl.monitor` in `hyprctl eval`) brings the colours back.

## Why (from the source)

`IHyprRenderer::handleFullscreenSettings` re-sends HDR metadata only when
`pMonitor->inHDR() != wantHDR`, and `CMonitor::inHDR()` reads
`m_output->state->state().hdrMetadata` — aquamarine's cached copy of what was
last committed, not the hardware. The DPMS-on commit after resume carries
`hdrMetadata` only when `AQ_OUTPUT_STATE_HDR` is among the committed
properties (`CDRMOutput::commitState`), and a plain `setEnabled(true)` commit
doesn't set it. If the driver or the panel dropped the HDR_OUTPUT_METADATA
state over the suspend, the cache still says "eotf = PQ", nothing re-sends
it, and the panel stays in SDR while Hyprland keeps rendering PQ.

Toggling `cm` changes the image description, which flips `wantHDR` and forces
two `setHDRMetadata` calls, so the blob is committed again. Any other change
that touches the image description would do the same.

## Log around the wake (aquamarine only)

```
drm: Disabling output eDP-1
drm: Connector eDP-1 enabledState changed true -> false
drm: eDP-1 is disabled, releasing crtc 200
drm: backup slot 0 crtc 200 assigned to disabled eDP-1
...
drm: Modesetting eDP-1 with 2560x1600@165.00Hz
drm: Connector eDP-1 enabledState changed false -> true
drm: connector eDP-1 crtc supports HDR (8)
ERR: GBM: Failed to allocate a GBM buffer: format XR30 isn't supported by primary backend
ERR: Couldn't allocate a gbm buffer with size [Vector2D: x: 2560, y: 1600] and format XR30
ERR: Swapchain: Failed acquiring a buffer
drm: Modesetting eDP-1 with 2560x1600@165.00Hz
```

No "[CM] Updating HDR metadata from monitor" line can be checked because
Hyprland's own logging is off; enabling `debug:disable_logs = false` before
the next suspend would confirm whether the metadata is re-sent on wake.

## Suggested fix

Include the HDR metadata (and wide-colour-gamut state) in the enable commit
after a DPMS off/on, or mark the cached `hdrMetadata` as unknown when an output
is re-enabled so the next frame re-sends it. aquamarine#163 did the same for
the VT-switch path.

## Reproduce

1. Configure an HDR-capable panel with `cm = "hdredid"` (forced support if the
   EDID isn't parsed, see `hdr-displayid-cta-not-detected.md`).
2. Suspend, resume, unlock.
3. Colours are washed out; `hyprctl monitors` still says `hdredid`.
4. `hl.monitor({ output = "eDP-1", cm = "srgb", ... })` then back to
   `hdredid`: colours are correct again.
