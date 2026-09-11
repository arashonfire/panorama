#!/usr/bin/env bash
# Installs Panorama for the current user from this checkout: symlinks the
# launcher into ~/.local/bin and the desktop entry into ~/.local/share/applications.
# Usage: install.sh [--uninstall]
set -euo pipefail

root=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
bin_dir=${XDG_BIN_HOME:-$HOME/.local/bin}
app_dir=${XDG_DATA_HOME:-$HOME/.local/share}/applications

if [[ ${1:-} == --uninstall ]]; then
  rm -fv "$bin_dir/panorama" "$app_dir/panorama.desktop"
  exit 0
fi

mkdir -p "$bin_dir" "$app_dir"
ln -sfnv "$root/bin/panorama" "$bin_dir/panorama"
ln -sfnv "$root/share/applications/panorama.desktop" "$app_dir/panorama.desktop"

case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) echo "note: $bin_dir is not on your PATH" >&2 ;;
esac
