#!/usr/bin/env bash

set -o errexit
set -o pipefail

SHELL="/bin/bash"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

# Environment variables
DB_HOST="${DB_HOST:-db.example}"
DB_PORT="${DB_PORT:-5432}"
DB_SIDECAR_DATABASE="${DB_SIDECAR_DATABASE:-sidecar}"
DB_SIDECAR_PASSWORD="${DB_SIDECAR_PASSWORD:-sidecar}"
DB_SIDECAR_USERNAME="${DB_SIDECAR_USERNAME:-sidecar}"
EGRESS_POLL_INTERVAL="${EGRESS_POLL_INTERVAL:-0}"
EKG_PORT="${EKG_PORT:-12788}"
NO_INTERPOOL_LOCALROOTS="${NO_INTERPOOL_LOCALROOTS:-false}"
LOG_TO_CONSOLE="${LOG_TO_CONSOLE:-true}"
LOG_TO_FILE="${LOG_TO_FILE:-true}"
MIN_SEVERITY="${MIN_SEVERITY:-Info}"
OUROBOROS_GENESIS="${OUROBOROS_GENESIS:-false}"
PEER_SHARING="${PEER_SHARING:-true}"
POOL_ID="${POOL_ID:-}"
PORT="${PORT:-3001}"
PROMETHEUS_LISTEN="${PROMETHEUS_LISTEN:-0.0.0.0}"
PROMETHEUS_PORT="${PROMETHEUS_PORT:-12798}"
SYSTEM_START="${SYSTEM_START:-$(date -d "@$(( ( $(date +%s) / 180 ) * 180 ))" +%Y-%m-%dT%H:%M:00Z)}"
TPS="${TSP:-1}"
TYPE="${TYPE:-bprelay}"
USE_LEDGER_AFTER_SLOT="${USE_LEDGER_AFTER_SLOT:-0}"
UTXOHD="${UTXOHD:-false}"

# Configuration files
BYRON_GENESIS_JSON="${BYRON_GENESIS_JSON:-/opt/cardano-node/pools/${POOL_ID}/configs/byron-genesis.json}"
CONFIG_JSON="/opt/cardano-node/pools/${POOL_ID}/configs/config.json"
CONFIG_PATH="/opt/cardano-node/config"
DATA_PATH="/opt/cardano-node/data"
DATABASE_PATH="/opt/cardano-node/data/db"
KEY_PATH="/opt/cardano-node/pools/${POOL_ID}/keys"
SHELLEY_GENESIS_JSON="${SHELLEY_GENESIS_JSON:-/opt/cardano-node/pools/${POOL_ID}/configs/shelley-genesis.json}"
SOCKET_PATH="/opt/cardano-node/data/db/node.socket"
PGPASS="$HOME/.pgpass"

# Log file
LOG_FILE="/opt/cardano-node/log/node.json"

# Implement sponge-like command without the need for binary nor TMPDIR environment variable
write_file() {
    # Create temporary file
    local tmp_file="${1}_$(tr </dev/urandom -dc A-Za-z0-9 | head -c16)"

    # Redirect the output to the temporary file
    cat >"${tmp_file}"

    # Replace the original file
    mv --force "${tmp_file}" "${1}"
}

config_pgpass() {
    # hostname:port:database:username:password
    (
        cat <<EOF
${DB_HOST}:${DB_PORT}:${DB_SIDECAR_DATABASE}:${DB_SIDECAR_USERNAME}:${DB_SIDECAR_PASSWORD}
EOF
    ) >"${PGPASS}"

    chmod 0600 "${PGPASS}"
}

verify_environment_variables() {
    if [ -z "${POOL_ID}" ]; then
        echo "POOL_ID not defined, exiting..."
        sleep 60
        exit 1
    fi
}

config_config_json() {
    # .AlonzoGenesisHash, .ByronGenesisHash, .ConwayGenesisHash, .ShelleyGenesisHash
    jq "del(.AlonzoGenesisHash, .ByronGenesisHash, .ConwayGenesisHash, .ShelleyGenesisHash)" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"

    # .hasEKG
    jq "del(.hasEKG)" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"

    # .minSeverity
    jq ".minSeverity = \"${MIN_SEVERITY^}\"" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"

    # .hasPrometheus
    jq ".hasPrometheus = [\"${PROMETHEUS_LISTEN}\", ${PROMETHEUS_PORT}]" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"

    # .hasEKG
    jq ".hasEKG = ${EKG_PORT}" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"

    # .defaultScribes, .setupScribes
    if [ "${LOG_TO_CONSOLE,,}" = "true" ] && [ "${LOG_TO_FILE,,}" = "true" ]; then
        jq ".\"defaultScribes\" = [[\"StdoutSK\", \"stdout\"], [\"FileSK\", \"${LOG_FILE}\"]]" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
        jq ".\"setupScribes\" = [{\"scFormat\": \"ScJson\", \"scKind\": \"StdoutSK\", \"scName\": \"stdout\", \"scRotation\": null}, {\"scFormat\": \"ScJson\", \"scKind\": \"FileSK\", \"scName\": \"${LOG_FILE}\", \"scRotation\": null}]" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
    elif [ "${LOG_TO_CONSOLE,,}" = "false" ] && [ "${LOG_TO_FILE,,}" = "true" ]; then
        jq ".\"defaultScribes\" = [[\"FileSK\", \"${LOG_FILE}\"]]" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
        jq ".\"setupScribes\" = [{\"scFormat\": \"ScJson\", \"scKind\": \"FileSK\", \"scName\": \"${LOG_FILE}\", \"scRotation\": null}]" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
    else
        jq '."defaultScribes" = [["StdoutSK", "stdout"]]' "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
        jq '."setupScribes" = [{"scFormat": "ScJson", "scKind": "StdoutSK", "scName": "stdout", "scRotation": null}]' "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
    fi

    # .PeerSharing
    if [ "${PEER_SHARING,,}" = "true" ]; then
        jq ".PeerSharing = true" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
    else
        jq ".PeerSharing = false" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
    fi

    if [ "${OUROBOROS_GENESIS,,}" = "true" ]; then
        jq ".ConsensusMode = \"GenesisMode\"" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
    else
        jq ".ConsensusMode = \"PraosMode\"" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
    fi

    if [ "${UTXOHD,,}" = "true" ]; then
        jq ".LedgerDB = {\"Backend\": \"V1LMDB\", \"LiveTablesPath\": \"${DATABASE_PATH}/lmdb\"  }" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
    else
        jq ".LedgerDB = {\"Backend\": \"V2InMemory\" }" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
    fi

    jq ".EgressPollInterval = ${EGRESS_POLL_INTERVAL}" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"
}

record_edges() {
    local source_host=$(uname -n | cut -d. -f1)
    local sql_file="${DATA_PATH}/localroot_edges.sql"

    # Initialize SQL file content (overwrite existing)
    cat <<EOF > "${sql_file}"
CREATE TABLE IF NOT EXISTS public.cn_edges (
    id text PRIMARY KEY,
    source text,
    target text
);

DELETE FROM public.cn_edges WHERE source = '${source_host}';

EOF

    # Append INSERT commands for each target
    for target in "$@"; do
        local edge_id="${source_host}-${target}"
        cat <<EOF >> "${sql_file}"
INSERT INTO public.cn_edges (id, source, target)
VALUES ('$edge_id', '$source_host', '$target')
ON CONFLICT(id) DO UPDATE SET
    source = EXCLUDED.source,
    target = EXCLUDED.target;

EOF
    done
}

bp_config_topology_json() {
    # The BP is only directly connected to its relays

        cat <<EOF > "${CONFIG_PATH}/topology.json"
{
  "localRoots": [
    {
      "accessPoints": [
        {"address": "p${POOL_ID}r1.example", "port": 3001},
        {"address": "p${POOL_ID}r2.example", "port": 3001},
        {"address": "p${POOL_ID}r3.example", "port": 3001}
      ],
    "advertise": false,
    "trustable": true,
    "valency": 3
    }
  ],
    "publicRoots": [],
    "useLedgerAfterSlot": -1
}
EOF

    record_edges "p${POOL_ID}r1" "p${POOL_ID}r2" "p${POOL_ID}r3"
}

bprelay_config_topology_json() {
    # Generate a ring topology, where pool_n relays are connected to pool_{n-1} and pool_{n+1}

    # Count number of pools
    POOLS=$(ls -d /opt/cardano-node/pools/* | wc -l)

    local num_pools=$POOLS
    local prev next

    prev=$((POOL_ID - 1))
    if [ $prev -eq 0 ]; then
        prev=$num_pools
    fi

    next=$((POOL_ID + 1))
    if [ $next -gt $num_pools ]; then
        next=1
    fi

        cat <<EOF > "${CONFIG_PATH}/topology.json"
{
  "localRoots": [
    {
      "accessPoints": [
        {"address": "p${prev}.example", "port": 3001}
      ],
    "advertise": false,
    "trustable": false,
    "valency": 1
    },
    {
      "accessPoints": [
        {"address": "p${next}.example", "port": 3001}
      ],
    "advertise": false,
    "trustable": false,
    "valency": 1
    }
  ],
    "publicRoots": [],
    "useLedgerAfterSlot": 0
}
EOF

    record_edges "p${prev}" "p${next}"
}

relay_config_topology_json() {
    # Count number of pools
    local num_pools=$(ls -d /opt/cardano-node/pools/* | wc -l)
    local prev=$((POOL_ID - 1))
    local next=$((POOL_ID + 1))

    # Wrap around pool numbers
    if [ $prev -eq 0 ]; then
        prev=$num_pools
    fi
    if [ $next -gt $num_pools ]; then
        next=1
    fi

    # Determine peer address based on RELAY_ID
    local peer_address
    if [ "$RELAY_ID" -eq 1 ]; then
        base_address="p${prev}r2"
        sibling_base_address="p${POOL_ID}r2"
    elif [ "$RELAY_ID" -eq 2 ]; then
        base_address="p${next}r1"
        sibling_base_address="p${POOL_ID}r1"
    else
        echo "Invalid RELAY_ID: must be 1 or 2" >&2
        return 1
    fi
    peer_address="${base_address}.example"
    sibling_address="${sibling_base_address}.example"

    # Generate the JSON topology file
    if [[ "${NO_INTERPOOL_LOCALROOTS}" == "true" ]]; then
        cat <<EOF > "${CONFIG_PATH}/topology.json"
{
  "localRoots": [
    {
      "accessPoints": [
        {"address": "p${POOL_ID}bp.example", "port": 3001}
      ],
      "advertise": false,
      "trustable": true,
      "valency": 1
    },
    {
      "accessPoints": [
        {"address": "${sibling_address}", "port": 3001}
      ],
      "advertise": false,
      "trustable": true,
      "valency": 1
    }
  ],
  "publicRoots": [],
  "useLedgerAfterSlot": 0
}
EOF

        record_edges "p${POOL_ID}bp" ${sibling_base_address}
    else
        cat <<EOF > "${CONFIG_PATH}/topology.json"
{
  "localRoots": [
    {
      "accessPoints": [
        {"address": "${peer_address}", "port": 3001}
      ],
      "advertise": false,
      "trustable": false,
      "valency": 1
    },
    {
      "accessPoints": [
        {"address": "p${POOL_ID}bp.example", "port": 3001}
      ],
      "advertise": false,
      "trustable": true,
      "valency": 1
    },
    {
      "accessPoints": [
        {"address": "${sibling_address}", "port": 3001}
      ],
      "advertise": false,
      "trustable": true,
      "valency": 1
    }
  ],
  "publicRoots": [],
  "useLedgerAfterSlot": 0
}
EOF

        record_edges ${base_address} "p${POOL_ID}bp" ${sibling_base_address}
    fi
}

privaterelay_config_topology_json() {
    # A private relay is only connected to its BP

    # Generate the JSON topology file
    cat <<EOF > "${CONFIG_PATH}/topology.json"
{
  "localRoots": [
    {
      "accessPoints": [
        {"address": "p${POOL_ID}bp.example", "port": 3001}
      ],
      "advertise": false,
      "trustable": true,
      "valency": 1
    }
  ],
  "publicRoots": [],
  "useLedgerAfterSlot": 0
}
EOF

    record_edges "p${POOL_ID}bp"
}

client_config_topology_json() {
    # A client doesn't have any localroots

        cat <<EOF > "${CONFIG_PATH}/topology.json"
{
  "localRoots": [
  ],
    "publicRoots": [],
    "useLedgerAfterSlot": 0
}
EOF
    record_edges
}


config_topology() {
  case $TYPE in
  "bp")
    bp_config_topology_json
    ;;
  "bprelay")
    bprelay_config_topology_json
    ;;
  "client" | "txg")
    client_config_topology_json
    ;;
  "relay")
    relay_config_topology_json
    ;;
  "privaterelay")
    privaterelay_config_topology_json
    ;;
  *)
    exit 1
    ;;
esac

}

set_start_time() {
    if [ ! -f "${DATA_PATH}/start_time.unix_epoch" ]; then
        # Convert ISO time to unix epoch
        SYSTEM_START_UNIX=$(date -d "${SYSTEM_START}" +%s)
        echo "${SYSTEM_START_UNIX}" >"${DATA_PATH}/start_time.unix_epoch"

        update_start_time
    else
        SYSTEM_START_UNIX="$(cat "${DATA_PATH}/start_time.unix_epoch")"
        update_start_time
    fi
}

update_start_time() {
    # Convert unix epoch to ISO time
    SYSTEM_START_ISO="$(date -d @${SYSTEM_START_UNIX} '+%Y-%m-%dT%H:%M:%SZ')"

    # .systemStart
    jq ".systemStart = \"${SYSTEM_START_ISO}\"" "${SHELLEY_GENESIS_JSON}" | write_file "${SHELLEY_GENESIS_JSON}"

    # .startTime
    jq ".startTime = ${SYSTEM_START_UNIX}" "${BYRON_GENESIS_JSON}" | write_file "${BYRON_GENESIS_JSON}"
}

canary_tx() {
    /canary_tx.sh >/dev/null 2>&1
}

tx_generator() {
    /tx-generator.sh >/dev/null 2>&1
}

config_pgpass() {
    # hostname:port:database:username:password
    (
        cat <<EOF
${DB_HOST}:${DB_PORT}:${DB_SIDECAR_DATABASE}:${DB_SIDECAR_USERNAME}:${DB_SIDECAR_PASSWORD}
EOF
    ) >"${PGPASS}"

    chmod 0600 "${PGPASS}"
}

start_node_exporter() {
    node_exporter >/dev/null 2>&1
}

start_process_exporter() {
    process_exporter -procnames cardano-node,node_exporter,process_exporte
}

localroot_edges() {
    /localroot_edges.sh >/dev/null 2>&1
}


assemble_command() {
    cmd=(/usr/local/bin/cardano-node)
    cmd+=(run)
    cmd+=(--database-path ${DATABASE_PATH})
    cmd+=(--socket-path ${SOCKET_PATH})

    # TYPE
    if [ "${TYPE,,}" = "bp" ] || [ "${TYPE,,}" = "bprelay" ]; then
        cmd+=(--shelley-operational-certificate ${KEY_PATH}/opcert.cert)
        cmd+=(--shelley-kes-key ${KEY_PATH}/kes.skey)
        cmd+=(--shelley-vrf-key ${KEY_PATH}/vrf.skey)
    fi

    cmd+=(--config ${CONFIG_JSON})
    cmd+=(--port ${PORT})
    cmd+=(--topology ${CONFIG_PATH}/topology.json)
}

# Establish run order
main() {
    verify_environment_variables
    config_config_json
    config_pgpass
    config_topology
    set_start_time
    if ( [ "${TYPE,,}" = "relay" ] && [ "${RELAY_ID,,}" -eq 1 ] ) || [ "${TYPE,,}" = "bprelay" ]; then
        canary_tx &
    fi
    if [ "${TYPE,,}" = "txg" ]; then
	tx_generator &
    fi
    /node_routes.sh
    start_node_exporter &
    start_process_exporter &
    localroot_edges &
    assemble_command
    "${cmd[@]}"
}

main
