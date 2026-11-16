#!/usr/bin/env bats
# ABOUTME: Tests for the shulportal-pi Debian package: its control fields, that it carries every kiosk file,
# ABOUTME: and that its install scripts never undo a live Pi's setup. Build tests need dpkg-deb.

load helpers/common

ROOT="$BATS_TEST_DIRNAME/.."

build() {
  command -v dpkg-deb >/dev/null || skip "dpkg-deb not installed"
  "$ROOT/scripts/build-deb.sh" 1.2.3 "$BATS_TEST_TMPDIR/out" >/dev/null
  DEB="$BATS_TEST_TMPDIR/out/shulportal-pi_1.2.3_all.deb"
}

@test "the package carries the version, name and dependencies" {
  build
  [ "$(dpkg-deb -f "$DEB" Package)" = shulportal-pi ]
  [ "$(dpkg-deb -f "$DEB" Version)" = 1.2.3 ]
  [ "$(dpkg-deb -f "$DEB" Architecture)" = all ]
  depends=$(dpkg-deb -f "$DEB" Depends)
  for p in cage seatd chromium qrencode unattended-upgrades comitup curl openssl; do
    [[ ", $depends," == *", $p,"* ]] || { echo "missing $p in: $depends"; false; }
  done
}

@test "comitup is set up before the package unpacks, so its config is in place to divert" {
  build
  [ "$(dpkg-deb -f "$DEB" Pre-Depends)" = comitup ]
}

@test "the package holds every kiosk file, executable" {
  build
  contents=$(dpkg-deb -c "$DEB")
  [[ $(grep ' ./usr/local/bin/shulportal-kiosk$' <<<"$contents") == "-rwxr-xr-x root/root"* ]] || {
    grep shulportal-kiosk <<<"$contents"; false
  }
  while IFS= read -r f; do
    grep -q " \./${f#./}\$" <<<"$contents" || { echo "missing $f"; false; }
  done < <(cd "$FILES" && find . -type f)
}

@test "postinst never touches setup state" {
  [ -f "$ROOT/debian/postinst" ]
  run grep -nE 'comitup\.json|rm .*var/lib/shulportal' "$ROOT/debian/postinst"
  [ "$status" -eq 1 ]
}

# divert_calls SCRIPT ARG: runs a debian/ maintainer script with a dpkg-divert that only logs, and prints
# each path it was asked to divert ("DIVERTED.comitup DIVERTED" calls give DIVERTED).
divert_calls() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho "$@" >> "%s/divert.log"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/bin/dpkg-divert"
  chmod +x "$BATS_TEST_TMPDIR/bin/dpkg-divert"
  rm -f "$BATS_TEST_TMPDIR/divert.log"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" sh "$ROOT/debian/$1" "$2"
  awk '{print $NF}' "$BATS_TEST_TMPDIR/divert.log"
}

# The comitup pages the package replaces: every shipped .html in comitup's folder but our own shulportal-* parts.
shipped_pages() {
  (cd "$FILES" && find usr/share/comitup/web/templates -maxdepth 1 -name '*.html' ! -name 'shulportal-*' | sed 's|^|/|' | sort)
}

@test "preinst diverts comitup's config and exactly the Wi-Fi pages the package ships" {
  diverted=$(divert_calls preinst install)
  grep -qx /etc/comitup.conf <<<"$diverted"
  [ "$(grep -v '^/etc/' <<<"$diverted" | sort)" = "$(shipped_pages)" ] || {
    echo "diverted: $diverted"; echo "shipped: $(shipped_pages)"; false
  }
  [ "$(shipped_pages | wc -l)" -eq 3 ]
  grep -q -- '--add --rename --divert /usr/share/comitup/web/templates/index.html.comitup ' "$BATS_TEST_TMPDIR/divert.log"
}

@test "postrm gives comitup back everything preinst took" {
  taken=$(divert_calls preinst install)
  [ "$(divert_calls postrm remove)" = "$taken" ]
  [ "$(grep -c -- '--remove --rename' "$BATS_TEST_TMPDIR/divert.log")" -eq 4 ]
  [ -z "$(divert_calls postrm upgrade)" ]
}
