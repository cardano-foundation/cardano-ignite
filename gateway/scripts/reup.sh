#!/bin/bash

# Bring all down interfaces back up

ip -4 -br addr show | awk 'NR > 1 && $2 == "DOWN" {print $1}' | while read -r full_interface; do
    interface="${full_interface%%@*}"
    echo "Bringing interface $interface back up"
    ip link set "$interface" up
done
