#!/usr/bin/env bash

set -o errexit
set -o pipefail

SHELL="/bin/bash"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

# Environment variables
TPS="${TPS:-1}"
TX_GEN_MODE="${TX_GEN_MODE:-plain}"
TX_GENERATOR_TARGETS="${TX_GENERATOR_TARGETS:-}"

# Check if required environment variables are set
if [[ -z "${POOL_ID}" ]]; then
    echo "Error: POOL_ID environment variable must be set" >&2
    exit 1
fi

if [[ -z "${TPS}" ]]; then
    echo "Error: TPS environment variable must be set" >&2
    exit 1
fi

# Create a temporary directory and change into it
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR" || {
    echo "Failed to change to temporary directory" >&2
    exit 1
}

build_target_nodes_json() {
    local targets_csv
    local first=true
    local index=0
    local emitted=0

    if [[ -n "${TX_GENERATOR_TARGETS}" ]]; then
        targets_csv="${TX_GENERATOR_TARGETS}"
    else
        targets_csv="127.0.0.1"
    fi

    IFS=',' read -r -a targets <<< "${targets_csv}"

    printf '['
    for target in "${targets[@]}"; do
        target="${target#"${target%%[![:space:]]*}"}"
        target="${target%"${target##*[![:space:]]}"}"
        [[ -z "${target}" ]] && continue

        if [[ "${first}" == false ]]; then
            printf ','
        fi
        first=false
        emitted=$((emitted + 1))

        printf '
    {
      "addr": "%s",
      "name": "target-%d",
      "port": 3001
    }'             "${target}" "${index}"
        index=$((index + 1))
    done

    if [[ ${emitted} -eq 0 ]]; then
        echo "Error: TX_GENERATOR_TARGETS did not contain any valid target addresses" >&2
        exit 1
    fi

    printf '
  ]'
}

TARGET_NODES_JSON="$(build_target_nodes_json)"

# Generate the JSON configuration file
cat <<EOF > tx-generator.json
{
  "add_tx_size": 100,
  "debugMode": false,
  "era": "Conway",
  "init_cooldown": 5,
  "inputs_per_tx": 2,
  "localNodeSocketPath": "/opt/cardano-node/data/db/node.socket",
  "min_utxo_value": 10000000,
  "nodeConfigFile": "/opt/cardano-node/pools/${POOL_ID}/configs/config.json",
  "outputs_per_tx": 2,
  "plutus": null,
  "sigKey": "/opt/cardano-node/utxos/keys/genesis.${POOL_ID}.skey",
  "targetNodes": ${TARGET_NODES_JSON},
  "tps": ${TPS},
  "tx_count": 172800,
  "tx_fee": 1000000
}
EOF

cat <<EOF > tx-generator-plutus.json
{
  "add_tx_size": 100,
  "debugMode": false,
  "era": "Conway",
  "init_cooldown": 45,
  "inputs_per_tx": 1,
  "localNodeSocketPath": "/opt/cardano-node/data/db/node.socket",
  "min_utxo_value": 10000000,
  "nodeConfigFile": "/opt/cardano-node/pools/${POOL_ID}/configs/config.json",
  "outputs_per_tx": 1,
  "sigKey": "/opt/cardano-node/utxos/keys/genesis.${POOL_ID}.skey",
  "targetNodes": ${TARGET_NODES_JSON},
  "plutus": {
    "datum": null,
    "limitExecutionMem": null,
    "limitExecutionSteps": null,
    "redeemer": "plutus-redeemer.json",
    "script": {
      "Right": "/opt/tx-generator/scripts-fallback/Loop.plutus"
    },
    "type": "LimitSaturationLoop"
  },
  "tps": 0.85,
  "tx_count": 61200,
  "tx_fee": 1360000
}
EOF

cat <<EOF > plutus-redeemer.json
{
  "int":1000000
}
EOF

while [ ! -S /opt/cardano-node/data/db/node.socket ]; do
    echo "node.socket not found. Waiting 3 seconds..."
    sleep 3
done

# Launch the tx-generator process
case $TX_GEN_MODE in
  "plain")
    tx-generator json_highlevel tx-generator.json
    ;;
  "plutus")
    tx-generator json_highlevel tx-generator-plutus.json
    ;;
  *)
    echo "Unknown TX_GEN_MODE ${TX_GEN_MODE}."
    exit 1
    ;;
esac
