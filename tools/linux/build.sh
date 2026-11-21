#!/bin/bash
# Builds the desktop release: dist/encore-<version>-linux-<arch>.tar.gz (unpack and run install.sh, or let
# Encore update itself), dist/encore-<version>-1.<dist>.<arch>.rpm, and their lines for SHA256SUMS.txt.
# Usage: tools/linux/build.sh [--deb] [--arch] [--no-rpm] [--no-flutter]
#   --deb         also the Debian/Ubuntu package (dpkg-deb here, or a Debian container)
#   --arch        also the Arch package (makepkg in an archlinux container)
#   --no-rpm      skip the RPM (no rpmbuild here)
#   --no-flutter  package the bundle already in build/linux (don't build it again)
# From the repository; needs Flutter, rpmbuild and inkscape, rsvg-convert or ImageMagick.
set -euo pipefail
deb=0 archpkg=0 rpm=1 flutter=1
for a in "$@"; do
  case "$a" in
    --deb) deb=1 ;;
    --arch) archpkg=1 ;;
    --no-rpm) rpm=0 ;;
    --no-flutter) flutter=0 ;;
    *) echo "unknown option $a" >&2; exit 2 ;;
  esac
done
cd "$(dirname "$0")/../.."
root=$PWD
version=$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' pubspec.yaml)
arch=$(uname -m)
name=encore-$version-linux-$arch
out=$root/dist
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

[ $flutter = 1 ] && flutter build linux --release
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
  elif command -v rsvg-convert >/dev/null; then
    rsvg-convert -w "$s" -h "$s" docs/logo.svg -o "$work/$name/icons/${s}x${s}/dev.safro.encore.png"
  else
    magick -background none -density 600 docs/logo.svg -resize "${s}x${s}" "$work/$name/icons/${s}x${s}/dev.safro.encore.png"
  fi
done
mkdir -p "$work/$name/icons/scalable"
cp docs/logo.svg "$work/$name/icons/scalable/dev.safro.encore.svg"

tar -C "$work" -czf "$out/$name.tar.gz" "$name"

# the RPM, from the same files
if [ $rpm = 1 ]; then
  mkdir -p "$work/rpm/SOURCES"
  cp "$out/$name.tar.gz" "$work/rpm/SOURCES/"
  rpmbuild -bb --quiet --define "_topdir $work/rpm" --define "encore_version $version" \
    --define "_metainfodir %{_datadir}/metainfo" tools/linux/encore.spec
  find "$work/rpm/RPMS" -name '*.rpm' -exec cp {} "$out/" \;
fi

# the .deb and the Arch package, from the same archive
if [ $deb = 1 ]; then
  if command -v dpkg-deb >/dev/null; then tools/debian/build-deb.sh "$out/$name.tar.gz"
  else tools/debian/in-container.sh "dist/$name.tar.gz"; fi
fi
[ $archpkg = 1 ] && tools/arch/build.sh "$out/$name.tar.gz"

cd "$out"
sha256sum "$name.tar.gz" $(ls encore-"$version"-*.rpm encore_"$version"_*.deb encore-bin-"$version"-*.pkg.tar.zst 2>/dev/null) \
  > SHA256SUMS-linux.txt
echo "Built:"; ls -la "$out"
