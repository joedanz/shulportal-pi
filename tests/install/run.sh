#!/usr/bin/env bash
# ABOUTME: Installs and updates the real shulportal-pi package in a Debian trixie container (CI's install job):
# ABOUTME: setup state survives install, repeat and update, and shulportal-update installs a signed 9.0.1 from a stub.
set -euo pipefail
cd "$(dirname "$0")/../.."

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq openssl curl python3 ca-certificates >/dev/null

work=$(mktemp -d)
openssl genpkey -algorithm ed25519 -out "$work/key.pem"
openssl pkey -in "$work/key.pem" -pubout -out "$work/pub.pem"
scripts/build-deb.sh 9.0.0 "$work"
scripts/build-deb.sh 9.0.1 "$work"
scripts/sign-deb.sh "$work/shulportal-pi_9.0.1_all.deb" "$work/key.pem"

# A Pi that's been set up: comitup's id, and the kiosk's device id.
mkdir -p /var/lib/comitup /var/lib/shulportal
echo '{"id": "7A01"}' > /var/lib/comitup/comitup.json
echo 0123456789abcdef0123456789abcdef > /var/lib/shulportal/device-id
seeded() { sha256sum /var/lib/comitup/comitup.json /var/lib/shulportal/device-id; }
before=$(seeded)

apt-get install -y -qq "$work/shulportal-pi_9.0.0_all.deb" >/dev/null
/var/lib/dpkg/info/shulportal-pi.postinst configure
apt-get install -y -qq --reinstall "$work/shulportal-pi_9.0.0_all.deb" >/dev/null
[ "$(seeded)" = "$before" ] || { echo "FAIL: install touched setup state"; exit 1; }
[ "$(dpkg-divert --listpackage /etc/comitup.conf)" = shulportal-pi ] || { echo "FAIL: comitup.conf not diverted"; exit 1; }
grep -q 'ShulPortal-Setup-' /etc/comitup.conf || { echo "FAIL: /etc/comitup.conf isn't ours"; exit 1; }
# comitup's own copy is kept aside, when its package ships one.
if dpkg -L comitup | grep -qx /etc/comitup.conf; then
  [ -f /etc/comitup.conf.comitup ] || {
    echo "FAIL: comitup's own config is gone"
    dpkg-divert --list | grep comitup || true
    ls -la /etc/comitup* || true
    grep -n comitup.conf /var/lib/dpkg/info/comitup.conffiles /var/lib/dpkg/info/comitup.list 2>/dev/null || true
    grep -nE 'Unpacking|Setting up|Preparing' /var/log/dpkg.log /var/log/apt/term.log 2>/dev/null | grep -E 'comitup|shulportal' | head -20 || true
    exit 1
  }
fi
id kiosk >/dev/null || { echo "FAIL: no kiosk user"; exit 1; }

# An update from a stub shulportal.com, signed with the throwaway key.
cp "$work/shulportal-pi_9.0.0_all.deb" /var/lib/shulportal-update/current.deb
python3 -I tests/install/stub_server.py "$work" 8765 "$work/checks.log" &
server=$!
trap 'kill $server 2>/dev/null || true' EXIT
for _ in $(seq 50); do curl -s -o /dev/null http://127.0.0.1:8765/ && break; sleep 0.1; done
STUB_LOG=$work SHULPORTAL_API=http://127.0.0.1:8765 SHULPORTAL_RELEASE_KEY="$work/pub.pem" \
  SHULPORTAL_SYSTEMCTL="$PWD/tests/helpers/bin/systemctl" SHULPORTAL_REFRESH=/bin/true \
  /usr/local/bin/shulportal-update

# shellcheck disable=SC2016 # ${Version} is dpkg-query's format, not the shell's.
installed=$(dpkg-query -W -f='${Version}' shulportal-pi)
[ "$installed" = 9.0.1 ] || { echo "FAIL: installed $installed, not 9.0.1"; exit 1; }
grep -q '"version":"9.0.0"' "$work/checks.log" || { echo "FAIL: no check from 9.0.0"; cat "$work/checks.log"; exit 1; }
grep -qx reboot "$work/systemctl.log" || { echo "FAIL: no reboot"; cat "$work/systemctl.log"; exit 1; }
cmp -s /var/lib/shulportal-update/current.deb "$work/shulportal-pi_9.0.1_all.deb" || { echo "FAIL: current.deb isn't 9.0.1"; exit 1; }
[ "$(seeded)" = "$before" ] || { echo "FAIL: the update touched setup state"; exit 1; }
echo "install test: OK"
