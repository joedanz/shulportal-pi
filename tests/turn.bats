#!/usr/bin/env bats
# ABOUTME: Tests for the turn helper: the phone's setup page picks how the TV hangs, the TV's pages read it back.
# ABOUTME: Runs the real helper on a spare port; "the hotspot" is loopback here, set by SHULPORTAL_HOTSPOT_ADDR.

load helpers/common

setup() {
  common_setup
  HELPER="$FILES/usr/local/libexec/shulportal/turn-helper"
  export SHULPORTAL_TURN_PORT
  SHULPORTAL_TURN_PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
}

teardown() {
  if [ -n "${pid:-}" ]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
}

# start HOTSPOT_ADDR: runs the helper, taking requests that reach HOTSPOT_ADDR as coming over the hotspot.
start() {
  SHULPORTAL_HOTSPOT_ADDR=$1 python3 "$HELPER" 2>/dev/null &
  pid=$!
  for _ in $(seq 50); do
    python3 -c "import socket; socket.create_connection(('127.0.0.1', $SHULPORTAL_TURN_PORT), 1)" 2>/dev/null && return 0
    sleep 0.1
  done
  return 1
}

# ask METHOD [BODY]: prints "STATUS BODY ACAO" for a request to /turn on loopback.
ask() {
  python3 - "$SHULPORTAL_TURN_PORT" "$@" <<'PY'
import sys, urllib.request, urllib.error
port, method = sys.argv[1], sys.argv[2]
data = sys.argv[3].encode() if len(sys.argv) > 3 else None
req = urllib.request.Request(f"http://127.0.0.1:{port}/turn", data=data, method=method,
                             headers={"Content-Type": "application/x-www-form-urlencoded"})
try:
    r = urllib.request.urlopen(req, timeout=5)
except urllib.error.HTTPError as e:
    r = e
print(r.status, r.read().decode() or "-", r.headers.get("Access-Control-Allow-Origin"))
PY
}

@test "a pick on the phone saves the turn the kiosk reads" {
  start 127.0.0.1
  [ "$(ask POST turn=left)" = "204 - *" ]
  [ "$(cat "$SHULPORTAL_STATE/turn")" = left ]
  # shellcheck source=/dev/null
  source "$SHULPORTAL_LIB"
  [ "$(saved_turn "$SHULPORTAL_STATE/turn")" = left ]
}

@test "the phone and the TV's pages read the turn back, with none when there isn't one" {
  start 127.0.0.1
  [ "$(ask GET)" = "200 none *" ]
  echo right > "$SHULPORTAL_STATE/turn"
  [ "$(ask GET)" = "200 right *" ]
  echo sideways > "$SHULPORTAL_STATE/turn"
  [ "$(ask GET)" = "200 none *" ]
}

@test "Horizontal forgets the turn" {
  echo right > "$SHULPORTAL_STATE/turn"
  start 127.0.0.1
  [ "$(ask POST turn=none)" = "204 - *" ]
  [ ! -e "$SHULPORTAL_STATE/turn" ]
  [ "$(ask POST turn=none)" = "204 - *" ]
}

@test "the same pick isn't written again" {
  echo left > "$SHULPORTAL_STATE/turn"
  touch -t 202001010000 "$SHULPORTAL_STATE/turn"
  start 127.0.0.1
  ask POST turn=left
  [ -z "$(find "$SHULPORTAL_STATE/turn" -newermt 2021-01-01)" ]
}

@test "anything but right, left or none is refused and changes nothing" {
  echo left > "$SHULPORTAL_STATE/turn"
  start 127.0.0.1
  [ "$(ask POST turn=upside-down)" = "400 - *" ]
  [ "$(ask POST "turn=$(printf 'x%.0s' $(seq 80))")" = "400 - *" ]
  [ "$(ask POST other=1)" = "400 - *" ]
  [ "$(cat "$SHULPORTAL_STATE/turn")" = left ]
}

@test "off the hotspot nobody can change the turn, but the TV's own pages can still read it" {
  echo left > "$SHULPORTAL_STATE/turn"
  start 10.41.0.1
  [ "$(ask POST turn=right)" = "403 - *" ]
  [ "$(cat "$SHULPORTAL_STATE/turn")" = left ]
  [ "$(ask GET)" = "200 left *" ]
}

@test "only /turn is served" {
  start 127.0.0.1
  run python3 -c "import urllib.request,urllib.error
try: urllib.request.urlopen('http://127.0.0.1:$SHULPORTAL_TURN_PORT/etc/passwd', timeout=5)
except urllib.error.HTTPError as e: print(e.code)"
  [ "$output" = 404 ]
}
