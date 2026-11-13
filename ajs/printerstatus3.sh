#!/usr/bin/env bash
# printerstatus.sh
Version="1.35"
# Self-healing diagnostics for Klipper, Moonraker, NGINX/Mainsail, and KIAUH.
# Supports:
#   --repair (default)
#   --dry-run (ultra-detailed simulation)
#   --msg_detail=1,2,3 (verbosity control)

set -euo pipefail

# -------- CONFIG --------
USER_NAME="ajs"
HOME_DIR="/home/${USER_NAME}"
PRINTER_DATA="${HOME_DIR}/printer_data"
KLIPPER_DIR="${HOME_DIR}/klipper"
KLIPPER_ENV="${HOME_DIR}/klippy-env"
MOONRAKER_DIR="${HOME_DIR}/moonraker"
MOONRAKER_ENV="${HOME_DIR}/moonraker-env"
KIAUH_DIR="${HOME_DIR}/kiauh"

KLIPPER_SERVICE="/etc/systemd/system/klipper.service"
MOONRAKER_SERVICE="/etc/systemd/system/moonraker.service"

MOONRAKER_ENVFILE_DIR="${PRINTER_DATA}/systemd"
MOONRAKER_ENVFILE="${MOONRAKER_ENVFILE_DIR}/moonraker.env"

LOG_DIR="${PRINTER_DATA}/logs"

NGINX_DIR="/etc/nginx"
NGINX_SITES_AVAILABLE="${NGINX_DIR}/sites-available"
NGINX_SITES_ENABLED="${NGINX_DIR}/sites-enabled"
NGINX_MAINSAIL_CFG="${NGINX_SITES_AVAILABLE}/mainsail"
NGINX_MAINSAIL_LINK="${NGINX_SITES_ENABLED}/mainsail"

# -------- MODE + VERBOSITY --------
MODE="repair"
MSG_DETAIL=2

for arg in "$@"; do
    case "$arg" in
        --dry-run)
            MODE="dryrun"
            MSG_DETAIL=1
            ;;
        --repair)
            MODE="repair"
            ;;
        --msg_detail=1)
            MSG_DETAIL=1
            ;;
        --msg_detail=2)
            MSG_DETAIL=2
            ;;
        --msg_detail=3)
            MSG_DETAIL=3
            ;;
        *)
            printf '[WARN] Unknown argument: %s\n' "$arg"
            ;;
    esac
done

# -------- OUTPUT HELPERS --------
info()  { printf '[INFO] %s\n' "$*"; }
warn()  { printf '[WARN] %s\n' "$*" >&2; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

detail() {
    local level="$1"
    shift
    if (( MSG_DETAIL <= level )); then
        printf '[DETAIL-%d] %s\n' "$level" "$*"
    fi
}

# -------- ACTION WRAPPERS --------
do_action() {
    local cmd="$*"
    if [[ "${MODE}" == "dryrun" ]]; then
        detail 1 "Would run: ${cmd}"
    else
        detail 2 "Running: ${cmd}"
        eval "${cmd}"
    fi
}

write_file() {
    local path="$1"
    local content="$2"

    if [[ "${MODE}" == "dryrun" ]]; then
        detail 1 "Would write file: ${path}"
        if (( MSG_DETAIL == 1 )); then
            printf '%s\n' "${content}" | sed 's/^/    | /'
        fi
    else
        detail 2 "Writing file: ${path}"
        printf '%s\n' "${content}" | sudo tee "${path}" >/dev/null
    fi
}

show_diff() {
    local path="$1"
    local new_content="$2"

    if [[ "${MODE}" != "dryrun" ]]; then
        return
    fi

    if (( MSG_DETAIL > 2 )); then
        return
    fi

    if [[ -f "${path}" ]]; then
        detail 2 "Diff for ${path}:"
        diff -u "${path}" <(printf '%s\n' "${new_content}") || true
    else
        detail 2 "File ${path} does not exist; would create new file."
    fi
}

# -------- SYSTEMD HELPERS --------
have_cmd() { command -v "$1" >/dev/null 2>&1; }
systemd_has_unit() {
    systemctl list-unit-files | awk '{print $1}' | grep -qx "$1"
}

systemd_is_active() {
    systemctl is-active --quiet "$1"
}

# -------- KLIPPER SERVICE --------
fix_klipper_service() {
    if [[ -f "${KLIPPER_SERVICE}" ]] && grep -q ' -I ' "${KLIPPER_SERVICE}"; then
        warn "klipper.service contains '-I'. Removing automatically."
        do_action "sudo sed -i 's/ -I [^ ]*//g' ${KLIPPER_SERVICE}"
        do_action "sudo systemctl daemon-reload"
        do_action "sudo systemctl restart klipper.service"
    fi
}

check_klipper_service() {
    info "Checking Klipper service"

    if ! systemd_has_unit "klipper.service"; then
        warn "klipper.service missing."
        return
    fi

    fix_klipper_service

    systemctl status klipper.service --no-pager || true

    if ! systemd_is_active "klipper.service"; then
        warn "Klipper inactive. Attempting restart."
        do_action "sudo systemctl restart klipper.service"
    fi
}

# -------- MOONRAKER SERVICE --------
moonraker_service_content() {
cat <<EOF
[Unit]
Description=Moonraker API Server
After=network.target klipper.service

[Service]
Type=simple
User=${USER_NAME}
WorkingDirectory=${MOONRAKER_DIR}
EnvironmentFile=${MOONRAKER_ENVFILE}
ExecStart=${MOONRAKER_ENV}/bin/python ${MOONRAKER_DIR}/moonraker/moonraker.py -l ${LOG_DIR}/moonraker.log
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
}

repair_moonraker_service_file() {
    local content
    content="$(moonraker_service_content)"

    show_diff "${MOONRAKER_SERVICE}" "${content}"
    write_file "${MOONRAKER_SERVICE}" "${content}"
    do_action "sudo systemctl daemon-reload"
}

ensure_moonraker_envfile() {
    if [[ ! -d "${MOONRAKER_ENVFILE_DIR}" ]]; then
        do_action "sudo mkdir -p ${MOONRAKER_ENVFILE_DIR}"
        do_action "sudo chown ${USER_NAME}:${USER_NAME} ${MOONRAKER_ENVFILE_DIR}"
    fi

    if [[ ! -f "${MOONRAKER_ENVFILE}" ]]; then
        write_file "${MOONRAKER_ENVFILE}" "MOONRAKER_ARGS="
        do_action "sudo chown ${USER_NAME}:${USER_NAME} ${MOONRAKER_ENVFILE}"
    fi
}

ensure_log_dir() {
    if [[ ! -d "${LOG_DIR}" ]]; then
        do_action "sudo mkdir -p ${LOG_DIR}"
        do_action "sudo chown -R ${USER_NAME}:${USER_NAME} ${LOG_DIR}"
    fi
}

fix_moonraker_service_if_corrupt() {
    if [[ ! -f "${MOONRAKER_SERVICE}" ]]; then
        warn "Moonraker service missing. Recreating."
        repair_moonraker_service_file
        return
    fi

    if grep -q "${KLIPPER_ENV}" "${MOONRAKER_SERVICE}" || \
       grep -q "Klipper 3D Printer Firmware" "${MOONRAKER_SERVICE}"; then
        warn "Moonraker service corrupted. Repairing."
        repair_moonraker_service_file
        return
    fi

    if ! grep -q "${MOONRAKER_ENV}/bin/python" "${MOONRAKER_SERVICE}"; then
        warn "Moonraker ExecStart incorrect. Repairing."
        repair_moonraker_service_file
    fi
}

check_moonraker_service() {
    info "Checking Moonraker service"

    if ! systemd_has_unit "moonraker.service"; then
        warn "moonraker.service missing. Creating."
        repair_moonraker_service_file
        do_action "sudo systemctl enable moonraker.service"
    else
        fix_moonraker_service_if_corrupt
    fi

    ensure_moonraker_envfile
    ensure_log_dir

    do_action "sudo systemctl restart moonraker.service"
    systemctl status moonraker.service --no-pager || true
}

# -------- NGINX / MAINSAIL --------
check_nginx_and_mainsail_scaffold() {
    info "Checking NGINX/Mainsail scaffold"

    [[ -d "${NGINX_SITES_AVAILABLE}" ]] || do_action "sudo mkdir -p ${NGINX_SITES_AVAILABLE}"
    [[ -d "${NGINX_SITES_ENABLED}" ]]   || do_action "sudo mkdir -p ${NGINX_SITES_ENABLED}"

    if [[ ! -f "${NGINX_MAINSAIL_CFG}" ]]; then
        warn "Missing Mainsail config. Creating placeholder."
        write_file "${NGINX_MAINSAIL_CFG}" ""
    fi

    if [[ ! -L "${NGINX_MAINSAIL_LINK}" ]]; then
        do_action "sudo ln -sf ${NGINX_MAINSAIL_CFG} ${NGINX_MAINSAIL_LINK}"
    fi

    if systemd_has_unit "nginx.service"; then
        if have_cmd nginx; then
            detail 2 "Testing nginx config"
            do_action "sudo nginx -t"
        fi
    else
        warn "nginx.service missing. Mainsail will not function until installed."
    fi
}

# -------- KIAUH --------
check_kiauh() {
    info "Checking KIAUH"

    if [[ -d "${KIAUH_DIR}" ]]; then
        if [[ ! -x "${KIAUH_DIR}/kiauh.sh" ]]; then
            warn "kiauh.sh not executable. Fixing."
            do_action "sudo chmod +x ${KIAUH_DIR}/kiauh.sh"
        fi
    else
        warn "KIAUH not found at ${KIAUH_DIR}"
    fi
}

# -------- MAIN --------
main() {
    info "printerstatus.sh v$Version — mode=${MODE}, msg_detail=${MSG_DETAIL}"

    check_klipper_service
    check_moonraker_service
    check_nginx_and_mainsail_scaffold
    check_kiauh

    info "Diagnostics complete."
}

main "$@"
