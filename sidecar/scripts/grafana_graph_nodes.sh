#!/bin/bash

# Configuration
PROMETHEUS_URL="http://prometheus.example:9090/api/v1/query"
PROMETHEUS_QUERY_MAIN="cardano_node_metrics_inboundGovernor_hot{job=\"cardano-node\"}"
PROMETHEUS_QUERY_SECONDARY="rate(cardano_node_metrics_served_block_latest_count_int[1h])/rate(cardano_node_metrics_blockNum_int[1h])*100"
DB_SIDECAR_DATABASE="${DB_SIDECAR_DATABASE:-sidecar}"
DB_SIDECAR_USERNAME="${DB_SIDECAR_USERNAME:-sidecar}"
DB_HOST="${DB_HOST:-db.example}"
PSQL_CMD="/usr/bin/psql --host ${DB_HOST} --dbname ${DB_SIDECAR_DATABASE} --user ${DB_SIDECAR_USERNAME}"

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo "jq is required but not installed. Aborting."
    exit 1
fi

# Parse JSON response and populate associative array
parse_metric_response() {
    local response="$1"
    local -n metric_map="$2"

    echo "Parsing response for $metric_map..."

    # Use command substitution to avoid subshell
    results=$(echo "$response" | jq -c '.data.result[]?')

    # This loop now runs in the main shell
    while IFS= read -r result; do
        instance=$(echo "$result" | jq -r '.metric.instance')
        raw_value=$(echo "$result" | jq -r '.value[1]')

        # Convert to string in case it's a quoted number
        value=$(echo "$raw_value" | sed 's/^"\(.*\)"$/\1/')

        # Skip null or NaN values
        if [[ "$value" == "null" || "$value" == "NaN" ]]; then
            echo "Skipping $instance: null or NaN"
            continue
        fi

        # Validate numeric (allowing floats and integers)
        if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            metric_map["$instance"]=$value
            echo "Valid Value: $instance -> $value"
        else
            echo "Skipping $instance: invalid numeric value: $value"
        fi
    done <<< "$results"
}

while true; do
    echo "=== Starting new cycle ==="

    # 1. Fetch both metrics from Prometheus
    response_main=$(curl -s -G --data-urlencode "query=$PROMETHEUS_QUERY_MAIN" "$PROMETHEUS_URL")
    response_secondary=$(curl -s -G --data-urlencode "query=$PROMETHEUS_QUERY_SECONDARY" "$PROMETHEUS_URL")

    # 2. Validate both responses
    if [[ $(echo "$response_main" | jq -r '.status') != "success" ]]; then
        echo "Error: Failed to fetch mainstat from Prometheus"
        echo "Response: $response_main"
        sleep 10
        continue
    fi

    if [[ $(echo "$response_secondary" | jq -r '.status') != "success" ]]; then
        echo "Error: Failed to fetch secondarystat from Prometheus"
        echo "Response: $response_secondary"
        sleep 10
        continue
    fi

    # 3. Initialize associative arrays
    declare -A mainstats
    declare -A secondarystats

    # 4. Parse both responses
    echo "Parsing mainstat response..."
    parse_metric_response "$response_main" mainstats

    echo "Parsing secondarystat response..."
    parse_metric_response "$response_secondary" secondarystats

    # 5. Process all instances from mainstat
    for instance in "${!mainstats[@]}"; do
        main_val="${mainstats[$instance]}"
        secondary_val="${secondarystats[$instance]}"

        # Skip if secondary stat is missing
        if [[ -z "$secondary_val" ]]; then
            secondary_val=0
        fi

        # Extract node_id from instance (e.g., p1r1.example:12798 → p1r1)
        node_id=$(echo "$instance" | awk -F: '{split($1, a, "."); print a[1]}')

        if [[ -z "$node_id" ]]; then
            echo "Error: Failed to extract node_id from instance: $instance"
            continue
        fi

        # 6. Update PostgreSQL with both stats
        $PSQL_CMD -c "UPDATE ci_nodes SET mainstat = $main_val, secondarystat = $secondary_val WHERE id = '$node_id';"

        if [ $? -eq 0 ]; then
            echo "Success: Updated $node_id | mainstat=$main_val | secondarystat=$secondary_val"
        else
            echo "Error: Failed to update $node_id"
        fi
    done

    # 7. Wait before next iteration
    echo "=== Cycle completed. Sleeping for 60s ==="
    sleep 60
done
