#!/usr/bin/env bash
# Repro + workaround: Hyprland 0.56.2 ignores monitor rules that change only `vrr`.
#
# CMonitorRule::compare() (src/config/shared/monitor/MonitorRule.cpp) never
# compares m_vrr, so such a rule is a FULL_MATCH. ensureMonitorStatus() skips it,
# the monitor keeps its old m_activeMonitorRule, and ensureVRR() uses the old value.
#
# Workaround: send the rule once with a harmless soft-property nudge (a soft
# mismatch → applyMonitorRuleSoft replaces the active rule), then the real values.
#
# Safety: a detached watchdog reloads the config after 40 s no matter what.
set -u
OUT=${OUT:-eDP-1}
B=${B:-"output = \"$OUT\", mode = \"2560x1600@165\", position = \"0x0\", scale = 1.6"}

pidfile=$(mktemp)
setsid bash -c 'echo $$ >"$1"; sleep 40; hyprctl reload >/dev/null' _ "$pidfile" >/dev/null 2>&1 &
disarm() { kill "$(cat "$pidfile")" 2>/dev/null && echo "watchdog disarmed"; rm -f "$pidfile"; }
trap disarm EXIT

log="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.log"
start=$(wc -l <"$log")

s() {
  printf '   monitor.vrr=%s  misc:vrr=%s\n' \
    "$(hyprctl -j monitors | jq -r --arg n "$OUT" '.[] | select(.name == $n) | .vrr')" \
    "$(hyprctl getoption misc:vrr -j | jq -r .int)"
}
rule() { hyprctl eval "hl.monitor({ $B, $1 })" >/dev/null; }

echo "0: establish rule, vrr=0";                rule "vrr = 0"; sleep 2; s
echo "1: vrr-only change to 1 (ignored: bug)";  rule "vrr = 1"; sleep 2; s
echo "2: vrr=1 with soft nudge, then real";     rule "vrr = 1, sdrsaturation = 1.0001"; sleep 1; rule "vrr = 1, sdrsaturation = 1.0"; sleep 2; s
echo "3: vrr-only change to 0 (ignored: bug)";  rule "vrr = 0"; sleep 2; s
echo "4: vrr=0 with soft nudge, then real";     rule "vrr = 0, sdrsaturation = 1.0001"; sleep 1; rule "vrr = 0, sdrsaturation = 1.0"; sleep 2; s

echo "--- VRR log lines during this run"
tail -n +"$start" "$log" | grep -iE 'vrr|adaptive' || echo "   (none)"

hyprctl reload >/dev/null; sleep 2
echo "after reload:"; s
