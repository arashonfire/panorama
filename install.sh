#!/usr/bin/env bash
# Installs Panorama for the current user from this checkout: symlinks the
# launcher into ~/.local/bin and writes a desktop entry pointing at this
# directory, so the menu entry works wherever the checkout lives -- and whether
# or not ~/.local/bin is on the PATH a launcher happens to have.
# Usage: install.sh [--uninstall]
set -euo pipefail

root=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
bin_dir=${XDG_BIN_HOME:-$HOME/.local/bin}
app_dir=${XDG_DATA_HOME:-$HOME/.local/share}/applications
launcher=$root/bin/panorama
desktop=$app_dir/panorama.desktop

if [[ ${1:-} == --uninstall ]]; then
  rm -fv "$bin_dir/panorama" "$desktop"
  exit 0
fi

mkdir -p "$bin_dir" "$app_dir"
ln -sfnv "$launcher" "$bin_dir/panorama"

# Exec= is a command line, not a path: reserved characters have to be quoted,
# and a checkout can live anywhere. TryExec= is a plain path and takes none.
exec_field=$launcher
case $exec_field in
  *[[:space:]\"\'\\\`\$\<\>\~\|\&\;\*\?\#\(\)]*)
    exec_field=\"$(printf '%s' "$launcher" | sed 's/[\\"`$]/\\&/g')\"
    ;;
esac

# The packaged entry runs `panorama` from PATH (/usr/bin/panorama); from a
# checkout that name may not resolve, so point straight at the launcher.
while IFS= read -r line; do
  case $line in
    Exec=*) printf 'TryExec=%s\nExec=%s\n' "$launcher" "$exec_field" ;;
    TryExec=*) ;;
    *) printf '%s\n' "$line" ;;
  esac
done <"$root/share/applications/panorama.desktop" >"$desktop.new"
mv -f "$desktop.new" "$desktop"
echo "wrote '$desktop' -> $launcher"

if command -v desktop-file-validate >/dev/null; then
  desktop-file-validate "$desktop" || echo "note: the desktop entry did not validate cleanly" >&2
fi
command -v update-desktop-database >/dev/null && update-desktop-database -q "$app_dir" || true

case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *)
    echo "note: $bin_dir is not on your PATH." >&2
    echo "      Add it, or use $launcher in keybindings." >&2
    ;;
esac
