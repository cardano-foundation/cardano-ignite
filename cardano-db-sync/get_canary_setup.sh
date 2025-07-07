#!/bin/bash

set -o errexit
set -o pipefail

DB_DBSYNC_DATABASE="${DB_DBSYNC_DATABASE:-dbsync}"
DB_DBSYNC_PASSWORD="${DB_DBSYNC_PASSWORD:-dbsync}"
DB_DBSYNC_USERNAME="${DB_DBSYNC_USERNAME:-dbsync}"
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-5432}"

# Initialize array for WHERE clause conditions
conditions=()

# Extract addresses from .addr.info files
for file in /opt/cardano-node/utxos/keys/delegated.*.addr.info; do
    addr=$(jq -r '.address' "$file")
    if [[ -n "$addr" && "$addr" != "null" ]]; then
        conditions+=("tx_out.address = '$addr'")
    fi
done

# Check if any valid addresses were found
if [[ ${#conditions[@]} -eq 0 ]]; then
    echo "Error: No valid addresses found in the .addr.info files." >&2
    exit 1
fi

# Build WHERE clause
where_clause=""
for i in "${!conditions[@]}"; do
    if [[ $i -gt 0 ]]; then
        where_clause+=" OR "
    fi
    where_clause+="${conditions[i]}"
done

# Wait until tx_out relation exists
while true; do
    # Query to check for existence of tx_out
    exists=$(psql \
        --host "${DB_HOST}" \
        --port "${DB_PORT}" \
        --dbname "${DB_DBSYNC_DATABASE}" \
        --user "${DB_DBSYNC_USERNAME}" \
        -t -c "SELECT EXISTS (SELECT 1 FROM pg_class WHERE relname = 'tx_out');" 2>/dev/null | xargs)

    if [[ "$exists" == "t" ]]; then
        break
    else
        echo "tx_out relation not found. Retrying in 3 seconds..." >&2
        sleep 3
    fi
done

# Send the SQL function to PostgreSQL
cat << EOF | psql \
    --host "${DB_HOST}" \
    --port "${DB_PORT}" \
    --dbname "${DB_DBSYNC_DATABASE}" \
    --user "${DB_DBSYNC_USERNAME}" \
    --set ON_ERROR_STOP=1 2>&1
CREATE OR REPLACE FUNCTION get_canary_delay()
RETURNS TABLE(
    "time" TIMESTAMP,
    delay INT,
    "json" JSONB,
    avg_delay NUMERIC
) AS \$\$
    SELECT
        a."time",
        a.delay,
        a."json",
        ROUND(AVG(a.delay) OVER (ORDER BY a."time" ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 1) AS avg_delay
    FROM (
        SELECT
            b."time",
            tm."json",
            b.slot_no - (tm.json->>'absolute_slot')::WORD63TYPE AS delay
        FROM tx_out
        INNER JOIN tx_in ON tx_out.tx_id = tx_in.tx_out_id
        INNER JOIN tx ON tx.id = tx_in.tx_in_id AND tx_in.tx_out_index = tx_out.index
        INNER JOIN block b ON tx.block_id = b.id
        INNER JOIN tx_metadata tm ON tm.tx_id = tx.id
        WHERE ( $where_clause )
        ORDER BY b."time"
    ) a;
\$\$ LANGUAGE SQL;
CREATE OR REPLACE FUNCTION get_canary_percentage(start_time TIMESTAMP, end_time TIMESTAMP)
RETURNS NUMERIC AS \$\$
    SELECT 100 * (1 - MIN(1.0 * bork) / MAX(bork))
    FROM (
        SELECT 'kaka' AS name, COUNT(*) AS bork
        FROM (
            SELECT
                b.time,
                tm.json,
                b.slot_no,
                CAST(tm.json->>'absolute_slot' AS word63type) AS sub_slot_no,
                b.slot_no - CAST(tm.json->>'absolute_slot' AS word63type) AS delay
            FROM tx_out
            INNER JOIN tx_in ON tx_out.tx_id = tx_in.tx_out_id
            INNER JOIN tx ON tx.id = tx_in.tx_in_id AND tx_in.tx_out_index = tx_out.index
            INNER JOIN block b ON tx.block_id = b.id
            INNER JOIN tx_metadata tm ON tm.tx_id = tx.id
            WHERE ( $where_clause )
            ORDER BY b.time
        ) a
        JOIN (SELECT slot_no, block_no FROM block) b
          ON b.slot_no <= a.slot_no AND b.slot_no >= a.sub_slot_no
        WHERE a.time >= start_time AND a.time <= end_time

        UNION ALL

        SELECT 'kaka' AS name, COUNT(*) AS bark
        FROM (
            SELECT time, COUNT(b.block_no) AS block_delay
            FROM (
                SELECT
                    b.time,
                    tm.json,
                    b.slot_no,
                    CAST(tm.json->>'absolute_slot' AS word63type) AS sub_slot_no,
                    b.slot_no - CAST(tm.json->>'absolute_slot' AS word63type) AS delay
                FROM tx_out
                INNER JOIN tx_in ON tx_out.tx_id = tx_in.tx_out_id
                INNER JOIN tx ON tx.id = tx_in.tx_in_id AND tx_in.tx_out_index = tx_out.index
                INNER JOIN block b ON tx.block_id = b.id
                INNER JOIN tx_metadata tm ON tm.tx_id = tx.id
                WHERE ( $where_clause )
                ORDER BY b.time
            ) a
            JOIN (SELECT slot_no, block_no FROM block) b
              ON b.slot_no <= a.slot_no AND b.slot_no >= a.sub_slot_no
            WHERE a.time >= start_time AND a.time <= end_time
            GROUP BY time
            ORDER BY time DESC
        ) c
        WHERE block_delay > 2
    ) d
\$\$ LANGUAGE SQL;
EOF

# Check if the psql command succeeded
if [[ $? -eq 0 ]]; then
    echo "SQL function successfully inserted into the database." >&2
else
    echo "Error: Failed to insert SQL function into the database." >&2
    exit 1
fi
