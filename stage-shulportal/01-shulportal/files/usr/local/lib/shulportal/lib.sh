# shellcheck shell=bash
# ABOUTME: Decision functions for the ShulPortal Pi (page choice, watchdog, hotspot name, updates), plus the few
# ABOUTME: small file helpers they need (device id, setup page). Sourced by the kiosk, refresh, watchdog and updater.

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

# ensure_device_id FILE: prints this Pi's device id (32 lowercase hex, 128 random bits), creating FILE (mode 600)
# the first time. ShulPortal knows the Pi by it for remote updates, so it's a secret like a TV link: never log it.
ensure_device_id() {
  local f=$1 id
  id=$(cat "$f" 2>/dev/null || true)
  if [[ ! $id =~ ^[0-9a-f]{32}$ ]]; then
    id=$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')
    [[ $id =~ ^[0-9a-f]{32}$ ]] || return 1
    (umask 077 && printf '%s\n' "$id" > "$f.tmp") && mv "$f.tmp" "$f" || return 1
  fi
  printf '%s\n' "$id"
}

# is_version V: V is a release version, x.y.z with up to 4 digits each (dev builds aren't).
is_version() {
  [[ $1 =~ ^[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}$ ]]
}

# version_gt A B: succeeds when release version A is newer than B (both x.y.z; 08 is eight, not octal).
version_gt() {
  local -a a b
  local i
  IFS=. read -r -a a <<<"$1"
  IFS=. read -r -a b <<<"$2"
  for i in 0 1 2; do
    if ((10#${a[i]} > 10#${b[i]})); then return 0; fi
    if ((10#${a[i]} < 10#${b[i]})); then return 1; fi
  done
  return 1
}

# reply_field REPLY KEY VALUE_ERE: the string KEY holds in ShulPortal's one-line JSON check reply, printed only when
# it matches VALUE_ERE whole; other fields, in any order, are fine. A reply that isn't a JSON object (an HTML
# error page, junk) prints nothing.
reply_field() {
  printf '%s\n' "$1" | sed -En '/^[[:space:]]*\{.*\}[[:space:]]*$/ s/.*"'"$2"'"[[:space:]]*:[[:space:]]*"('"$3"')".*/\1/p' | head -n1
}

# install_target REPLY CURRENT: the version ShulPortal's check reply asks this Pi to install, printed only when
# it's x.y.z, CURRENT is a release version, and the target is newer. Anything else prints nothing.
install_target() {
  local v
  v=$(reply_field "$1" install '[0-9.]+')
  if is_version "$v" && is_version "$2" && version_gt "$v" "$2"; then printf '%s\n' "$v"; fi
  return 0
}

# reply_turn REPLY: how ShulPortal says this TV's sign hangs (right, left or none), or nothing when no sign has
# linked this Pi yet.
reply_turn() { reply_field "$1" turn 'right|left|none'; }

# saved_turn FILE: the turn the kiosk uses (right or left), or nothing. A linked Pi's sign sets it (save_turn);
# before that, the setup page on the phone does (set_turn, from libexec/shulportal/turn-helper).
saved_turn() {
  local t
  t=$(cat "$1" 2>/dev/null || true)
  case $t in right | left) printf '%s\n' "$t" ;; esac
}

# save_turn FILE REPLY: keeps the turn a check reply gives, or forgets it on "none". A reply with no turn leaves
# it alone, so a Pi no sign has linked keeps the turn picked on the phone. Writes only when it changes, so a
# check every 5 minutes leaves the SD card alone.
save_turn() {
  local turn
  turn=$(reply_turn "$2")
  [ -z "$turn" ] || set_turn "$1" "$turn"
}

# set_turn FILE TURN: keeps right or left, or forgets the turn on none (anything else changes nothing). Writes
# only on a change. The one writer of the turn file: save_turn and the turn helper both come here.
set_turn() {
  case $2 in
    none) rm -f "$1" ;;
    right | left) [ "$2" = "$(saved_turn "$1")" ] || { printf '%s\n' "$2" > "$1.tmp" && mv "$1.tmp" "$1"; } ;;
    *) return 1 ;;
  esac
}

# check_body DEVICE VERSION [FAILED_VERSION REASON]: the JSON body of a check (see ShulPortal's piHttp.ts).
# The reason loses any quote, backslash or control character, so it can't break the JSON.
check_body() {
  if [ $# -ge 4 ]; then
    local reason
    reason=$(printf '%s' "$4" | tr -d '"\134\000-\037' | cut -c1-120)
    printf '{"device":"%s","version":"%s","failed":{"version":"%s","reason":"%s"}}\n' "$1" "$2" "$3" "$reason"
  else
    printf '{"device":"%s","version":"%s"}\n' "$1" "$2"
  fi
}

# chromium_blocked VERSION PINFILE: succeeds when Chromium VERSION matches any "Pin: version" pattern in
# PINFILE (an apt preferences file whose entries keep known-bad builds off the Pi).
chromium_blocked() {
  local v=$1 pattern
  while read -r pattern; do
    # shellcheck disable=SC2254 # the pin's version is a glob, as apt reads it.
    case $v in $pattern) return 0 ;; esac
  done < <(sed -n 's/^Pin:[[:space:]]*version[[:space:]]\{1,\}//p' "$2")
  return 1
}
