# `vrr` reports true after the driver refused adaptive sync

**Draft for hyprwm/Hyprland — not filed.**

## Environment

- Hyprland 0.56.2 (efb50993)

## What happens

`hyprctl monitors` shows `"vrr": true` for a monitor even when the output did
not accept adaptive sync. The only trace is a debug log line:
`Pending output <name> does not accept VRR.`

## Cause

In `CMonitorRuleManager::ensureVRR()` (`src/config/shared/monitor/MonitorRuleManager.cpp`),
for `vrr = 1`:

```cpp
m->m_output->state->setAdaptiveSync(true);
if (!m->m_state.test()) {
    Log::logger->log(Log::DEBUG, "Pending output {} does not accept VRR.", m->m_output->name);
    m->m_output->state->setAdaptiveSync(false);
}
if (!m->m_state.commit()) ...
m->m_vrrActive = true;   // set regardless of the test result
```

`m_vrrActive` becomes `true` even when the test failed and adaptive sync was
turned back off. It's also skipped entirely on later calls because of the
`if (!m->m_vrrActive)` guard, so a later successful attempt never happens.

## Suggested fix

Set `m_vrrActive` from the outcome, e.g.
`m->m_vrrActive = m->m_output->state->state().adaptiveSync;` after the commit,
in both the `vrr = 1` and fullscreen branches.
