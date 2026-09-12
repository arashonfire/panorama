#!/usr/bin/env bash
# Checks bin/panorama-persist on throwaway files: backups, atomic writes,
# symlinks, refusals and restores. Never touches the real monitors.lua.
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export PANORAMA_MONITORS_FILE=$tmp/hypr/monitors.lua
export PANORAMA_BACKUP_DIR=$tmp/backups
export PANORAMA_KEEP_BACKUPS=4
persist=$root/bin/panorama-persist
file=$PANORAMA_MONITORS_FILE
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

count_backups() { find "$PANORAMA_BACKUP_DIR" -maxdepth 1 -type f ! -name '*.before-restore' | wc -l; }

echo "1. first save creates the file"
backup=$(echo 'hl.monitor({ output = "A" })' | "$persist" save)
check "content written" "$(cat "$file")" 'hl.monitor({ output = "A" })'
check "missing file recorded as .absent" "${backup##*.}" absent

echo "2. next save backs up the previous content and keeps permissions"
chmod 600 "$file"
sleep 0.01
backup=$(echo 'hl.monitor({ output = "B" })' | "$persist" save)
check "content replaced" "$(cat "$file")" 'hl.monitor({ output = "B" })'
check "backup holds the old content" "$(cat "$backup")" 'hl.monitor({ output = "A" })'
check "permissions kept" "$(stat -c %a "$file")" 600
check "no temp files left" "$(find "$tmp/hypr" -name '.*panorama*' | wc -l)" 0

echo "3. refusals leave the file alone"
printf '' | "$persist" save 2>/dev/null
check "empty input refused" "$?" 1
if command -v luac >/dev/null; then
  echo 'hl.monitor({ output = ' | "$persist" save 2>/dev/null
  check "invalid Lua refused" "$?" 1
fi
check "file unchanged" "$(cat "$file")" 'hl.monitor({ output = "B" })'

echo "4. restore puts the newest backup back, and is repeatable"
restored=$("$persist" restore)
check "restored the newest backup" "$restored" "$backup"
check "content back to A" "$(cat "$file")" 'hl.monitor({ output = "A" })'
"$persist" restore >/dev/null
check "second restore gives the same file" "$(cat "$file")" 'hl.monitor({ output = "A" })'
check "safety copy taken" "$(find "$PANORAMA_BACKUP_DIR" -name '*.before-restore' | wc -l | tr -d ' ')" 2

echo "5. restoring an .absent backup removes the file"
first=$("$persist" backups | grep '\.absent$' | head -n 1)
"$persist" restore "$first" >/dev/null
check "file removed" "$([[ -e $file ]] && echo present || echo gone)" gone

echo "6. symlinked config: the link survives, its target is updated"
mkdir -p "$tmp/dotfiles"
echo 'old' >"$tmp/dotfiles/monitors.lua"
ln -sfn "$tmp/dotfiles/monitors.lua" "$file"
echo 'hl.monitor({ output = "C" })' | "$persist" save >/dev/null
check "still a symlink" "$([[ -L $file ]] && echo link || echo file)" link
check "target updated" "$(cat "$tmp/dotfiles/monitors.lua")" 'hl.monitor({ output = "C" })'

echo "7. old backups are pruned"
for n in 1 2 3 4 5 6; do
  echo "hl.monitor({ output = \"P$n\" })" | "$persist" save >/dev/null
  sleep 0.01
done
check "at most $PANORAMA_KEEP_BACKUPS files kept" "$(find "$PANORAMA_BACKUP_DIR" -type f | wc -l | tr -d ' ')" 4
check "newest backup is the previous save" "$(cat "$("$persist" backups | grep -v before-restore | head -n 1)")" 'hl.monitor({ output = "P5" })'

echo "8. is the file loaded by the Hyprland config?"
cfg=$tmp/hypr
cp /usr/share/hypr/hyprland.lua "$cfg/hyprland.lua" 2>/dev/null || printf 'hl.monitor({ output = "" })\n' >"$cfg/hyprland.lua"
check "a Lua config that requires nothing" "$("$persist" loaded)" missing
printf 'hl.monitor({})\n-- require("monitors")\n' >>"$cfg/hyprland.lua"
check "a commented-out require doesn't count" "$("$persist" loaded)" missing
check "the require line is added" "$("$persist" require)" "$cfg/hyprland.lua"
check "and is picked up" "$("$persist" loaded)" loaded
check "hyprland.lua backed up" "$(find "$PANORAMA_BACKUP_DIR" -name 'hyprland.lua.*' | wc -l | tr -d ' ')" 1
check "still valid Lua" "$(luac -p "$cfg/hyprland.lua" 2>&1)" ""
"$persist" require >/dev/null
check "adding it twice writes one line" "$(grep -c '^require("monitors")$' "$cfg/hyprland.lua")" 1
check "hyprland.lua is not a monitors.lua backup" "$("$persist" backups | grep -c hyprland || true)" 0
mv "$cfg/hyprland.lua" "$cfg/hyprland.conf"
check "the old .conf format is reported" "$("$persist" loaded)" legacy
rm -f "$cfg/hyprland.conf"
check "no config to judge by" "$("$persist" loaded)" unknown

echo
echo "$pass passed, $fail failed"
((fail == 0))
