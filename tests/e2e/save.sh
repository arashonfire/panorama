#!/usr/bin/env bash
# End-to-end check of saving: runs a separate Panorama instance against a
# scratch copy of monitors.lua (PANORAMA_MONITORS_FILE) and a scratch backup
# dir, saves, checks the file and the live state, then undoes. Hyprland reloads
# its real config along the way, which is harmless as long as no applied
# change is waiting to be saved. Quits a running Panorama first and leaves it
# stopped. Set SHOTS=<dir> to also screenshot the save dialog.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
# Start from Omarchy's stock monitors.lua, not the real one, so the test
# doesn't depend on whether you've saved with Panorama already.
real=$root/tests/fixtures/omarchy-monitors.lua
tmp=$(mktemp -d)
export PANORAMA_MONITORS_FILE=$tmp/monitors.lua
export PANORAMA_BACKUP_DIR=$tmp/backups
file=$PANORAMA_MONITORS_FILE
pass=0
fail=0

ipc() { qs -p "$root" ipc call panorama "$@"; }
persist() { ipc state | jq -r ".persist.$1"; }
live() { hyprctl -j monitors all | jq -c '[.[] | {name, x, y, width, height, scale, transform, disabled}]'; }

check() {
  if [[ $2 == "$3" ]]; then
    echo "  ✔ $1"
    ((pass++))
  else
    echo "  ✖ $1: got '$2', want '$3'"
    ((fail++))
  fi
}

wait_idle() {
  sleep 0.3
  for _ in $(seq 1 60); do
    [[ $(persist state) == idle ]] && return 0
    sleep 0.25
  done
  return 1
}

cp -- "$real" "$file"
cp -- "$real" "$tmp/original"

"$root/bin/panorama" --quit
sleep 1
qs -n -p "$root" >"$tmp/log" 2>&1 &
pid=$!
trap 'kill $pid 2>/dev/null; rm -rf "$tmp"' EXIT
for _ in $(seq 1 40); do
  ipc state >/dev/null 2>&1 && break
  sleep 0.25
done

echo "1. before saving"
check "uses the scratch file" "$(persist path)" "$file"
check "no Panorama section yet" "$(persist hasSection)" false
check "not saved" "$(persist saved)" false

if [[ -n ${SHOTS:-} ]]; then
  ipc openSave
  sleep 0.8
  grim -o "$(hyprctl -j monitors | jq -r '.[] | select(.focused) | .name')" "$SHOTS/save-dialog.png"
  ipc closeSave
fi

echo "2. save"
before=$(live)
ipc save
wait_idle
check "one Panorama section" "$(grep -c '^-- >>> panorama' "$file")" 1
check "one rule per monitor" "$(sed -n '/^-- >>> panorama/,/^-- <<< panorama/p' "$file" | grep -c '^hl\.monitor')" \
  "$(hyprctl -j monitors all | jq length)"
check "rest of the file untouched" "$(head -n "$(wc -l <"$tmp/original")" "$file")" "$(cat "$tmp/original")"
check "Lua parses" "$(luac -p "$file" 2>&1 && echo ok)" ok
check "reported saved" "$(persist saved)" true
check "success message" "$(persist message | cut -c1-9)" "Saved to "
check "no error" "$(persist messageIsError)" false
check "backup holds the original" "$(cat "$(persist lastBackup)")" "$(cat "$tmp/original")"
check "live layout unchanged by the reload" "$(live)" "$before"
cp -- "$file" "$tmp/saved"

echo "3. undo"
ipc undoSave
wait_idle
check "file back to the original" "$(cat "$file")" "$(cat "$tmp/original")"
check "restore message" "$(persist message | cut -c1-9)" "Restored "
check "not saved any more" "$(persist saved)" false

echo "4. the app log is clean"
check "no QML warnings" "$(grep -E 'WARN|ERROR' "$tmp/log" | grep -cvE 'host portal|not previously tracked')" 0
grep -E 'WARN|ERROR' "$tmp/log" | grep -vE 'host portal|not previously tracked' | head -5

echo
echo "saved section was:"
sed -n '/^-- >>> panorama/,/^-- <<< panorama/p' "$tmp/saved"
echo
echo "$pass passed, $fail failed"
((fail == 0))
