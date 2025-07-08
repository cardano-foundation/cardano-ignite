#!/usr/bin/env bash

set -o errexit
set -o pipefail

SHELL="/bin/bash"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

# Environment variables
DB_ADMIN_DATABASE="${DB_ADMIN_DATABASE:-postgres}"
DB_ADMIN_PASSWORD="${DB_ADMIN_PASSWORD:-admin}"
DB_ADMIN_USERNAME="${DB_ADMIN_USERNAME:-admin}"
DB_DBSYNC_DATABASE="${DB_DBSYNC_DATABASE:-dbsync}"
DB_DBSYNC_PASSWORD="${DB_DBSYNC_PASSWORD:-dbsync}"
DB_DBSYNC_USERNAME="${DB_DBSYNC_USERNAME:-dbsync}"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-5432}"
LOG_TO_CONSOLE="${LOG_TO_CONSOLE:-true}"
MIN_SEVERITY="${MIN_SEVERITY:-Notice}"
NETWORK="${NETWORK:-testnet}"
NETWORK_ID="${NETWORK_ID:-42}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-8080}"

DB_OPTIONS="postgres://${DB_ADMIN_USERNAME}:${DB_ADMIN_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_ADMIN_DATABASE} --quiet"

# Configuration files
SRC_DIR="/opt/cardano-node/pools/1/configs"
DST_DIR="/opt/cardano-db-sync/cardano-node"
CONFIG_JSON_SRC="/opt/cardano-node/pools/1/configs/config.json"
CONFIG_JSON="/opt/cardano-db-sync/cardano-node/config.json"
DBSYNC_CONFIG_JSON_SRC="/usr/local/src/cardano-db-sync/config/config.json"
DBSYNC_CONFIG_JSON="/opt/cardano-db-sync/config/config.json"
PGPASS="/opt/cardano-db-sync/config/pgpass"

DB_SYNC_DATA="/opt/cardano-db-sync/data"
DB_SYNC_SCHEMA="/usr/local/src/cardano-db-sync/schema"
DB_SYNC_SCRIPTS="/usr/local/src/cardano-db-sync/scripts"

# Implement sponge-like command without the need for binary nor TMPDIR environment variable
write_file() {
    # Create temporary file
    local tmp_file="${1}_$(tr </dev/urandom -dc A-Za-z0-9 | head -c16)"

    # Redirect the output to the temporary file
    cat >"${tmp_file}"

    # Replace the original file
    mv --force "${tmp_file}" "${1}"
}

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

reset_configuration() {
    # Copy template configuration file
    cp --force ${SRC_DIR}/* "${DST_DIR}/"
    cp --force "${DBSYNC_CONFIG_JSON_SRC}" "${DBSYNC_CONFIG_JSON}"
}

insert_genesis_hashes() {
    ALONZO_GENESIS_JSON="$(cardano-cli conway genesis hash --genesis ${SRC_DIR}/alonzo-genesis.json)"
    BYRON_GENESIS_JSON="$(cardano-cli byron genesis print-genesis-hash --genesis-json ${SRC_DIR}/byron-genesis.json)"
    CONWAY_GENESIS_JSON="$(cardano-cli conway genesis hash --genesis ${SRC_DIR}/conway-genesis.json)"
    SHELLEY_GENESIS_JSON="$(cardano-cli latest genesis hash --genesis ${SRC_DIR}/shelley-genesis.json)"

    jq ".AlonzoGenesisHash = \"${ALONZO_GENESIS_JSON}\"" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
    jq ".ByronGenesisHash = \"${BYRON_GENESIS_JSON}\"" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
    jq ".ConwayGenesisHash = \"${CONWAY_GENESIS_JSON}\"" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
    jq ".ShelleyGenesisHash = \"${SHELLEY_GENESIS_JSON}\"" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
}

config_database_instance() {
    if [ $(psql ${DB_OPTIONS} --no-align --tuples-only --command="SELECT COUNT(*) FROM pg_database WHERE datname = '${DB_DBSYNC_DATABASE}';") -ne 1 ]; then
        psql ${DB_OPTIONS} --command="CREATE DATABASE ${DB_DBSYNC_DATABASE};"
    fi
}

config_database_user() {
    if [ $(psql ${DB_OPTIONS} --no-align --tuples-only --command="SELECT COUNT(*) FROM pg_roles WHERE rolname = '${DB_DBSYNC_USERNAME}';") -ne 1 ]; then
        psql ${DB_OPTIONS} --command="CREATE USER ${DB_DBSYNC_USERNAME} WITH PASSWORD '${DB_DBSYNC_PASSWORD}';"
        psql ${DB_OPTIONS} --command="ALTER ROLE ${DB_DBSYNC_USERNAME} WITH SUPERUSER;"
        psql ${DB_OPTIONS} --command="GRANT ALL PRIVILEGES ON DATABASE ${DB_DBSYNC_DATABASE} TO ${DB_DBSYNC_USERNAME};"
    fi
}

config_pgpass() {
    # hostname:port:database:username:password
    (
        cat <<EOF
${DB_HOST}:${DB_PORT}:${DB_DBSYNC_DATABASE}:${DB_DBSYNC_USERNAME}:${DB_DBSYNC_PASSWORD}
EOF
    ) >"${PGPASS}"

    chmod 0600 "${PGPASS}"
}

config_db_sync_config_json() {
    # .minSeverity
    jq ".minSeverity = \"${MIN_SEVERITY}\"" "${DBSYNC_CONFIG_JSON}" | write_file "${DBSYNC_CONFIG_JSON}"

    # .PrometheusPort
    jq ".PrometheusPort = ${PROMETHEUS_PORT}" "${DBSYNC_CONFIG_JSON}" | write_file "${DBSYNC_CONFIG_JSON}"

    # .defaultScribes, .setupScribes
    if [ "${LOG_TO_CONSOLE}" = "true" ]; then
        jq '."defaultScribes" = [["StdoutSK", "stdout"]]' "${DBSYNC_CONFIG_JSON}" | write_file "${DBSYNC_CONFIG_JSON}"

        jq '."setupScribes" = [{"scFormat": "ScText", "scKind": "StdoutSK", "scName": "stdout", "scRotation": null}]' "${DBSYNC_CONFIG_JSON}" | write_file "${DBSYNC_CONFIG_JSON}"
    fi
}

create_db_sync_database() {
    "${DB_SYNC_SCRIPTS}/postgresql-setup.sh" --createdb
}

setup_canary() {
    /get_canary_setup.sh >/dev/null 2>&1
}

start_process_exporter() {
    process_exporter -procnames cardano-db-sync,process_exporte
}

assemble_command() {
    cmd=(exec)
    cmd+=(/usr/local/bin/cardano-db-sync)
    cmd+=(--config "${DBSYNC_CONFIG_JSON}")
    cmd+=(--schema-dir "${DB_SYNC_SCHEMA}")
    cmd+=(--socket-path "${CARDANO_NODE_SOCKET_PATH}")
    cmd+=(--state-dir "${DB_SYNC_DATA}")
}

# Establish run order
main() {
    get_network_id
    wait_for_cardano_node
    wait_for_postgresql
    reset_configuration
    insert_genesis_hashes
    config_database_instance
    config_database_user
    config_pgpass
    config_db_sync_config_json
    create_db_sync_database
    setup_canary &
    start_process_exporter &
    assemble_command
    "${cmd[@]}"
}

main
