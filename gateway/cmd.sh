#!/usr/bin/env bash

set -o errexit
set -o pipefail

SHELL="/bin/bash"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

/opt/scripts/gw_routes.sh

iptables -A FORWARD -j ACCEPT

while true; do
    sleep 60
done
