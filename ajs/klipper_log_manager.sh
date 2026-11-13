#!/bin/bash

#  ~/klipper_log_manager.sh
LOGDIR="/home/ajs/printer_data/logs"
KLIPPY_LOG="$LOGDIR/klippy.log"
# # # MAX_MB = 20
MAXSIZE=$((20 * 1024 * 1024))   # 20MB
DAYS_TO_KEEP=7
STAMPFILE="$LOGDIR/.last_rotation"

# Get printer state
STATE=$(curl -s http://localhost:7125/printer/objects/query?print_stats \
  | grep -o '"state":"[^"]*"' \
  | cut -d':' -f2 \
  | tr -d '"')

if [ "$STATE" = "printing" ]; then
    exit 0
fi

ROTATE=false

# Rotate if too large
if [ -f "$KLIPPY_LOG" ]; then
    FILESIZE=$(stat -c%s "$KLIPPY_LOG")
    if [ "$FILESIZE" -ge "$MAXSIZE" ]; then
        ROTATE=true
    fi
fi

# Rotate if new day
TODAY=$(date +%F)
if [ -f "$STAMPFILE" ]; then
    LASTDAY=$(cat "$STAMPFILE")
else
    LASTDAY=""
fi

if [ "$TODAY" != "$LASTDAY" ]; then
    ROTATE=true
fi

# Perform rotation
if [ "$ROTATE" = true ]; then
    mv "$KLIPPY_LOG" "$KLIPPY_LOG.$(date +%F_%H-%M-%S)"
    touch "$KLIPPY_LOG"
    echo "$TODAY" > "$STAMPFILE"
fi

# Compress rotated logs (not current)
find "$LOGDIR" -type f -name "klippy.log.20*" ! -name "*.gz" -exec gzip {} \;

# Delete logs older than X days
find "$LOGDIR" -type f -name "klippy.log.20*" -mtime +$DAYS_TO_KEEP -delete
