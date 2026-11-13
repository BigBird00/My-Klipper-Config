#!/bin/bash

#run_if_not_printing.sh

#######################################################
#        MUST ADD TO CROM								##############

# (bash)		crontab -e
# runs every 10 minutes
#    */10 * * * * /home/yourusername/run_if_not_printing.sh >> /home/yourusername/cron.log 2>&1
# runs every day at 3:30 am
#30 3 * * * /home/yourusername/klipper_log_cleanup.sh >> /home/yourusername/log_cleanup.log 2>&1

#!/bin/bash

########################################
# Klipper Safe Log Cleanup Script
########################################

LOG_DIR="$HOME/printer_data/logs"   # Adjust if needed
RETENTION_DAYS=1                   # Keep logs for this many days
MOONRAKER_URL="http://localhost:7125"
# include environment VaRIABLES
export PATH=/usr/bin:/bin

echo "--------------------------------------"
echo "$(date): Starting log cleanup check..."

LOCKFILE="/tmp/mainsail_busy"
MOONRAKER="http://127.0.0.1:7125/printer/objects/query"
CPU_THRESHOLD=4.0   # Adjust as needed (load average threshold)
Delay=3600 # one hour


# CPU load check
cpu_high() {
    LOAD=$(awk '{print $1}' /proc/loadavg)
    awk -v load="$LOAD" -v threshold="$CPU_THRESHOLD" 'BEGIN {exit (load > threshold)}'
}

# Moonraker query helper
mq() {
    curl -s "$MOONRAKER$1" || echo ""
}

while true; do
    # 1. Lock file
    if [[ -f "$LOCKFILE" ]]; then
        echo "Lock file present. Waiting..."
        sleep Delay
        continue
    fi

    # 2. Klipper motion (toolhead)
    TOOLHEAD=$(mq "?toolhead")
    if [[ -z "$TOOLHEAD" ]]; then
        echo "Moonraker unreachable. Waiting..."
        sleep Delay
        continue
    fi

    VELOCITY=$(echo "$TOOLHEAD" | jq -r '.result.status.toolhead.velocity')
    if (( $(echo "$VELOCITY > 0" | bc -l) )); then
        echo "Klipper moving. Waiting..."
        sleep Delay
        continue
    fi

    # 3. Heating/cooling
    HEATERS=$(mq "?heater_bed&extruder")
    BED_TGT=$(echo "$HEATERS" | jq -r '.result.status.heater_bed.target')
    BED_CUR=$(echo "$HEATERS" | jq -r '.result.status.heater_bed.temperature')
    EXT_TGT=$(echo "$HEATERS" | jq -r '.result.status.extruder.target')
    EXT_CUR=$(echo "$HEATERS" | jq -r '.result.status.extruder.temperature')

    if [[ "$BED_TGT" != "$BED_CUR" || "$EXT_TGT" != "$EXT_CUR" ]]; then
        echo "Heating/cooling in progress. Waiting..."
        sleep Delay
        continue
    fi

    # 4. Print job state
    PRINT_STATE=$(mq "?print_stats" | jq -r '.result.status.print_stats.state')
    if [[ "$PRINT_STATE" != "standby" && "$PRINT_STATE" != "complete" ]]; then
        echo "Print job active ($PRINT_STATE). Waiting..."
        sleep Delay
        continue
    fi

    # 5. G-code queue
    QUEUE=$(mq "?gcode_move" | jq -r '.result.status.gcode_move.queue')
    if [[ "$QUEUE" != "[]" ]]; then
        echo "G-code queue not empty. Waiting..."
        sleep Delay
        continue
    fi

    # 6. CPU load
    if cpu_high; then
        echo "CPU load high. Waiting..."
        sleep Delay
        continue
    fi


done



#acutal code to execute when coast is clear
echo "System idle. Running job..."
 

# Make sure log directory exists
if [ ! -d "$LOG_DIR" ]; then
    echo "$(date): Log directory not found: $LOG_DIR"
    exit 1
fi

echo "$(date): Printer idle. Cleaning rotated logs older than $RETENTION_DAYS days..."

# Delete only rotated logs (never current logs)
find "$LOG_DIR" -type f \
    \( -name "moonraker.log.*" -o -name "klipper.log.*" \) \
    -mtime +$RETENTION_DAYS \
    -print -delete

echo "$(date): Cleanup complete."
echo "--------------------------------------"

exit 0


