#!/usr/bin/env bash
# Checks bin/panorama-omarchy-internal on a throwaway toggles directory: the
# flag Omarchy's clamshell watcher reads, the exact bytes it expects, refusals,
# and the no-op off Omarchy. Never touches the real toggles directory.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export PANORAMA_TOGGLES_DIR=$tmp/toggles/hypr
helper=$root/bin/panorama-omarchy-internal
flag=$PANORAMA_TOGGLES_DIR/internal-monitor-disable.lua
pass=0
fail=0

check() {
  if [[ $2 == "$3" ]]; then
    echo "  ✔ $1"
    ((pass++))
  else
    echo "  ✖ $1: got '$2', want '$3'"
    ((fail++))
  fi
}

echo "1. a panel Omarchy still owns reads as on"
check "state" "$("$helper" state)" on
check "no flag file" "$([[ -e $flag ]] && echo yes || echo no)" no

echo "2. turning it off writes the flag Omarchy reads"
"$helper" off eDP-1
check "state" "$("$helper" state)" off
# omarchy-hyprland-monitor-internal compares the file against this exact string,
# so a difference would make it rewrite the flag and reload Hyprland.
check "byte-for-byte what Omarchy writes" "$(cat "$flag")" 'hl.monitor({ output = "eDP-1", disabled = true })'
check "directory created" "$([[ -d $PANORAMA_TOGGLES_DIR ]] && echo yes || echo no)" yes

echo "3. setting it twice is stable"
"$helper" off eDP-1
check "state" "$("$helper" state)" off
check "content unchanged" "$(cat "$flag")" 'hl.monitor({ output = "eDP-1", disabled = true })'

echo "4. handing the panel back removes the flag"
"$helper" on
check "state" "$("$helper" state)" on
check "flag gone" "$([[ -e $flag ]] && echo yes || echo no)" no
"$helper" on
check "removing twice is fine" "$?" 0

echo "5. the name goes into Lua, so only a connector may pass"
out=$("$helper" off 'eDP-1" }) os.execute("rm -rf /' 2>&1)
check "refused" "$?" 1
check "says why" "${out##*: }" 'eDP-1" }) os.execute("rm -rf /'
check "nothing written" "$([[ -e $flag ]] && echo yes || echo no)" no
"$helper" off >/dev/null 2>&1
check "a missing name is refused" "$?" 1

echo "6. off Omarchy there is no watcher to appease"
check "state" "$(env -u PANORAMA_TOGGLES_DIR -u XDG_STATE_HOME HOME=$tmp/elsewhere "$helper" state)" absent
env -u PANORAMA_TOGGLES_DIR -u XDG_STATE_HOME HOME="$tmp/elsewhere" "$helper" off eDP-1
check "off is a no-op that succeeds" "$?" 0
check "no state directory created" "$([[ -e $tmp/elsewhere ]] && echo yes || echo no)" no

echo
echo "$pass passed, $fail failed"
((fail == 0))
