#!/bin/bash
# PostgreSQL configuration
DB_HOST="${DB_HOST:-db.example}"
DB_SIDECAR_DATABASE="${DB_SIDECAR_DATABASE:-sidecar}"
DB_SIDECAR_USERNAME="${DB_SIDECAR_USERNAME:-sidecar}"
# Loki configuration
LOKI_URL="${LOKI_URL:-http://loki.example:3100/loki/api/v1/query_range}"
LOKI_QUERY='{container_name=~"p[0-9]+(bp|r[0-9])?|(c[0-9]+)"} | json | data_kind="TxInboundAddedToMempool"'

# Function to resolve IP to hostname using reverse DNS
resolve_ip() {
    local ip="$1"
    if [[ -n "${ip_cache[$ip]}" ]]; then
        printf "%s" "${ip_cache[$ip]}"
        return
    fi
    local hostname
    hostname=$(getent hosts "$ip" | awk '{print $2}' | head -n1)
    if [[ -n "$hostname" ]]; then
        local hostname_short="${hostname%%.*}"
        ip_cache["$ip"]="$hostname_short"
        printf "%s" "$hostname_short"
    else
        ip_cache["$ip"]="$ip"
        printf "%s" "$ip"
    fi
}

# Associative array to cache resolved hostnames
declare -A ip_cache=()

# Ensure PostgreSQL table exists
psql -h "${DB_HOST}" -d "${DB_SIDECAR_DATABASE}" -U "${DB_SIDECAR_USERNAME}" -c "
    CREATE TABLE IF NOT EXISTS tx_propagation (
        txid TEXT NOT NULL,
        timestamp TIMESTAMP NOT NULL,
        local_addr TEXT,
        local_port INTEGER,
        remote_addr TEXT,
        remote_port INTEGER,
        UNIQUE (local_addr, local_port, txid)
    );" || { echo "Error creating table in PostgreSQL" >&2; exit 1; }

current_ntime=$(date +%s%N)
start_ntime=$((current_ntime - 70000000000))  # 70s ago (in nanoseconds)
end_ntime=$((current_ntime -   60000000000))  # 60s ago (in nanoseconds)

# Infinite loop
while true; do

    # Pagination loop
    while true; do
        echo "Fetching logs from Loki: $(date -d @$((start_ntime / 1000000000))) to $(date -d @$((end_ntime / 1000000000)))"
        loki_response=$(curl -s -G --get \
            --data-urlencode "query=${LOKI_QUERY}" \
            --data-urlencode "start=${start_ntime}" \
            --data-urlencode "end=${end_ntime}" \
            --data-urlencode "limit=1000" \
	    --data-urlencode "direction=forward" \
            "${LOKI_URL}")

        # Check for Loki errors
        echo "$loki_response" | jq -e '.status != "success"' > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            error_msg=$(echo "$loki_response" | jq -r '.error')
            echo "Error querying Loki: $error_msg" >&2
            echo "Raw Error querying Loki: $loki_response" >&2
	    end_ntime=$(start_ntime)
            break
        fi

        # Extract structured data including Loki timestamp
        insert_data=$(echo "$loki_response" | jq -r '
            if has("data") and (.data | has("result")) then
                .data.result[].values[]
            else
                empty
            end
            | .[0] as $loki_timestamp
            | .[1] as $json_str
            | $json_str | fromjson as $log
            | $log.data.txids[] as $txid
            | $log.data.peer.local.addr as $local_addr
            | $log.data.peer.local.port as $local_port
            | $log.data.peer.remote.addr as $remote_addr
            | $log.data.peer.remote.port as $remote_port
            | $log.at as $timestamp
            | "\($loki_timestamp)\t\($txid)\t\($timestamp)\t\($local_addr)\t\($local_port)\t\($remote_addr)\t\($remote_port)"'
        )

        # Check if any data was found
        if [ -z "$insert_data" ]; then
            echo "No new transactions found in the last interval"
            break
        fi

        # Process each line to resolve IPs and build SQL statements
        insert_statements=""
        while IFS=$'\t' read -r loki_timestamp txid log_timestamp local_addr local_port remote_addr remote_port; do
            local_hostname=$(resolve_ip "$local_addr")
            remote_hostname=$(resolve_ip "$remote_addr")

            txid_escaped=$(printf "%s" "$txid" | sed "s/'/''/g")
            timestamp_escaped=$(printf "%s" "$log_timestamp" | sed "s/'/''/g")
            local_hostname_escaped=$(printf "%s" "$local_hostname" | sed "s/'/''/g")
            remote_hostname_escaped=$(printf "%s" "$remote_hostname" | sed "s/'/''/g")

            insert_sql="INSERT INTO tx_propagation (txid, timestamp, local_addr, local_port, remote_addr, remote_port) VALUES ('$txid_escaped', '$timestamp_escaped', '$local_hostname_escaped', $local_port, '$remote_hostname_escaped', $remote_port) ON CONFLICT (local_addr, local_port, txid) DO UPDATE SET timestamp = EXCLUDED.timestamp, remote_addr = EXCLUDED.remote_addr, remote_port = EXCLUDED.remote_port WHERE EXCLUDED.timestamp < tx_propagation.timestamp;"
            insert_statements+="$insert_sql"$'\n'
        done <<< "$insert_data"

        # Remove trailing newline
        insert_statements=${insert_statements%$'\n'}

        count=$(echo "$insert_data" | wc -l)
        echo "$insert_statements" | psql -h "${DB_HOST}" -d "${DB_SIDECAR_DATABASE}" -U "${DB_SIDECAR_USERNAME}" > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "Error inserting data into PostgreSQL" >&2
        else
		echo "Successfully inserted $(echo "$insert_statements" | wc -l) transaction records into the database out of $count log lines"
        fi

        # Pagination logic
        if [ $count -lt 1000 ]; then
            break
        else
            last_loki_timestamp=$(echo "$insert_data" | tail -n1 | cut -f1)
            start_ntime=$((last_loki_timestamp - 1))
	    echo "last log entry: $last_loki_timestamp, $(date -d @$((start_ntime / 1000000000)))"
        fi
    done
    # Sleep for 5s before next iteration
    sleep 5

    start_ntime=$((end_ntime))
    current_time=$(date +%s%N)
    end_ntime=$(( (current_time - 60000000000 > start_ntime + 5000000000) ? current_time - 60000000000 : start_ntime + 6000000000 ))

done
