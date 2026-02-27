# MeshCore WiFi Firmware Builder

Builds and flashes [MeshCore](https://github.com/ripplebiz/MeshCore) companion radio firmware with Wi-Fi support for the **Heltec WiFi LoRa 32 V3** (ESP32-S3).

Your Wi-Fi credentials and LoRa region are baked into the firmware at build time. The output is a single merged binary ready to flash.

> **Warning:** Do not share `firmware-merged.bin` publicly — it contains your Wi-Fi credentials.

---

## Disclaimer

This script is provided **as-is, with no warranty of any kind**. By using it you accept full responsibility for whatever happens to your device, your network, or anything else. Flashing custom firmware carries inherent risk — you can brick your device, void your warranty, or cause other unintended consequences. I am not responsible for any damage, data loss, bricked hardware, or any other outcome resulting from the use of this script. If you don't know what you're doing, proceed with caution or don't proceed at all.

---

## Requirements

- Linux (Debian/Ubuntu, Fedora/RHEL, CentOS, or Arch)
- `sudo` access (for installing packages)
- Internet connection (to clone MeshCore and install tools)

All other dependencies (PlatformIO, esptool, etc.) are installed automatically.

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

1. Installs missing system dependencies via the distro's package manager
2. Installs PlatformIO if not already present
3. Clones MeshCore (latest commit by default, or the one specified with `--commit`) to a temp directory under `/tmp`
4. Patches `platformio.ini` with your Wi-Fi credentials and selected LoRa frequency
5. Builds the firmware with PlatformIO
6. Merges `bootloader.bin`, `partitions.bin`, `boot_app0.bin`, and `firmware.bin` into a single `firmware-merged.bin` using esptool
7. Copies the merged binary to your working directory
8. Optionally flashes the device over serial
9. Cleans up all temp files

---

## Flashing Later

If you skipped flashing during the build, you can flash manually any time:

```bash
esptool --chip esp32s3 --port /dev/ttyUSB0 --baud 921600 write_flash 0x0 firmware-merged.bin
```

If the device doesn't respond, hold **BOOT** and press **RESET** to enter bootloader mode, then retry.

---

## Supported Distros

| Distro | Package Manager |
|--------|----------------|
| Debian / Ubuntu | apt |
| Fedora / RHEL | dnf |
| CentOS / RHEL (older) | yum |
| Arch Linux | pacman |

---

## MeshCore Version

By default the script builds from the latest commit on the MeshCore repo. To pin a specific commit (e.g. for reproducibility), use `--commit e738a74` or `-c e738a74`.
