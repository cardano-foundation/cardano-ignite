#!/usr/bin/env bash

set -o errexit
set -o pipefail

SHELL="/bin/bash"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

FUNDME_ADDRESS="$1"
NETWORK_ID="--testnet-magic 42"
POOL_ID="${POOL_ID:-}"
WORK_DIR="${WORK_DIR:-/tmp/fundme}"

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
    if [ -f "/opt/cardano-node/utxos/keys/genesis.${POOL_ID}.addr.info" ]; then
        PAYMENT_ADDRESS=$(jq -er '.address' /opt/cardano-node/utxos/keys/genesis.${POOL_ID}.addr.info)

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

build_fundme_transaction() {
    debug_to_console "* Building fundme transaction..."

    # Assemble command
    local cmd=(cardano-cli ${ERA,,} transaction build)
    local cmd+=($(echo ${NETWORK_ID}))

    for utxo in $(jq -r 'keys[]' "${WORK_DIR}/payment_address_utxo.json") ; do
        local cmd+=(--tx-in ${utxo})
    done

    local cmd+=(--change-address "${FUNDME_ADDRESS}")
    local cmd+=(--out-file "${WORK_DIR}/fundme_transaction.json")

    # Run assembled command
    "${cmd[@]}"
}

sign_fundme_transaction() {
    debug_to_console "* Signing fundme transaction..."

    cardano-cli ${ERA,,} transaction sign \
        $(echo ${NETWORK_ID}) \
        --signing-key-file "/opt/cardano-node/utxos/keys/genesis.${POOL_ID}.skey" \
        --tx-body-file "${WORK_DIR}/fundme_transaction.json" \
        --out-file "${WORK_DIR}/fundme_transaction_signed.json"
}

submit_fundme_transaction() {
    debug_to_console "* Submitting fundme transaction..."

    cardano-cli ${ERA,,} transaction submit \
        $(echo ${NETWORK_ID}) \
        --tx-file "${WORK_DIR}/fundme_transaction_signed.json"
}

print_success() {
    debug_to_console "* Payment address balance has been transferred successfully."
}

# Establish run order
main() {
    create_work_dir
    verify_environment_variables
    wait_for_socket
    wait_for_sync
    get_cardano_era
    get_payment_address

    POOLS=$(ls /opt/cardano-node/pools | sort -n | tail -1)

    get_payment_address_balance

    get_protocol_params
    wait_for_payment_address_funds

    build_fundme_transaction
    sign_fundme_transaction
    if ! submit_fundme_transaction; then
        debug_to_console "Warning: Failed to submit transaction. Continuing to next cycle..."
    else
        print_success
    fi

    print_success
}

main
