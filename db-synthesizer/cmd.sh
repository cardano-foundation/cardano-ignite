#!/usr/bin/env bash

set -o errexit
set -o pipefail

SHELL="/bin/bash"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

# Environment variables
DATA_PATH=/opt/cardano-node/data
SYSTEM_START="${SYSTEM_START:-$(date -d "@$(( ( $(date +%s) / 180 ) * 180 ))" +%Y-%m-%dT%H:%M:00Z)}"
BYRON_GENESIS_JSON="${BYRON_GENESIS_JSON:-/opt/cardano-node/pools/1/configs/byron-genesis.json}"
SHELLEY_GENESIS_JSON="${SHELLEY_GENESIS_JSON:-/opt/cardano-node/pools/1/configs/shelley-genesis.json}"
PRE_EPOCHS="${PRE_EPOCHS:-0}"
MAX_POOLS="${MAX_POOLS:-}"

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
    if [ ! -f "${DATA_PATH}/start_time.unix_epoch" ]; then
        # Convert ISO time to unix epoch
        SYSTEM_START_UNIX=$(date -d "${SYSTEM_START}" +%s)
        update_start_time
    else
        update_start_time
    fi
}

epochLength="$(jq -r '.epochLength' "${SHELLEY_GENESIS_JSON}")"

update_start_time() {

    SYSTEM_START_UNIX_ADJUSTED=$(( SYSTEM_START_UNIX - PRE_EPOCHS * epochLength ))

    local SYSTEM_START_ISO
    # Convert unix epoch to ISO time
    SYSTEM_START_ISO="$(date -d @${SYSTEM_START_UNIX_ADJUSTED} '+%Y-%m-%dT%H:%M:%SZ')"

    # .systemStart
    jq ".systemStart = \"${SYSTEM_START_ISO}\"" "${SHELLEY_GENESIS_JSON}" | write_file "${SHELLEY_GENESIS_JSON}"

    # .startTime
    jq ".startTime = ${SYSTEM_START_UNIX_ADJUSTED}" "${BYRON_GENESIS_JSON}" | write_file "${BYRON_GENESIS_JSON}"
}

generate_pre_epochs() {

    # Temporary directory for intermediate JSON files
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT

    # Output file
    output_file="/tmp/bulk.json"

    echo "Creating bulk credentials"
    # Loop through each pool directory
    count=0
    for keys_dir in /opt/cardano-node/pools/*/keys/; do
        # Early exit if we've reached the max number of pools
        if [[ -n "${MAX_POOLS}" && "$count" -ge "${MAX_POOLS}" ]]; then
            break
        fi

        opcert="$keys_dir/opcert.cert"
        vrf="$keys_dir/vrf.skey"
        kes="$keys_dir/kes.skey"

        # Skip if any required file is missing
        if [[ ! -f "$opcert" || ! -f "$vrf" || ! -f "$kes" ]]; then
            echo "Skipping pool in $keys_dir: missing required files" >&2
            continue
        fi

        # Append a JSON array: [ opcert_content, vrf_content, kes_content ]
        jq -n \
            --slurpfile opcert "$opcert" \
            --slurpfile vrf "$vrf" \
            --slurpfile kes "$kes" \
            '[ $opcert[0], $vrf[0], $kes[0] ]' >> "$tmpdir/arrays.json"

        count=$((count + 1))
    done

    # Combine all inner arrays into a single top-level JSON array
    if [[ -f "$tmpdir/arrays.json" ]]; then
        jq -s . "$tmpdir/arrays.json" > "$output_file"
    else
        echo '[]' > "$output_file"
    fi

    echo "Generating synthetic chain data for ${PRE_EPOCHS} epochs"
    cd "${DATA_PATH}"
    db-synthesizer --config /opt/cardano-node/pools/1/configs/config.json --db "${DATA_PATH}"/db --bulk-credentials-file "${output_file}" -e "${PRE_EPOCHS}"

    echo 42 > "${DATA_PATH}"/db/protocolMagicId
    echo "${SYSTEM_START_UNIX_ADJUSTED}" >"${DATA_PATH}/start_time.unix_epoch"

}

if [ ! -f "${DATA_PATH}/start_time.unix_epoch" ]; then
    set_start_time
    
    if [ -n "${PRE_EPOCHS}" ] && [ "${PRE_EPOCHS}" -gt 0 ] 2>/dev/null; then
        generate_pre_epochs
    fi

    echo "${SYSTEM_START_UNIX_ADJUSTED}" >"${DATA_PATH}/start_time.unix_epoch"
fi
