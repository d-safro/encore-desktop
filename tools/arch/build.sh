#!/bin/bash
# Makes dist/encore-bin-<version>-1-x86_64.pkg.tar.zst and dist/PKGBUILD (ready for the AUR) from the Linux
# release archive. makepkg runs only on Arch: this does it inside an archlinux container (podman or docker)
# unless it's already on Arch.
# Usage: tools/arch/build.sh dist/encore-1.8.0-linux-x86_64.tar.gz
set -euo pipefail
cd "$(dirname "$0")/../.."
tarball=$(realpath "$1")
out=$(dirname "$tarball")
base=$(basename "$tarball" .tar.gz)
version=${base#encore-}; version=${version%-linux-*}
sum=$(sha256sum "$tarball" | cut -d' ' -f1)
work=$(mktemp -d -p "$out" arch.XXXXXX)
trap 'rm -rf "$work"' EXIT
sed -e "s/@VERSION@/$version/" -e "s/@SHA256@/$sum/" tools/arch/PKGBUILD > "$work/PKGBUILD"
cp "$work/PKGBUILD" "$out/PKGBUILD"
cp "$tarball" "$work/"   # makepkg uses this copy instead of downloading it

if command -v makepkg >/dev/null; then
  (cd "$work" && makepkg -f --nodeps)
else
  engine=$(command -v podman || command -v docker)
  rel=${work#"$PWD"/}
  # the files go back to you afterwards (rootless podman's root is you; docker's is real root)
  owner=0:0
  [ "$(basename "$engine")" = docker ] && owner=$(id -u):$(id -g)
  # makepkg refuses to run as root: a throwaway user does it
  "$engine" run --rm -e OWNER="$owner" -v "$PWD:/src:Z" -w "/src/$rel" archlinux:latest bash -c '
    set -e
    pacman -Sy --noconfirm --needed base-devel >/dev/null
    useradd -m builder
    chown -R builder .
    su builder -c "makepkg -f --nodeps"
    chown -R "$OWNER" .'
fi
cp "$work"/encore-bin-*.pkg.tar.zst "$out/"
echo "Built:"; ls "$out"/encore-bin-*.pkg.tar.zst
