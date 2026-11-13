#check klipper status

#!/bin/bash

SERVICES=("klipper" "moonraker" "mainsail")

echo "========================================"
echo "   Klipper Stack Status Check"
echo "========================================"
echo

for SERVICE in "${SERVICES[@]}"; do
    echo "----------------------------------------"
    echo "Checking: $SERVICE"
    echo "----------------------------------------"

    if systemctl list-unit-files | grep -q "^${SERVICE}.service"; then
        STATUS=$(systemctl is-active $SERVICE 2>/dev/null)

        echo "Service status: $STATUS"
        echo

        echo "Detailed status:"
        systemctl status $SERVICE --no-pager

        echo
        echo "Recent warnings/errors (last 50 lines):"
        journalctl -u $SERVICE -n 50 --no-pager | grep -i -E "error|warn|failed|critical" || echo "No recent errors or warnings found."
    else
        echo "Service $SERVICE not found on this system."
    fi

    echo
done

echo "========================================"
echo "   Check Complete"
echo "========================================"







#   #  ##  #Moonraker Status: Check if Moonraker is running by using the command 
#   #  ##  sudo systemctl status moonraker.service
#   #  ##  #. If it shows that Moonraker is running, you can proceed with your terminal commands.
#   #  ##  # 
#   #  ##  js@klipper:~$ sudo systemctl status moonraker.service
#   #  ##  [sudo] password for ajs:
#   #  ##  ● moonraker.service - API Server for Klipper SV1
#   #  ##       Loaded: loaded (/etc/systemd/system/moonraker.service; enabled; preset: en>
#   #  ##       Active: active (running) since Tue 2026-02-17 12:43:46 PST; 3min 35s ago
#   #  ##         Docs: https://moonraker.readthedocs.io/
#   #  ##     Main PID: 1197 (python)
#   #  ##        Tasks: 10 (limit: 2220)
#   #  ##       Memory: 83.6M (peak: 90.4M)
#   #  ##          CPU: 2.957s
#   #  ##       CGroup: /system.slice/moonraker.service
#   #  ##               └─1197 /home/ajs/moonraker-env/bin/python /home/ajs/moonraker/moon>
#   #  ##  
#   #  ##  Feb 17 12:44:36 klipper python[1197]: **User=ajs
#   #  ##  Feb 17 12:44:36 klipper python[1197]: [server.py:add_log_rollover_item()] - Kli>
#   #  ##  Feb 17 12:44:36 klipper python[1197]: [klippy_connection.py:_request_initial_su>
#   #  ##  Feb 17 12:44:36 klipper python[1197]: [klippy_connection.py:_request_initial_su>
#   #  ##  Feb 17 12:44:36 klipper python[1197]: [klippy_connection.py:_check_ready()] -
#   #  ##  Feb 17 12:44:36 klipper python[1197]: Can not update MCU 'mcu' config as it is >
#   #  ##  Feb 17 12:44:36 klipper python[1197]: Once the underlying issue is corrected, u>
#   #  ##  Feb 17 12:44:36 klipper python[1197]: "FIRMWARE_RESTART" command to reset the f>
#   #  ##  Feb 17 12:44:36 klipper python[1197]: config, and restart the host software.
#   #  ##  Feb 17 12:44:36 klipper python[1197]: Error configuring printer
#   #  ##  lines 1-21/21 (END)
#   #  ##  ● moonraker.service - API Server for Klipper SV1
#   #  ##       Loaded: loaded (/etc/systemd/system/moonraker.service; enabled; preset: enabled)
#   #  ##       Active: active (running) since Tue 2026-02-17 12:43:46 PST; 3min 35s ago
#   #  ##         Docs: https://moonraker.readthedocs.io/
#   #  ##     Main PID: 1197 (python)
#   #  ##        Tasks: 10 (limit: 2220)
#   #  ##       Memory: 83.6M (peak: 90.4M)
#   #  ##          CPU: 2.957s
#   #  ##       CGroup: /system.slice/moonraker.service
#   #  ##               └─1197 /home/ajs/moonraker-env/bin/python /home/ajs/moonraker/moonraker/moonrake>
#   #  ##  
#   #  ##  Feb 17 12:44:36 klipper python[1197]: **User=ajs
#   #  ##  Feb 17 12:44:36 klipper python[1197]: [server.py:add_log_rollover_item()] - Klipper Version: >
#   #  ##  Feb 17 12:44:36 klipper python[1197]: [klippy_connection.py:_request_initial_subscriptions()]>
#   #  ##  Feb 17 12:44:36 klipper python[1197]: [klippy_connection.py:_request_initial_subscriptions()]>
#   #  ##  Feb 17 12:44:36 klipper python[1197]: [klippy_connection.py:_check_ready()] -
#   #  ##  Feb 17 12:44:36 klipper python[1197]: Can not update MCU 'mcu' config as it is shutdown
#   #  ##  Feb 17 12:44:36 klipper python[1197]: Once the underlying issue is corrected, use the
#   #  ##  Feb 17 12:44:36 klipper python[1197]: "FIRMWARE_RESTART" command to reset the firmware, reloa>
#   #  ##  Feb 17 12:44:36 klipper python[1197]: config, and restart the host software.
#   #  ##  Feb 17 12:44:36 klipper python[1197]: Error configuring printer
#   #  ##  ~
#   #  ##  ~
#   #  ##  
#   #  ##  1