#!/bin/bash -e
# ABOUTME: Installs the ShulPortal kiosk files into the image and enables its services.
# ABOUTME: Runs on the build host with ROOTFS_DIR pointing at the image's root filesystem.

# Copy as root (ownership root:root), keeping the executable bits from git.
cp -R --preserve=mode,timestamps files/. "${ROOTFS_DIR}/"

on_chroot << 'CHROOT'
# Chromium 156.0.8078.73 crashes every page on the Pi, and the archive's index no longer lists the
# version before it, so fetch 156.0.8078.47 from the archive's pool by name and check each file.
# etc/apt/preferences.d/shulportal-chromium keeps updates from bringing .73 back.
v=156.0.8078.47-1~deb13u1+rpt1
pool=https://archive.raspberrypi.com/debian/pool/main/c/chromium
d=$(mktemp -d)
curl -fsSL -o "$d/chromium.deb" "$pool/chromium_${v}_arm64.deb"
curl -fsSL -o "$d/chromium-common.deb" "$pool/chromium-common_${v}_arm64.deb"
curl -fsSL -o "$d/chromium-l10n.deb" "$pool/chromium-l10n_${v}_all.deb"
sha256sum -c << SUMS
097ee390f77a2443e32a7cebe72cdfc5a7722fdb60f3a327408961cd15a359da  $d/chromium.deb
a962d6dacb43ab96d4367f3b3a314f7dd7e96485a28ffd4a27146b260994558b  $d/chromium-common.deb
1f37f4591ee680ae7a8308208105f015925a052c18ce4d47e39495270087a938  $d/chromium-l10n.deb
SUMS
apt-get install -y --allow-downgrades "$d/chromium.deb" "$d/chromium-common.deb" "$d/chromium-l10n.deb"
rm -rf "$d"
id kiosk >/dev/null 2>&1 || useradd --create-home --shell /usr/sbin/nologin --groups video,render,input kiosk
# No one logs in on the screen; the build-time password is thrown away and the account locked.
passwd --lock pi
install -d -o kiosk -g kiosk -m 700 /var/lib/shulportal /var/lib/shulportal/chromium
# comitup runs its own dnsmasq through NetworkManager; the system ones must stay out of its way.
systemctl mask dnsmasq.service systemd-resolved.service
systemctl enable seatd.service shulportal-kiosk.service shulportal-firstboot.service \
  shulportal-watchdog.timer shulportal-reboot.timer comitup.service
# Every Pi names its own hotspot on first boot (shulportal-firstboot).
rm -f /var/lib/comitup/comitup.json
CHROOT

# No text-console blanking under the kiosk.
cmdline="${ROOTFS_DIR}/boot/firmware/cmdline.txt"
grep -q consoleblank= "$cmdline" || sed -i '1 s/$/ consoleblank=0/' "$cmdline"
