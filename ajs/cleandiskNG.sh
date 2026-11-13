#!/bin/bash

human() {
    local n=$1
    if (( n >= 1024*1024 )); then
        printf "%.2f GB" "$(echo "$n / 1024 / 1024" | bc -l)"
    elif (( n >= 1024 )); then
        printf "%.2f MB" "$(echo "$n / 1024" | bc -l)"
    else
        printf "%'d KB" "$n"
    fi
}

# Capture baseline
before=$(df --output=used / | tail -1)
current_usage=$before

# 1. Apt Autoremove
echo "Running apt autoremove..."
sudo apt autoremove --purge -y > /dev/null
after_autoremove=$(df --output=used / | tail -1)
freed_autoremove=$((current_usage - after_autoremove))
current_usage=$after_autoremove

# 2. Apt Clean
echo "Running apt clean..."
sudo apt clean
after_aptclean=$(df --output=used / | tail -1)
freed_aptclean=$((current_usage - after_aptclean))
current_usage=$after_aptclean

# 3. Var Log
echo "Cleaning Var Log..."
sudo find /var/log -type f -mtime +1 -delete 2>/dev/null
after_vl=$(df --output=used / | tail -1)
freed_vl=$((current_usage - after_vl))
current_usage=$after_vl

# 4. Journals
echo "Cleaning Journals..."
sudo journalctl --vacuum-time=1d > /dev/null
after_journals=$(df --output=used / | tail -1)
freed_journals=$((current_usage - after_journals))
current_usage=$after_journals

totalfreed=$((before - current_usage))

echo "----------------------------------------"
printf "                  Disk space before: %'15d KB\n" "$before"
printf "Disk space freed by apt autoremove : %'15d KB\n" "$freed_autoremove"
printf "     Disk space freed via apt clean: %'15d KB\n" "$freed_aptclean"
printf "       Disk space freed via VarLogs: %'15d KB\n" "$freed_vl"
printf "      Disk space freed via Journals: %'15d KB\n" "$freed_journals"
echo "----------------------------------------"
printf "                  Total space freed: %'15d KB (%s)\n" "$totalfreed" "$(human "$totalfreed")"
echo "----------------------------------------"

echo ""
echo "Done freeing space, showing 15 largest directories..."
echo ""
sudo du -a / 2>/dev/null | sort -n -r | head -n 15
echo "Complete"