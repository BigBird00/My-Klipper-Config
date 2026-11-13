#!/bin/bash

# wifi.sh
# program to connect pcie wifi adapter to an SSID given the pw

# Check for required arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <SSID> <PASSWORD>"
    echo "Error: SSID and password are required."
    exit 1
fi

SSID="$1"
PW="$2"

# Run the nmcli command
sudo nmcli device wifi connect "$SSID" password "$PW"
