#!/usr/bin/env bash
# ABOUTME: Builds the shulportal-pi Debian package from the image's kiosk files and debian/.
# ABOUTME: Usage: build-deb.sh VERSION OUTDIR. Writes OUTDIR/shulportal-pi_VERSION_all.deb.
set -euo pipefail

version=$1
outdir=$2
repo=$(cd "$(dirname "$0")/.." && pwd)
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT

# Modes come from git (executables stay executable); --root-owner-group makes everything root's.
cp -Rp "$repo/stage-shulportal/01-shulportal/files/." "$root/"
mkdir -p "$root/DEBIAN"
sed "s/@VERSION@/$version/" "$repo/debian/control.in" > "$root/DEBIAN/control"
for s in preinst postinst postrm; do install -m 755 "$repo/debian/$s" "$root/DEBIAN/$s"; done

mkdir -p "$outdir"
dpkg-deb --root-owner-group -Zxz --build "$root" "$outdir/shulportal-pi_${version}_all.deb"
