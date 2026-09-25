#!/usr/bin/env bash

set -o errexit
set -o pipefail

SHELL="/bin/bash"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

# Required
: "${POOL_ID:?POOL_ID must be set}"

# Tunables
TPS="${TPS:-10}"
NETWORK_MAGIC="${NETWORK_MAGIC:-42}"
FIREHOSE_FEE="${FIREHOSE_FEE:-1000000}"
# Metadata colour tagging every tx (hex RGB or "auto"), so mempool-monitor can
# attribute mempool contents to this generator.
FIREHOSE_COLOR="${FIREHOSE_COLOR:-auto}"
# Space separated "seconds:tps" phases, repeated forever and aligned to the
# chain's start time so every generator switches phase at the same moment.
# Unset: run at TPS continuously.
FIREHOSE_PHASES="${FIREHOSE_PHASES:-}"
FIREHOSE_RESTART_BACKOFF="${FIREHOSE_RESTART_BACKOFF:-30}"

# Spends the pool's genesis-UTxO fund (genesis.${POOL_ID}), held at the key's
# enterprise address.
SIG_KEY="/opt/cardano-node/utxos/keys/genesis.${POOL_ID}.skey"
SOCKET="/opt/cardano-node/data/db/node.socket"
START_FILE="/opt/cardano-node/data/start_time.unix_epoch"

if [[ ! -f "${SIG_KEY}" ]]; then
    echo "Error: genesis key not found for pool ${POOL_ID}" >&2
    exit 1
fi

if [[ -z "${FIREHOSE_PHASES}" ]]; then
    FIREHOSE_PHASES="86400:$(printf '%.0f' "${TPS}")"
fi

read -r -a PHASES <<< "${FIREHOSE_PHASES}"
CYCLE=0
for phase in "${PHASES[@]}"; do
    CYCLE=$((CYCLE + ${phase%%:*}))
done

TMP_DIR="$(mktemp -d)"
cd "${TMP_DIR}"

while [[ ! -S "${SOCKET}" ]]; do
    echo "node.socket not found. Waiting 3 seconds..."
    sleep 3
done

sleep 60

START="$(cat "${START_FILE}")"

# Prints "<index> <tps> <seconds left>" for the phase active now.
current_phase() {
    local now offset i duration
    now="$(date +%s)"
    offset=$(( (now - START) % CYCLE ))
    (( offset < 0 )) && offset=$(( offset + CYCLE ))
    for i in "${!PHASES[@]}"; do
        duration="${PHASES[$i]%%:*}"
        if (( offset < duration )); then
            echo "${i} ${PHASES[$i]##*:} $(( duration - offset ))"
            return
        fi
        offset=$(( offset - duration ))
    done
}

while true; do
    read -r index tps left <<< "$(current_phase)"
    echo "tx-firehose phase ${index}: ${tps} tps for ${left}s"

    # One trace line per accepted tx is too much for the container log; keep
    # the rest (startup, rejects, build failures, exit).
    set +e
    timeout "${left}" tx-firehose \
        --socket-path "${SOCKET}" \
        --testnet-magic "${NETWORK_MAGIC}" \
        --signing-key-file "${SIG_KEY}" \
        --tps "${tps}" \
        --fee "${FIREHOSE_FEE}" \
        --color "${FIREHOSE_COLOR}" \
        2>&1 | grep --line-buffered -v '"ns":"TxFirehose.Submit.Success"'
    rc=${PIPESTATUS[0]}
    set -e

    # 124: the phase ended. Anything else: tx-firehose gave up early, typically
    # because the previous run's txs still hold its UTxO in the mempool.
    if (( rc != 124 )); then
        echo "tx-firehose exited (${rc}), restarting in ${FIREHOSE_RESTART_BACKOFF}s" >&2
        sleep "${FIREHOSE_RESTART_BACKOFF}"
    fi
done
