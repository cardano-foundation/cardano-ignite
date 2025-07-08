#!/usr/bin/env bash

# This script sends transactions on average once per 60 seconds including metadata when it was submitted.

set -o errexit
set -o pipefail

SHELL="/bin/bash"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

NETWORK_ID="--testnet-magic 42"
WORK_DIR="${WORK_DIR:-/tmp/canary_tx}"
POOL_ID="${POOL_ID:-}"
TTL="${TTL:-50}"

debug_to_console() {
    local message=${1}

    if [ -t 1 ]; then
        echo "${message}" >&2
    fi
}

create_work_dir() {
    if [ ! -d "${WORK_DIR}" ]; then
        mkdir -p "${WORK_DIR}"
    fi
}

verify_environment_variables() {
    if [ -z "${POOL_ID}" ]; then
        debug_to_console "POOL_ID not defined, exiting..."
        sleep 60
        exit 1
    fi
}

get_genesis_start_time() {
    START_TIME=$(jq -er '.startTime' /opt/cardano-node/pools/${POOL_ID}/configs/byron-genesis.json)
}

get_slot_length() {
    SLOT_LENGTH=$(jq -er '.slotLength' /opt/cardano-node/pools/${POOL_ID}/configs/shelley-genesis.json)
}

wait_for_socket() {
    while [ ! -S "${CARDANO_NODE_SOCKET_PATH}" ]; do
        debug_to_console "* Waiting for cardano-node socket..."
        sleep 5
    done
}

get_sync_progress() {
    SYNC_PROGRESS=$(cardano-cli query tip $(echo ${NETWORK_ID}) | jq -r '.syncProgress')

    debug_to_console "  .syncProgress: ${SYNC_PROGRESS}%"
}

wait_for_sync() {
    debug_to_console "* Please wait until blockchain is fully synchronized."

    get_sync_progress

    while [ -z "${SYNC_PROGRESS}" ] || [ "${SYNC_PROGRESS}" != '100.00' ]; do
        get_sync_progress
        sleep 5
    done
}

get_cardano_era() {
    ERA=$(cardano-cli query tip $(echo ${NETWORK_ID}) | jq -r '.era')
}

get_payment_address() {
    if [ -f "/opt/cardano-node/utxos/keys/delegated.${POOL_ID}.addr.info" ]; then
        PAYMENT_ADDRESS=$(jq -er '.address' /opt/cardano-node/utxos/keys/delegated.${POOL_ID}.addr.info)

	debug_to_console ${PAYMENT_ADDRESS}
    fi
}

get_protocol_params() {
    debug_to_console "* Getting protocol parameters..."

    cardano-cli query protocol-parameters \
        $(echo ${NETWORK_ID}) \
        --out-file "${WORK_DIR}/protocol_params.json"
}

get_payment_address_utxo() {
    # Remove existing file and query latest UTXO
    if [ "${WORK_DIR}/payment_address_utxo.json" ]; then
        rm --force "${WORK_DIR}/payment_address_utxo.json"
    fi

    cardano-cli query utxo \
        $(echo ${NETWORK_ID}) \
        --address ${PAYMENT_ADDRESS} \
        --out-file "${WORK_DIR}/payment_address_utxo.json"

    PAYMENT_ADDRESS_UTXO=$(cat ${WORK_DIR}/payment_address_utxo.json)
}

get_payment_address_balance() {
    get_payment_address_utxo

    PAYMENT_ADDRESS_INPUTS=$(echo ${PAYMENT_ADDRESS_UTXO} | jq '. | to_entries[] | select(.value.value | length == 1 and has("lovelace")) | .value.value.lovelace')

    PAYMENT_ADDRESS_BALANCE="0"
    for input in ${PAYMENT_ADDRESS_INPUTS}; do
        PAYMENT_ADDRESS_BALANCE=$(( PAYMENT_ADDRESS_BALANCE + input ))
    done

    debug_to_console "  Payment address balance: ${PAYMENT_ADDRESS_BALANCE:-0}"
}

wait_for_payment_address_funds() {
    debug_to_console "* Waiting until payment-address is funded..."

    get_payment_address_balance

    while [ -z "${PAYMENT_ADDRESS_BALANCE}" ] || [ ${PAYMENT_ADDRESS_BALANCE} -eq 0 ]; do
        debug_to_console "Info: Please send funds to address: ${PAYMENT_ADDRESS}"

        get_payment_address_balance

        sleep 5
    done
}

get_payment_address_transaction_count() {
    get_payment_address_utxo

    if [ -f "${WORK_DIR}/payment_address_utxo.json" ]; then
        debug_to_console "* Getting payment-address transaction count..."

        TX_COUNT=$(jq -r '. | length' ${WORK_DIR}/payment_address_utxo.json)

        debug_to_console "  Transaction count: ${TX_COUNT}"
    fi
}

build_metadata() {
    debug_to_console "* Building metadata..."

    target_epoch=$(date --date="+10 seconds" +%s)

    # Calculate absolute_slot: ((target_epoch - START_TIME) / SLOT_LENGTH), rounded to nearest integer
    absolute_slot=$(echo "scale=10; a=$target_epoch; b=$START_TIME; c=$SLOT_LENGTH; x=(a - b)/c; scale=0; (x + 0.5)/1" | bc)

    # Calculate TX_TTL: ((target_epoch + TTL - START_TIME) / SLOT_LENGTH), rounded to nearest integer
    TX_TTL=$(echo "scale=10; a=$target_epoch; b=$START_TIME; c=$SLOT_LENGTH; d=$TTL; x=(a + d - b)/c; scale=0; (x + 0.5)/1" | bc)

    echo "{ \"1\": {\"absolute_slot\": \"${absolute_slot}\", \"timestamp\": \"${target_epoch}\", \"sequence_no\": \"${CURRENT_SEQ}\"} }" >"${WORK_DIR}/metadata.json"
}

build_canary_transaction() {
    debug_to_console "* Building canary transaction..."

    # Assemble command
    local cmd=(cardano-cli ${ERA,,} transaction build)
    local cmd+=($(echo ${NETWORK_ID}))

    for utxo in $(jq -r 'keys[]' "${WORK_DIR}/payment_address_utxo.json") ; do
        local cmd+=(--tx-in ${utxo})
    done

    local cmd+=(--change-address "${PAYMENT_ADDRESS}")
    local cmd+=(--metadata-json-file "${WORK_DIR}/metadata.json")
    local cmd+=(--invalid-hereafter "${TX_TTL}")
    local cmd+=(--out-file "${WORK_DIR}/canary_transaction.json")

    # Run assembled command
    "${cmd[@]}"
}

sign_canary_transaction() {
    debug_to_console "* Signing canary transaction..."

    cardano-cli ${ERA,,} transaction sign \
        $(echo ${NETWORK_ID}) \
        --signing-key-file "/opt/cardano-node/utxos/keys/payment.${POOL_ID}.skey" \
        --tx-body-file "${WORK_DIR}/canary_transaction.json" \
        --out-file "${WORK_DIR}/canary_transaction_signed.json"
}

wait_canary_transaction() {
    debug_to_console "* Waiting until send time..."

    current_epoch=$(date +%s)
    sleep_seconds=$(( "${target_epoch} - ${current_epoch}" ))
    sleep "${sleep_seconds}"
}

submit_canary_transaction() {
    debug_to_console "* Submitting canary transaction..."

    cardano-cli ${ERA,,} transaction submit \
        $(echo ${NETWORK_ID}) \
        --tx-file "${WORK_DIR}/canary_transaction_signed.json"
}

print_success() {
    debug_to_console "* Payment address balance has been transferred successfully."
}

sleep_random_time() {
    debug_to_console "* Sleep for random time..."

    random_seconds=$((RANDOM % 11))
    total_sleep=$((55 + random_seconds))
    sleep ${total_sleep}
}

# Establish run order
main() {
    create_work_dir
    verify_environment_variables
    wait_for_socket
    wait_for_sync
    get_cardano_era
    get_genesis_start_time
    get_payment_address
    get_slot_length

    CURRENT_SEQ=0

    while true; do
        get_payment_address_balance

        get_protocol_params
        wait_for_payment_address_funds

        build_metadata
        build_canary_transaction
        sign_canary_transaction
        wait_canary_transaction
        submit_canary_transaction
	CURRENT_SEQ=$((CURRENT_SEQ + 1))

        get_payment_address_balance

        print_success

        sleep_random_time
    done
}

main
