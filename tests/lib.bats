#!/usr/bin/env bats
# ABOUTME: Tests for the pure decision functions in lib.sh: hotspot id, Wi-Fi QR payload,
# ABOUTME: which page the kiosk shows, what the offline watchdog does, and comitup on Ethernet.

setup() {
  # shellcheck source=/dev/null
  source "$BATS_TEST_DIRNAME/../stage-shulportal/01-shulportal/files/usr/local/lib/shulportal/lib.sh"
}

@test "ap_id_from_serial takes the last 4 hex digits, uppercased" {
  run ap_id_from_serial 10000000a1b2c3d4
  [ "$output" = "C3D4" ]
}

@test "ap_id_from_serial falls back to 0000 for short, empty or non-hex serials" {
  run ap_id_from_serial abc;  [ "$output" = "0000" ]
  run ap_id_from_serial "";   [ "$output" = "0000" ]
  run ap_id_from_serial zz12; [ "$output" = "0000" ]
}

@test "wifi_qr_payload builds an open-network join code" {
  run wifi_qr_payload ShulPortal-Setup-C3D4
  [ "$output" = 'WIFI:T:nopass;S:ShulPortal-Setup-C3D4;;' ]
}

@test "wifi_qr_payload escapes the QR special characters" {
  run wifi_qr_payload 'a;b,c:d\e"f'
  [ "$output" = 'WIFI:T:nopass;S:a\;b\,c\:d\\e\"f;;' ]
}

@test "choose_page shows ShulPortal whenever the internet is up" {
  run choose_page full yes setup 900; [ "$output" = "online" ]
  run choose_page full no "" 0;       [ "$output" = "online" ]
}

@test "choose_page shows setup when the hotspot is on the air and the internet is not" {
  run choose_page none yes connecting 0;  [ "$output" = "setup" ]
  run choose_page limited yes "" 0;       [ "$output" = "setup" ]
}

@test "choose_page keeps a showing display through 5 minutes offline, then shows setup" {
  run choose_page none yes online 299; [ "$output" = "online" ]
  run choose_page none yes online 300; [ "$output" = "setup" ]
}

@test "choose_page ignores comitup saying HOTSPOT when no hotspot is up" {
  run choose_page none no online 900; [ "$output" = "online" ]
  run choose_page none no setup 900;  [ "$output" = "setup" ]
}

@test "choose_page shows connecting before anything is known" {
  run choose_page none no "" 0; [ "$output" = "connecting" ]
}

@test "watchdog_action does nothing while online or under 300s offline" {
  run watchdog_action 1000 "" full no;   [ "$output" = "none" ]
  run watchdog_action 1299 1000 none no; [ "$output" = "none" ]
}

@test "watchdog_action never touches a running comitup" {
  run watchdog_action 1300 1000 none yes;    [ "$output" = "none" ]
  run watchdog_action 9000 1000 limited yes; [ "$output" = "none" ]
}

@test "watchdog_action starts comitup after 300s offline when it was stopped" {
  run watchdog_action 1300 1000 none no; [ "$output" = "start-comitup" ]
}

@test "active_hotspot finds the setup hotspot among active connections" {
  run active_hotspot <<< $'Wired connection 1\nShulPortal-Setup-C3D4-9f2a'; [ "$output" = "ShulPortal-Setup-C3D4-9f2a" ]
  run active_hotspot <<< $'Wired connection 1\nShul Office'; [ -z "$output" ]
  run active_hotspot < /dev/null; [ -z "$output" ]
}

@test "wired_should_stop_comitup only when Ethernet is up with full internet" {
  run wired_should_stop_comitup full yes; [ "$output" = "yes" ]
  run wired_should_stop_comitup full no;  [ "$output" = "no" ]
  run wired_should_stop_comitup none yes; [ "$output" = "no" ]
}
