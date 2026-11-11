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

@test "preinst diverts comitup's config" {
  grep -q 'dpkg-divert --package shulportal-pi --add --rename --divert /etc/comitup.conf.comitup /etc/comitup.conf' "$ROOT/debian/preinst"
}

@test "postrm gives comitup its config back when the package goes" {
  grep -q 'dpkg-divert --package shulportal-pi --remove --rename --divert /etc/comitup.conf.comitup /etc/comitup.conf' "$ROOT/debian/postrm"
}
