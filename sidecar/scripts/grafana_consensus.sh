#!/usr/bin/env bash

set -o errexit
set -o pipefail

SHELL="/bin/bash"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

# Environment variables setup
DB_HOST="${DB_HOST:-db.example}"
DB_SIDECAR_DATABASE="${DB_SIDECAR_DATABASE:-sidecar}"
DB_SIDECAR_USERNAME="${DB_SIDECAR_USERNAME:-sidecar}"
POOLS="${POOLS:-}"
PORT="${PORT:-3001}"
PSQL_CMD="/usr/bin/psql --host ${DB_HOST} --dbname ${DB_SIDECAR_DATABASE} --user ${DB_SIDECAR_USERNAME}"
TOPOLOGY="${TOPOLOGY:-simple}"

# Database table creation SQL
TABLE_CREATION=$(cat <<EOF
CREATE TABLE IF NOT EXISTS node_tips (
    pool_id VARCHAR PRIMARY KEY,
    hash CHAR(64) NULL,
    block BIGINT NULL,
    slot BIGINT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
EOF
)

verify_environment_variables() {
    if [ -z "${POOLS}" ]; then
        echo "POOLS not defined, exiting..." >&2
        sleep 60
        exit 1
    fi
}

setup_database() {
    ${PSQL_CMD} <<<"${TABLE_CREATION}"
}

query_node_tips() {
    local temp_dir=$(mktemp -d)
    declare -a pids=()

    for i in $(seq 1 "${POOLS}"); do
        (
            if [ "${TOPOLOGY,,}" = "fancy" ]; then
                host="p${i}bp.example"
            else
                host="p${i}.example"
            fi

            output=$(cardano-cli ping -j --magic 42 --host ${host} --port ${PORT} --tip --quiet -c1)

            if [ $? -eq 0 ] && tip_data=$(echo "$output" | jq -r '.tip[0] | .hash + " " + (.blockNo|tostring) + " " + (.slotNo|tostring)' 2>/dev/null); then
                echo "${tip_data}" > "${temp_dir}/pool_${i}"
            else
                touch "${temp_dir}/failed_${i}"
            fi
        ) &
        pids+=($!)
    done

    for pid in "${pids[@]}"; do
        wait $pid || true
    done

    echo "$temp_dir"
}

check_consensus() {
    local temp_dir=$1

    # Check if any nodes failed (indicated by existence of failed files)
    if ls -U ${temp_dir}/failed_* 2>/dev/null | grep -q . ; then
        return 1
    fi

    declare -a hashes=()

    for i in $(seq 1 "${POOLS}"); do
        if [ -f "${temp_dir}/pool_${i}" ]; then
            read hash _block _slot < "${temp_dir}/pool_${i}"
            hashes+=("$hash")
        fi
    done

    # Check for uniform hashes among successful nodes
    local unique_hash_count=$(printf "%s\n" "${hashes[@]}" | sort -u | wc -l)

    [[ $unique_hash_count == 1 ]]
}

update_database() {
    local temp_dir=$1
    declare -a values=()

    for i in $(seq 1 "${POOLS}"); do
        pool_id="$i"
        if [ "${TOPOLOGY,,}" = "fancy" ]; then
            host_id="p${i}bp"
        else
            host_id="p${i}"
        fi

        if [ -f "${temp_dir}/pool_${i}" ]; then
            read hash block slot < "${temp_dir}/pool_${i}"
            values+=("('$host_id', '$hash', $block, $slot)")
        else
            # Insert NULLs for failed nodes
            values+=("('$host_id', NULL, NULL, NULL)")
        fi
    done

    if (( ${#values[@]} > 0 )); then
        local sql=$(cat <<EOF
INSERT INTO node_tips (pool_id, hash, block, slot)
VALUES
$(IFS=','; echo "${values[*]}")
ON CONFLICT (pool_id) DO UPDATE SET
hash = EXCLUDED.hash,
block = EXCLUDED.block,
slot = EXCLUDED.slot,
updated_at = CURRENT_TIMESTAMP;
EOF
        )

        ${PSQL_CMD} <<<"$sql"
    fi

    rm -rf "${temp_dir}"
}

# Main execution flow with dynamic sleep time
main() {
    verify_environment_variables
    setup_database

    while true; do
        temp_directory=$(query_node_tips)

        # Default to normal 60s interval
        sleep_time=60

        if ! check_consensus "$temp_directory"; then
            echo "Consensus broken: Failures or hash mismatches detected. Sleeping for 1s."
            sleep_time=1
        fi

        update_database "$temp_directory"

        # Sleep based on consensus status
        sleep $sleep_time
    done
}

main
