#!/usr/bin/env bash

set -o errexit
set -o pipefail

SHELL="/bin/bash"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

GATEWAY_ID="${GATEWAY_ID:-}"
GATEWAY_PEERS="${GATEWAY_PEERS:-}"

add_route() {
    local dst="$1" gw="$2" netem="$3"
    local iface
    iface=$(ip route get "${gw}" | awk 'NR==1 { for (i=1; i<=NF; i++) if ($i=="dev") print $(i+1) }')
    ip route replace "${dst}" via "${gw}" dev "${iface}"
    if [ -n "${netem}" ]; then
        tc qdisc replace dev "${iface}" root netem ${netem}
    fi
}

echo "starting gateway ${GATEWAY_ID} with peers: ${GATEWAY_PEERS}"

for peer in ${GATEWAY_PEERS}; do
    case "${GATEWAY_ID}:${peer}" in
        "nagw:eu") add_route 172.16.3.0/24 172.16.2.12  "rate 1000mbit delay 50ms 3ms loss 0.5%" ;;
        "nagw:as") add_route 172.16.4.0/24 172.16.6.13  "rate 1000mbit delay 100ms 6ms loss 0.5%" ;;
        "nagw:ad") add_route 172.16.7.0/24 172.16.10.14 "" ;;

        "eugw:na") add_route 172.16.1.0/24 172.16.2.11  "rate 1000mbit delay 50ms 3ms loss 0.5%" ;;
        "eugw:as") add_route 172.16.4.0/24 172.16.5.13  "rate 1000mbit delay 75ms 6ms loss 0.5%" ;;
        "eugw:ad") add_route 172.16.7.0/24 172.16.9.14  "" ;;

        "asgw:eu") add_route 172.16.3.0/24 172.16.5.12  "rate 1000mbit delay 75ms 6ms loss 0.5%" ;;
        "asgw:na") add_route 172.16.1.0/24 172.16.6.11  "rate 1000mbit delay 100ms 6ms loss 0.5%" ;;
        "asgw:ad") add_route 172.16.7.0/24 172.16.8.14  "" ;;

        "adgw:eu") add_route 172.16.3.0/24 172.16.9.12  "" ;;
        "adgw:na") add_route 172.16.1.0/24 172.16.10.11 "" ;;
        "adgw:as") add_route 172.16.4.0/24 172.16.8.13  "" ;;

        *)
            echo "unknown gateway/peer combo: ${GATEWAY_ID}:${peer}" >&2
            exit 1
            ;;
    esac
done
