#!/bin/bash
# Builds dist/encore-<version>-x86_64.flatpak: one file to install with
#   flatpak install --user encore-<version>-x86_64.flatpak
# (the GNOME runtime it needs comes from Flathub). Encore updates it itself (Settings › Check now).
# Usage: tools/flatpak/build.sh [path/to/encore-<version>-linux-x86_64.tar.gz]
#   Without an archive, it builds one from this source (tools/linux/build.sh --no-rpm).
# Needs flatpak, flatpak-builder (or org.flatpak.Builder from Flathub), and the GNOME 51 SDK:
#   flatpak install --user flathub org.flatpak.Builder org.gnome.Sdk//51
set -euo pipefail
cd "$(dirname "$0")/../.."
root=$PWD
version=$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' pubspec.yaml)
archive=${1:-}
if [ -z "$archive" ]; then
  tools/linux/build.sh --no-rpm
  archive=dist/encore-$version-linux-x86_64.tar.gz
fi
here=$root/tools/flatpak
cp "$archive" "$here/encore-linux.tar.gz"
# flatpak-builder keeps a module built from a local file even when the file changed: with the archive's checksum in
# the manifest, a new archive builds Encore's module again (libmpv and the rest stay cached)
sum=$(sha256sum "$here/encore-linux.tar.gz" | cut -d' ' -f1)
manifest=$here/.build-dev.safro.encore.yml
trap 'rm -f "$here/encore-linux.tar.gz" "$manifest"' EXIT
sed "s|^        path: encore-linux.tar.gz\$|        path: encore-linux.tar.gz\n        sha256: $sum|" "$here/dev.safro.encore.yml" > "$manifest"
grep -q "sha256: $sum" "$manifest"
if command -v flatpak-builder >/dev/null; then builder=(flatpak-builder)
else builder=(flatpak run --no-documents-portal --filesystem="$root" org.flatpak.Builder); fi
work=$root/build/flatpak
mkdir -p "$work" dist
"${builder[@]}" --force-clean --user --disable-rofiles-fuse --state-dir="$work/state" --repo="$work/repo" \
  "$work/app" "$manifest"
flatpak build-bundle --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo \
  "$work/repo" "dist/encore-$version-x86_64.flatpak" dev.safro.encore
(cd dist && sha256sum "encore-$version-x86_64.flatpak" > SHA256SUMS-flatpak.txt)
echo "Built dist/encore-$version-x86_64.flatpak"
