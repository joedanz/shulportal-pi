# shellcheck shell=bash
# ABOUTME: Pure decision functions for the ShulPortal Pi (page choice, watchdog, hotspot name).
# ABOUTME: Sourced by the kiosk, refresh, watchdog and network scripts; does no I/O of its own.

# Seconds offline before a showing display gives way to setup, or Ethernet's stopped comitup restarts.
SHULPORTAL_OFFLINE_SECS=${SHULPORTAL_OFFLINE_SECS:-300}

# ap_id_from_serial SERIAL: the hotspot suffix, the serial's last 4 hex digits uppercased.
ap_id_from_serial() {
  local tail=${1: -4}
  if [ ${#1} -ge 4 ] && [[ $tail =~ ^[0-9a-fA-F]{4}$ ]]; then
    printf '%s\n' "$tail" | tr '[:lower:]' '[:upper:]'
  else
    printf '0000\n'
  fi
}

# wifi_qr_payload SSID: the QR text a phone camera reads as "join this open network".
wifi_qr_payload() {
  local s=$1 out='' c i
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case $c in
      \\ | ';' | ',' | ':' | '"') out+="\\$c" ;;
      *) out+=$c ;;
    esac
  done
  printf 'WIFI:T:nopass;S:%s;;\n' "$out"
}

# choose_page CONNECTIVITY HOTSPOT_UP CURRENT OFFLINE_SECS [SEEN_ONLINE]: online, cached, setup
# or connecting. Setup needs the hotspot really on the air (comitup reports HOTSPOT without one
# while it retries saved Wi-Fi). A showing display keeps its content for 5 minutes offline.
# cached: offline at boot on a Pi that has been online; opens the TV page from the browser's copy.
choose_page() {
  local connectivity=$1 hotspot_up=$2 current=$3 offline_secs=$4 seen_online=${5:-no}
  # A Pi that has shown its sign boots like a showing sign, whichever of Wi-Fi or the hotspot comes first.
  if [ -z "$current" ] && [ "$seen_online" = yes ]; then current=cached; fi
  if [ "$connectivity" = full ]; then
    echo online
  elif [ "$hotspot_up" = yes ] && [[ $current != online && $current != cached || $offline_secs -ge $SHULPORTAL_OFFLINE_SECS ]]; then
    echo setup
  else
    echo "${current:-connecting}"
  fi
}

# watchdog_action NOW OFFLINE_SINCE CONNECTIVITY COMITUP_ACTIVE WIRED_UP: none or start-comitup.
# comitup brings its own hotspot up when saved Wi-Fi fails; this only restarts it after
# Ethernet had it stopped, Ethernet is now unplugged, and the internet has been gone 5 minutes.
# (Plugged-in Ethernet with the ISP down needs no Wi-Fi setup page.)
watchdog_action() {
  local now=$1 since=$2 connectivity=$3 active=$4 wired=$5
  if [ "$connectivity" != full ] && [ -n "$since" ] && [ "$active" != yes ] && [ "$wired" != yes ] &&
    [ $((now - since)) -ge "$SHULPORTAL_OFFLINE_SECS" ]; then
    echo start-comitup
  else
    echo none
  fi
}

# active_hotspot: reads active NetworkManager connection names on stdin and prints the
# setup hotspot's (comitup names it ShulPortal-Setup-XXXX-<hash>), or nothing.
active_hotspot() {
  local name
  while IFS= read -r name; do
    case $name in ShulPortal-Setup-*) printf '%s\n' "$name"; return 0 ;; esac
  done
  return 0
}

# wired_up: reads "TYPE:STATE" lines from "nmcli -t -f TYPE,STATE device" on stdin and prints
# yes when an Ethernet device is connected, otherwise no.
wired_up() {
  local line
  while IFS= read -r line; do
    if [ "$line" = ethernet:connected ]; then echo yes; return 0; fi
  done
  echo no
}

# wired_should_stop_comitup CONNECTIVITY WIRED_UP: yes when Ethernet carries the internet,
# so no open setup hotspot runs beside a working wired link.
wired_should_stop_comitup() {
  if [ "$1" = full ] && [ "$2" = yes ]; then echo yes; else echo no; fi
}

# setup_ssid ID: the setup hotspot's name for comitup id ID (see etc/comitup.conf ap_name).
setup_ssid() {
  printf 'ShulPortal-Setup-%s\n' "$1"
}

# mark_clean_exit PREFS_FILE: tell Chromium its last run ended cleanly, so a power cut
# never brings up the "restore pages" bubble. A missing file is left alone.
mark_clean_exit() {
  local f=$1
  [ -f "$f" ] || return 0
  sed -e 's/"exit_type":"[^"]*"/"exit_type":"Normal"/' \
      -e 's/"exited_cleanly":false/"exited_cleanly":true/' "$f" > "$f.tmp"
  mv "$f.tmp" "$f"
}

# render_setup_page TEMPLATE OUT SSID: the TV's "connect your phone" page, with an
# inline QR code that joins the open setup hotspot.
render_setup_page() {
  local template=$1 out=$2 ssid=$3 page qr
  qr=$(qrencode -t SVG -m 2 -o - "$(wifi_qr_payload "$ssid")")
  page=$(<"$template")
  page=${page//'{{SSID}}'/"$ssid"}
  page=${page//'{{QR}}'/"$qr"}
  printf '%s\n' "$page" > "$out.tmp"
  mv "$out.tmp" "$out"
}
