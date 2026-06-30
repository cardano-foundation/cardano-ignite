#!/usr/bin/env bash

# Validate exactly one argument is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <docker-compose-file>"
    exit 1
fi

DOCKER_COMPOSE_FILE="$1"

# Extract services with POOL_ID in their environment
mapfile -t targets < <(yq -r '
  .services
  | to_entries[]
  | select(.value.environment?.POOL_ID != null)
  | .value.hostname
' "$DOCKER_COMPOSE_FILE" 2>/dev/null)

# Check if any services were found
if [ ${#targets[@]} -eq 0 ]; then
    echo "No services with POOL_ID found in the Docker Compose file."
    exit 1
fi

# Several monitored services are optional and absent from some topologies: simple/
# bridge networks have no ns (they resolve via Docker's embedded DNS).
# Scraping or probing an absent service is a permanent failure in Grafana
# (target down / probe_http_status_code == 0), so emit
# a target line only when the compose actually defines that service.
target_if_present() {
    if [ "$(yq -r ".services | has(\"$1\")" "$DOCKER_COMPOSE_FILE" 2>/dev/null)" = "true" ]; then
        echo "        - $2"
    fi
}

# Generate Prometheus scrape configs
cat <<EOF
rule_files:
  - /etc/prometheus/rules.yml

scrape_configs:
  - job_name: 'node_exporter'
    static_configs:
      - targets:
EOF
target_if_present nagw "nagw.example:9100"
target_if_present eugw "eugw.example:9100"
target_if_present asgw "asgw.example:9100"
target_if_present adgw "adgw.example:9100"

for target in "${targets[@]}"; do
    echo "        - ${target}:9100"
done

cat <<EOF
  - job_name: 'process_exporter'
    static_configs:
      - targets:
        - db.example:9256
        - sidecar.example:9256
EOF
target_if_present dbsync     "dbsync.example:9256"
target_if_present blockfrost "blockfrost.example:9256"
target_if_present yaci       "yaci.example:9256"

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

# The amaru job only applies to testnets that run amaru nodes; jaeger/otlp
# receive amaru's metrics. Skip the job entirely everywhere else.
if [ "$(yq -r '.services | has("jaeger") or has("otlp")' "$DOCKER_COMPOSE_FILE" 2>/dev/null)" = "true" ]; then
cat <<EOF
  - job_name: 'amaru'
    static_configs:
      - targets:
EOF
target_if_present jaeger "jaeger.example:8889"
target_if_present otlp   "otlp.example:8889"
fi

# Blackbox HTTP health probes. blackbox/grafana/loki/prometheus belong to every
# testnet's core profile and are always probed; blockfrost/dbsync/ns/yaci are gated
# by target_if_present (defined above).
cat <<EOF
  - job_name: 'http_ip4_basic'
    metrics_path: /probe
    params:
      module: [http_ip4_basic]
    static_configs:
      - targets:
        - http://blackbox.example:9115/metrics
        - http://grafana.example:3000
        - http://loki.example:3100/metrics
        - http://prometheus.example:9090/metrics
EOF
target_if_present blockfrost "http://blockfrost.example:3000/health"
target_if_present dbsync     "http://dbsync.example:8080"
target_if_present ns         "http://ns.example:8090/health"
target_if_present yaci       "http://yaci.example:8080/actuator/health"
echo

for target in "${targets[@]}"; do
    echo "        - http://${target}:12798/metrics"
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
