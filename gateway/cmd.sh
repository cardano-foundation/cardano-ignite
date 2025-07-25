#!/usr/bin/env bash

set -o errexit
set -o pipefail

SHELL="/bin/bash"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

/opt/scripts/gw_routes.sh

iptables -A FORWARD -j ACCEPT

node_exporter >/dev/null 2>&1

