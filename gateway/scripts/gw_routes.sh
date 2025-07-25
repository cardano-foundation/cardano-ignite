#!/usr/bin/env bash

set -o errexit
set -o pipefail

GATEWAY_ID="${GATEWAY_ID:-}"

SHELL="/bin/bash"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

case ${GATEWAY_ID} in
    "nagw")
        echo "starting North America Gateway"

        echo "North America <-> Europe"
        GW="172.16.2.12"
        INTERFACE=$(ip route get "${GW}" | awk '{print $3}')
        ip route add 172.16.3.0/24 via "${GW}" dev "${INTERFACE}"
        tc qdisc replace dev "${INTERFACE}" root netem rate 1000mbit delay 50ms 3ms loss 0.5%

        echo "North America <-> Asia"
        GW="172.16.6.13"
        INTERFACE=$(ip route get "${GW}" | awk '{print $3}')
        ip route add 172.16.4.0/24 via "${GW}" dev "${INTERFACE}"
        tc qdisc replace dev "${INTERFACE}" root netem rate 1000mbit delay 100ms 6ms loss 0.5%

        echo "North America <-> Admin"
        GW="172.16.10.14"
        INTERFACE=$(ip route get "${GW}" | awk '{print $3}')
        ip route add 172.16.7.0/24 via "${GW}" dev "${INTERFACE}"
        ;;
    "eugw")
        echo "starting Europe Gateway"

        echo "Europe <-> North America"
        GW="172.16.2.11"
        INTERFACE=$(ip route get "${GW}" | awk '{print $3}')
        ip route add 172.16.1.0/24 via "${GW}" dev "${INTERFACE}"
        tc qdisc replace dev "${INTERFACE}" root netem rate 1000mbit delay 50ms 3ms loss 0.5%

        echo "Europe <-> Asia"
        GW="172.16.5.13"
        INTERFACE=$(ip route get "${GW}" | awk '{print $3}')
        ip route add 172.16.4.0/24 via "${GW}" dev "${INTERFACE}"
        tc qdisc replace dev "${INTERFACE}" root netem rate 1000mbit delay 75ms 6ms loss 0.5%

        echo "Europe <-> Admin"
        GW="172.16.9.14"
        INTERFACE=$(ip route get "${GW}" | awk '{print $3}')
        ip route add 172.16.7.0/24 via "${GW}" dev "${INTERFACE}"
        ;;
    "asgw")
        echo "starting Asia Gateway"

        echo "Asia <-> Europe"
        GW="172.16.5.12"
        INTERFACE=$(ip route get "${GW}" | awk '{print $3}')
        ip route add 172.16.3.0/24 via "${GW}" dev "${INTERFACE}"
        tc qdisc replace dev "${INTERFACE}" root netem rate 1000mbit delay 75ms 6ms loss 0.5%

        echo "Asia <-> North America"
        GW="172.16.6.11"
        INTERFACE=$(ip route get "${GW}" | awk '{print $3}')
        ip route add 172.16.1.0/24 via "${GW}" dev "${INTERFACE}"
        tc qdisc replace dev "${INTERFACE}" root netem rate 1000mbit delay 100ms 6ms loss 0.5%

        echo "Asia <-> Admin"
        GW="172.16.8.14"
        INTERFACE=$(ip route get "${GW}" | awk '{print $3}')
        ip route add 172.16.7.0/24 via "${GW}" dev "${INTERFACE}"
        ;;
    "adgw")
        echo "starting Admin Gateway"

        echo "Admin <-> Europe"
        GW="172.16.9.12"
        INTERFACE=$(ip route get "${GW}" | awk '{print $3}')
        ip route add 172.16.3.0/24 via "${GW}" dev "${INTERFACE}"

        echo "Admin <-> North America"
        GW="172.16.10.11"
        INTERFACE=$(ip route get "${GW}" | awk '{print $3}')
        ip route add 172.16.1.0/24 via "${GW}" dev "${INTERFACE}"

        echo "Admin <-> Asia"
        GW="172.16.8.13"
        INTERFACE=$(ip route get "${GW}" | awk '{print $3}')
        ip route add 172.16.4.0/24 via "${GW}" dev "${INTERFACE}"
        ;;
    *)
        echo "unknown Gateway"
        ;;
esac
