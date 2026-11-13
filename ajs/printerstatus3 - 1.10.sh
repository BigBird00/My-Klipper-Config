#!/bin/bash
# Klipper Stack Health Checker
# Version: 1.10

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
RESET="\e[0m"

SERVICES=()
STATUSES=()

# ---- CONFIG PATHS (adjust if needed) ----
declare -A CONFIG_PATHS
CONFIG_PATHS["klipper"]="$HOME/printer_data/config/printer.cfg"
CONFIG_PATHS["moonraker"]="$HOME/printer_data/config/moonraker.conf"

# ---- REQUIRED PORTS ----
declare -A PORTS
PORTS["moonraker"]="7125"
PORTS["mainsail"]="80"
PORTS["mainsail-web"]="80"
PORTS["caddy"]="80"
PORTS["klipper"]=""

# -----------------------------
# PORT CHECKER
# -----------------------------
check_port() {
    local SERVICE="$1"
    local PORT="${PORTS[$SERVICE]}"

    if [ -z "$PORT" ]; then
        return 0
    fi

    if sudo lsof -iTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1; then
        echo -e "${RED}Port $PORT is already in use!${RESET}"
        echo -e "${YELLOW}Process using port $PORT:${RESET}"
        sudo lsof -iTCP:$PORT -sTCP:LISTEN
        return 1
    fi

    return 0
}

# -----------------------------
# CONFIG FILE INTEGRITY CHECK
# -----------------------------
check_config_file() {
    local SERVICE="$1"
    local CONFIG_PATH="$2"

    if [ -z "$CONFIG_PATH" ]; then
        return 0
    fi

    if [ ! -f "$CONFIG_PATH" ]; then
        echo -e "${RED}Config file missing for ${SERVICE}: ${CONFIG_PATH}${RESET}"
        return 1
    fi

    local SIZE
    SIZE=$(stat -c%s "$CONFIG_PATH")

    if [ "$SIZE" -lt 10 ]; then
        echo -e "${RED}Config file too small (${SIZE} bytes) for ${SERVICE}: ${CONFIG_PATH}${RESET}"
        return 1
    fi

    echo -e "${GREEN}Config file OK for ${SERVICE}: ${CONFIG_PATH} (${SIZE} bytes)${RESET}"
    return 0
}

# -----------------------------
# EXECS TART VALIDATOR
# -----------------------------
validate_execstart() {
    local SERVICE="$1"
    local SERVICE_FILE="/etc/systemd/system/${SERVICE}.service"

    if [ ! -f "$SERVICE_FILE" ]; then
        echo -e "${YELLOW}No service file found for ${SERVICE}${RESET}"
        return 0
    fi

    local EXECSTART
    EXECSTART=$(grep -E "^ExecStart=" "$SERVICE_FILE" | sed 's/ExecStart=//')

    if [[ -z "$EXECSTART" ]]; then
        echo -e "${RED}ExecStart missing in ${SERVICE_FILE}${RESET}"
        return 1
    fi

    if [[ "$SERVICE" == "klipper" ]]; then
        if ! echo "$EXECSTART" | grep -q "klippy.py"; then
            echo -e "${RED}ExecStart for klipper does not call klippy.py${RESET}"
            return 1
        fi
        if ! echo "$EXECSTART" | grep -q "printer.cfg"; then
            echo -e "${RED}ExecStart for klipper is missing printer.cfg argument${RESET}"
            echo -e "${YELLOW}This will cause the INVALIDARGUMENT error you saw.${RESET}"
            return 1
        fi
    fi

    echo -e "${GREEN}ExecStart OK for ${SERVICE}${RESET}"
    return 0
}

# -----------------------------
# SELF-HEALING LOGIC
# -----------------------------
auto_fix_service() {
    local SERVICE="$1"

    echo -e "${BLUE}Running self-healing for ${SERVICE}...${RESET}"

    # Ensure systemd directory exists
    if [ ! -d "/etc/systemd/system" ]; then
        sudo mkdir -p /etc/systemd/system
    fi

    # Ensure log directory exists
    local LOG_DIR="/var/log/${SERVICE}"
    if [ ! -d "$LOG_DIR" ]; then
        sudo mkdir -p "$LOG_DIR"
        sudo chmod 755 "$LOG_DIR"
    fi

    # Ensure log file exists
    local LOG_FILE="$LOG_DIR/${SERVICE}.log"
    if [ ! -f "$LOG_FILE" ]; then
        sudo touch "$LOG_FILE"
        sudo chmod 644 "$LOG_FILE"
    fi

    # Klipper socket placeholder
    if [ "$SERVICE" = "klipper" ]; then
        if [ ! -S "/tmp/klippy_uds" ] && [ ! -e "/tmp/klippy_uds" ]; then
            echo -e "${YELLOW}Creating Klipper socket placeholder /tmp/klippy_uds${RESET}"
            sudo touch /tmp/klippy_uds
        fi
    fi

    # Moonraker runtime dir
    if [ "$SERVICE" = "moonraker" ]; then
        if [ ! -d "/run/moonraker" ]; then
            sudo mkdir -p /run/moonraker
        fi
    fi

    sudo systemctl daemon-reload
}

# -----------------------------
# SERVICE CHECKER
# -----------------------------
check_service() {
    local SERVICE="$1"
    local DISPLAY_NAME="$2"

    echo -e "\n=============================="
    echo -e " Checking ${DISPLAY_NAME}"
    echo -e "=============================="

    SERVICES+=("$DISPLAY_NAME")

    # ExecStart validation (only where meaningful)
    if [[ "$SERVICE" == "klipper" ]]; then
        if ! validate_execstart "$SERVICE"; then
            STATUSES+=("ServiceCorrupt")
            return
        fi
    fi

    # Config file integrity (if defined)
    local CFG="${CONFIG_PATHS[$SERVICE]}"
    if ! check_config_file "$SERVICE" "$CFG"; then
        STATUSES+=("ConfigError")
        return
    fi

    # Port conflict check
    if ! check_port "$SERVICE"; then
        STATUSES+=("Blocked")
        return
    fi

    # If service missing → attempt self-heal + start
    if ! systemctl list-unit-files | grep -q "^${SERVICE}.service"; then
        echo -e "${YELLOW}${DISPLAY_NAME} service missing — attempting self-heal...${RESET}"
        auto_fix_service "$SERVICE"
        sudo systemctl start "$SERVICE" 2>/dev/null
        sleep 1
    fi

    # First status check
    local STATUS
    STATUS=$(systemctl is-active "$SERVICE")

    if [ "$STATUS" = "active" ]; then
        echo -e "${GREEN}${DISPLAY_NAME} is running${RESET}"
        STATUSES+=("Running")
        return
    fi

    echo -e "${RED}${DISPLAY_NAME} is NOT running${RESET}"
    echo -e "${YELLOW}Attempting self-heal + restart...${RESET}"

    auto_fix_service "$SERVICE"
    sudo systemctl restart "$SERVICE" 2>/dev/null
    sleep 1

    STATUS=$(systemctl is-active "$SERVICE")

    if [ "$STATUS" = "active" ]; then
        echo -e "${GREEN}${DISPLAY_NAME} recovered successfully${RESET}"
        STATUSES+=("Recovered")
    else
        echo -e "${RED}${DISPLAY_NAME} failed to start${RESET}"
        STATUSES+=("Failed")
        echo -e "${YELLOW}Reason:${RESET}"
        journalctl -u "$SERVICE" -n 20 --no-pager
    fi
}

# -----------------------------
# RUN CHECKS
# -----------------------------
check_service "klipper" "Klipper"
check_service "moonraker" "Moonraker"
check_service "mainsail" "Mainsail"
check_service "mainsail-web" "Mainsail-Web (alt)"
check_service "caddy" "Caddy (Mainsail Web Server)"

# -----------------------------
# SUMMARY TABLE
# -----------------------------
echo -e "\n\n=============================="
echo -e "        SUMMARY TABLE"
echo -e "=============================="

printf "%-25s %-20s\n" "Service" "Status"
printf "%-25s %-20s\n" "------------------------" "--------------------"

for i in "${!SERVICES[@]}"; do
    printf "%-25s %-20s\n" "${SERVICES[$i]}" "${STATUSES[$i]}"
done

echo -e "==============================\n"
