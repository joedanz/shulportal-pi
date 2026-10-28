# shellcheck shell=bash
# ABOUTME: Shared bats setup: a temp root with the image's paths, stub commands and their logs.
# ABOUTME: Scripts under test read every path from SHULPORTAL_* variables pointed here.

FILES="$BATS_TEST_DIRNAME/../stage-shulportal/01-shulportal/files"

common_setup() {
  export STUB_LOG="$BATS_TEST_TMPDIR/log"
  mkdir -p "$STUB_LOG"
  export SHULPORTAL_LIB="$FILES/usr/local/lib/shulportal/lib.sh"
  export SHULPORTAL_SHARE="$FILES/usr/local/share/shulportal"
  export SHULPORTAL_BIN="$FILES/usr/local/bin"
  export SHULPORTAL_RUN="$BATS_TEST_TMPDIR/run"
  export SHULPORTAL_PROFILE="$BATS_TEST_TMPDIR/profile"
  export SHULPORTAL_SERIAL_FILE="$BATS_TEST_TMPDIR/serial-number"
  export SHULPORTAL_COMITUP_JSON="$BATS_TEST_TMPDIR/comitup.json"
  export SHULPORTAL_NMCLI="$BATS_TEST_DIRNAME/helpers/bin/nmcli"
  export SHULPORTAL_SYSTEMCTL="$BATS_TEST_DIRNAME/helpers/bin/systemctl"
  export SHULPORTAL_CHROMIUM="$BATS_TEST_DIRNAME/helpers/bin/chromium"
  mkdir -p "$SHULPORTAL_RUN"
  printf '10000000a1b2c3d4\0' > "$SHULPORTAL_SERIAL_FILE"
}

logged() { cat "$STUB_LOG/$1.log" 2>/dev/null || true; }
