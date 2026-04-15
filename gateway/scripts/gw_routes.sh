#!/usr/bin/env bash

set -o errexit
set -o pipefail

SHELL="/bin/bash"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

GATEWAY_ID="${GATEWAY_ID:-}"

case ${GATEWAY_ID} in
    "nagw")
        echo "starting North America Gateway"

        if ip route show scope link | grep -q '^172\.16\.2\.'; then
            echo "North America <-> Europe"
            GW="172.16.2.12"
            INTERFACE=$(ip route get "${GW}" | awk '{print $3}')
            ip route add 172.16.3.0/24 via "${GW}" dev "${INTERFACE}"
            tc qdisc replace dev "${INTERFACE}" root netem rate 1000mbit delay 50ms 3ms loss 0.5%
        fi

        if ip route show scope link | grep -q '^172\.16\.6\.'; then
            echo "North America <-> Asia"
            GW="172.16.6.13"
            INTERFACE=$(ip route get "${GW}" | awk '{print $3}')
            ip route add 172.16.4.0/24 via "${GW}" dev "${INTERFACE}"
            tc qdisc replace dev "${INTERFACE}" root netem rate 1000mbit delay 100ms 6ms loss 0.5%
        fi

        if ip route show scope link | grep -q '^172\.16\.10\.'; then
            echo "North America <-> Admin"
            GW="172.16.10.14"
            INTERFACE=$(ip route get "${GW}" | awk '{print $3}')
            ip route add 172.16.7.0/24 via "${GW}" dev "${INTERFACE}"
        fi
        ;;
    "eugw")
        echo "starting Europe Gateway"

        if ip route show scope link | grep -q '^172\.16\.2\.'; then
            echo "Europe <-> North America"
            GW="172.16.2.11"
            INTERFACE=$(ip route get "${GW}" | awk '{print $3}')
            ip route add 172.16.1.0/24 via "${GW}" dev "${INTERFACE}"
            tc qdisc replace dev "${INTERFACE}" root netem rate 1000mbit delay 50ms 3ms loss 0.5%
        fi

        if ip route show scope link | grep -q '^172\.16\.5\.'; then
            echo "Europe <-> Asia"
            GW="172.16.5.13"
            INTERFACE=$(ip route get "${GW}" | awk '{print $3}')
            ip route add 172.16.4.0/24 via "${GW}" dev "${INTERFACE}"
            tc qdisc replace dev "${INTERFACE}" root netem rate 1000mbit delay 75ms 6ms loss 0.5%
        fi

        if ip route show scope link | grep -q '^172\.16\.9\.'; then
            echo "Europe <-> Admin"
            GW="172.16.9.14"
            INTERFACE=$(ip route get "${GW}" | awk '{print $3}')
            ip route add 172.16.7.0/24 via "${GW}" dev "${INTERFACE}"
        fi
        ;;
    "asgw")
        echo "starting Asia Gateway"

        if ip route show scope link | grep -q '^172\.16\.5\.'; then
            echo "Asia <-> Europe"
            GW="172.16.5.12"
            INTERFACE=$(ip route get "${GW}" | awk '{print $3}')
            ip route add 172.16.3.0/24 via "${GW}" dev "${INTERFACE}"
            tc qdisc replace dev "${INTERFACE}" root netem rate 1000mbit delay 75ms 6ms loss 0.5%
        fi

        if ip route show scope link | grep -q '^172\.16\.6\.'; then
            echo "Asia <-> North America"
            GW="172.16.6.11"
            INTERFACE=$(ip route get "${GW}" | awk '{print $3}')
            ip route add 172.16.1.0/24 via "${GW}" dev "${INTERFACE}"
            tc qdisc replace dev "${INTERFACE}" root netem rate 1000mbit delay 100ms 6ms loss 0.5%
        fi

        if ip route show scope link | grep -q '^172\.16\.8\.'; then
            echo "Asia <-> Admin"
            GW="172.16.8.14"
            INTERFACE=$(ip route get "${GW}" | awk '{print $3}')
            ip route add 172.16.7.0/24 via "${GW}" dev "${INTERFACE}"
        fi
        ;;
    "adgw")
        echo "starting Admin Gateway"

        if ip route show scope link | grep -q '^172\.16\.9\.'; then
            echo "Admin <-> Europe"
            GW="172.16.9.12"
            INTERFACE=$(ip route get "${GW}" | awk '{print $3}')
            ip route add 172.16.3.0/24 via "${GW}" dev "${INTERFACE}"
        fi

        if ip route show scope link | grep -q '^172\.16\.10\.'; then
            echo "Admin <-> North America"
            GW="172.16.10.11"
            INTERFACE=$(ip route get "${GW}" | awk '{print $3}')
            ip route add 172.16.1.0/24 via "${GW}" dev "${INTERFACE}"
        fi

        if ip route show scope link | grep -q '^172\.16\.8\.'; then
            echo "Admin <-> Asia"
            GW="172.16.8.13"
            INTERFACE=$(ip route get "${GW}" | awk '{print $3}')
            ip route add 172.16.4.0/24 via "${GW}" dev "${INTERFACE}"
        fi
        ;;
    *)
        echo "unknown Gateway"
        ;;
esac
