#!/bin/bash -e
# ABOUTME: Installs the shulportal-pi package (built by scripts/build-deb.sh) into the image, plus the steps
# ABOUTME: only a fresh image needs. Runs on the build host with ROOTFS_DIR pointing at the image's root filesystem.

install -m 644 shulportal-pi.deb "${ROOTFS_DIR}/tmp/"

on_chroot << 'CHROOT'
# The package's postinst creates the kiosk user, enables the services and sets consoleblank=0.
apt-get install -y /tmp/shulportal-pi.deb
# If the archive's newest Chromium is one the package blocks, put back the build it names.
/usr/local/bin/shulportal-chromium-check
# Kept for shulportal-update to put back if a later update fails.
install -m 600 /tmp/shulportal-pi.deb /var/lib/shulportal-update/current.deb
# Every Pi names its own hotspot on first boot (shulportal-firstboot). Never done by an update.
rm -f /var/lib/comitup/comitup.json /tmp/shulportal-pi.deb
CHROOT
