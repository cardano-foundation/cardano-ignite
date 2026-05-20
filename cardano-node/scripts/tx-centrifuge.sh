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
CENTRIFUGE_FUND_VALUE="${CENTRIFUGE_FUND_VALUE:-600000000000000}"

SIG_KEY="/opt/cardano-node/utxos/keys/genesis.${POOL_ID}.skey"
NODE_CONFIG="/opt/cardano-node/pools/${POOL_ID}/configs/config.json"
SOCKET="/opt/cardano-node/data/db/node.socket"

if [[ ! -f "${SIG_KEY}" ]]; then
    echo "Error: signing key not found at ${SIG_KEY}" >&2
    exit 1
fi

TMP_DIR="$(mktemp -d)"
cd "${TMP_DIR}"

# funds.json — mirror existing tx-generator's "use the pool's genesis key"
# pattern. tx_in is omitted so tx-centrifuge derives the genesis UTxO TxIn from
# the signing key (matches legacy tx-generator behavior).
cat <<EOF > funds.json
[
  {
    "signing_key": "${SIG_KEY}",
    "value": ${CENTRIFUGE_FUND_VALUE}
  }
]
EOF

# targets — one entry per host in TX_GENERATOR_TARGETS, port=3001 implied.
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

while [[ ! -S "${SOCKET}" ]]; do
    echo "node.socket not found. Waiting 3 seconds..."
    sleep 3
done

sleep 60

exec tx-centrifuge tx-centrifuge.json
