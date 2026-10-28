#!/bin/bash -e
# ABOUTME: Installs the ShulPortal kiosk files into the image and enables its services.
# ABOUTME: Runs on the build host with ROOTFS_DIR pointing at the image's root filesystem.

# Copy as root (ownership root:root), keeping the executable bits from git.
cp -R --preserve=mode,timestamps files/. "${ROOTFS_DIR}/"

on_chroot << 'CHROOT'
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
