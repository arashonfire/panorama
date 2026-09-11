# HDR and BT.2020 not detected on a panel that has them in a DisplayID extension

**Draft for hyprwm/Hyprland (EDID parsing via libdisplay-info) — not filed.
Check first whether this belongs to libdisplay-info.**

## Environment

- Hyprland 0.56.2 (efb50993), aquamarine, libdisplay-info as shipped on Arch
  (2026-09)
- Lenovo Legion Pro 5 16IAX10H, Samsung ATNA60HS01-0 OLED (eDP), NVIDIA GB205M,
  open driver 610.57.04
- `edid-decode` output: Panorama's `tests/fixtures/edid-edp.txt`

## What happens

With `cm = "hdr"` (or `"hdredid"`) and `supports_hdr`/`supports_wide_color`
left at auto (0), Hyprland falls back to sRGB: `colorManagementPreset` reads
`srgb`. With both forced to 1, HDR works (PQ, BT.2020 or EDID primaries,
10-bit, luminance overrides).

## Why

The panel advertises HDR only inside a **CTA-861 data block embedded in a
DisplayID extension** (blocks 1 and 2 of the EDID). The base EDID has no CTA
extension:

```
Block 1, DisplayID Extension Block:
  Display Interface Features Data Block:
    Supported color space and EOTF standard combination 1: DCI-P3, BT.2020/SMPTE ST 2084
  CTA-861 DisplayID Data Block:
  Colorimetry Data Block:
    BT2020RGB
  HDR Static Metadata Data Block:
    Electro optical transfer functions:
      Traditional gamma - SDR luminance range
      SMPTE ST2084
    Desired content max luminance: 143 (1107.128 cd/m^2)
    Desired content max frame-average luminance: 106 (496.743 cd/m^2)
    Desired content min luminance: 2 (0.001 cd/m^2)
```

`CMonitor::supportsHDR()` returns `false` unless `supportsWideColor()` is
true, and in auto mode those come from `parsedEDID.hdrMetadata->supportsPQ`
and `parsedEDID.supportsBT2020`, which stay unset for this EDID.

## Expected

HDR and BT.2020 detected from the CTA data block inside DisplayID, as
`edid-decode` does, so `cm = "hdr"` works without forcing.

## Workaround

```lua
hl.monitor({ output = "eDP-1", cm = "hdr", bitdepth = 10, supports_hdr = 1, supports_wide_color = 1 })
```

Note: forcing only `supports_hdr` isn't enough, because `supportsHDR()` also
requires wide color.
