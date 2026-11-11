#!/usr/bin/env bash
# ABOUTME: Builds the shulportal-pi Debian package from the image's kiosk files and debian/.
# ABOUTME: Usage: build-deb.sh VERSION OUTDIR. Writes OUTDIR/shulportal-pi_VERSION_all.deb.
set -euo pipefail

version=$1
outdir=$2
repo=$(cd "$(dirname "$0")/.." && pwd)
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT

# Executable bits come from git; --root-owner-group makes everything root's.
cp -Rp "$repo/stage-shulportal/01-shulportal/files/." "$root/"
# Never writable by anyone but root, whatever the checkout's umask (NetworkManager refuses a group-writable hook).
chmod -R go-w "$root"
mkdir -p "$root/DEBIAN"
sed "s/@VERSION@/$version/" "$repo/debian/control.in" > "$root/DEBIAN/control"
for s in preinst postinst postrm; do install -m 755 "$repo/debian/$s" "$root/DEBIAN/$s"; done

mkdir -p "$outdir"
dpkg-deb --root-owner-group -Zxz --build "$root" "$outdir/shulportal-pi_${version}_all.deb"
