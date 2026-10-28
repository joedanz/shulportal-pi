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
  run choose_page full HOTSPOT setup; [ "$output" = "online" ]
  run choose_page full "" "";         [ "$output" = "online" ]
}

@test "choose_page shows setup when the hotspot is up and the internet is not" {
  run choose_page none HOTSPOT online;        [ "$output" = "setup" ]
  run choose_page limited HOTSPOT connecting; [ "$output" = "setup" ]
}

@test "choose_page keeps the current page through a short network blip" {
  run choose_page none CONNECTING online; [ "$output" = "online" ]
  run choose_page none CONNECTED online;  [ "$output" = "online" ]
  run choose_page none CONNECTING setup;  [ "$output" = "setup" ]
}

@test "choose_page shows connecting before anything is known" {
  run choose_page none "" "";         [ "$output" = "connecting" ]
  run choose_page none CONNECTING ""; [ "$output" = "connecting" ]
}

@test "watchdog_action does nothing while online or under 300s offline" {
  run watchdog_action 1000 "" full CONNECTED yes;    [ "$output" = "none" ]
  run watchdog_action 1299 1000 none CONNECTED yes;  [ "$output" = "none" ]
  run watchdog_action 1299 1000 none "" no;          [ "$output" = "none" ]
}

@test "watchdog_action drops Wi-Fi after 300s with Wi-Fi up but no internet" {
  run watchdog_action 1300 1000 none CONNECTED yes;    [ "$output" = "disconnect-wifi" ]
  run watchdog_action 1300 1000 limited CONNECTED yes; [ "$output" = "disconnect-wifi" ]
}

@test "watchdog_action leaves an already-running hotspot alone" {
  run watchdog_action 1300 1000 none HOTSPOT yes; [ "$output" = "none" ]
}

@test "watchdog_action starts comitup after 300s offline when it was stopped" {
  run watchdog_action 1300 1000 none "" no; [ "$output" = "start-comitup" ]
}

@test "wired_should_stop_comitup only when Ethernet is up with full internet" {
  run wired_should_stop_comitup full yes; [ "$output" = "yes" ]
  run wired_should_stop_comitup full no;  [ "$output" = "no" ]
  run wired_should_stop_comitup none yes; [ "$output" = "no" ]
}
