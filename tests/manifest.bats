#!/usr/bin/env bats
# ABOUTME: Tests for the Raspberry Pi Imager manifest the release publishes, which lets Imager
# ABOUTME: offer its Wi-Fi/hostname settings for our image and checks the download.

setup() {
  head -c 5000 /dev/urandom > "$BATS_TEST_TMPDIR/test.img"
  xz -k "$BATS_TEST_TMPDIR/test.img"
  MANIFEST="$BATS_TEST_DIRNAME/../scripts/imager-manifest.sh"
}

@test "manifest describes the extracted image's size and checksum" {
  run "$MANIFEST" "$BATS_TEST_TMPDIR/test.img.xz" https://example.com/test.img.xz 2026-10-28
  [ "$status" -eq 0 ]
  [ "$(jq '.os_list[0].extract_size' <<<"$output")" = 5000 ]
  [ "$(jq -r '.os_list[0].extract_sha256' <<<"$output")" = "$(shasum -a 256 "$BATS_TEST_TMPDIR/test.img" | cut -d' ' -f1)" ]
  [ "$(jq '.os_list[0].image_download_size' <<<"$output")" = "$(wc -c < "$BATS_TEST_TMPDIR/test.img.xz" | tr -d ' ')" ]
  [ "$(jq -r '.os_list[0].url' <<<"$output")" = https://example.com/test.img.xz ]
  [ "$(jq -r '.os_list[0].release_date' <<<"$output")" = 2026-10-28 ]
}

@test "manifest offers Imager customisation for Pi 3, Pi 4 and Pi 5 only" {
  run "$MANIFEST" "$BATS_TEST_TMPDIR/test.img.xz" https://example.com/test.img.xz 2026-10-28
  [ "$(jq -c '.os_list[0].devices' <<<"$output")" = '["pi5-64bit","pi4-64bit","pi3-64bit"]' ]
  [ "$(jq -r '.os_list[0].init_format' <<<"$output")" = cloudinit-rpi ]
  [ "$(jq -r '.os_list[0].name' <<<"$output")" = "ShulPortal Pi" ]
  [ "$(jq -c '[.imager.devices[].name]' <<<"$output")" = '["Raspberry Pi 5","Raspberry Pi 4","Raspberry Pi 3"]' ]
}
