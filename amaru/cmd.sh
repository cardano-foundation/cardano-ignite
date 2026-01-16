#!/usr/bin/env bash

# Required for overriding exit code
set -o errexit
set -o pipefail

PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

# Environment variables
PEER_PORT="${PEER_PORT:-3001}"
PEER_HOST="${PEER_HOST:-p1}"
PEER="${PEER_HOST}":"${PEER_PORT}"
POOL_ID="${POOL_ID:-1}"
RELAY_ID="${RELAY_ID:-1}"
PORT="${PORT:-3001}"
DB_SIDECAR_DATABASE="${DB_SIDECAR_DATABASE:-sidecar}"
DB_SIDECAR_PASSWORD="${DB_SIDECAR_PASSWORD:-sidecar}"
DB_SIDECAR_USERNAME="${DB_SIDECAR_USERNAME:-sidecar}"
DB_HOST="${DB_HOST:-db.example}"
DB_PORT="${DB_PORT:-5432}"

# Configuration files
BYRON_GENESIS_JSON="${BYRON_GENESIS_JSON:-/opt/cardano-node/pools/${POOL_ID}/configs/byron-genesis.json}"
CONFIG_JSON="/opt/cardano-node/pools/${POOL_ID}/configs/config.json"
DATA_PATH="/opt/cardano-node/data"
DATABASE_PATH="/opt/cardano-node/data/db"
SHELLEY_GENESIS_JSON="${SHELLEY_GENESIS_JSON:-/opt/cardano-node/pools/${POOL_ID}/configs/shelley-genesis.json}"
PGPASS="$HOME/.pgpass"
BASE_DIR="/opt/amaru/"
SYNTH_DIR="/opt/synth"
NETWORK="testnet_42"

# Implement sponge-like command without the need for binary nor TMPDIR environment variable
write_file() {
    # Create temporary file
    local tmp_file="${1}_$(tr </dev/urandom -dc A-Za-z0-9 | head -c16)"

    # Redirect the output to the temporary file
    cat >"${tmp_file}"

    # Replace the original file
    mv --force "${tmp_file}" "${1}"
}

config_config_json() {
    # .AlonzoGenesisHash, .ByronGenesisHash, .ConwayGenesisHash, .ShelleyGenesisHash
    jq "del(.AlonzoGenesisHash, .ByronGenesisHash, .ConwayGenesisHash, .ShelleyGenesisHash)" "${CONFIG_JSON}" | write_file "${CONFIG_JSON}"

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

amaru_topology() {
    record_edges "$(echo "${PEER_HOST}" | cut -d. -f1)"
}

set_start_time() {
    cp /opt/synth/start_time.unix_epoch "${DATA_PATH}/start_time.unix_epoch"
    SYSTEM_START_UNIX="$(cat "${DATA_PATH}/start_time.unix_epoch")"
    update_start_time
}

update_start_time() {
    # Convert unix epoch to ISO time
    SYSTEM_START_ISO="$(date -d @"${SYSTEM_START_UNIX}" '+%Y-%m-%dT%H:%M:%SZ')"

    # .systemStart
    jq ".systemStart = \"${SYSTEM_START_ISO}\"" "${SHELLEY_GENESIS_JSON}" | write_file "${SHELLEY_GENESIS_JSON}"

    # .startTime
    jq ".startTime = ${SYSTEM_START_UNIX}" "${BYRON_GENESIS_JSON}" | write_file "${BYRON_GENESIS_JSON}"
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
    process_exporter -procnames amaru,node_exporter,process_exporte
}

generate_amaru_snapshots() {
    local TARGET_DIR="${BASE_DIR}/${NETWORK}/snapshots"
    local NONCES_FILE="${BASE_DIR}/${NETWORK}/nonces.json"
    local STATE_DIR="${BASE_DIR}/state"

    # Create target directories if they don't exist
    mkdir -p "$TARGET_DIR"

    # Find all snapshot files (numeric filenames) and process them
    echo "Processing snapshot files in $SYNTH_DIR..."

    local snapshots=()

    # Find all numeric snapshot files
    mapfile -t snapshots < <(find "$SYNTH_DIR" -maxdepth 1 -type f -regex '.*/[0-9]+' | sort)

    # Process each snapshot
    for snapshot in "${snapshots[@]}"; do
        snapshot_name=$(basename "$snapshot")
        echo "Processing snapshot: $snapshot_name"
        amaru convert-ledger-state --network "$NETWORK" --snapshot "$snapshot" --target-dir "$TARGET_DIR"
        if [[ $? -ne 0 ]]; then
            echo "Warning: Failed to process snapshot $snapshot_name" >&2 && exit 1
        fi
    done

    # Find the latest and second-to-latest snapshots by slot number
    echo "Finding latest snapshots..."
    local latest_slot=""
    local latest_hash=""
    local second_latest_slot=""
    local second_latest_hash=""

    # Get all snapshot files and extract slot/hash information
    local snapshot_info_array=()

    for file in "$TARGET_DIR"/nonces.*.json; do
        if [[ -f "$file" ]]; then
            basename_file=$(basename "$file")
            # Extract slot.number from filename like "nonces.17253.hash.json"
            slot_and_hash=$(echo "$basename_file" | sed 's/nonces\.//' | sed 's/\.json$//')
            slot=$(echo "$slot_and_hash" | cut -d'.' -f1)
            hash=$(echo "$slot_and_hash" | cut -d'.' -f2-)
            snapshot_info_array+=("$slot:$hash")
        fi
    done

    # Sort snapshots by slot number (descending order)
    if [[ ${#snapshot_info_array[@]} -gt 0 ]]; then
        # Sort by slot number (first field) in reverse numerical order
        local sorted_snapshots
        mapfile -t sorted_snapshots < <(printf '%s\n' "${snapshot_info_array[@]}" | sort -t':' -k1 -nr)

        # Get latest snapshot
        if [[ ${#sorted_snapshots[@]} -ge 1 ]]; then
            IFS=':' read -r latest_slot latest_hash <<< "${sorted_snapshots[0]}"
            echo "Latest snapshot: $latest_slot.$latest_hash"

            # Get second latest snapshot
            if [[ ${#sorted_snapshots[@]} -ge 2 ]]; then
                IFS=':' read -r second_latest_slot second_latest_hash <<< "${sorted_snapshots[1]}"
                echo "Second latest snapshot: $second_latest_slot.$second_latest_hash"
            fi
        fi
    else
        echo "Error: No snapshot files found in $TARGET_DIR" >&2
        return 1
    fi

    # Copy the latest nonce file to the target location
    if [[ -n "$latest_slot" && -n "$latest_hash" ]]; then
        local latest_nonce_file="$TARGET_DIR/nonces.$latest_slot.$latest_hash.json"

        if [[ -f "$latest_nonce_file" ]]; then
            echo "Copying latest nonce file to $NONCES_FILE"
            cp "$latest_nonce_file" "$NONCES_FILE"

            # Update the tail field if we have a second latest snapshot
            if [[ -n "$second_latest_hash" ]]; then
                echo "Updating tail field to: $second_latest_hash"

                # Use jq to update the tail field
                jq --arg new_tail "$second_latest_hash" '.tail = $new_tail' "$NONCES_FILE" > "$NONCES_FILE.tmp" && \
                    mv "$NONCES_FILE.tmp" "$NONCES_FILE"

                echo "Updated nonces.json:"
                jq '.' "$NONCES_FILE"
            else
                echo "Only one snapshot found, tail field not updated"
            fi
        else
            echo "Error: Latest nonce file not found: $latest_nonce_file" >&2
            return 1
        fi
    else
        echo "Error: Could not determine latest snapshot" >&2
        return 1
    fi
    
    echo "Snapshot processing completed successfully!"

    mkdir -p ${BASE_DIR}/${NETWORK}/headers

    # list headers to retrieve 2 headers for last snapshot
    db-server query --query list-blocks \
        --config "${CONFIG_JSON}" \
        --db "${DATABASE_PATH}" |  jq -rc "[ .[] | select(.slot <= ${latest_slot}) ] | .[0:2] | .[] | [.slot, .hash] | @csv" > ${BASE_DIR}/${NETWORK}/headers.csv
    # list headers to retrieve 2 headers for second to last snapshot
    db-server query --query list-blocks \
        --config "${CONFIG_JSON}" \
        --db "${DATABASE_PATH}" |  jq -rc "[ .[] | select(.slot <= ${second_latest_slot}) ] | .[0:2] | .[] | [.slot, .hash] | @csv" >> ${BASE_DIR}/${NETWORK}/headers.csv

    cat ${BASE_DIR}/${NETWORK}/headers.csv | tr -d '"' | while IFS=, read -ra hdr ; do
        db-server query --query "get-header ${hdr[0]}.${hdr[1]}" \
            --config "${CONFIG_JSON}" \
            --db "${DATABASE_PATH}" >  "${BASE_DIR}/${NETWORK}/headers/header.${hdr[0]}.${hdr[1]}.cbor"
    done

    # import ledger state
    RUST_BACKTRACE=1 amaru import-ledger-state --network ${NETWORK} --ledger-dir ${BASE_DIR}/ledger.${NETWORK}.db --snapshot-dir ${BASE_DIR}/${NETWORK}/snapshots/

    # import headers
    RUST_BACKTRACE=1 amaru import-headers --network ${NETWORK} --chain-dir ${BASE_DIR}/chain.${NETWORK}.db --config-dir ${BASE_DIR}/

    # import nonces
    RUST_BACKTRACE=1 amaru import-nonces  --nonces-file ${BASE_DIR}/${NETWORK}/nonces.json --network ${NETWORK} --chain-dir ${BASE_DIR}/chain.${NETWORK}.db/

    mkdir -p "${STATE_DIR}/ledger.db" "${STATE_DIR}/chain.db"
    (shopt -s dotglob nullglob; cp -a "${BASE_DIR}/ledger.${NETWORK}.db/"* "${STATE_DIR}/ledger.db/";)
    (shopt -s dotglob nullglob; cp -a "${BASE_DIR}/chain.${NETWORK}.db/"* "${STATE_DIR}/chain.db/";)

    return 0
}

localroot_edges() {
    /localroot_edges.sh >/dev/null 2>&1
}

assemble_command() {
    cmd=(/usr/local/bin/amaru)
    cmd+=(--with-json-traces)
    cmd+=(run)
    cmd+=(--peer-address "${PEER}")
    cmd+=(--chain-dir chain."${NETWORK}".db)
    cmd+=(--network "${NETWORK}")
    cmd+=(--listen-address 0.0.0.0:3001)
}

# Establish run order
main() {
    config_config_json
    config_pgpass

    # If we don't have a db copy it from synth
    if [ ! -f "${DATA_PATH}/start_time.unix_epoch" ]; then
        while [ ! -f /opt/synth/start_time.unix_epoch ]; do
            #echo "Waiting for initialization to complete..."
            sleep 1
        done
        set_start_time

        cp -r /opt/synth/db "${DATA_PATH}"
        cp /opt/synth/start_time.unix_epoch "${DATA_PATH}"

        generate_amaru_snapshots
    fi

    amaru_topology
    /node_routes.sh

    start_node_exporter &
    start_process_exporter &
    localroot_edges &

    cd "${BASE_DIR}"

    export AMARU_WITH_OPEN_TELEMETRY=true
    export AMARU_OTLP_SPAN_URL=http://jaeger.example:4317
    export AMARU_OTLP_METRIC_URL=http://otlp.example:4318/v1/metrics
    export AMARU_SERVICE_NAME=a"${RELAY_ID}"
    assemble_command
    exec "${cmd[@]}"
}

main
