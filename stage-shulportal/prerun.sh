#!/bin/bash -e
# ABOUTME: pi-gen stage prerun: start this stage from stage2's Raspberry Pi OS Lite root filesystem.
# ABOUTME: Same as pi-gen's own stages.
if [ ! -d "${ROOTFS_DIR}" ]; then
	copy_previous
fi
