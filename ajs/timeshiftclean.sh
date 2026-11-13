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

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo)."
    exit 1
fi

echo "Measuring disk space before cleanup..."
before=$(df --output=avail / | tail -1)

echo "Deleting all Timeshift snapshots..."
timeshift --delete-all

echo "Measuring disk space after cleanup..."
after=$(df --output=avail / | tail -1)

freed=$((after - before))

echo "----------------------------------------"
printf "Disk space before: %'15d KB\n" "$before" 
printf "Disk space after : %'15d KB\n" "$after"
echo "----------------------------------------"
printf "Total space freed: %'15d KB\n" "$freed"
echo "----------------------------------------"

# Convert to human-readable MB/GB
echo "Human-readable:"
printf "Total space freed: %s\n" "$(human "$freed")"




