# shellcheck shell=bash
# ABOUTME: Pure decision functions for the ShulPortal Pi (page choice, watchdog, hotspot name).
# ABOUTME: Sourced by the kiosk, refresh, watchdog and network scripts; does no I/O of its own.

# Seconds without internet before the watchdog brings the setup hotspot back.
SHULPORTAL_OFFLINE_SECS=${SHULPORTAL_OFFLINE_SECS:-300}

# ap_id_from_serial SERIAL: the hotspot suffix, the serial's last 4 hex digits uppercased.
ap_id_from_serial() {
  local tail=${1: -4}
  if [ ${#1} -ge 4 ] && [[ $tail =~ ^[0-9a-fA-F]{4}$ ]]; then
    printf '%s\n' "${tail^^}"
  else
    printf '0000\n'
  fi
}

# wifi_qr_payload SSID: the QR text a phone camera reads as "join this open network".
wifi_qr_payload() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//;/\;}
  s=${s//,/\\,}
  s=${s//:/\\:}
  s=${s//\"/\\\"}
  printf 'WIFI:T:nopass;S:%s;;\n' "$s"
}

# choose_page CONNECTIVITY COMITUP_STATE CURRENT: online, setup or connecting.
# A blip keeps the current page, so a showing display keeps its cached content.
choose_page() {
  local connectivity=$1 state=$2 current=$3
  if [ "$connectivity" = full ]; then
    echo online
  elif [ "$state" = HOTSPOT ]; then
    echo setup
  elif [ -n "$current" ]; then
    echo "$current"
  else
    echo connecting
  fi
}

# watchdog_action NOW OFFLINE_SINCE CONNECTIVITY COMITUP_STATE COMITUP_ACTIVE:
# none, disconnect-wifi (so comitup falls back to its hotspot) or start-comitup.
watchdog_action() {
  local now=$1 since=$2 connectivity=$3 state=$4 active=$5
  if [ "$connectivity" = full ] || [ -z "$since" ] || [ $((now - since)) -lt "$SHULPORTAL_OFFLINE_SECS" ]; then
    echo none
  elif [ "$active" != yes ]; then
    echo start-comitup
  elif [ "$state" = CONNECTED ]; then
    echo disconnect-wifi
  else
    echo none
  fi
}

# wired_should_stop_comitup CONNECTIVITY WIRED_UP: yes when Ethernet carries the internet,
# so no open setup hotspot runs beside a working wired link.
wired_should_stop_comitup() {
  if [ "$1" = full ] && [ "$2" = yes ]; then echo yes; else echo no; fi
}
