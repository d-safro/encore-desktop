#!/bin/sh
# Installs Encore for you only (no sudo): the app in ~/.local/share/encore/app, a menu entry and icons, and
# `encore` in ~/.local/bin. Run it from the unpacked encore-<version>-linux-<arch> folder.
#   ./install.sh             install or update
#   ./install.sh --uninstall remove it again (your music, settings and downloads stay)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
data=${XDG_DATA_HOME:-$HOME/.local/share}
app=$data/encore/app
bin=$HOME/.local/bin

if [ "${1:-}" = "--uninstall" ]; then
  rm -rf "$data/encore/app" "$data/encore/app.old" "$data/encore/app.new"
  rm -f "$bin/encore" "$data/applications/dev.safro.encore.desktop" "$data/metainfo/dev.safro.encore.metainfo.xml"
  find "$data/icons/hicolor" -name dev.safro.encore.png -delete 2>/dev/null || true
  rm -f "$data/icons/hicolor/scalable/apps/dev.safro.encore.svg"
  echo "Encore removed. Your settings and downloads are in $data/dev.safro.encore (delete that folder to remove them too)."
  exit 0
fi

mkdir -p "$data/encore" "$bin" "$data/applications" "$data/metainfo"
rm -rf "$app.new"
cp -a "$here/app" "$app.new"
echo "installed by install.sh" > "$app.new/.encore-install"   # lets Encore update itself
rm -rf "$app.old"
[ -d "$app" ] && mv "$app" "$app.old"
mv "$app.new" "$app"
rm -rf "$app.old"
ln -sf "$app/encore" "$bin/encore"
sed "s|^Exec=encore|Exec=$app/encore|" "$here/dev.safro.encore.desktop" > "$data/applications/dev.safro.encore.desktop"
cp "$here/dev.safro.encore.metainfo.xml" "$data/metainfo/"
for d in "$here"/icons/*; do
  size=$(basename "$d")
  mkdir -p "$data/icons/hicolor/$size/apps"
  cp "$d"/* "$data/icons/hicolor/$size/apps/"
done
command -v update-desktop-database >/dev/null && update-desktop-database "$data/applications" 2>/dev/null || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q "$data/icons/hicolor" 2>/dev/null || true
echo "Encore is installed: find it in the application menu, or run 'encore'."
echo "It needs mpv's library: sudo dnf install mpv-libs   (Fedora; most desktops have it already)"
