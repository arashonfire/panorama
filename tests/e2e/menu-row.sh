#!/usr/bin/env bash
# Checks `bin/panorama --add-menu-row` / `--remove-menu-row` end to end on
# throwaway files: the real launcher, Quickshell and lib/menu.js. Never touches
# the real Omarchy menu, and sends no notifications.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOME=$tmp/home
menu=$HOME/.config/omarchy/extensions/omarchy-menu.jsonc
template=${OMARCHY_PATH:-/usr/share/omarchy}/config/omarchy/extensions/omarchy-menu.jsonc
mkdir -p "$tmp/bin"
printf '#!/bin/sh\nexit 0\n' >"$tmp/bin/notify-send"
chmod +x "$tmp/bin/notify-send"
export PATH=$tmp/bin:$PATH
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

# Runs the launcher; sets $out and $rc.
panorama() { out=$("$root/bin/panorama" "$@" 2>&1); rc=$?; }
rows() { local n; n=$(grep -c '"setup.panorama":' "$menu" 2>/dev/null) || true; echo "${n:-0}"; }
fresh() { rm -rf "$HOME"; mkdir -p "$(dirname "$menu")"; }

if [[ ! -f $template ]]; then
  template=$tmp/template.jsonc
  printf '{\n  // Extend the Quickshell Omarchy menu with JSONC.\n}\n' >"$template"
fi

echo "1. add to Omarchy's template, then remove: the file comes back as it was"
fresh
cp "$template" "$menu"
panorama --add-menu-row
check "exit 0" "$rc" 0
check "says so" "$(grep -c 'added Setup > Display Settings' <<<"$out")" 1
check "one row" "$(rows)" 1
check "opens the plugin" "$(grep -c 'omarchy-shell shell summon com.arashlab.panorama' "$menu")" 1
panorama --add-menu-row
check "again: nothing to do, exit 0" "$rc" 0
check "  ... says it's there" "$(grep -c 'already has a setup.panorama row' <<<"$out")" 1
check "  ... still one row" "$(rows)" 1
panorama --remove-menu-row
check "remove: exit 0" "$rc" 0
check "  ... byte for byte the template" "$(cmp -s "$menu" "$template" && echo same || echo changed)" same
panorama --remove-menu-row
check "remove again: nothing to do, exit 0" "$rc" 0
check "  ... says there's none" "$(grep -c 'no Panorama row' <<<"$out")" 1

echo "2. a row of the user's own under the same id"
fresh
printf '{\n  "setup.panorama": {"label":"Display Settings","action":"panorama"}\n}\n' >"$menu"
cp "$menu" "$tmp/own"
panorama --add-menu-row
check "add leaves it" "$(cmp -s "$menu" "$tmp/own" && echo same || echo changed)" same
panorama --remove-menu-row
check "remove leaves it" "$(cmp -s "$menu" "$tmp/own" && echo same || echo changed)" same
check "  ... and says whose it is" "$(grep -c "so it's yours" <<<"$out")" 1

echo "3. a file the menu can't read"
fresh
printf '{\n  "a": {"label":"A"} // inline comments break the menu\n}\n' >"$menu"
cp "$menu" "$tmp/bad"
panorama --add-menu-row
check "add fails, exit 1" "$rc" 1
check "  ... untouched" "$(cmp -s "$menu" "$tmp/bad" && echo same || echo changed)" same
check "  ... says why" "$(grep -c "can't read" <<<"$out")" 1

echo "4. no menu file yet"
rm -rf "$HOME"
panorama --remove-menu-row
check "remove: nothing to do" "$rc" 0
check "  ... creates nothing" "$([[ -e $menu ]] && echo exists || echo none)" none
panorama --add-menu-row
check "add creates it with the row" "$rc/$(rows)" 0/1

echo
echo "$pass passed, $fail failed"
((fail == 0))
