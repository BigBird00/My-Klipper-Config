#!/bin/bash
LOGDIR="/home/ajs/printer_data/logs"
LOGFILE="$LOGDIR/klippy.log"

if [ -f "$LOGFILE" ]; then
    mv "$LOGFILE" "$LOGFILE.$(date +%Y%m%d-%H%M%S)"
fi

touch "$LOGFILE"
chown ajs:ajs "$LOGFILE"
