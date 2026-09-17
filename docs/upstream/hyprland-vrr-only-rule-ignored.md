# Monitor rules that only change `vrr` are ignored

**Draft for hyprwm/Hyprland — not filed.** Also reported, with more data, in
[arashonfire/panorama#1](https://github.com/arashonfire/panorama/issues/1).

## Environment

- Hyprland 0.56.2 (efb50993), Lua config
- Lenovo Legion Pro 5 16IAX10H, eDP-1 (Samsung ATNA60HS01 OLED, 2560×1600@165,
  `vrr_capable` = 1) on NVIDIA GB205M, open driver 610.57.04
- Also seen on an RTX 4080 with an Alienware AW3225QF over DisplayPort
  (3840×2160@240, `vrr_capable` = 1), CachyOS (panorama#1)

## What happens

A monitor rule that differs from the active one **only in `vrr`** has no
effect, neither at runtime (`hyprctl eval 'hl.monitor({...})'`) nor after
`hyprctl reload` with the change in the config file.

Changing a soft property in the same rule (e.g. `sdrsaturation`) is not a
reliable workaround:

- On the laptop above, it applies the new `vrr` immediately.
- On the desktop above, the applied `vrr` lags one rule behind: each
  `hl.monitor()` call takes effect with the `vrr` of the rule sent before it.

Sending the rule twice works on both machines. The first call has a soft
change; the second has the real values.

## Repro

```sh
B='output = "eDP-1", mode = "2560x1600@165", position = "0x0", scale = 1.6'
vrr() { hyprctl -j monitors | jq '.[] | select(.name == "eDP-1") | .vrr'; }
hyprctl eval "hl.monitor({ $B, vrr = 0 })"; sleep 2      # establish the rule
hyprctl eval "hl.monitor({ $B, vrr = 1 })"; sleep 2      # vrr-only change
vrr                                                      # false: ignored
hyprctl eval "hl.monitor({ $B, vrr = 1, sdrsaturation = 1.0001 })"; sleep 1
hyprctl eval "hl.monitor({ $B, vrr = 1 })"; sleep 2      # real values
vrr                                                      # true
```

(Full scripts with a watchdog: `spikes/vrr.sh` in Panorama. The one-rule lag
on the desktop is the command sequence in panorama#1.)

## Cause

Two things combine:

1. `CMonitorRule::compare()` (`src/config/shared/monitor/MonitorRule.cpp`)
   never looks at `m_vrr`, so a vrr-only difference is
   `COMPARISON_FULL_MATCH`. `CMonitorRuleManager::ensureMonitorStatus()` then
   skips the monitor, its `m_activeMonitorRule` keeps the old `vrr`, and
   `ensureVRR()` keeps using it.
2. Nothing orders `ensureVRR()` after the new rule becomes active.
   `hl.monitor()` (`LuaBindingsConfigRules.cpp`) adds the rule and calls
   `scheduleRefresh(REFRESH_MONITOR_STATES)`. The refresher runs from an idle
   callback and calls `scheduleReload()` and then `ensureVRR()` right away
   (`PropRefresher.cpp`). But the rule is only applied by
   `ensureMonitorStatus()` on the next `render.preChecks` event
   (`MonitorRuleManager.cpp`), and `applyMonitorRuleSoft()` doesn't call
   `ensureVRR()`. When the idle callback runs before the next frame,
   `ensureVRR()` reads the previous rule. Nothing checks VRR again until a
   later refresh or a workspace change (`CMonitor::changeWorkspace()`). This
   matches the lag on the desktop. We have not found why the laptop applies
   the new value immediately.

## Suggested fix

Treat `vrr` as a soft property in `compare()`:

```cpp
const auto SAME_VRR = m_vrr == other.m_vrr;
if (!SAME_CM || !SAME_POS || !SAME_TRANSFORM || !SAME_AUTO_DIR || !SAME_RESERVED || !SAME_MIRROR || !SAME_VRR)
    return COMPARISON_SOFT_MISMATCH;
```

Then re-check VRR once the new rules are active. For example, at the end of
`ensureMonitorStatus()`:

```cpp
for (const auto& m : monsForRefresh) {
    if (m->m_output)
        ensureVRR(m);
}
```

This makes the result independent of the order of the idle callback and
the frame.
