# MeshCore WiFi Firmware Builder

Builds and flashes [MeshCore](https://github.com/ripplebiz/MeshCore) companion radio firmware with Wi-Fi support for the **Heltec WiFi LoRa 32 V3** (ESP32-S3).

Your Wi-Fi credentials and LoRa region are baked into the firmware at build time. The output is a single merged binary ready to flash.

> **Warning:** Do not share `firmware-merged.bin` publicly — it contains your Wi-Fi credentials.

---

## Disclaimer

This script is provided **as-is, with no warranty of any kind**. By using it you accept full responsibility for whatever happens to your device, your network, or anything else. Flashing custom firmware carries inherent risk — you can brick your device, void your warranty, or cause other unintended consequences. I am not responsible for any damage, data loss, bricked hardware, or any other outcome resulting from the use of this script. If you don't know what you're doing, proceed with caution or don't proceed at all.

---

## Requirements

- Linux (any distro)
- [Docker](https://docs.docker.com/get-docker/) installed and running
- Internet connection (to pull the base image, clone MeshCore, and download PlatformIO toolchains)

That's it. Everything else — Python, PlatformIO, esptool, build tools — runs inside Docker and is cleaned up automatically when the build finishes.

---

## Usage

```bash
chmod +x buildFirmware.sh
./buildFirmware.sh
```

**Options:**
- `--commit COMMIT` or `-c COMMIT` — Build from a specific MeshCore commit (e.g. `e738a74`). If omitted, uses the latest commit from the repo.

The script is interactive. It will prompt you for:

1. **LoRa region** — select the frequency band for your country
2. **Wi-Fi SSID and password** — embedded into the firmware at compile time (password input is masked with asterisks)
3. **Confirmation** before the build starts
4. **Flash** — optionally flash directly to a connected device
5. **Full chip erase** — optionally wipe the device before flashing

The finished `firmware-merged.bin` is written to the directory you ran the script from.

---

## LoRa Regions

| # | Region | Frequency |
|---|--------|-----------|
| 1 | USA / Canada *(default)* | 910.525 MHz |
| 2 | USA / Canada (alternate 1) | 907.875 MHz |
| 3 | USA / Canada (alternate 2) | 927.875 MHz |
| 4 | Europe / UK | 869.525 MHz |
| 5 | Europe (alternate) | 868.731 MHz |
| 6 | Australia / New Zealand | 915.8 MHz |
| 7 | New Zealand (alternate) | 917.375 MHz |

> If you're unsure which to pick, go with option 1 for North America or option 4 for Europe and check with your local MeshCore network to confirm.

---

## What the Script Does

1. Checks that Docker is installed and the daemon is running
2. Prompts for region, Wi-Fi credentials, and optional commit hash
3. Builds a `python:3.12-slim`-based Docker image containing Python, git, PlatformIO, and esptool
4. Runs a container that:
   - Clones MeshCore (latest or pinned commit)
   - Patches `platformio.ini` with your Wi-Fi credentials and LoRa frequency
   - Compiles the firmware with PlatformIO
   - Merges `bootloader.bin`, `partitions.bin`, `boot_app0.bin`, and `firmware.bin` into a single `firmware-merged.bin` via esptool
   - Writes the merged binary to your working directory via a bind mount
5. Optionally flashes the device by passing the serial port into a second container with `--device`
6. Removes the Docker image and all temp files on exit (containers are auto-removed with `--rm`)

---

## Flashing Later

If you skipped flashing during the build, you can flash manually any time with esptool:

```bash
esptool --chip esp32s3 --port /dev/ttyUSB0 --baud 921600 write_flash 0x0 firmware-merged.bin
```

If the device doesn't respond, hold **BOOT** and press **RESET** to enter bootloader mode, then retry.

---

## Docker Permissions

If you get a "permission denied" error when the script tries to contact the Docker daemon, either:

```bash
# start the daemon (if it isn't running)
sudo systemctl start docker

# or add yourself to the docker group (requires logout/login)
sudo usermod -aG docker $USER
```

---

## MeshCore Version

By default the script builds from the latest commit on the MeshCore repo. To pin a specific commit (e.g. for reproducibility), use `--commit e738a74` or `-c e738a74`.
