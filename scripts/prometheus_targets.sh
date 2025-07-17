#!/bin/bash

# Validate exactly one argument is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <docker-compose-file>"
    exit 1
fi

DOCKER_COMPOSE_FILE="$1"

# Check for yq installation
if ! command -v yq &> /dev/null; then
    echo "Error: yq is not installed. Please install mikefarah/yq."
    exit 1
fi

# Extract services with POOL_ID in their environment
mapfile -t targets < <(yq -r '
  .services
  | to_entries[]
  | select(.value.environment?.POOL_ID != null)
  | .value.hostname
' "$DOCKER_COMPOSE_FILE")

# Check if any services were found
if [ ${#targets[@]} -eq 0 ]; then
    echo "No services with POOL_ID found in the Docker Compose file."
    exit 1
fi

# Generate Prometheus scrape configs
cat <<EOF
scrape_configs:
  - job_name: 'node_exporter'
    static_configs:
      - targets:
EOF

for target in "${targets[@]}"; do
    echo "        - ${target}:9100"
done

cat <<EOF
  - job_name: 'process_exporter'
    static_configs:
      - targets:
        - db.example:9256
        - dbsync.example:9256
        - blockfrost.example:9256
        - sidecar.example:9256
        - yaci.example:9256
EOF

for target in "${targets[@]}"; do
    echo "        - ${target}:9256"
done

cat <<EOF
  - job_name: 'cardano-node'
    fallback_scrape_protocol: PrometheusText0.0.4
    static_configs:
      - targets:
EOF

for target in "${targets[@]}"; do
    echo "        - ${target}:12798"
done

cat <<EOF
  - job_name: 'http_ip4_basic'
    metrics_path: /probe
    params:
      module: [http_ip4_basic]
    static_configs:
      - targets:
        - http://ns.example:8090/health
        - http://dbsync.example:8080
        - http://blockfrost.example:3000/health
        - http://prometheus.example:9090/metrics
        - http://blackbox.example:9115/metrics
        - http://loki.example:3100/metrics
        - http://grafana.example:3000
EOF

for target in "${targets[@]}"; do
    echo "        - http://${target}:12798"
done

cat <<EOF
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox.example:9115
EOF
