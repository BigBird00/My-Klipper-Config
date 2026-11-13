#!/bin/bash
set -euo pipefail

########################################
# USER SETTINGS
########################################
BACKUP_DIR="/root/backups"
KEEP_ARCHIVES=1
COMPRESSION="auto"
ENABLE_CHECKSUM=false
ENABLE_RSYNC=false
RSYNC_TARGET="backup@nas:/volume1/klipper-backups"

# --- Color codes ---
GREEN="\e[32m"
BLUE="\e[34m"
CYAN="\e[36m"
RED="\e[31m"
RESET="\e[0m"
echoGreen() { echo -e "${GREEN}$*${RESET}"; }
echoBlue()  { echo -e "${BLUE}$*${RESET}"; }
echoCyan()  { echo -e "${CYAN}$*${RESET}"; }
echoRed()   { echo -e "${RED}$*${RESET}"; }

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

########################################
# Helpers
########################################

human_size() {
    local size
    size=$(sudo stat -c %s "$1" 2>/dev/null || echo 0)
    awk -v s="$size" '
        function human(x) {
            if (x >= 1024^3) return sprintf("%.2f GB", x/1024^3)
            if (x >= 1024^2) return sprintf("%.2f MB", x/1024^2)
            if (x >= 1024)   return sprintf("%.2f KB", x/1024)
            return sprintf("%d B", x)
        }
        BEGIN { print human(s) }
    '
}

run() {
  if $DRY_RUN; then
    echo "[DRY-RUN] $*"
  else
    "$@"
  fi
}

# CPU detection
CPU_CORES=$(nproc)
ZSTD_LEVEL=3
ZSTD_THREADS=$(( CPU_CORES > 1 ? CPU_CORES - 1 : 1 ))
EXT="tar.zst"
TAR_COMPRESS="zstd -$ZSTD_LEVEL -T$ZSTD_THREADS"

SOURCE="/"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
ARCHIVE_NAME="full_backup_$TIMESTAMP.$EXT"
ARCHIVE_PATH="$BACKUP_DIR/$ARCHIVE_NAME"
KLIPPER_ARCHIVE="/home/ajs/klipper-archive.sh"

EXCLUDES=(
  "$BACKUP_DIR"
  "*/.cache/*" "/home/ajs/.cache"
  "/dev/*" "/proc/*" "/sys/*" "/tmp/*" "/run/*" "/mnt/*" "/media/*"
  "/lost+found" "/swapfile" "/timeshift"
  "/var/tmp/*" "/var/cache/*" "/var/lib/snapd/*" "/var/log/*" "/var/lock"
  "full_backup*" "*.sock"
)

TAR_EXCLUDES=()
for p in "${EXCLUDES[@]}"; do
  TAR_EXCLUDES+=( "--exclude=$p" )
done

# Initialize
run sudo mkdir -p "$BACKUP_DIR"

restore() {
  echo -e "\nRestoring Klipper services..."
  if [ -f "$KLIPPER_ARCHIVE" ]; then
    run sudo "$KLIPPER_ARCHIVE" post || true
  fi
}
trap restore ERR INT

# Pre-clean
echo "Cleaning journal logs..."
run sudo journalctl --vacuum-time=5d > /dev/null 2>&1 || true

# Klipper pre-archive
if [ -f "$KLIPPER_ARCHIVE" ] && [ ! -f "$HOME/.klipper_archive_lock" ]; then
    run sudo "$KLIPPER_ARCHIVE" pre
fi

# Estimate size
echoBlue "Estimating size..."
TOTAL_SIZE=$(sudo du -sb "${TAR_EXCLUDES[@]}" "$SOURCE" | awk '{print $1}')
echoBlue "Estimated size: $((TOTAL_SIZE / 1024 / 1024)) MiB"

# Check space (using df -B1 for byte-precision)
FREE_BYTES=$(df -B1 "$BACKUP_DIR" | tail -1 | awk '{print $4}')
if (( FREE_BYTES < TOTAL_SIZE )); then
    echoRed "ERROR: Not enough space on $BACKUP_DIR."
    exit 1
fi

########################################
# Run backup
########################################
echoBlue "Starting backup..."

# Wrapped in bash -c to ensure the redirection (>) happens with sudo privileges
sudo bash -c "tar -c \
    --warning=no-file-changed \
    --ignore-failed-read \
    --use-compress-program='$TAR_COMPRESS' \
    ${TAR_EXCLUDES[*]} \
    '$SOURCE' \
    2>tar-errors.log \
    | pv -s $TOTAL_SIZE \
    > '$ARCHIVE_PATH'"
	
filesize=$(human_size "$ARCHIVE_PATH")
echoGreen "Final size is $filesize"

echo "Checking For Errors..."
if [ -s tar-errors.log ] && [ "$(wc -c < tar-errors.log)" -gt 50 ]; then
    echoRed "Check tar-errors.log for significant issues."
fi

if $ENABLE_CHECKSUM; then
  echo "Calculating Checksum..."
  run sudo bash -c "sha256sum '$ARCHIVE_PATH' > '$ARCHIVE_PATH.sha256'"
fi

echo "Auto Pruning old archives..."
mapfile -t ARCHIVES < <(sudo ls -1t "$BACKUP_DIR"/full_backup_*."$EXT" 2>/dev/null || true)
if (( ${#ARCHIVES[@]} > KEEP_ARCHIVES )); then
  for (( i=KEEP_ARCHIVES; i<${#ARCHIVES[@]}; i++ )); do
    echo "Removing old backup: ${ARCHIVES[$i]}"
    run sudo rm -f "${ARCHIVES[$i]}" "${ARCHIVES[$i]}.sha256"
  done
fi

if [ -f "/usr/local/bin/nginxlogsfix.sh" ]; then
    echoBlue "Running NGINX log fix..."
    sudo /usr/local/bin/nginxlogsfix.sh || true
fi

restore
trap - ERR INT
echoGreen "✅ Backup complete: $ARCHIVE_PATH"