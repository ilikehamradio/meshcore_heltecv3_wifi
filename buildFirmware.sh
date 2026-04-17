#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

IMAGE_TAG="meshcore-pio-builder:$$"
DOCKER_CTX="/tmp/meshcore_docker_$$"
ORIGINAL_PWD="$PWD"
MESHCORE_COMMIT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --commit|--c|-c)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --commit requires a value"
                echo "Usage: $0 [--commit COMMIT]"
                exit 1
            fi
            MESHCORE_COMMIT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--commit COMMIT]"
            exit 1
            ;;
    esac
done

cleanup() {
    echo
    echo -e "${YELLOW}Cleaning up...${NC}"
    if docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
        docker rmi "$IMAGE_TAG" >/dev/null 2>&1 \
            && echo -e "${GREEN}  Removed Docker image: ${IMAGE_TAG}${NC}" \
            || echo -e "${RED}  Failed to remove image: ${IMAGE_TAG}${NC}"
    fi
    rm -rf "$DOCKER_CTX"
    unset WIFI_SSID WIFI_PWD 2>/dev/null || true
}
trap cleanup EXIT

check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}Error: docker is required but not installed.${NC}"
        echo "  Install Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
    if ! docker info >/dev/null 2>&1; then
        echo -e "${RED}Error: Docker daemon is not running or you lack permission.${NC}"
        echo "  Try:  sudo systemctl start docker"
        echo "  Or:   sudo usermod -aG docker \$USER  (then log out and back in)"
        exit 1
    fi
}

echo -e "${BLUE}==== MeshCore WiFi Firmware Builder (Docker) ====${NC}"
echo

check_docker

echo "Select your LoRa region:"
echo "  1) USA / Canada                (910.525 MHz)"
echo "  2) USA / Canada (alternate 1)  (907.875 MHz)"
echo "  3) USA / Canada (alternate 2)  (927.875 MHz)"
echo "  4) Europe / UK                 (869.525 MHz)"
echo "  5) Europe (alternate)          (868.731 MHz)"
echo "  6) Australia / New Zealand     (915.8 MHz)"
echo "  7) New Zealand (alternate)     (917.375 MHz)"
echo
read -rp "Region [1-7, default: 1]: " REGION_CHOICE
case "${REGION_CHOICE:-1}" in
    1) LORA_FREQ="910.525";     LORA_BW="250"; LORA_SF="11"; REGION_NAME="USA/Canada" ;;
    2) LORA_FREQ="907.875";     LORA_BW="250"; LORA_SF="11"; REGION_NAME="USA/Canada (alt 1)" ;;
    3) LORA_FREQ="927.875";     LORA_BW="250"; LORA_SF="11"; REGION_NAME="USA/Canada (alt 2)" ;;
    4) LORA_FREQ="869.525";     LORA_BW="250"; LORA_SF="11"; REGION_NAME="Europe/UK" ;;
    5) LORA_FREQ="868.731018";  LORA_BW="250"; LORA_SF="11"; REGION_NAME="Europe (alt)" ;;
    6) LORA_FREQ="915.8";       LORA_BW="250"; LORA_SF="11"; REGION_NAME="Australia/NZ" ;;
    7) LORA_FREQ="917.375";     LORA_BW="250"; LORA_SF="11"; REGION_NAME="New Zealand (alt)" ;;
    *)
        echo -e "${RED}Invalid selection.${NC}"
        exit 1
        ;;
esac
echo "  Region: $REGION_NAME ($LORA_FREQ MHz, BW=${LORA_BW} kHz, SF=${LORA_SF})"

echo
read -rp "Enter WiFi SSID: " WIFI_SSID
printf "Enter WiFi Password: "
WIFI_PWD=""
while IFS= read -r -n 1 -s char; do
    if [[ -z "$char" ]]; then
        break
    elif [[ "$char" == $'\x7f' || "$char" == $'\b' ]]; then
        if [[ -n "$WIFI_PWD" ]]; then
            WIFI_PWD="${WIFI_PWD:0:-1}"
            printf '\b \b'
        fi
    else
        WIFI_PWD+="$char"
        printf '*'
    fi
done
echo
echo

echo "  SSID:   $WIFI_SSID"
echo "  Region: $REGION_NAME"
if [ -n "$MESHCORE_COMMIT" ]; then
    echo "  Commit: $MESHCORE_COMMIT"
else
    echo "  Commit: latest"
fi
read -rp "Continue build? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# ---------------------------------------------------------------------------
# Write Docker build context
# ---------------------------------------------------------------------------
mkdir -p "$DOCKER_CTX"

cat > "$DOCKER_CTX/Dockerfile" <<'DOCKERFILE_EOF'
FROM python:3.12-slim
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends git curl build-essential && \
    rm -rf /var/lib/apt/lists/*
RUN pip install --quiet platformio esptool
COPY build_inner.sh /build_inner.sh
RUN chmod +x /build_inner.sh
ENTRYPOINT ["/build_inner.sh"]
DOCKERFILE_EOF

# Single-quoted delimiter so nothing inside is expanded by the outer shell;
# the inner script's own $VAR references are resolved at container runtime.
cat > "$DOCKER_CTX/build_inner.sh" <<'INNER_EOF'
#!/usr/bin/env bash
set -euo pipefail

MESHCORE_REPO="https://github.com/ripplebiz/MeshCore.git"
ENV_NAME="Heltec_v3_companion_radio_wifi"
BUILD_DIR="/tmp/meshcore_build"
PLATFORMIO_INI="variants/heltec_v3/platformio.ini"

if [ -z "${MESHCORE_COMMIT:-}" ]; then
    echo "Fetching latest MeshCore commit..."
    MESHCORE_COMMIT=$(git ls-remote "$MESHCORE_REPO" refs/heads/main | cut -f1)
    echo "  Using latest: $MESHCORE_COMMIT"
else
    echo "  Using commit: $MESHCORE_COMMIT"
fi

echo "Cloning MeshCore..."
git clone "$MESHCORE_REPO" "$BUILD_DIR"
cd "$BUILD_DIR"
git checkout --detach "$MESHCORE_COMMIT"

if [ ! -f "$PLATFORMIO_INI" ]; then
    echo "Error: ${PLATFORMIO_INI} not found in cloned repository."
    exit 1
fi

echo "Embedding Wi-Fi credentials..."
python3 - "$PLATFORMIO_INI" <<'PYEOF'
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

echo "Setting LoRa region..."
python3 - "$PLATFORMIO_INI" <<'PYEOF'
import os, sys, re
path = sys.argv[1]
freq = os.environ["LORA_FREQ"]
bw   = os.environ["LORA_BW"]
sf   = os.environ["LORA_SF"]
with open(path, "r") as f:
    content = f.read()
content = re.sub(r'-D LORA_FREQ=[\d.]+', f'-D LORA_FREQ={freq}', content)
content = re.sub(r'-D LORA_BW=[\d.]+',   f'-D LORA_BW={bw}',     content)
content = re.sub(r'-D LORA_SF=[\d.]+',   f'-D LORA_SF={sf}',     content)
with open(path, "w") as f:
    f.write(content)
PYEOF

unset WIFI_PWD

echo "Building firmware (this may take a while on first run)..."
pio run -e "$ENV_NAME"

BUILD_OUT=".pio/build/${ENV_NAME}"
if [ ! -f "${BUILD_OUT}/firmware.bin" ]; then
    echo "Build finished but firmware.bin was not found."
    ls -la "${BUILD_OUT}/" 2>/dev/null || echo "(directory not found)"
    exit 1
fi

BOOT_APP0=$(find /root/.platformio/packages/framework-arduinoespressif32 \
    -name "boot_app0.bin" 2>/dev/null | head -1)
if [ -z "$BOOT_APP0" ]; then
    echo "Error: boot_app0.bin not found in PlatformIO packages."
    exit 1
fi

echo "Merging bootloader + partitions + boot_app0 + firmware..."
python3 -m esptool --chip esp32s3 merge-bin \
    --output /output/firmware-merged.bin \
    0x00000 "${BUILD_OUT}/bootloader.bin" \
    0x08000 "${BUILD_OUT}/partitions.bin" \
    0x0e000 "$BOOT_APP0" \
    0x10000 "${BUILD_OUT}/firmware.bin"

echo "Merged firmware written to /output/firmware-merged.bin"
INNER_EOF

# ---------------------------------------------------------------------------
# Build image
# ---------------------------------------------------------------------------
echo
echo -e "${YELLOW}Building Docker image...${NC}"
docker build -t "$IMAGE_TAG" "$DOCKER_CTX"

# ---------------------------------------------------------------------------
# Run build container  (--rm auto-removes the container on exit)
# ---------------------------------------------------------------------------
echo
echo -e "${YELLOW}Building firmware inside container...${NC}"
docker run --rm \
    -e WIFI_SSID="$WIFI_SSID" \
    -e WIFI_PWD="$WIFI_PWD" \
    -e LORA_FREQ="$LORA_FREQ" \
    -e LORA_BW="$LORA_BW" \
    -e LORA_SF="$LORA_SF" \
    -e MESHCORE_COMMIT="$MESHCORE_COMMIT" \
    -v "${ORIGINAL_PWD}:/output" \
    "$IMAGE_TAG"

if [ ! -f "${ORIGINAL_PWD}/firmware-merged.bin" ]; then
    echo -e "${RED}Error: firmware-merged.bin was not produced.${NC}"
    exit 1
fi

echo
echo -e "${GREEN}Build successful!${NC}"
echo "  Merged firmware → ${ORIGINAL_PWD}/firmware-merged.bin"

# ---------------------------------------------------------------------------
# Optional flash (runs esptool inside Docker via --device passthrough)
# ---------------------------------------------------------------------------
echo
read -rp "Flash firmware to device now? (y/N): " FLASH_CONFIRM
if [[ ! "$FLASH_CONFIRM" =~ ^[Yy]$ ]]; then
    echo
    echo -e "${GREEN}Firmware saved to:${NC} ${ORIGINAL_PWD}/firmware-merged.bin"
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

esptool_docker() {
    docker run --rm \
        --entrypoint python3 \
        --device "${FLASH_PORT}:${FLASH_PORT}" \
        -v "${ORIGINAL_PWD}:/output" \
        "$IMAGE_TAG" \
        -m esptool "$@"
}

if [[ "$ERASE_CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Erasing flash on ${FLASH_PORT}...${NC}"
    esptool_docker --chip esp32s3 --port "$FLASH_PORT" --baud 921600 erase_flash
    echo
    echo -e "${GREEN}Erase complete.${NC}"
    echo
fi

echo -e "${YELLOW}Flashing to ${FLASH_PORT}...${NC}"
esptool_docker --chip esp32s3 --port "$FLASH_PORT" --baud 921600 \
    write_flash 0x0 /output/firmware-merged.bin

echo
echo -e "${GREEN}Flash complete!${NC}"
echo
echo -e "${GREEN}Done.${NC}"
