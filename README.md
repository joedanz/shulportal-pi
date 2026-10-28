# ShulPortal Pi

A Raspberry Pi image that turns a **Raspberry Pi 4 or Pi 5** into a [ShulPortal](https://shulportal.com) lobby screen.
The image is the same for every shul. It opens `shulportal.com/tv`, which shows a short code; you link that code to one
of your shul's signs from ShulPortal, and the screen shows that sign from then on, through reboots and power cuts.

## Set up a screen

1. **Download** `shulportal-pi.rpi-imager-manifest` from the [latest release](https://github.com/joedanz/shulportal-pi/releases/latest)
   and open it in [Raspberry Pi Imager](https://www.raspberrypi.com/software/). Pick **ShulPortal Pi**, then your SD card.
   - Imager offers its settings screen. You can enter the shul's Wi-Fi there if you know it. That's optional.
   - You can also download the `.img.xz` and use **Use custom** in Imager (no settings screen then).
2. **Plug the Pi into the TV** and power it on.
   - **Ethernet:** nothing to set up. The TV shows a code.
   - **Wi-Fi you set in Imager:** the TV shows a code.
   - **No network yet:** after about 30 seconds the TV says *Connect your phone to Wi-Fi ShulPortal-Setup-XXXX* and shows a QR
     code. Scan it (or join that network), pick the shul's Wi-Fi on the page that opens, and enter its password. The TV then
     shows a code.
3. **Link it:** scan the QR code on the TV with your phone, or type the code into **Digital Signage → Set up a screen** in
   ShulPortal, and choose which sign it shows.

If the shul's Wi-Fi changes, the Pi brings the `ShulPortal-Setup-XXXX` network back after about 5 minutes without internet.
Set the new Wi-Fi the same way; no keyboard or re-flash needed.

To link a screen to a different sign, open ShulPortal on a phone, rotate that sign's key, and the TV shows a new code.

## What's on the image

- Raspberry Pi OS Lite (Trixie, 64-bit), with Chromium full screen in the `cage` compositor. No desktop, no cursor, no
  screen blanking, no "restore pages" bubble.
- [comitup](https://github.com/davesteele/comitup) for the setup hotspot. A small watchdog brings it back when the Pi is
  online on Wi-Fi without internet, and it stays off while Ethernet works.
- Security updates install every day (Debian security and Raspberry Pi's archive, which carries Chromium), and the Pi
  restarts around 4am in its time zone (America/New_York unless set in Imager).
- No login: SSH is off and the default account is locked.

## Development

- `bats tests/` runs the tests; CI also runs `shellcheck` on every script.
- The image is built by `.github/workflows/release.yml` with [pi-gen](https://github.com/RPi-Distro/pi-gen) (`arm64`
  branch) on GitHub's arm64 runner, using `config` and the custom stage in `stage-shulportal/`. A manual run of the
  workflow keeps the image as a workflow artifact; `scripts/check-image.sh` checks it before anything is published.
- **Release:** `git tag v1.0.1 && git push --tags`. The workflow publishes the `.img.xz`, its `.sha256` and the Imager
  manifest as a GitHub Release.
