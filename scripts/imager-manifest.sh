#!/usr/bin/env bash
# ABOUTME: Prints the Raspberry Pi Imager manifest (.rpi-imager-manifest) for a built image, so Imager
# ABOUTME: lists ShulPortal Pi and offers its Wi-Fi/hostname settings. Usage: IMG_XZ URL RELEASE_DATE
set -euo pipefail

img_xz=$1 url=$2 release_date=$3

sha256() { if command -v sha256sum >/dev/null; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }

jq -n \
  --arg url "$url" \
  --arg release_date "$release_date" \
  --argjson extract_size "$(xz -dc "$img_xz" | wc -c | tr -d ' ')" \
  --arg extract_sha256 "$(xz -dc "$img_xz" | sha256)" \
  --argjson image_download_size "$(wc -c < "$img_xz" | tr -d ' ')" \
  --arg image_download_sha256 "$(sha256 < "$img_xz")" \
  '{
    imager: {
      devices: [
        {name: "Raspberry Pi 5", tags: ["pi5-64bit"], matching_type: "exclusive", capabilities: []},
        {name: "Raspberry Pi 4", tags: ["pi4-64bit"], matching_type: "inclusive", capabilities: []},
        {name: "Raspberry Pi 3", tags: ["pi3-64bit"], matching_type: "inclusive", capabilities: []}
      ]
    },
    os_list: [{
      name: "ShulPortal Pi",
      description: "Turns a Raspberry Pi 3 B+, 4 or 5 into a ShulPortal lobby screen.",
      url: $url,
      extract_size: $extract_size,
      extract_sha256: $extract_sha256,
      image_download_size: $image_download_size,
      image_download_sha256: $image_download_sha256,
      release_date: $release_date,
      init_format: "cloudinit-rpi",
      devices: ["pi5-64bit", "pi4-64bit", "pi3-64bit"]
    }]
  }'
