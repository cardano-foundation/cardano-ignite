#!/usr/bin/env bash

set -o errexit
set -o pipefail

SHELL="/bin/bash"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

# Environment variables
NETWORK="${NETWORK:-testnet}"
NETWORK_ID="${NETWORK_ID:-42}"
SINK_COMPRESS_FILES="${SINK_COMPRESS_FILES:-true}"
SINK_MAX_BYTES_PER_FILE="${SINK_MAX_BYTES_PER_FILE:-1_000_000}"
SINK_MAX_TOTAL_FILES="${SINK_MAX_TOTAL_FILES:-10}"
SINK_OUTPUT_FORMAT="${SINK_OUTPUT_FORMAT:-JSONL}"
SINK_OUTPUT_PATH="/var/local/oura/logs"
SINK_THROTTLE_MIN_SPAN_MILLIS="${SINK_THROTTLE_MIN_SPAN_MILLIS:-500}"
SINK_TYPE="${SINK_TYPE:-Terminal}"
SINK_WRAP="${SINK_WRAP:-true}"
SOURCE_ADDRESS="${SOURCE_ADDRESS:-${CARDANO_NODE_SOCKET_PATH}}"
SOURCE_TYPE="${SOURCE_TYPE:-N2C}"

# Configuration files
CONFIG_SRC="/usr/local/etc/oura"
CONFIG_DST="/opt/oura/config"

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

get_cardano_node_type() {
    if echo "${SOURCE_ADDRESS}" | grep -qE '^\/|^\.\.?\/'; then
        cardano_node_type="socket"
    elif echo "${SOURCE_ADDRESS}" | grep -q ':'; then
        cardano_node_type="address"
    else
        echo "* Unable to get 'cardano-node' type. Please specify a valid address or socket path. Exiting..."
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

    if [ "${cardano_node_type}" = "socket" ]; then
        cmd+=(--unixsock "${SOURCE_ADDRESS}")
        cmd+=(--tip)
    else
        cmd+=(--host "${SOURCE_ADDRESS%:*}")
        cmd+=(--port "${SOURCE_ADDRESS##*:}")
        cmd+=(--tip)
        cmd+=(--count 1)
    fi

    i=0
    wait=90
    sleep 3
    # shellcheck disable=SC2068,SC2143
    until [ "$(${cmd[@]} | grep 'handshake rtt:')" ]; do
        if [ ${i} -lt ${wait} ]; then
            echo "* Trying to connect to 'cardano-node' on ${cardano_node_type} '${SOURCE_ADDRESS}'..."
        else
            echo "* Unable to connect to 'cardano-node' on ${cardano_node_type} '${SOURCE_ADDRESS}', giving up..."
            exit 1
        fi
        i=$((i + 1))
        sleep 3
    done
    echo "* Connection to 'cardano-node' on ${cardano_node_type} '${SOURCE_ADDRESS}' was successful."
}

reset_configuration() {
    # Purge existing configuration files
    for file in ${CONFIG_DST}/daemon.toml; do
        if [ -f "${file}" ]; then
            rm --force "${file}"
        fi
    done

    # Copy oura configuration file
    if [ ! -f "${CONFIG_DST}/daemon.toml" ]; then
        touch "${CONFIG_DST}/daemon.toml"
    fi
}

assemble_daemon_toml() {
    # source
    cat "${CONFIG_SRC}/source.toml" >"${CONFIG_DST}/daemon.toml"

    # filter
    cat "${CONFIG_SRC}/filters.toml" >>"${CONFIG_DST}/daemon.toml"

    # sink
    if [ "${SINK_TYPE,,}" = "logs" ]; then
        cat "${CONFIG_SRC}/sink-logs.toml" >>"${CONFIG_DST}/daemon.toml"
    else
        cat "${CONFIG_SRC}/sink-terminal.toml" >>"${CONFIG_DST}/daemon.toml"
    fi
}

config_daemon_toml() {
    if [ "${NETWORK,,}" = "mainnet" ]; then
        SOURCE_MAGIC="mainnet"
    elif [ "${NETWORK,,}" = "preprod" ]; then
        SOURCE_MAGIC="preprod"
    elif [ "${NETWORK,,}" = "preview" ]; then
        SOURCE_MAGIC="preview"
    elif [ "${NETWORK,,}" = "testnet" ]; then
        SOURCE_MAGIC="testnet"
    else
        echo "* Please define a supported network ('mainnet', 'testnet', 'preprod', 'preview'). Exiting..."
        sleep 60
        exit 1
    fi

    # source.type / source.address
    if [ "${SOURCE_TYPE,,}" = "n2c" ] || [ "${cardano_node_type}" = "socket" ]; then
        sed -i "/^\[source\]$/,/^\[/ s@^type = .*@type = \"N2C\"@" "${CONFIG_DST}/daemon.toml"
        sed -i "/^\[source\]$/,/^\[/ s@^address = .*@address = [\"Unix\", \"${SOURCE_ADDRESS}\"]@" "${CONFIG_DST}/daemon.toml"
    else
        sed -i "/^\[source\]$/,/^\[/ s@^type = .*@type = \"N2N\"@" "${CONFIG_DST}/daemon.toml"
        sed -i "/^\[source\]$/,/^\[/ s@^address = .*@address = [\"Tcp\", \"${SOURCE_ADDRESS}\"]@" "${CONFIG_DST}/daemon.toml"
    fi

    # source.magic
    sed -i "/^\[source\]$/,/^\[/ s@^magic = .*@magic = \"${NETWORK_ID}\"@" "${CONFIG_DST}/daemon.toml"

    # sink.*
    if [ "${SINK_TYPE,,}" = "terminal" ]; then
        sed -i "/^\[sink\]$/,/^\[/ s@^throttle_min_span_millis = .*@throttle_min_span_millis = ${SINK_THROTTLE_MIN_SPAN_MILLIS}@" "${CONFIG_DST}/daemon.toml"

        if [ "${SINK_WRAP}" = "false" ]; then
            sed -i "/^\[sink\]$/,/^\[/ s@^wrap = .*@wrap = false@" "${CONFIG_DST}/daemon.toml"
        else
            sed -i "/^\[sink\]$/,/^\[/ s@^wrap = .*@wrap = true@" "${CONFIG_DST}/daemon.toml"
        fi
    else
        sed -i "/^\[sink\]$/,/^\[/ s@^output_path = .*@output_path = \"${SINK_OUTPUT_PATH}\"@" "${CONFIG_DST}/daemon.toml"
        sed -i "/^\[sink\]$/,/^\[/ s@^output_format = .*@output_format = \"${SINK_OUTPUT_FORMAT}\"@" "${CONFIG_DST}/daemon.toml"
        sed -i "/^\[sink\]$/,/^\[/ s@^max_bytes_per_file = .*@max_bytes_per_file = ${SINK_MAX_BYTES_PER_FILE}@" "${CONFIG_DST}/daemon.toml"
        sed -i "/^\[sink\]$/,/^\[/ s@^max_total_files = .*@max_total_files = ${SINK_MAX_TOTAL_FILES}@" "${CONFIG_DST}/daemon.toml"

        if [ "${SINK_COMPRESS_FILES}" = "false" ]; then
            sed -i "/^\[sink\]$/,/^\[/ s@^compress_files = .*@compress_files = false@" "${CONFIG_DST}/daemon.toml"
        else
            sed -i "/^\[sink\]$/,/^\[/ s@^compress_files = .*@compress_files = true@" "${CONFIG_DST}/daemon.toml"
        fi
    fi
}

assemble_command() {
    cmd=(exec)
    cmd+=(/usr/local/bin/oura)
    cmd+=(daemon)
    cmd+=(--config "${CONFIG_DST}/daemon.toml")
}

# Establish run order
main() {
    get_network_id
    get_cardano_node_type
    wait_for_cardano_node
    reset_configuration
    assemble_daemon_toml
    config_daemon_toml
    assemble_command
    "${cmd[@]}"
}

main
