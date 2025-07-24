#!/usr/bin/env bash
set -o errexit
set -o pipefail

LOCAL_DELAY="${LOCAL_DELAY:-5ms}"
LOCAL_JITTER="${LOCAL_JITTER:-1ms}"
LOCAL_LOSS="${LOCAL_LOSS:-0.01%}"

case ${REGION} in
    "NA")
        doas ip route add 172.16.2.0/24 via 172.16.1.11 dev eth0
        doas ip route add 172.16.3.0/24 via 172.16.1.11 dev eth0
        doas ip route add 172.16.4.0/24 via 172.16.1.11 dev eth0
        doas ip route add 172.16.7.0/24 via 172.16.1.11 dev eth0
        doas tc qdisc replace dev eth0 root netem rate 100mbit delay ${LOCAL_DELAY} ${LOCAL_JITTER} loss ${LOCAL_LOSS}
        ;;
    "EU")
        doas ip route add 172.16.1.0/24 via 172.16.3.12 dev eth0
        doas ip route add 172.16.2.0/24 via 172.16.3.12 dev eth0
        doas ip route add 172.16.4.0/24 via 172.16.3.12 dev eth0
        doas ip route add 172.16.7.0/24 via 172.16.3.12 dev eth0
        doas tc qdisc replace dev eth0 root netem rate 100mbit delay ${LOCAL_DELAY} ${LOCAL_JITTER} loss ${LOCAL_LOSS}
        ;;
    "AS")
        doas ip route add 172.16.1.0/24 via 172.16.4.13 dev eth0
        doas ip route add 172.16.2.0/24 via 172.16.4.13 dev eth0
        doas ip route add 172.16.3.0/24 via 172.16.4.13 dev eth0
        doas ip route add 172.16.7.0/24 via 172.16.4.13 dev eth0
        doas tc qdisc replace dev eth0 root netem rate 100mbit delay ${LOCAL_DELAY} ${LOCAL_JITTER} loss ${LOCAL_LOSS}
        ;;
    "AD")
        doas ip route add 172.16.1.0/24 via 172.16.7.14 dev eth0
        doas ip route add 172.16.2.0/24 via 172.16.7.14 dev eth0
        doas ip route add 172.16.3.0/24 via 172.16.7.14 dev eth0
        doas ip route add 172.16.4.0/24 via 172.16.7.14 dev eth0
        ;;
    *)
        true
        ;;
esac
