#!/bin/bash
# Attaches files to a GitHub release and keeps its SHA256SUMS.txt whole: the lines for these files are
# replaced, the lines for files already there (the APKs, another platform's builds) stay. The release is
# made as a draft if it doesn't exist yet, so nobody's updater sees it before it's published.
# Usage: tools/release/upload.sh v1.8.0 dist/file1 dist/file2 …   (needs gh, logged in)
set -euo pipefail
tag=$1; shift
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
gh release view "$tag" >/dev/null 2>&1 || gh release create "$tag" --draft --title "${tag#v}" --notes "Encore ${tag#v}"
gh release download "$tag" -p SHA256SUMS.txt -D "$work" 2>/dev/null || touch "$work/SHA256SUMS.txt"
for f in "$@"; do
  n=$(basename "$f")
  grep -v "  $n\$" "$work/SHA256SUMS.txt" > "$work/s" || true
  mv "$work/s" "$work/SHA256SUMS.txt"
  (cd "$(dirname "$f")" && sha256sum "$n") >> "$work/SHA256SUMS.txt"
done
sort -k2 -o "$work/SHA256SUMS.txt" "$work/SHA256SUMS.txt"
gh release upload "$tag" --clobber "$@" "$work/SHA256SUMS.txt"
echo "Attached to $tag: $* and SHA256SUMS.txt"
