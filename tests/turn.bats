#!/usr/bin/env bats
# ABOUTME: Tests for the turn helper: the phone's setup page picks how the TV hangs, the TV's setup page reads it back.
# ABOUTME: Runs the real helper on a spare port; "the hotspot" is loopback here unless a test says otherwise.

load helpers/common

setup() {
  common_setup
  export SHULPORTAL_TURN_PORT
  SHULPORTAL_TURN_PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
}

teardown() {
  if [ -n "${pid:-}" ]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
}

# start [HOTSPOT_ADDR]: runs the helper, taking requests that reach HOTSPOT_ADDR (loopback) as from the hotspot.
start() {
  SHULPORTAL_HOTSPOT_ADDR=${1:-127.0.0.1} python3 "$FILES/usr/local/libexec/shulportal/turn-helper" &
  pid=$!
  for _ in $(seq 50); do
    python3 -c "import socket; socket.create_connection(('127.0.0.1', $SHULPORTAL_TURN_PORT), 1)" 2>/dev/null && return 0
    sleep 0.1
  done
  return 1
}

# ask METHOD [BODY] [PATH]: prints "STATUS BODY" (- for none) for a request on loopback; HEADER=name adds that header.
ask() {
  python3 - "$SHULPORTAL_TURN_PORT" "$1" "${2:-}" "${3:-/turn}" "${HEADER:-}" <<'PY'
import sys, urllib.request, urllib.error
port, method, body, path, header = sys.argv[1:]
req = urllib.request.Request(f"http://127.0.0.1:{port}{path}", data=body.encode() or None, method=method,
                             headers={"Content-Type": "application/x-www-form-urlencoded"})
try:
    r = urllib.request.urlopen(req, timeout=5)
except urllib.error.HTTPError as e:
    r = e
out = [str(r.status), r.read().decode() or "-"] + ([str(r.headers.get(header))] if header else [])
print(*out)
PY
}

@test "a pick on the phone saves the turn the kiosk reads" {
  start
  [ "$(ask POST turn=left)" = "204 -" ]
  # shellcheck source=/dev/null
  source "$SHULPORTAL_LIB"
  [ "$(saved_turn "$SHULPORTAL_STATE/turn")" = left ]
}

@test "the phone and the TV's setup page read the turn back, with none when there isn't one" {
  start
  [ "$(HEADER=Access-Control-Allow-Origin ask GET)" = "200 none *" ]
  echo right > "$SHULPORTAL_STATE/turn"
  [ "$(ask GET)" = "200 right" ]
  echo sideways > "$SHULPORTAL_STATE/turn"
  [ "$(ask GET)" = "200 none" ]
}

@test "Horizontal forgets the turn" {
  echo right > "$SHULPORTAL_STATE/turn"
  start
  [ "$(HEADER=Access-Control-Allow-Origin ask POST turn=none)" = "204 - *" ]
  [ ! -e "$SHULPORTAL_STATE/turn" ]
  [ "$(ask POST turn=none)" = "204 -" ]
}

@test "anything but right, left or none is refused and changes nothing" {
  echo left > "$SHULPORTAL_STATE/turn"
  start
  [ "$(ask POST turn=upside-down)" = "400 -" ]
  [ "$(ask POST "turn=$(printf 'x%.0s' $(seq 80))")" = "400 -" ]
  [ "$(ask POST other=1)" = "400 -" ]
  [ "$(cat "$SHULPORTAL_STATE/turn")" = left ]
}

@test "off the hotspot nobody can change the turn, but the TV's setup page can still read it" {
  echo left > "$SHULPORTAL_STATE/turn"
  start 10.41.0.1
  [ "$(ask POST turn=right)" = "403 -" ]
  [ "$(cat "$SHULPORTAL_STATE/turn")" = left ]
  [ "$(ask GET)" = "200 left" ]
}

@test "only /turn is served" {
  start
  [ "$(ask GET "" /etc/passwd)" = "404 -" ]
}
