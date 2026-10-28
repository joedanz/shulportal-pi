#!/usr/bin/env bats
# ABOUTME: Tests for the kiosk launcher, the page refresh and the local setup page.
# ABOUTME: Chromium, nmcli and systemctl are stubs that log how they were called.

load helpers/common

setup() {
  common_setup
  # shellcheck source=/dev/null
  source "$SHULPORTAL_LIB"
}

@test "mark_clean_exit rewrites a crashed profile" {
  mkdir -p "$BATS_TEST_TMPDIR/p"
  cp "$BATS_TEST_DIRNAME/fixtures/crashed-preferences.json" "$BATS_TEST_TMPDIR/p/Preferences"
  mark_clean_exit "$BATS_TEST_TMPDIR/p/Preferences"
  run cat "$BATS_TEST_TMPDIR/p/Preferences"
  [[ $output == *'"exit_type":"Normal"'* ]]
  [[ $output == *'"exited_cleanly":true'* ]]
  [[ $output == *'"name":"Person 1"'* ]]
}

@test "mark_clean_exit ignores a missing file" {
  run mark_clean_exit "$BATS_TEST_TMPDIR/nope/Preferences"
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/nope/Preferences" ]
}

@test "render_setup_page embeds SSID and an svg" {
  render_setup_page "$SHULPORTAL_SHARE/setup.html.tmpl" "$BATS_TEST_TMPDIR/setup.html" ShulPortal-Setup-C3D4
  run cat "$BATS_TEST_TMPDIR/setup.html"
  [[ $output == *ShulPortal-Setup-C3D4* ]]
  [[ $output == *'<svg'* ]]
  [[ $output != *'{{'* ]]
  [ "$(grep -o '<svg' "$BATS_TEST_TMPDIR/setup.html" | wc -l | tr -d ' ')" = 1 ]
}

@test "refresh restarts the kiosk when the page changes" {
  export STUB_CONNECTIVITY=none
  echo HOTSPOT > "$SHULPORTAL_RUN/comitup-state"
  echo connecting > "$SHULPORTAL_RUN/page"
  run "$SHULPORTAL_BIN/shulportal-refresh"
  [ "$status" -eq 0 ]
  [ "$(cat "$SHULPORTAL_RUN/page")" = setup ]
  grep -q ShulPortal-Setup-C3D4 "$SHULPORTAL_RUN/setup.html"
  [[ $(logged systemctl) == *"restart shulportal-kiosk"* ]]
}

@test "refresh names the hotspot from comitup's own id when it has one" {
  export STUB_CONNECTIVITY=none
  echo HOTSPOT > "$SHULPORTAL_RUN/comitup-state"
  echo '{"id": "7A01"}' > "$SHULPORTAL_COMITUP_JSON"
  "$SHULPORTAL_BIN/shulportal-refresh"
  grep -q ShulPortal-Setup-7A01 "$SHULPORTAL_RUN/setup.html"
}

@test "refresh does nothing when the page is unchanged" {
  export STUB_CONNECTIVITY=full
  echo online > "$SHULPORTAL_RUN/page"
  run "$SHULPORTAL_BIN/shulportal-refresh"
  [ "$status" -eq 0 ]
  [ -z "$(logged systemctl)" ]
}

@test "kiosk launches the online URL with a persistent profile" {
  echo online > "$SHULPORTAL_RUN/page"
  run "$SHULPORTAL_BIN/shulportal-kiosk"
  [ "$status" -eq 0 ]
  [[ $(logged chromium) == *"https://shulportal.com/tv"* ]]
  [[ $(logged chromium) == *"--user-data-dir=$SHULPORTAL_PROFILE"* ]]
  [[ $(logged chromium) == *"--kiosk"* ]]
}

@test "kiosk marks the profile clean before launching" {
  mkdir -p "$SHULPORTAL_PROFILE/Default"
  cp "$BATS_TEST_DIRNAME/fixtures/crashed-preferences.json" "$SHULPORTAL_PROFILE/Default/Preferences"
  "$SHULPORTAL_BIN/shulportal-kiosk"
  grep -q '"exit_type":"Normal"' "$SHULPORTAL_PROFILE/Default/Preferences"
}

@test "kiosk launches connecting page by default" {
  run "$SHULPORTAL_BIN/shulportal-kiosk"
  [[ $(logged chromium) == *"connecting.html"* ]]
}

@test "kiosk launches the local setup page in setup" {
  echo setup > "$SHULPORTAL_RUN/page"
  run "$SHULPORTAL_BIN/shulportal-kiosk"
  [[ $(logged chromium) == *"file://$SHULPORTAL_RUN/setup.html"* ]]
}
