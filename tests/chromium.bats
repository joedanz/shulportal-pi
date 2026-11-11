#!/usr/bin/env bats
# ABOUTME: Tests for the Chromium list: which builds the apt pin blocks, and putting a named build back
# ABOUTME: (downloaded from the archive's pool and checked by hash) when the installed one is blocked.

load helpers/common

GOOD=156.0.8078.79-1~deb13u1+rpt1

setup() {
  common_setup
  # shellcheck source=/dev/null
  source "$SHULPORTAL_LIB"
  export SHULPORTAL_PIN_FILE="$FILES/etc/apt/preferences.d/shulportal-chromium"
  export SHULPORTAL_POOL=https://pool.test/c/chromium
  # A fallback list for test files, with their real hashes.
  local fb="$BATS_TEST_TMPDIR/fallback" n
  echo "version $GOOD" > "$fb"
  for n in "chromium_${GOOD}_arm64.deb" "chromium-common_${GOOD}_arm64.deb" "chromium-l10n_${GOOD}_all.deb"; do
    echo "file $n" > "$STUB_FILES/$n"
    (cd "$STUB_FILES" && shasum -a 256 "$n" 2>/dev/null || sha256sum "$n") >> "$fb"
  done
  export SHULPORTAL_CHROMIUM_FALLBACK="$fb"
}

check() { run "$SHULPORTAL_BIN/shulportal-chromium-check"; }

@test "chromium_blocked matches the pinned build only" {
  chromium_blocked 1:156.0.8078.73-1~deb13u1+rpt1 "$SHULPORTAL_PIN_FILE"
  run chromium_blocked "1:$GOOD" "$SHULPORTAL_PIN_FILE"
  [ "$status" -eq 1 ]
}

@test "a blocked Chromium gets the named build, checked" {
  export STUB_CHROMIUM_VERSION=1:156.0.8078.73-1~deb13u1+rpt1
  check
  [ "$status" -eq 0 ]
  for n in "chromium_${GOOD}_arm64.deb" "chromium-common_${GOOD}_arm64.deb" "chromium-l10n_${GOOD}_all.deb"; do
    [[ $(logged curl) == *"https://pool.test/c/chromium/$n"* ]] || { echo "not fetched: $n"; false; }
  done
  [[ $(logged apt-get) == "-o DPkg::Lock::Timeout=600 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "* ]] || false
  [ "$(logged apt-env)" = noninteractive ]
  [[ $(logged apt-get) == *"install -y --allow-downgrades "*"chromium_${GOOD}_arm64.deb "*"chromium-common_${GOOD}_arm64.deb "*"chromium-l10n_${GOOD}_all.deb" ]] || false
}

@test "a hash mismatch installs nothing and fails with the reason" {
  export STUB_CHROMIUM_VERSION=1:156.0.8078.73-1~deb13u1+rpt1
  echo tampered > "$STUB_FILES/chromium-common_${GOOD}_arm64.deb"
  check
  [ "$status" -eq 1 ]
  [ -z "$(logged apt-get)" ]
  [ "${lines[${#lines[@]}-1]}" = "Couldn't put Chromium back to $GOOD." ]
}

@test "a failed download installs nothing and fails with the reason" {
  export STUB_CHROMIUM_VERSION=1:156.0.8078.73-1~deb13u1+rpt1
  rm "$STUB_FILES/chromium-l10n_${GOOD}_all.deb"
  check
  [ "$status" -eq 1 ]
  [ -z "$(logged apt-get)" ]
  [ "${lines[${#lines[@]}-1]}" = "Couldn't put Chromium back to $GOOD." ]
}

@test "Chromium that isn't blocked is left alone" {
  export STUB_CHROMIUM_VERSION="1:$GOOD"
  check
  [ "$status" -eq 0 ]
  [ -z "$(logged curl)" ]
  [ -z "$(logged apt-get)" ]
}

@test "the shipped fallback names three files, and isn't itself blocked" {
  fb="$FILES/usr/local/share/shulportal/chromium-fallback"
  v=$(sed -n '1s/^version //p' "$fb")
  [ -n "$v" ]
  run chromium_blocked "1:$v" "$SHULPORTAL_PIN_FILE"
  [ "$status" -eq 1 ]
  [ "$(sed -n '2,$p' "$fb" | grep -cE '^[0-9a-f]{64}  chromium(-common|-l10n)?_.*\.deb$')" = 3 ]
}
