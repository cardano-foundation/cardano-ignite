#!/usr/bin/env bash

# Required for overriding exit code
#set -o errexit
set -o pipefail

SHELL="/bin/bash"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

# Environment variables
LOCAL_DELAY="${LOCAL_DELAY:-5ms}"
LOCAL_JITTER="${LOCAL_JITTER:-1ms}"
LOCAL_LOSS="${LOCAL_LOSS:-0.01%}"

# Configuration files
BYRON_GENESIS_JSON="${BYRON_GENESIS_JSON:-/opt/yaci/config/byron-genesis.json}"
SHELLEY_GENESIS_JSON="${SHELLEY_GENESIS_JSON:-/opt/yaci/config/shelley-genesis.json}"
DATA_PATH="/opt/cardano-node/data"

# Implement sponge-like command without the need for binary nor TMPDIR environment variable
write_file() {
    # Create temporary file
    local tmp_file="${1}_$(tr </dev/urandom -dc A-Za-z0-9 | head -c16)"

    # Redirect the output to the temporary file
    cat >"${tmp_file}"

    # Replace the original file
    mv --force "${tmp_file}" "${1}"
}

set_start_time() {
    # Wait until cardano-node creates the the start_time file
    while [ ! -f "${DATA_PATH}/start_time.unix_epoch" ]; do
        sleep 1
    done

    SYSTEM_START_UNIX="$(cat "${DATA_PATH}/start_time.unix_epoch")"

    update_start_time
}

update_start_time() {
    # Convert unix epoch to ISO time
    SYSTEM_START_ISO="$(date -d @${SYSTEM_START_UNIX} '+%Y-%m-%dT%H:%M:%SZ')"

    # .systemStart
    jq ".systemStart = \"${SYSTEM_START_ISO}\"" "${SHELLEY_GENESIS_JSON}" | write_file "${SHELLEY_GENESIS_JSON}"

    # .startTime
    jq ".startTime = ${SYSTEM_START_UNIX}" "${BYRON_GENESIS_JSON}" | write_file "${BYRON_GENESIS_JSON}"
}

add_routes() {
    case ${REGION} in
        "NA")
            doas ip route add 172.16.2.0/24 via 172.16.1.11 dev eth0
            doas ip route add 172.16.3.0/24 via 172.16.1.11 dev eth0
            doas ip route add 172.16.4.0/24 via 172.16.1.11 dev eth0
            doas ip route add 172.16.7.0/24 via 172.16.1.11 dev eth0
            doas tc qdisc replace dev eth0 root netem delay ${LOCAL_DELAY} ${LOCAL_JITTER} loss ${LOCAL_LOSS}
            ;;
        "EU")
            doas ip route add 172.16.1.0/24 via 172.16.3.12 dev eth0
            doas ip route add 172.16.2.0/24 via 172.16.3.12 dev eth0
            doas ip route add 172.16.4.0/24 via 172.16.3.12 dev eth0
            doas ip route add 172.16.7.0/24 via 172.16.3.12 dev eth0
            doas tc qdisc replace dev eth0 root netem delay ${LOCAL_DELAY} ${LOCAL_JITTER} loss ${LOCAL_LOSS}
            ;;
        "AS")
            doas ip route add 172.16.1.0/24 via 172.16.4.13 dev eth0
            doas ip route add 172.16.2.0/24 via 172.16.4.13 dev eth0
            doas ip route add 172.16.3.0/24 via 172.16.4.13 dev eth0
            doas ip route add 172.16.7.0/24 via 172.16.4.13 dev eth0
            doas tc qdisc replace dev eth0 root netem delay ${LOCAL_DELAY} ${LOCAL_JITTER} loss ${LOCAL_LOSS}
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
}

start_node_exporter() {
    node_exporter >/dev/null 2>&1
}

start_process_exporter() {
    process_exporter -procnames yaci-store,node_exporter,process_exporte
}

main () {
    set_start_time
    add_routes
    start_node_exporter &
    start_process_exporter &

    cd /opt/yaci
    SPRING_PROFILES_ACTIVE=ledger-state ./yaci-store
}

main
