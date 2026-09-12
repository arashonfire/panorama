# A powered-down output is parked on a CRTC that cannot drive it, and never wakes

**Draft for hyprwm/aquamarine — not filed.**

## Environment

- Hyprland 0.56.2 (efb50993), aquamarine as shipped with it
- Laptop, NVIDIA, `/dev/dri/card1`. Connectors: eDP-1 (1214, Samsung
  ATNA60HS01, 2560x1600@165), HDMI-A-1 (1211), DP-1 (1217).
- CRTCs 200, 489, 778, 1067. eDP-1 runs on **489**; **200** is HDMI-A-1's.

## What happens

Whenever an output is powered down — an idle DPMS off is enough — aquamarine
releases its CRTC and assigns the connector a "backup" CRTC. That backup is not
checked against the connector's `possible_crtcs`, so when the output is brought
back every atomic commit is rejected with `EINVAL` and the screen stays dark.

On a laptop with no external monitor attached, this means **the machine cannot
wake from idle**: there is no second display to show anything, and no way to ask
for one.

```
drm: Disabling output eDP-1
drm: Connector eDP-1 enabledState changed true -> false
drm: Scanning connectors for /dev/dri/card1
drm: Rechecking CRTCs
drm: eDP-1 is disabled, releasing crtc 489
drm: slot 0 crtc 200 unassigned
drm: slot 1 crtc 489 unassigned
drm: backup slot 0 crtc 200 assigned to disabled eDP-1
drm: Modesetting eDP-1 with 2560x1600@165.00Hz
ERR: atomic drm request: failed to commit: Invalid argument, flags: ATOMIC_ALLOW_MODESET
drm: Modesetting eDP-1 with 2560x1600@165.00Hz
ERR: atomic drm request: failed to commit: Invalid argument, flags: ATOMIC_ALLOW_MODESET
drm: Disabling output eDP-1
ERR: atomic drm request: failed to commit: Invalid argument, flags: ATOMIC_ALLOW_MODESET
```

The connector is connected throughout (`Connector 1214 connection state: 1`) and
the mode is the panel's own preferred one. Retries reuse the same assignment, so
they all fail the same way.

It recovers only on a real udev DRM hotplug, which rescans and happens to hand
the connector a usable CRTC:

```
drm: Got a hotplug event for /dev/dri/card1
...
drm: Skipping connector eDP-1, has crtc 489 and is connected
drm: Modesetting eDP-1 with 2560x1600@165.00Hz
drm: Connector eDP-1 enabledState changed false -> true
```

Note that a connector scan alone does **not** fix it: one runs immediately after
the disable, in the trace above, and still produces the bad assignment. Which
backup slot is picked looks incidental — in one instance the same sequence
produced `backup slot 1 crtc 489 assigned to disabled eDP-1`, which worked.

Every failing commit in this log is on crtc 200; every successful one on 489.

## Cause (suspected)

The backup-slot assignment made when an output is disabled does not intersect the
connector's `possible_crtcs`. eDP-1 (connector 1214) is given crtc 200, which
belongs to HDMI-A-1, so the kernel rejects the atomic request. Because the
assignment is sticky until the next rescan, and nothing retries with a different
CRTC, the output cannot be brought back.

## Reproducing

Simplest form, single display, nothing else involved:

1. Laptop with only its internal panel, more than one CRTC on the device.
2. Let it idle until DPMS powers the panel off.
3. Press a key. The panel does not come back; the log fills with
   `failed to commit: Invalid argument`.
4. Plug any monitor in and out again. The hotplug rescan frees it.

It also reproduces via an explicit disable (`hyprctl keyword monitor eDP-1,disable`
or a Lua rule with `disabled = true`) while an external monitor is attached, then
unplugging the external.

## Notes for recovery tooling

The stuck output still reports a mode, so a check of the form "an enabled monitor
with `width == 0`" does not match it — Omarchy's
`omarchy-hyprland-monitor-modeless` is such a check, and its `hyprctl reload`
backoff therefore never runs for this state. A reload would likely not help
anyway: the fix observed here is a connector *re-probe*, which needs a real
hotplug (or root, to write `detect` to the connector's sysfs `status`).
