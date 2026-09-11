# Monitor rules that only change `vrr` are ignored

**Draft for hyprwm/Hyprland — not filed.**

## Environment

- Hyprland 0.56.2 (efb50993), Lua config
- Lenovo Legion Pro 5 16IAX10H, eDP-1 (Samsung ATNA60HS01 OLED, 2560×1600@165,
  `vrr_capable` = 1) on NVIDIA GB205M, open driver 610.57.04

## What happens

A monitor rule that differs from the active one **only in `vrr`** has no
effect, neither at runtime (`hyprctl eval 'hl.monitor({...})'`) nor after
`hyprctl reload` with the change in the config file. Changing any other field
along with it (e.g. `sdrsaturation`) makes the new `vrr` value apply.

## Repro

```sh
B='output = "eDP-1", mode = "2560x1600@165", position = "0x0", scale = 1.6'
hyprctl eval "hl.monitor({ $B, vrr = 0 })"   # establish the rule
hyprctl eval "hl.monitor({ $B, vrr = 1 })"   # vrr-only change
hyprctl -j monitors | jq '.[] | select(.name == "eDP-1") | .vrr'   # false
hyprctl eval "hl.monitor({ $B, vrr = 1, sdrsaturation = 1.0001 })"  # plus a soft change
hyprctl -j monitors | jq '.[] | select(.name == "eDP-1") | .vrr'   # true
```

(Full script with a watchdog: `spikes/vrr.sh` in Panorama.)

## Cause

`CMonitorRule::compare()` (`src/config/shared/monitor/MonitorRule.cpp`) never
looks at `m_vrr`, so a vrr-only difference is `COMPARISON_FULL_MATCH`.
`CMonitorRuleManager::ensureMonitorStatus()` then skips the monitor, its
`m_activeMonitorRule` keeps the old `vrr`, and `ensureVRR()` keeps using it.

## Suggested fix

Treat `vrr` as a soft property in `compare()`:

```cpp
const auto SAME_VRR = m_vrr == other.m_vrr;
if (!SAME_CM || !SAME_POS || !SAME_TRANSFORM || !SAME_AUTO_DIR || !SAME_RESERVED || !SAME_MIRROR || !SAME_VRR)
    return COMPARISON_SOFT_MISMATCH;
```

`applyMonitorRuleSoft()` replaces the active rule, and the refresh that
follows calls `ensureVRR()` with the new value.
