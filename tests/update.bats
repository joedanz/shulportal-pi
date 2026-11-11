#!/usr/bin/env bats
# ABOUTME: Tests for remote updates: the version and reply checks in lib.sh, and shulportal-update's check,
# ABOUTME: signed download, install, rollback and failure report, with curl, apt and dpkg stubbed out.

load helpers/common

ID=0123456789abcdef0123456789abcdef

setup() {
  common_setup
  # shellcheck source=/dev/null
  source "$SHULPORTAL_LIB"
  export SHULPORTAL_UPDATE_DIR="$BATS_TEST_TMPDIR/update"
  export SHULPORTAL_API=https://shulportal.test
  mkdir -p "$SHULPORTAL_UPDATE_DIR"
  echo "$ID" > "$SHULPORTAL_STATE/device-id"
  echo "old package" > "$SHULPORTAL_UPDATE_DIR/current.deb"
}

update() { run "$SHULPORTAL_BIN/shulportal-update"; }

# A throwaway signing key, and a release VERSION signed by it (or by another key with "badsig").
release() {
  openssl pkey -help 2>&1 | grep -q . || skip "no openssl"
  local k="$BATS_TEST_TMPDIR/key.pem" deb="$STUB_FILES/shulportal-pi_$1_all.deb"
  openssl genpkey -algorithm ed25519 -out "$k" 2>/dev/null
  openssl pkey -in "$k" -pubout -out "$BATS_TEST_TMPDIR/pub.pem"
  export SHULPORTAL_RELEASE_KEY="$BATS_TEST_TMPDIR/pub.pem"
  echo "package $1" > "$deb"
  if [ "${2:-}" = badsig ]; then openssl genpkey -algorithm ed25519 -out "$k" 2>/dev/null; fi
  openssl pkeyutl -sign -inkey "$k" -rawin -in "$deb" -out "$deb.sig" 2>/dev/null || skip "openssl can't sign ed25519 with -rawin"
  export STUB_REPLY="{\"install\":\"$1\"}"
}

# --- lib ---------------------------------------------------------------------------------------------

@test "version_gt compares numerically, with no octal surprises" {
  version_gt 1.10.0 1.9.9
  ! version_gt 1.1.0 1.1.0
  run version_gt 1.1.0 1.1.0
  [ "$status" -ne 0 ]
  version_gt 1.08.0 1.7.0
  run version_gt 1.0.9 1.1.0
  [ "$status" -ne 0 ]
}

@test "install_target takes only a newer x.y.z" {
  [ "$(install_target '{"install":"1.1.1"}' 1.1.0)" = 1.1.1 ]
  for reply in '{}' '<!doctype html>' '{"install":"1.1.0"}' '{"install":"0.9.0"}' \
    '{"install":"1.1.1;rm -rf /"}' '{"install":"v1.2.0"}' '{"install":"1.2"}' ''; do
    [ -z "$(install_target "$reply" 1.1.0)" ] || { echo "took: $reply"; false; }
  done
}

@test "install_target never installs on a Pi whose own version isn't x.y.z" {
  [ -z "$(install_target '{"install":"1.1.1"}' 0.0.0+dev.abc1234)" ]
}

@test "check_body writes the check, with or without a failure" {
  [ "$(check_body "$ID" 1.1.0)" = "{\"device\":\"$ID\",\"version\":\"1.1.0\"}" ]
  [ "$(check_body "$ID" 1.1.0 1.1.1 'The download didn"t "finish\.')" = \
    "{\"device\":\"$ID\",\"version\":\"1.1.0\",\"failed\":{\"version\":\"1.1.1\",\"reason\":\"The download didnt finish.\"}}" ]
}

# --- the updater -------------------------------------------------------------------------------------

@test "posts to shulportal.com by default" {
  unset SHULPORTAL_API
  update
  [ "$status" -eq 0 ]
  [[ $(logged curl) == *"https://shulportal.com/api/pi/check"* ]] || false
  [ "$(logged check)" = "{\"device\":\"$ID\",\"version\":\"1.1.0\"}" ]
}

@test "a Pi on a dev version reports 0.0.0 and installs nothing" {
  export STUB_PI_VERSION=0.0.0+dev.abc1234 STUB_REPLY='{"install":"1.1.1"}'
  update
  [ "$status" -eq 0 ]
  [[ $(logged check) == *'"version":"0.0.0"'* ]] || false
  [ -z "$(logged apt-get)" ]
}

@test "no device id yet: does nothing" {
  rm "$SHULPORTAL_STATE/device-id"
  update
  [ "$status" -eq 0 ]
  [ -z "$(logged curl)" ]
}

@test "a malformed device id: does nothing" {
  echo nope > "$SHULPORTAL_STATE/device-id"
  update
  [ "$status" -eq 0 ]
  [ -z "$(logged curl)" ]
}

@test "offline: exits quietly" {
  export STUB_CURL_OFFLINE=yes
  update
  [ "$status" -eq 0 ]
  [ -z "$(logged apt-get)" ]
}

@test "an install downloads both files from the fixed path, checks them, installs, keeps the package and reboots" {
  release 1.1.1
  update
  [ "$status" -eq 0 ]
  [[ $(logged curl) == *"https://shulportal.test/api/pi/release/1.1.1/shulportal-pi_1.1.1_all.deb"* ]] || false
  [[ $(logged curl) == *"https://shulportal.test/api/pi/release/1.1.1/shulportal-pi_1.1.1_all.deb.sig"* ]] || false
  [[ $(logged apt-get) == "-o DPkg::Lock::Timeout=600 install -y $SHULPORTAL_UPDATE_DIR/incoming/shulportal-pi_1.1.1_all.deb" ]] || false
  [ "$(cat "$SHULPORTAL_UPDATE_DIR/current.deb")" = "package 1.1.1" ]
  [ "$(logged chromium-check)" = ran ]
  [ "$(logged systemctl)" = "restart shulportal-kiosk
reboot" ]
  # The kiosk was shown the updating page, and stays there until the reboot.
  [ "$(cat "$SHULPORTAL_RUN/page")" = updating ]
  [ -e "$SHULPORTAL_RUN/installing" ]
}

@test "a bad signature installs nothing, reports, and never takes over the screen" {
  release 1.1.1 badsig
  echo online > "$SHULPORTAL_RUN/page"
  update
  [ "$status" -eq 0 ]
  [ -z "$(logged apt-get)" ]
  [ -z "$(logged systemctl)" ]
  [ -z "$(logged refresh)" ]
  [ "$(cat "$SHULPORTAL_RUN/page")" = online ]
  [ "$(tail -n1 "$STUB_LOG/check.log")" = \
    "{\"device\":\"$ID\",\"version\":\"1.1.0\",\"failed\":{\"version\":\"1.1.1\",\"reason\":\"The download's signature didn't check out.\"}}" ]
  [ ! -e "$SHULPORTAL_RUN/installing" ]
  [ "$(cat "$SHULPORTAL_UPDATE_DIR/current.deb")" = "old package" ]
}

@test "a missing download installs nothing and says so" {
  export STUB_REPLY='{"install":"1.1.1"}'
  update
  [ "$status" -eq 0 ]
  [ -z "$(logged apt-get)" ]
  [[ $(tail -n1 "$STUB_LOG/check.log") == *'"reason":"The download didn'"'"'t finish."'* ]] || false
}

@test "a package that isn't the version asked for installs nothing" {
  release 1.1.1
  export STUB_DEB_VERSION=1.1.2
  update
  [ -z "$(logged apt-get)" ]
  [[ $(tail -n1 "$STUB_LOG/check.log") == *"The download wasn't the version asked for."* ]] || false
}

@test "a failed install puts the old package back" {
  release 1.1.1
  export STUB_APT_FAIL=shulportal-pi_1.1.1_all.deb
  update
  [ "$status" -eq 0 ]
  [[ $(logged dpkg) == "--configure -a" ]] || false
  [[ $(logged apt-get) == *"install -y --reinstall --allow-downgrades $SHULPORTAL_UPDATE_DIR/current.deb"* ]] || false
  [[ $(tail -n1 "$STUB_LOG/check.log") == *'"reason":"Installing the new version failed."'* ]] || false
  [ "$(cat "$SHULPORTAL_UPDATE_DIR/current.deb")" = "old package" ]
  [[ $(logged systemctl) != *reboot* ]] || false
  # The screen was taken for the install, and is given back with the page cleared for refresh to choose.
  [ "$(logged refresh-state)" = "page= installing=no" ]
}

@test "a failed Chromium check puts the old package back" {
  release 1.1.1
  export STUB_CHROMIUM_CHECK_EXIT=1
  update
  [ "$status" -eq 0 ]
  [[ $(logged apt-get) == *"--allow-downgrades $SHULPORTAL_UPDATE_DIR/current.deb"* ]] || false
  [[ $(tail -n1 "$STUB_LOG/check.log") == *"\"reason\":\"Couldn't put Chromium back to 156.0.8078.79-1~deb13u1+rpt1.\""* ]] || false
  [[ $(logged systemctl) != *reboot* ]] || false
}

@test "a failure that couldn't be reported goes with the next check, then is dropped" {
  release 1.1.1 badsig
  # The report after the failure can't get through.
  cat > "$BATS_TEST_TMPDIR/flaky-curl" <<SH
#!/usr/bin/env bash
if [[ \$* == *"failed"* ]] && [ ! -e "$BATS_TEST_TMPDIR/back-online" ]; then exit 6; fi
exec "$STUB_BIN/curl" "\$@"
SH
  chmod +x "$BATS_TEST_TMPDIR/flaky-curl"
  export SHULPORTAL_CURL="$BATS_TEST_TMPDIR/flaky-curl"
  update
  [ -s "$SHULPORTAL_UPDATE_DIR/failed" ]
  touch "$BATS_TEST_TMPDIR/back-online"
  export STUB_REPLY='{}'
  update
  [[ $(tail -n1 "$STUB_LOG/check.log") == *'"failed":{"version":"1.1.1"'* ]] || false
  [ ! -e "$SHULPORTAL_UPDATE_DIR/failed" ]
  update
  [ "$(tail -n1 "$STUB_LOG/check.log")" = "{\"device\":\"$ID\",\"version\":\"1.1.0\"}" ]
}

@test "the updater runs every 5 minutes, as a one-shot with time to install" {
  t="$FILES/etc/systemd/system/shulportal-update.timer"
  s="$FILES/etc/systemd/system/shulportal-update.service"
  grep -qx 'OnBootSec=1min' "$t"
  grep -qx 'OnUnitActiveSec=5min' "$t"
  grep -qx 'RandomizedDelaySec=30s' "$t"
  grep -qx 'Type=oneshot' "$s"
  grep -qx 'TimeoutStartSec=30min' "$s"
  grep -qx 'ExecStart=/usr/local/bin/shulportal-update' "$s"
  grep -q 'shulportal-update.timer' "$BATS_TEST_DIRNAME/../debian/postinst"
}
