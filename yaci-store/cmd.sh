#!/usr/bin/env bash

set -o errexit
set -o pipefail

SHELL="/bin/bash"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

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

start_node_exporter() {
    node_exporter >/dev/null 2>&1
}

start_process_exporter() {
    process_exporter -procnames yaci-store,node_exporter,process_exporte
}

main () {
    set_start_time
    /node_routes.sh
    start_node_exporter &
    start_process_exporter &

    # Yaci-store can't handle early forks.
    # Wait until c1's tip is at least on block number 3.
    /wait_on_tip.sh c1.example 3001 3
    cd /opt/yaci
    SPRING_PROFILES_ACTIVE=ledger-state ./yaci-store
}

main
