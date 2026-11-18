#!/bin/bash
# Builds the desktop release: dist/encore-<version>-linux-<arch>.tar.gz (unpack and run install.sh, or let
# Encore update itself), dist/encore-<version>-1.<dist>.<arch>.rpm, and their lines for SHA256SUMS.txt.
# Usage: tools/linux/build.sh   (from the repository; needs Flutter, rpmbuild and inkscape or ImageMagick)
set -euo pipefail
cd "$(dirname "$0")/../.."
root=$PWD
version=$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' pubspec.yaml)
arch=$(uname -m)
name=encore-$version-linux-$arch
out=$root/dist
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

flutter build linux --release
bundle=$root/build/linux/x64/release/bundle
[ "$arch" = aarch64 ] && bundle=$root/build/linux/arm64/release/bundle

mkdir -p "$work/$name/app" "$out"
cp -a "$bundle/." "$work/$name/app/"
cp tools/linux/install.sh tools/linux/dev.safro.encore.desktop tools/linux/dev.safro.encore.metainfo.xml "$work/$name/"

# icons in the sizes Plasma asks for, from the logo
for s in 16 22 24 32 48 64 128 256 512; do
  mkdir -p "$work/$name/icons/${s}x${s}"
  if command -v inkscape >/dev/null; then
    inkscape docs/logo.svg -w "$s" -h "$s" -o "$work/$name/icons/${s}x${s}/dev.safro.encore.png" 2>/dev/null
  else
    magick -background none -density 600 docs/logo.svg -resize "${s}x${s}" "$work/$name/icons/${s}x${s}/dev.safro.encore.png"
  fi
done
mkdir -p "$work/$name/icons/scalable"
cp docs/logo.svg "$work/$name/icons/scalable/dev.safro.encore.svg"

tar -C "$work" -czf "$out/$name.tar.gz" "$name"

# the RPM, from the same files
mkdir -p "$work/rpm/SOURCES"
cp "$out/$name.tar.gz" "$work/rpm/SOURCES/"
rpmbuild -bb --quiet --define "_topdir $work/rpm" --define "encore_version $version" tools/linux/encore.spec
find "$work/rpm/RPMS" -name '*.rpm' -exec cp {} "$out/" \;

cd "$out"
sha256sum "$name.tar.gz" encore-"$version"-*.rpm > SHA256SUMS-linux.txt
echo "Built:"; ls -la "$out"
