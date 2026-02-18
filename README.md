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

The script is interactive. It will prompt you for:

1. **LoRa region** — select the frequency band for your country
2. **Wi-Fi SSID and password** — embedded into the firmware at compile time
3. **Confirmation** before the build starts
4. **Flash** — optionally flash directly to a connected device
5. **Full chip erase** — optionally wipe the device before flashing

The finished `firmware-merged.bin` is written to the directory you ran the script from.

---

## LoRa Regions

| # | Region | Frequency | Countries |
|---|--------|-----------|-----------|
| 1 | US915  | 915.0 MHz | USA, Canada, Mexico *(default)* |
| 2 | EU868  | 869.525 MHz | Europe |
| 3 | AU915  | 915.0 MHz | Australia, New Zealand |
| 4 | AS923  | 923.0 MHz | Japan, SE Asia |
| 5 | IN865  | 865.0 MHz | India |
| 6 | KR920  | 920.9 MHz | South Korea |
| 7 | RU868  | 868.9 MHz | Russia |

---

## What the Script Does

1. Installs missing system dependencies via the distro's package manager
2. Installs PlatformIO if not already present
3. Clones MeshCore (`e738a74`) to a temp directory under `/tmp`
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

## Pinned MeshCore Commit

The script builds from commit `e738a74` (MeshCore v1.12.0). To target a different commit, edit `MESHCORE_COMMIT` at the top of `buildFirmware.sh`.
