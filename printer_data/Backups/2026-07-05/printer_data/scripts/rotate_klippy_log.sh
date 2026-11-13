#!/bin/bash
LOG_DIR="$HOME/printer_data/logs"
LOG="$LOG_DIR/klippy.log"

# Timestamp for the rotated file
STAMP=$(date +"%Y-%m-%d_%H-%M-%S")

# Only rotate if the log exists
if [ -f "$LOG" ]; then
    mv "$LOG" "$LOG_DIR/klippy_$STAMP.log"
fi

# Touch a new empty log file
touch "$LOG"
