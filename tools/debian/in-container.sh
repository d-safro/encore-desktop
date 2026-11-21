#!/bin/bash
# Makes the .deb inside a Debian container (podman or docker), so it can be built on Fedora too.
# Usage: tools/debian/in-container.sh dist/encore-1.8.0-linux-x86_64.tar.gz
set -euo pipefail
cd "$(dirname "$0")/../.."
engine=$(command -v podman || command -v docker)
# rootless podman's root is you; docker's root is real root, so the file is handed back to you
own=""
[ "$(basename "$engine")" = docker ] && own="&& chown $(id -u):$(id -g) dist/encore_*.deb"
"$engine" run --rm -v "$PWD:/src:Z" -w /src debian:stable-slim bash -c "tools/debian/build-deb.sh '$1' $own"
