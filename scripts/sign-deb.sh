#!/usr/bin/env bash
# ABOUTME: Signs a release package for remote updates: sign-deb.sh DEB KEY writes DEB.sig, the raw ed25519
# ABOUTME: signature over the file's bytes that shulportal-update checks against release-key.pem.
set -euo pipefail
openssl pkeyutl -sign -inkey "$2" -rawin -in "$1" -out "$1.sig"
