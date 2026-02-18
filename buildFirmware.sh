#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="Heltec_v3_companion_radio_wifi"
MESHCORE_REPO="https://github.com/ripplebiz/MeshCore.git"
MESHCORE_COMMIT="e738a74"
BUILD_DIR="/tmp/meshcore_build_$$"
ORIGINAL_PWD="$PWD"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}==== MeshCore WiFi Firmware Builder ====${NC}"
echo

install_dependencies() {
    echo -e "${YELLOW}Checking dependencies...${NC}"

    if command -v apt-get >/dev/null 2>&1; then
        echo "  Distro: Debian / Ubuntu (apt)"
        local pkgs=()
        for pkg in git python3 python3-pip python3-venv curl build-essential; do
            dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed" \
                || pkgs+=("$pkg")
        done
        if [ ${#pkgs[@]} -gt 0 ]; then
            echo "  Installing: ${pkgs[*]}"
            sudo apt-get update -qq
            sudo apt-get install -y "${pkgs[@]}"
        else
            echo -e "${GREEN}  All apt dependencies already installed.${NC}"
        fi

    elif command -v dnf >/dev/null 2>&1; then
        echo "  Distro: Fedora / RHEL (dnf)"
        local pkgs=()
        for pkg in git python3 python3-pip curl gcc make; do
            rpm -q "$pkg" >/dev/null 2>&1 || pkgs+=("$pkg")
        done
        if [ ${#pkgs[@]} -gt 0 ]; then
            echo "  Installing: ${pkgs[*]}"
            sudo dnf install -y "${pkgs[@]}"
        else
            echo -e "${GREEN}  All dnf dependencies already installed.${NC}"
        fi

    elif command -v yum >/dev/null 2>&1; then
        echo "  Distro: CentOS / RHEL (yum)"
        local pkgs=()
        for pkg in git python3 python3-pip curl gcc make; do
            rpm -q "$pkg" >/dev/null 2>&1 || pkgs+=("$pkg")
        done
        if [ ${#pkgs[@]} -gt 0 ]; then
            echo "  Installing: ${pkgs[*]}"
            sudo yum install -y "${pkgs[@]}"
        else
            echo -e "${GREEN}  All yum dependencies already installed.${NC}"
        fi

    elif command -v pacman >/dev/null 2>&1; then
        echo "  Distro: Arch Linux (pacman)"
        local pkgs=()
        for pkg in git python python-pip curl base-devel; do
            pacman -Qi "$pkg" >/dev/null 2>&1 || pkgs+=("$pkg")
        done
        if [ ${#pkgs[@]} -gt 0 ]; then
            echo "  Installing: ${pkgs[*]}"
            sudo pacman -Sy --noconfirm "${pkgs[@]}"
        else
            echo -e "${GREEN}  All pacman dependencies already installed.${NC}"
        fi

    else
        echo -e "${RED}Error: No supported package manager found (apt-get, dnf, yum, pacman).${NC}"
        exit 1
    fi
}

install_platformio() {
    if command -v pio >/dev/null 2>&1 || [ -x "$HOME/.platformio/penv/bin/pio" ]; then
        echo -e "${GREEN}PlatformIO already installed — skipping.${NC}"
        return
    fi

    echo -e "${YELLOW}Installing PlatformIO...${NC}"
    local installer="/tmp/get-platformio-$$.py"
    curl -fsSL -o "$installer" \
        https://raw.githubusercontent.com/platformio/platformio-core-installer/master/get-platformio.py
    python3 "$installer"
    rm -f "$installer"
    echo -e "${GREEN}  PlatformIO installed.${NC}"
}

install_esptool() {
    if python3 -m esptool version >/dev/null 2>&1 || command -v esptool.py >/dev/null 2>&1; then
        return
    fi

    echo -e "${YELLOW}Installing esptool...${NC}"
    if command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --noconfirm esptool
    elif command -v apt-get >/dev/null 2>&1; then
        sudo apt-get install -y esptool || pip3 install esptool
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y esptool 2>/dev/null || pip3 install esptool
    else
        pip3 install esptool
    fi
}

cleanup() {
    if [ -d "$BUILD_DIR" ]; then
        echo
        echo -e "${YELLOW}Cleaning up build directory...${NC}"
        rm -rf "$BUILD_DIR"
        echo -e "${GREEN}  Removed ${BUILD_DIR}${NC}"
    fi
    unset WIFI_SSID WIFI_PWD 2>/dev/null || true
}
trap cleanup EXIT

install_dependencies
echo
install_platformio

PIO_CMD="pio"
if ! command -v pio >/dev/null 2>&1; then
    if [ -x "$HOME/.platformio/penv/bin/pio" ]; then
        PIO_CMD="$HOME/.platformio/penv/bin/pio"
    else
        echo -e "${RED}Error: PlatformIO not found after installation.${NC}"
        echo "  Make sure ~/.platformio/penv/bin is in your PATH, or re-run this script."
        exit 1
    fi
fi

echo
echo "Select your LoRa region:"
echo "  1) US915  — USA, Canada, Mexico           (915.0 MHz)"
echo "  2) EU868  — Europe                        (869.525 MHz)"
echo "  3) AU915  — Australia, New Zealand        (915.0 MHz)"
echo "  4) AS923  — Asia (Japan, SE Asia, etc.)   (923.0 MHz)"
echo "  5) IN865  — India                         (865.0 MHz)"
echo "  6) KR920  — South Korea                   (920.9 MHz)"
echo "  7) RU868  — Russia                        (868.9 MHz)"
echo
read -rp "Region [1-7, default: 1]: " REGION_CHOICE
case "${REGION_CHOICE:-1}" in
    1) LORA_FREQ="915.0";   REGION_NAME="US915" ;;
    2) LORA_FREQ="869.525"; REGION_NAME="EU868" ;;
    3) LORA_FREQ="915.0";   REGION_NAME="AU915" ;;
    4) LORA_FREQ="923.0";   REGION_NAME="AS923" ;;
    5) LORA_FREQ="865.0";   REGION_NAME="IN865" ;;
    6) LORA_FREQ="920.9";   REGION_NAME="KR920" ;;
    7) LORA_FREQ="868.9";   REGION_NAME="RU868" ;;
    *)
        echo -e "${RED}Invalid selection.${NC}"
        exit 1
        ;;
esac
echo "  Region: $REGION_NAME ($LORA_FREQ MHz)"

echo
read -rp "Enter WiFi SSID: " WIFI_SSID
read -rsp "Enter WiFi Password: " WIFI_PWD
echo

echo "  SSID:   $WIFI_SSID"
echo "  Region: $REGION_NAME"
read -rp "Continue build? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo
echo -e "${YELLOW}Cloning MeshCore repository to ${BUILD_DIR}...${NC}"
mkdir -p "$BUILD_DIR"
git clone "$MESHCORE_REPO" "$BUILD_DIR/MeshCore"
cd "$BUILD_DIR/MeshCore"

echo -e "${YELLOW}Checking out commit ${MESHCORE_COMMIT}...${NC}"
git checkout --detach "$MESHCORE_COMMIT"

PLATFORMIO_INI="variants/heltec_v3/platformio.ini"
if [ ! -f "$PLATFORMIO_INI" ]; then
    echo -e "${RED}Error: ${PLATFORMIO_INI} not found in cloned repository.${NC}"
    exit 1
fi

echo -e "${YELLOW}Embedding Wi-Fi credentials...${NC}"
WIFI_SSID="$WIFI_SSID" WIFI_PWD="$WIFI_PWD" python3 - "$PLATFORMIO_INI" <<'PYEOF'
import os, sys
path = sys.argv[1]
ssid = os.environ["WIFI_SSID"]
pwd  = os.environ["WIFI_PWD"]
with open(path, "r") as f:
    content = f.read()
content = content.replace("myssid", ssid).replace("mypwd", pwd)
with open(path, "w") as f:
    f.write(content)
PYEOF

echo -e "${YELLOW}Setting LoRa region: ${REGION_NAME} (${LORA_FREQ} MHz)...${NC}"
LORA_FREQ="$LORA_FREQ" python3 - "platformio.ini" <<'PYEOF'
import os, sys, re
path = sys.argv[1]
freq = os.environ["LORA_FREQ"]
with open(path, "r") as f:
    content = f.read()
content = re.sub(r'-D LORA_FREQ=[\d.]+', f'-D LORA_FREQ={freq}', content)
with open(path, "w") as f:
    f.write(content)
PYEOF

unset WIFI_PWD

echo
echo -e "${YELLOW}Building firmware (this may take a while)...${NC}"
"$PIO_CMD" run -e "$ENV_NAME"

BUILD_OUT=".pio/build/${ENV_NAME}"
if [ ! -f "${BUILD_OUT}/firmware.bin" ]; then
    echo
    echo -e "${RED}Build finished, but firmware.bin was not found.${NC}"
    echo "  Expected: $BUILD_DIR/MeshCore/${BUILD_OUT}/firmware.bin"
    echo "  Build output directory contents:"
    ls -la "${BUILD_OUT}/" 2>/dev/null || echo "  (directory not found)"
    exit 1
fi

install_esptool

ESPTOOL="python3 -m esptool"
if command -v esptool.py >/dev/null 2>&1; then
    ESPTOOL="esptool.py"
fi

BOOT_APP0=$(find "${HOME}/.platformio/packages/framework-arduinoespressif32" \
    -name "boot_app0.bin" 2>/dev/null | head -1)
if [ -z "$BOOT_APP0" ]; then
    echo -e "${RED}Error: boot_app0.bin not found in PlatformIO packages.${NC}"
    exit 1
fi

echo
echo -e "${YELLOW}Merging bootloader + partitions + boot_app0 + firmware...${NC}"
$ESPTOOL --chip esp32s3 merge-bin \
    --output "${ORIGINAL_PWD}/firmware-merged.bin" \
    0x00000 "${BUILD_OUT}/bootloader.bin" \
    0x08000 "${BUILD_OUT}/partitions.bin" \
    0x0e000 "$BOOT_APP0" \
    0x10000 "${BUILD_OUT}/firmware.bin"

echo
echo -e "${GREEN}Build successful!${NC}"
echo "  Merged firmware → ${ORIGINAL_PWD}/firmware-merged.bin"

echo
read -rp "Flash firmware to device now? (y/N): " FLASH_CONFIRM
if [[ ! "$FLASH_CONFIRM" =~ ^[Yy]$ ]]; then
    echo
    echo -e "${GREEN}Firmware already saved to:${NC} ${ORIGINAL_PWD}/firmware-merged.bin"
    echo
    echo -e "${GREEN}Done.${NC}"
    exit 0
fi

echo
echo -e "${YELLOW}Detecting serial ports...${NC}"
PORTS=()
for p in /dev/ttyUSB* /dev/ttyACM* /dev/tty.usbserial* /dev/tty.usbmodem*; do
    [ -e "$p" ] && PORTS+=("$p")
done

if [ ${#PORTS[@]} -eq 0 ]; then
    echo -e "${RED}No serial ports detected. Is the device plugged in?${NC}"
    echo "  Firmware is still available at: ${ORIGINAL_PWD}/firmware-merged.bin"
    exit 1
elif [ ${#PORTS[@]} -eq 1 ]; then
    FLASH_PORT="${PORTS[0]}"
    echo "  Auto-selected port: $FLASH_PORT"
else
    echo "  Available ports:"
    for i in "${!PORTS[@]}"; do
        echo "    $((i+1))) ${PORTS[$i]}"
    done
    read -rp "  Select port number [1-${#PORTS[@]}]: " PORT_NUM
    PORT_IDX=$((PORT_NUM - 1))
    if [ "$PORT_IDX" -lt 0 ] || [ "$PORT_IDX" -ge "${#PORTS[@]}" ]; then
        echo -e "${RED}Invalid selection.${NC}"
        exit 1
    fi
    FLASH_PORT="${PORTS[$PORT_IDX]}"
fi

echo
read -rp "Full chip erase before flashing? Clears all settings/config (y/N): " ERASE_CONFIRM

echo
echo -e "${YELLOW}  If the device doesn't respond, hold BOOT and press RESET, then retry.${NC}"
echo

if [[ "$ERASE_CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Erasing flash on ${FLASH_PORT}...${NC}"
    $ESPTOOL --chip esp32s3 --port "$FLASH_PORT" --baud 921600 erase_flash
    echo
    echo -e "${GREEN}Erase complete.${NC}"
    echo
fi

echo -e "${YELLOW}Flashing to ${FLASH_PORT}...${NC}"
$ESPTOOL \
    --chip esp32s3 \
    --port "$FLASH_PORT" \
    --baud 921600 \
    write_flash 0x0 "${ORIGINAL_PWD}/firmware-merged.bin"

echo
echo -e "${GREEN}Flash complete!${NC}"
echo
echo -e "${GREEN}Done.${NC}"
