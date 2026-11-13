#!/usr/bin/env bash
#
# printerstatus3 v1.11 – Structural Health Diagnostics
# Scans ONLY *.cfg files. Never touches .theme/.css/.svg/.md/etc.

#############################################
# CONFIG
#############################################

PRINTER_DATA="/home/ajs/printer_data"
CONFIG_DIR="$PRINTER_DATA/config"
MAIN_CFG="$CONFIG_DIR/printer.cfg"

KLIPPER_SERVICE="klipper"
KLIPPER_SERVICE_FILE="/etc/systemd/system/klipper.service"
KLIPPER_SOCKET="$PRINTER_DATA/comms/klippy.sock"
MOONRAKER_CONF="$CONFIG_DIR/moonraker.conf"

LOGFILE="/home/ajs/printerstatus3.log"

SOCKET_WARN_MIN=10
SOCKET_CRIT_MIN=60

#############################################
# COLORS
#############################################

RED='\033[31m'
YEL='\033[33m'
GRN='\033[32m'
NC='\033[0m'

#############################################
# LOGGING (self-healing)
#############################################

if [ ! -f "$LOGFILE" ]; then
    touch "$LOGFILE" 2>/dev/null || sudo touch "$LOGFILE"
fi
chmod 666 "$LOGFILE" 2>/dev/null || sudo chmod 666 "$LOGFILE"

strip_colors() {
    sed -r "s/\x1B

\[[0-9;]*[mK]//g"
}

log_and_print() {
    printf "%b\n" "$1"
    printf "%b\n" "$1" | strip_colors >> "$LOGFILE"
}

start_log() {
    {
        echo "==============================================="
        echo "printerstatus3 v1.11 run at: $(date)"
        echo "==============================================="
    } >> "$LOGFILE"
}

#############################################
# FORMAT HELPERS
#############################################

section() {
    log_and_print ""
    log_and_print "=== $1 ==="
}

ok()   { log_and_print "${GRN}OK${NC} – $*"; }
warn() { log_and_print "${YEL}WARN${NC} – $*"; }
crit() { log_and_print "${RED}CRITICAL${NC} – $*"; }

#############################################
# SERVICE HELPERS
#############################################

klipper_running() {
    systemctl is-active --quiet "$KLIPPER_SERVICE"
}

moonraker_running() {
    systemctl is-active --quiet moonraker
}

#############################################
# MODULE 1 – Klipper ExecStart / socket arg
#############################################

check_service_socket_arg() {
    section "Klipper Service ExecStart Validation"

    if [ ! -f "$KLIPPER_SERVICE_FILE" ]; then
        crit "Service file missing: $KLIPPER_SERVICE_FILE"
        return
    fi

    local exec
    exec="$(grep -E '^[[:space:]]*ExecStart=' "$KLIPPER_SERVICE_FILE" | sed 's/^[[:space:]]*ExecStart=//')"

    if [[ -z "$exec" ]]; then
        crit "ExecStart not found in service file"
        return
    fi

    if ! echo "$exec" | grep -q " -a "; then
        crit "Klipper service missing -a (no API socket will be created)"
        log_and_print "     ExecStart: $exec"
        log_and_print "     FIX: Add: -a $KLIPPER_SOCKET"
        return
    fi

    if echo "$exec" | grep -q "$KLIPPER_SOCKET"; then
        ok "ExecStart includes -a and correct socket path"
    else
        warn "ExecStart has -a but NOT the expected socket path"
        log_and_print "     ExecStart: $exec"
    fi
}

#############################################
# MODULE 2 – Klipper UNIX socket open (lsof)
#############################################

check_klipper_unix_socket() {
    section "Klipper UNIX Socket Open Check"

    if ! klipper_running; then
        warn "Klipper is not running; skipping UNIX socket check"
        return
    fi

    local out
    out="$(sudo lsof -U 2>/dev/null | grep -E 'klippy\.py|klipper' || true)"

    if [[ -z "$out" ]]; then
        crit "Klipper is running but has NO UNIX sockets open"
        log_and_print "     This usually means Klipper was started WITHOUT -a."
    else
        ok "Klipper has active UNIX socket(s):"
        echo "$out" | sed 's/^/     /' | while read -r line; do log_and_print "$line"; done
    fi
}

#############################################
# MODULE 3 – Socket file existence + staleness
#############################################

check_socket_file() {
    section "Klipper Socket File Health"

    if [ ! -S "$KLIPPER_SOCKET" ]; then
        if [ -e "$KLIPPER_SOCKET" ]; then
            crit "Socket path exists but is NOT a socket"
            ls -l "$KLIPPER_SOCKET" | while read -r line; do log_and_print "     $line"; done
        else
            crit "Socket file missing: $KLIPPER_SOCKET"
        fi
        return
    fi

    local now ts age age_min
    now=$(date +%s)
    ts=$(stat -c %Y "$KLIPPER_SOCKET")
    age=$(( now - ts ))
    age_min=$(( age / 60 ))

    ok "Socket exists: $KLIPPER_SOCKET"
    ls -l "$KLIPPER_SOCKET" | while read -r line; do log_and_print "     $line"; done
    log_and_print "     Age: ${age_min} minutes"

    if (( age_min >= SOCKET_CRIT_MIN )); then
        crit "Socket is stale (> ${SOCKET_CRIT_MIN} min old)"
    elif (( age_min >= SOCKET_WARN_MIN )); then
        warn "Socket older than ${SOCKET_WARN_MIN} minutes"
    else
        ok "Socket age is normal"
    fi
}

#############################################
# MODULE 4 – Moonraker ↔ Klipper socket alignment
#############################################

check_moonraker_socket() {
    section "Moonraker ↔ Klipper Socket Alignment"

    if [ ! -f "$MOONRAKER_CONF" ]; then
        warn "Moonraker config not found: $MOONRAKER_CONF"
        return
    fi

    local mr_path
    mr_path="$(awk '
        /^

\[klippy_uds\]

/ { insec=1; next }
        /^

\[/ { insec=0 }
        insec && $1 ~ /^path:/ { sub(/path:[[:space:]]*/, "", $0); print $0; exit }
    ' "$MOONRAKER_CONF")"

    if [[ -z "$mr_path" ]]; then
        warn "Moonraker has no [klippy_uds] path configured"
        return
    fi

    log_and_print "     Moonraker configured path: $mr_path"

    if [[ "$mr_path" != "$KLIPPER_SOCKET" ]]; then
        crit "Moonraker socket path does NOT match Klipper socket"
        log_and_print "     Expected: $KLIPPER_SOCKET"
        log_and_print "     Actual:   $mr_path"
    else
        ok "Moonraker socket path matches Klipper"
    fi

    if [ ! -S "$mr_path" ]; then
        crit "Moonraker-configured socket does not exist or is not a socket"
    fi
}

#############################################
# MODULE 5 – Include File Scanner (ONLY *.cfg)
#############################################

collect_includes() {
    awk '
        /^[[:space:]]*include[[:space:]]+/ {
            sub(/^[[:space:]]*include[[:space:]]+/, "", $0);
            gsub(/[[:space:]]+$/, "", $0);
            print $0;
        }
    ' "$MAIN_CFG" 2>/dev/null
}

scan_include_file() {
    local path="$1"

    if [ ! -f "$path" ]; then
        crit "Included file missing: $path"
        return
    fi

    if [[ "$path" != *.cfg ]]; then
        warn "Included file is not a .cfg, skipping: $path"
        return
    fi

    if ! grep -q '^

\[' "$path"; then
        warn "Included .cfg has no section headers: $path"
        return
    fi

    local bad
    bad="$(grep -n '^

\[' "$path" | grep -Ev '^

\[[A-Za-z0-9_ \-]+\]

$' || true)"

    if [[ -n "$bad" ]]; then
        crit "Suspicious section-like lines in: $path"
        echo "$bad" | while read -r line; do log_and_print "     $line"; done
    else
        ok "Include file looks structurally sane: $path"
    fi
}

run_include_scanner() {
    section "Broken Include File Scanner (cfg only)"

    if [ ! -f "$MAIN_CFG" ]; then
        crit "Main config not found: $MAIN_CFG"
        return
    fi

    local inc rel abs
    mapfile -t inc < <(collect_includes)

    if ((${#inc[@]} == 0)); then
        warn "No include directives found in $MAIN_CFG"
        return
    fi

    for rel in "${inc[@]}"; do
        if [[ "$rel" = /* ]]; then
            abs="$rel"
        else
            abs="$CONFIG_DIR/$rel"
        fi
        scan_include_file "$abs"
    done
}

#############################################
# MODULE 6 – LED-effect sanity checker (ONLY *.cfg)
#############################################

run_led_effect_sanity() {
    section "LED-Effect Section Sanity (cfg only)"

    local hits
    hits="$(find "$CONFIG_DIR" -type f -name '*.cfg' -print0 \
        | xargs -0 grep -n "^

\[led_effect" 2>/dev/null || true)"

    if [[ -z "$hits" ]]; then
        ok "No [led_effect] sections found in *.cfg files"
        return
    fi

    warn "Found [led_effect] sections – ensure LED extension is installed:"
    echo "$hits" | while read -r line; do log_and_print "     $line"; done
}

#############################################
# MODULE 7 – Config Syntax Validator (ONLY *.cfg)
#############################################

run_config_validator() {
    section "Config Syntax Validator (cfg only)"

    if [ ! -d "$CONFIG_DIR" ]; then
        crit "Config directory not found: $CONFIG_DIR"
        return
    fi

    local bad
    bad="$(find "$CONFIG_DIR" -type f -name '*.cfg' -print0 \
        | xargs -0 grep -n "^

\[" 2>/dev/null \
        | grep -Ev '^\S+:[0-9]+:

\[[A-Za-z0-9_ \-]+\]

$' || true)"

    if [[ -z "$bad" ]]; then
        ok "No malformed section headers detected in *.cfg files"
    else
        crit "Malformed section headers detected in *.cfg files:"
        echo "$bad" | while read -r line; do log_and_print "     $line"; done
    fi
}

#############################################
# MAIN
#############################################

main() {
    start_log

    section "Core Service Status"
    if klipper_running; then ok "Klipper service: active"; else crit "Klipper service: inactive"; fi
    if moonraker_running; then ok "Moonraker service: active"; else warn "Moonraker service: inactive"; fi

    check_service_socket_arg
    check_klipper_unix_socket
    check_socket_file
    check_moonraker_socket

    run_include_scanner
    run_led_effect_sanity
    run_config_validator

    section "printerstatus3 v1.11 – Run Complete"
}

main "$@"
