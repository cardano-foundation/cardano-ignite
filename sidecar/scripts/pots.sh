#!/bin/bash

set -uo pipefail

# Set default environment variables
DB_HOST="${DB_HOST:-db.example}"
DB_SIDECAR_DATABASE="${DB_SIDECAR_DATABASE:-sidecar}"
DB_SIDECAR_USERNAME="${DB_SIDECAR_USERNAME:-sidecar}"
DB_YACI_DATABASE="${DB_YACI_DATABASE:-yaci}"
DB_YACI_USERNAME="${DB_YACI_USERNAME:-yaci}"
DB_DBSYNC_DATABASE="${DB_DBSYNC_DATABASE:-dbsync}"
DB_DBSYNC_USERNAME="${DB_DBSYNC_USERNAME:-dbsync}"

# Build command aliases for PostgreSQL connections
SIDECAR_CMD="/usr/bin/psql --host ${DB_HOST} --dbname ${DB_SIDECAR_DATABASE} --user ${DB_SIDECAR_USERNAME}"
DBSYNC_CMD="/usr/bin/psql --host ${DB_HOST} --dbname ${DB_DBSYNC_DATABASE} --user ${DB_DBSYNC_USERNAME}"
YACI_CMD="/usr/bin/psql --host ${DB_HOST} --dbname ${DB_YACI_DATABASE} --user ${DB_YACI_USERNAME}"

# Function to wait for a table to exist in a PostgreSQL database
wait_for_table() {
    local db_cmd="$1"
    local table_name="$2"

    while true; do
        local exists=$($db_cmd -t -A -c "SELECT EXISTS (SELECT 1 FROM pg_tables WHERE tablename = '$table_name');" 2>/dev/null || echo "")

        if [[ "$exists" == "t" ]]; then
            echo "[$(date)] Table '$table_name' found. Proceeding..."
            break
        else
            echo "[$(date)] Table '$table_name' not found. Waiting 30 seconds before retrying..."
            sleep 30
        fi
    done
}

# Wait for both source tables to exist
wait_for_table "${DBSYNC_CMD}" "ada_pots"
wait_for_table "${YACI_CMD}" "adapot"

# Ensure the table exists in the sidecar database
create_table_sql="CREATE TABLE IF NOT EXISTS ada_pots (
    epoch_no integer,
    source text,
    fees numeric(38,0),
    treasury numeric(38,0),
    reserves numeric(38,0),
    PRIMARY KEY (epoch_no, source)
);"

${SIDECAR_CMD} -c "${create_table_sql}"

# Function to fetch and upsert data from a source
insert_data_from_source() {
    local source_name="$1"
    local query="$2"
    local db_cmd="$3"

    echo "[$(date)] Fetching data from $source_name..."
    set +e
    $db_cmd -t -A -F '|' -c "$query" | while IFS='|' read -r epoch fees treasury reserves; do
        # Skip empty or malformed lines
        if [[ -z "$epoch" || -z "$fees" ]]; then
            continue
        fi

        # Upsert into sidecar database
        $SIDECAR_CMD -c "INSERT INTO ada_pots (epoch_no, source, fees, treasury, reserves)
                         VALUES ($epoch, '$source_name', $fees, $treasury, $reserves)
                         ON CONFLICT (epoch_no, source) DO UPDATE SET
                             fees = EXCLUDED.fees,
                             treasury = EXCLUDED.treasury,
                             reserves = EXCLUDED.reserves;"
    done
    set -e
}

# Main loop: run every 60 seconds
while true; do
    echo "[$(date)] Starting import cycle..."

    # Insert data from DBSync
    insert_data_from_source "dbsync" \
        "SELECT epoch_no, fees, treasury, reserves FROM ada_pots WHERE epoch_no > 0;" \
        "${DBSYNC_CMD}"

    # Insert data from Yaci
    insert_data_from_source "yaci" \
        "SELECT epoch, fees, treasury, reserves FROM adapot WHERE epoch > 0;" \
        "${YACI_CMD}"

    echo "[$(date)] Import cycle completed."

    # Wait for 60 seconds before next run
    sleep 60
done
