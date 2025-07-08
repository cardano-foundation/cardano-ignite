#!/usr/bin/env bash

set -o errexit
set -o pipefail

SHELL="/bin/bash"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

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
  "targetNodes": [
    {
      "addr": "127.0.0.1",
      "name": "node-0",
      "port": 3001
    }
  ],
  "tps": ${TPS},
  "tx_count": 172800,
  "tx_fee": 1000000
}
EOF

while [ ! -S /opt/cardano-node/data/db/node.socket ]; do
    echo "node.socket not found. Waiting 3 seconds..."
    sleep 3
done

# Launch the tx-generator process
tx-generator json_highlevel tx-generator.json
