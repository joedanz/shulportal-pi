#!/usr/bin/env bash
# ABOUTME: Checks a built ShulPortal Pi .img before release: kiosk files, enabled services and
# ABOUTME: first-boot state. Run as root on Linux: check-image.sh IMG. Exits non-zero naming what's wrong.
set -euo pipefail

img=$1
loop=$(losetup --find --partscan --show "$img")
mnt=$(mktemp -d)
cleanup() {
  umount "$mnt/boot/firmware" 2>/dev/null || true
  umount "$mnt" 2>/dev/null || true
  losetup -d "$loop"
  rmdir "$mnt"
}
trap cleanup EXIT
mount -o ro "${loop}p2" "$mnt"
mount -o ro "${loop}p1" "$mnt/boot/firmware"

failed=0
fail() { echo "FAIL: $*"; failed=1; }
executable() { [ -x "$mnt/$1" ] || fail "$1 is missing or not executable"; }
contains() { grep -q -- "$2" "$mnt/$1" 2>/dev/null || fail "$1 does not contain $2"; }
absent() { [ ! -e "$mnt/$1" ] || fail "$1 should not be in the image"; }
enabled() { [ -n "$(find "$mnt/etc/systemd/system" -path "*.wants/$1" -print -quit)" ] || fail "$1 is not enabled"; }
masked() { [ "$(readlink "$mnt/etc/systemd/system/$1")" = /dev/null ] || fail "$1 is not masked"; }

for f in usr/bin/cage usr/bin/chromium usr/bin/qrencode usr/sbin/dnsmasq \
  usr/local/bin/shulportal-nightly-reboot \
  usr/local/bin/shulportal-kiosk usr/local/bin/shulportal-refresh usr/local/bin/comitup-callback \
  usr/local/bin/shulportal-watchdog usr/local/bin/shulportal-firstboot \
  etc/NetworkManager/dispatcher.d/90-shulportal; do
  executable "$f"
done
installed() { [ -f "$mnt/var/lib/dpkg/info/$1.list" ] || fail "package $1 is not installed"; }

for p in cage chromium comitup qrencode seatd unattended-upgrades; do
  installed "$p"
done
contains etc/comitup.conf 'ShulPortal-Setup-<nnnn>'
contains etc/comitup.conf 'external_callback: /usr/local/bin/comitup-callback'
contains usr/local/share/shulportal/setup.html.tmpl '{{QR}}'
contains boot/firmware/cmdline.txt 'consoleblank=0'
absent var/lib/comitup/comitup.json
for u in seatd.service shulportal-kiosk.service shulportal-firstboot.service \
  shulportal-watchdog.timer shulportal-reboot.timer comitup.service; do
  enabled "$u"
done
masked dnsmasq.service
# comitup runs its own dnsmasq; with systemd-resolved masked, a stub resolv.conf would break DNS.
if [ -L "$mnt/etc/resolv.conf" ] && [[ $(readlink "$mnt/etc/resolv.conf") == *systemd/resolve* ]]; then
  fail "etc/resolv.conf points at systemd-resolved, which is masked"
fi
contains etc/systemd/system/apt-daily-upgrade.timer.d/shulportal.conf '03:15'

kiosk_uid=$(awk -F: '$1 == "kiosk" { print $3 }' "$mnt/etc/passwd")
[ -n "$kiosk_uid" ] || fail "no kiosk user"
[ "$(stat -c %u "$mnt/var/lib/shulportal/chromium")" = "$kiosk_uid" ] || fail "Chromium profile is not owned by kiosk"
[ "$(stat -c %u "$mnt/etc/NetworkManager/dispatcher.d/90-shulportal")" = 0 ] || fail "dispatcher hook is not owned by root"

awk -F: '$1 == "pi" { print $2 }' "$mnt/etc/shadow" | grep -q '^!' || fail "the pi account is not locked"

if [ "$failed" -ne 0 ]; then exit 1; fi
echo "check-image: OK"
