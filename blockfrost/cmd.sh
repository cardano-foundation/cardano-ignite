#!/usr/bin/env bash

set -o errexit
set -o pipefail

SHELL="/bin/bash"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

# Environment variables
DB_DBSYNC_DATABASE="${DB_DBSYNC_DATABASE:-dbsync}"
DB_DBSYNC_PASSWORD="${DB_DBSYNC_PASSWORD:-dbsync}"
DB_DBSYNC_USERNAME="${DB_DBSYNC_USERNAME:-dbsync}"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-5432}"
NETWORK="${NETWORK:-testnet}"
NETWORK_ID="${NETWORK_ID:-42}"

DB_OPTIONS="postgres://${DB_DBSYNC_USERNAME}:${DB_DBSYNC_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_DBSYNC_DATABASE} --quiet"

export BLOCKFROST_CONFIG_DBSYNC_DATABASE="${DB_DBSYNC_DATABASE:-dbsync}"
export BLOCKFROST_CONFIG_DBSYNC_HOST="${DB_HOST:-127.0.0.1}"
export BLOCKFROST_CONFIG_DBSYNC_MAX_CONN="${BLOCKFROST_CONFIG_DBSYNC_MAX_CONN:-10}"
export BLOCKFROST_CONFIG_DBSYNC_PASSWORD="${DB_DBSYNC_PASSWORD:-dbsync}"
export BLOCKFROST_CONFIG_DBSYNC_PORT="${DB_PORT:-5432}"
export BLOCKFROST_CONFIG_DBSYNC_USER="${DB_DBSYNC_USERNAME:-dbsync}"
export BLOCKFROST_CONFIG_NETWORK="${NETWORK:-testnet}"
export BLOCKFROST_CONFIG_SERVER_DEBUG="${BLOCKFROST_CONFIG_SERVER_DEBUG:-true}"
export BLOCKFROST_CONFIG_SERVER_LISTEN_ADDRESS="${BLOCKFROST_CONFIG_SERVER_LISTEN_ADDRESS:-0.0.0.0}"
export BLOCKFROST_CONFIG_SERVER_PORT="${BLOCKFROST_CONFIG_SERVER_PORT:-3000}"
export BLOCKFROST_CONFIG_TOKEN_REGISTRY_URL="${BLOCKFROST_CONFIG_TOKEN_REGISTRY_URL:-https://tokens.cardano.org}"

get_network_id() {
    if [ "${NETWORK,,}" = "mainnet" ]; then
        unset NETWORK_ID
    elif [ "${NETWORK,,}" = "preprod" ]; then
        NETWORK_ID="${NETWORK_ID:-1}"
    elif [ "${NETWORK,,}" = "preview" ]; then
        NETWORK_ID="${NETWORK_ID:-2}"
    elif [ "${NETWORK}" = "testnet" ] && [ "${NETWORK_ID}" != "" ]; then
        NETWORK_ID="${NETWORK_ID:-}"
    else
        echo "* Unable to get 'cardano-node' network ID (NETWORK_ID). Exiting..."
        sleep 60
        exit 1
    fi
}

wait_for_cardano_node() {
    # Wait until 'cardano-node' is available
    cmd=(timeout 10)
    cmd+=(cardano-cli)
    cmd+=(ping)

    if [ -n "${NETWORK_ID}" ]; then
        cmd+=(--magic "${NETWORK_ID}")
    fi

    cmd+=(--unixsock "${CARDANO_NODE_SOCKET_PATH}")
    cmd+=(--tip)

    i=0
    wait=90
    sleep 3
    until [ "$(${cmd[@]} | grep 'handshake rtt:')" ]; do
        if [ ${i} -lt ${wait} ]; then
            echo "* Trying to connect to 'cardano-node' on socket '${CARDANO_NODE_SOCKET_PATH}'..."
        else
            echo "* Unable to connect to 'cardano-node' on socket '${CARDANO_NODE_SOCKET_PATH}', giving up..."
            exit 1
        fi
        i=$((i + 1))
        sleep 3
    done
    echo "* Connection to 'cardano-node' on socket '${CARDANO_NODE_SOCKET_PATH}' was successful."
}

wait_for_postgresql() {
    # Wait until 'postgresql' is available
    cmd="psql ${DB_OPTIONS} --list"
    i=0
    wait=90
    sleep 1
    until ${cmd} >/dev/null 2>&1; do
        if [ ${i} -lt ${wait} ]; then
            echo "* Trying to connect to 'postgresql' on address '${DB_HOST}:${DB_PORT}'..."
        else
            echo "* Unable to connect to 'postgresql' on address '${DB_HOST}:${DB_PORT}', giving up..."
            exit 1
        fi
        i=$((i + 1))
        sleep 3
    done
    echo "* Connection to 'postgresql' on address '${DB_HOST}:${DB_PORT}' was successful."
}

create_indices() {
    psql ${DB_OPTIONS} -v 'ON_ERROR_STOP=1' -f '/usr/local/src/blockfrost-backend-ryo/indices.sql'
}

start_process_exporter() {
    process_exporter -procnames node,process_exporte
}

assemble_command() {
    cmd=(exec)
    cmd+=(node)
    cmd+=(/usr/local/src/blockfrost-backend-ryo/dist/server.js)
}

# Establish run order
main() {
    get_network_id
    wait_for_cardano_node
    wait_for_postgresql
    create_indices
    start_process_exporter &
    assemble_command
    "${cmd[@]}"
}

main
