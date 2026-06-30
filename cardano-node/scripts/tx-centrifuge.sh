#!/usr/bin/env bash

set -o errexit
set -o pipefail

SHELL="/bin/bash"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

# Required
: "${POOL_ID:?POOL_ID must be set}"

# Tunables (with defaults mirroring tx-centrifuge data/config-shared-10.json)
TPS="${TPS:-10}"
TX_GENERATOR_TARGETS="${TX_GENERATOR_TARGETS:-127.0.0.1}"
NETWORK_MAGIC="${NETWORK_MAGIC:-42}"
CENTRIFUGE_INPUTS_PER_TX="${CENTRIFUGE_INPUTS_PER_TX:-1}"
CENTRIFUGE_OUTPUTS_PER_TX="${CENTRIFUGE_OUTPUTS_PER_TX:-1}"
CENTRIFUGE_FEE="${CENTRIFUGE_FEE:-1000000}"
CENTRIFUGE_RECYCLE="${CENTRIFUGE_RECYCLE:-on_pull}"
CENTRIFUGE_MAX_BATCH_SIZE="${CENTRIFUGE_MAX_BATCH_SIZE:-500}"

# tx-centrifuge spends the pool's genesis-UTxO fund (genesis.${POOL_ID}). This is
# distinct from the canary, which uses delegated.${POOL_ID}/payment.${POOL_ID}.
SIG_KEY="/opt/cardano-node/utxos/keys/genesis.${POOL_ID}.skey"
VKEY="/opt/cardano-node/utxos/keys/genesis.${POOL_ID}.vkey"
NODE_CONFIG="/opt/cardano-node/pools/${POOL_ID}/configs/config.json"
SOCKET="/opt/cardano-node/data/db/node.socket"
export CARDANO_NODE_SOCKET_PATH="${SOCKET}"

if [[ ! -f "${SIG_KEY}" || ! -f "${VKEY}" ]]; then
    echo "Error: genesis key(s) not found for pool ${POOL_ID}" >&2
    exit 1
fi

TMP_DIR="$(mktemp -d)"
cd "${TMP_DIR}"

# the payment address where the funds actually live.
PAYMENT_ADDR="$(cardano-cli address build --payment-verification-key-file "${VKEY}" --testnet-magic "${NETWORK_MAGIC}")"

while [[ ! -S "${SOCKET}" ]]; do
    echo "node.socket not found. Waiting 3 seconds..."
    sleep 3
done

# Wait until the genesis UTxO is queryable, then take the largest UTxO at the
# payment address (the genesis fund) as the seed input.
TX_IN=""
VALUE=""
for _ in $(seq 1 60); do
    UTXO_JSON="$(cardano-cli query utxo --address "${PAYMENT_ADDR}" --testnet-magic "${NETWORK_MAGIC}" --output-json 2>/dev/null || echo '{}')"
    TX_IN="$(echo "${UTXO_JSON}" | jq -r 'to_entries | max_by(.value.value.lovelace) | .key // empty')"
    VALUE="$(echo "${UTXO_JSON}" | jq -r 'to_entries | max_by(.value.value.lovelace) | .value.value.lovelace // empty')"
    [[ -n "${TX_IN}" && -n "${VALUE}" ]] && break
    echo "Waiting for genesis UTxO at ${PAYMENT_ADDR}..."
    sleep 3
done

if [[ -z "${TX_IN}" || -z "${VALUE}" ]]; then
    echo "Error: no UTxO found at payment address ${PAYMENT_ADDR}" >&2
    exit 1
fi
echo "tx-centrifuge seed: ${TX_IN} (value ${VALUE}) at ${PAYMENT_ADDR}"

# funds.json with explicit tx_in => FundEntryPayment, signing the real UTxO with the
# genesis UTxO key directly.
cat <<EOF > funds.json
[
  {
    "signing_key": "${SIG_KEY}",
    "value": ${VALUE},
    "tx_in": "${TX_IN}"
  }
]
EOF

# targets: one entry per host in TX_GENERATOR_TARGETS, port=3001 implied.
build_targets_json() {
    local first=true
    local idx=0
    IFS=',' read -r -a targets <<< "${TX_GENERATOR_TARGETS}"
    printf '{'
    for target in "${targets[@]}"; do
        target="${target#"${target%%[![:space:]]*}"}"
        target="${target%"${target##*[![:space:]]}"}"
        [[ -z "${target}" ]] && continue
        if [[ "${first}" == false ]]; then printf ','; fi
        first=false
        printf '
        "node-%d": { "addr": "%s", "port": 3001 }' "${idx}" "${target}"
        idx=$((idx + 1))
    done
    printf '
      }'
}

TARGETS_JSON="$(build_targets_json)"

cat <<EOF > tx-centrifuge.json
{
  "initial_inputs": {
    "type": "genesis_utxo_keys",
    "params": {
      "network_magic": ${NETWORK_MAGIC},
      "signing_keys_file": "${TMP_DIR}/funds.json"
    }
  },
  "builder": {
    "type": "value",
    "params": {
      "inputs_per_tx": ${CENTRIFUGE_INPUTS_PER_TX},
      "outputs_per_tx": ${CENTRIFUGE_OUTPUTS_PER_TX},
      "fee": ${CENTRIFUGE_FEE}
    },
    "recycle": { "type": "${CENTRIFUGE_RECYCLE}" }
  },
  "rate_limit": {
    "type": "token_bucket",
    "scope": "shared",
    "params": { "tps": ${TPS} }
  },
  "max_batch_size": ${CENTRIFUGE_MAX_BATCH_SIZE},
  "workloads": {
    "default": {
      "targets": ${TARGETS_JSON}
    }
  },
  "nodeConfig": "${NODE_CONFIG}"
}
EOF

sleep 60

exec tx-centrifuge tx-centrifuge.json
