#!/usr/bin/env bash

set -o errexit
set -o pipefail

SHELL="/bin/bash"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

# Required
: "${POOL_ID:?POOL_ID must be set}"

# Tunables
MEMPOOL_MONITOR_INTERVAL="${MEMPOOL_MONITOR_INTERVAL:-15}"
MEMPOOL_MONITOR_RESTART_BACKOFF="${MEMPOOL_MONITOR_RESTART_BACKOFF:-30}"
DB_HOST="${DB_HOST:-db.example}"
DB_SIDECAR_DATABASE="${DB_SIDECAR_DATABASE:-sidecar}"
DB_SIDECAR_USERNAME="${DB_SIDECAR_USERNAME:-sidecar}"
export PGCONNECT_TIMEOUT=5

SOCKET="/opt/cardano-node/data/db/node.socket"
TSV_FILE="/tmp/mempool-monitor.tsv"
SHELLEY_GENESIS_JSON="/opt/cardano-node/pools/${POOL_ID}/configs/shelley-genesis.json"
NETWORK_MAGIC="$(jq -r .networkMagic "${SHELLEY_GENESIS_JSON}")"
LABEL="${HOSTNAME%%.*}"

SCHEMA_SQL="
CREATE TABLE IF NOT EXISTS mempool_snapshots (
    ts          timestamptz NOT NULL,
    node        text        NOT NULL,
    slot        bigint      NOT NULL,
    txs         integer     NOT NULL,
    drained     integer     NOT NULL,
    drain_secs  real        NOT NULL,
    PRIMARY KEY (node, ts)
);
CREATE INDEX IF NOT EXISTS mempool_snapshots_ts ON mempool_snapshots (ts);
ALTER TABLE mempool_snapshots ADD COLUMN IF NOT EXISTS bytes bigint;
ALTER TABLE mempool_snapshots ADD COLUMN IF NOT EXISTS capacity bigint;
CREATE TABLE IF NOT EXISTS mempool_colors (
    ts     timestamptz NOT NULL,
    node   text        NOT NULL,
    color  text        NOT NULL,
    txs    integer     NOT NULL,
    PRIMARY KEY (node, ts, color)
);
CREATE INDEX IF NOT EXISTS mempool_colors_ts ON mempool_colors (ts);
"
SCHEMA_OK=false

sidecar_psql() {
    psql --host "${DB_HOST}" --dbname "${DB_SIDECAR_DATABASE}" --user "${DB_SIDECAR_USERNAME}" \
        --quiet --no-psqlrc -v ON_ERROR_STOP=1 >/dev/null 2>&1
}

# Every node runs this at startup. Each DDL statement commits on its own, so
# concurrent runs can't deadlock with each other's inserts.
ensure_schema() {
    if [[ "${SCHEMA_OK}" != true ]] && sidecar_psql <<< "${SCHEMA_SQL}"; then
        SCHEMA_OK=true
    fi
}

# Store one TSV row from mempool-monitor: slot, txs, bytes, capacity, drained,
# colours, drainSecs, composition (e.g. "ff0000:16700,(none):3115").
# A failed insert only loses that snapshot.
record_snapshot() {
    local slot=$1 txs=$2 bytes=$3 capacity=$4 drained=$5 secs=$7 composition=${8:-}
    local v
    for v in "${slot}" "${txs}" "${bytes}" "${capacity}" "${drained}"; do
        [[ "${v}" =~ ^[0-9]+$ ]] || return 0
    done
    [[ "${secs}" =~ ^[0-9.]+$ ]] || return 0
    ensure_schema
    [[ "${SCHEMA_OK}" == true ]] || return 0
    local sql="BEGIN;"
    sql+="INSERT INTO mempool_snapshots (ts, node, slot, txs, drained, drain_secs, bytes, capacity)"
    sql+=" VALUES (now(), '${LABEL}', ${slot}, ${txs}, ${drained}, ${secs}, ${bytes}, ${capacity});"
    local entry color
    for entry in ${composition//,/ }; do
        color="${entry%%:*}"
        [[ "${color}" == "(none)" ]] && color="none"
        [[ "${color}" =~ ^([0-9a-f]{6}|none)$ && "${entry##*:}" =~ ^[0-9]+$ ]] || continue
        sql+="INSERT INTO mempool_colors VALUES (now(), '${LABEL}', '${color}', ${entry##*:});"
    done
    sql+="COMMIT;"
    sidecar_psql <<< "${sql}" || true
}

while [[ ! -S "${SOCKET}" ]]; do
    sleep 3
done

# mempool-monitor logs one line per snapshot (the container log) and appends a
# TSV row with the same snapshot's sizes, which is what gets stored. tail exits
# with mempool-monitor.
while true; do
    set +e
    rm -f "${TSV_FILE}"
    mempool-monitor \
        --socket-path "${SOCKET}" \
        --testnet-magic "${NETWORK_MAGIC}" \
        --label "${LABEL}" \
        --interval "${MEMPOOL_MONITOR_INTERVAL}" \
        --tsv "${TSV_FILE}" &
    monitor_pid=$!
    tail -n +2 -F --pid="${monitor_pid}" "${TSV_FILE}" 2>/dev/null |
        while IFS=$'\t' read -r -a row; do
            record_snapshot "${row[@]}"
        done
    wait "${monitor_pid}"
    rc=$?
    set -e
    echo "mempool-monitor exited (${rc}), restarting in ${MEMPOOL_MONITOR_RESTART_BACKOFF}s" >&2
    sleep "${MEMPOOL_MONITOR_RESTART_BACKOFF}"
done
