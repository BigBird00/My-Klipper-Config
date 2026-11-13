#!/bin/bash
# klipper_backup.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color (reset)

# === Timestamp ===
TS=$(date +"%Y-%m-%d_%H-%M")

# === Backup root ===
BACKUP_DIR="/klipper_backup/$TS"

# === Create backup directory ===
sudo mkdir -p "$BACKUP_DIR"

echo "Backing up to: $BACKUP_DIR"

# === Klipper configs ===
echo "Backing up: Klipper Configs"
sudo mkdir -p "$BACKUP_DIR/klipper_config"
sudo cp -r ~/printer_data/config "$BACKUP_DIR/klipper_config/"

# === Moonraker configs ===
echo "Backing up: Moonraker Configs"
sudo mkdir -p "$BACKUP_DIR/moonraker"
sudo cp -r ~/.moonraker "$BACKUP_DIR/moonraker/"

# === Mainsail config (if exists) ===
if [ -d ~/.config/mainsail ]; then
    echo "Backing up: Mainsail Configs"
    sudo mkdir -p "$BACKUP_DIR/mainsail"
    sudo cp -r ~/.config/mainsail "$BACKUP_DIR/mainsail/"
else
    echo -e "${RED}Error: Mainsail Config Not Found * * * * * * * * * * * * *${NC}"
fi



# === Full printer_data backup ===
echo "Backing up: Full Printer_Data"
sudo mkdir -p "$BACKUP_DIR/printer_data"
sudo cp -r ~/printer_data "$BACKUP_DIR/printer_data/"



# === System info snapshot ===
sudo bash -c "uname -a > $BACKUP_DIR/system_info.txt"
sudo bash -c "df -h >> $BACKUP_DIR/system_info.txt"
sudo bash -c "mount >> $BACKUP_DIR/system_info.txt"

echo "Backup complete."
echo "Location: $BACKUP_DIR"
