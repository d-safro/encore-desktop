#!/bin/bash
# Makes dist/encore_<version>_<arch>.deb (Debian, Ubuntu, Mint…) from the Linux release archive that
# tools/linux/build.sh makes. Needs dpkg-deb: run it on Debian/Ubuntu, in a container (tools/debian/in-container.sh),
# or on Fedora after `sudo dnf install dpkg`.
# Usage: tools/debian/build-deb.sh dist/encore-1.8.0-linux-x86_64.tar.gz
set -euo pipefail
tarball=$(realpath "$1")
here=$(cd "$(dirname "$0")" && pwd)
out=$(dirname "$tarball")
base=$(basename "$tarball" .tar.gz)            # encore-1.8.0-linux-x86_64
version=${base#encore-}; version=${version%-linux-*}
arch=${base##*-linux-}
case "$arch" in x86_64) debarch=amd64 ;; aarch64) debarch=arm64 ;; *) debarch=$arch ;; esac
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

tar -C "$work" -xzf "$tarball"
src=$work/$base
root=$work/pkg
mkdir -p "$root/DEBIAN" "$root/usr/lib/encore" "$root/usr/bin" "$root/usr/share/applications" "$root/usr/share/metainfo"
cp -a "$src/app/." "$root/usr/lib/encore/"
ln -s ../lib/encore/encore "$root/usr/bin/encore"
install -m644 "$src/dev.safro.encore.desktop" "$root/usr/share/applications/"
install -m644 "$src/dev.safro.encore.metainfo.xml" "$root/usr/share/metainfo/"
for d in "$src"/icons/*; do
  install -Dm644 "$d"/* -t "$root/usr/share/icons/hicolor/$(basename "$d")/apps/"
done
size=$(du -sk "$root/usr" | cut -f1)

# What the app needs from the system (the bundle carries its own Flutter libraries). The "t64" names are
# Debian 13 / Ubuntu 24.04's; the plain ones are older releases'. The C library must be at least as new as
# the newest one the programs were built to use (the build machine's): read from the programs themselves,
# so apt refuses a system that couldn't start them.
libc=$(find "$root/usr/lib/encore" -type f \( -name encore -o -name '*.so*' \) -exec grep -aoh 'GLIBC_2\.[0-9][0-9]*' {} + |
  sed 's/^GLIBC_//' | sort -uV | tail -1)
[ -n "$libc" ] || { echo "Couldn't tell which C library the app needs" >&2; exit 1; }
sed -e "s/@VERSION@/$version/" -e "s/@ARCH@/$debarch/" -e "s/@SIZE@/$size/" -e "s/@LIBC@/$libc/" \
  "$here/control" > "$root/DEBIAN/control"
install -m755 "$here/postinst" "$here/postrm" "$root/DEBIAN/"

dpkg-deb --root-owner-group -Zxz --build "$root" "$out/encore_${version}_${debarch}.deb"
echo "Built $out/encore_${version}_${debarch}.deb"
