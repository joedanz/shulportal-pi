#!/usr/bin/env bats
# ABOUTME: Tests for the comitup callback, the offline watchdog, first boot and the
# ABOUTME: NetworkManager hook that keeps the setup hotspot off while Ethernet works.

load helpers/common

setup() {
  common_setup
  export SHULPORTAL_REFRESH="$BATS_TEST_DIRNAME/helpers/bin/refresh"
  export SHULPORTAL_NOW=1000
}

dispatcher() { "$BATS_TEST_DIRNAME/../stage-shulportal/01-shulportal/files/etc/NetworkManager/dispatcher.d/90-shulportal" "$@"; }

@test "callback writes state and returns at once" {
  export STUB_REFRESH_SLEEP=3
  start=$SECONDS
  run "$SHULPORTAL_BIN/comitup-callback" HOTSPOT
  [ "$status" -eq 0 ]
  [ $((SECONDS - start)) -lt 2 ]
  [ "$(cat "$SHULPORTAL_RUN/comitup-state")" = HOTSPOT ]
}

@test "callback triggers a refresh" {
  "$SHULPORTAL_BIN/comitup-callback" CONNECTED
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$STUB_LOG/refresh.log" ] && break; sleep 0.2; done
  [ "$(logged refresh)" = ran ]
}

@test "watchdog records first offline time" {
  export STUB_CONNECTIVITY=none
  "$SHULPORTAL_BIN/shulportal-watchdog"
  [ "$(cat "$SHULPORTAL_RUN/offline-since")" = 1000 ]
  [ "$(logged refresh)" = ran ]
}

@test "watchdog clears offline time when online" {
  export STUB_CONNECTIVITY=full
  echo 500 > "$SHULPORTAL_RUN/offline-since"
  "$SHULPORTAL_BIN/shulportal-watchdog"
  [ ! -e "$SHULPORTAL_RUN/offline-since" ]
}

@test "watchdog keeps the first offline time while still offline" {
  export STUB_CONNECTIVITY=none
  echo 900 > "$SHULPORTAL_RUN/offline-since"
  echo CONNECTED > "$SHULPORTAL_RUN/comitup-state"
  "$SHULPORTAL_BIN/shulportal-watchdog"
  [ "$(cat "$SHULPORTAL_RUN/offline-since")" = 900 ]
  [ -z "$(logged nmcli | grep disconnect || true)" ]
}

@test "watchdog disconnects wifi after 300s offline on CONNECTED" {
  export STUB_CONNECTIVITY=none SHULPORTAL_NOW=1300
  echo 1000 > "$SHULPORTAL_RUN/offline-since"
  echo CONNECTED > "$SHULPORTAL_RUN/comitup-state"
  "$SHULPORTAL_BIN/shulportal-watchdog"
  [[ $(logged nmcli) == *"device disconnect wlan0"* ]]
  [ ! -e "$SHULPORTAL_RUN/offline-since" ]
}

@test "watchdog starts comitup when it was stopped and wired is gone" {
  export STUB_CONNECTIVITY=none SHULPORTAL_NOW=1300 STUB_COMITUP_ACTIVE=no
  echo 1000 > "$SHULPORTAL_RUN/offline-since"
  "$SHULPORTAL_BIN/shulportal-watchdog"
  [[ $(logged systemctl) == *"start comitup"* ]]
  [ ! -e "$SHULPORTAL_RUN/offline-since" ]
}

@test "firstboot writes id from serial once" {
  "$SHULPORTAL_BIN/shulportal-firstboot"
  grep -q '"id": *"C3D4"' "$SHULPORTAL_COMITUP_JSON"
  printf '10000000ffffeeee\0' > "$SHULPORTAL_SERIAL_FILE"
  "$SHULPORTAL_BIN/shulportal-firstboot"
  grep -q '"id": *"C3D4"' "$SHULPORTAL_COMITUP_JSON"
}

@test "dispatcher stops comitup on wired internet" {
  export STUB_CONNECTIVITY=full STUB_DEVICES=$'ethernet:connected\nwifi:disconnected'
  echo HOTSPOT > "$SHULPORTAL_RUN/comitup-state"
  dispatcher eth0 connectivity-change
  [[ $(logged systemctl) == *"stop comitup"* ]]
  [ ! -e "$SHULPORTAL_RUN/comitup-state" ]
  [ "$(logged refresh)" = ran ]
}

@test "dispatcher leaves comitup alone on wifi" {
  export STUB_CONNECTIVITY=full STUB_DEVICES=$'ethernet:unavailable\nwifi:connected'
  dispatcher wlan0 up
  [ -z "$(logged systemctl)" ]
  [ "$(logged refresh)" = ran ]
}

@test "dispatcher ignores unrelated events" {
  dispatcher wlan0 dhcp4-change
  [ -z "$(logged refresh)" ]
}
