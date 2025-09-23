#!/usr/bin/env bash

# Validate exactly two arguments are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <docker-compose-file> <target-directory>"
    exit 1
fi

DOCKER_COMPOSE_FILE="$1"
TARGET_DIR="$2"

# Check for yq installation
if ! command -v yq &> /dev/null; then
    echo "Error: yq is not installed. Please install mikefarah/yq."
    exit 1
fi

# Create the target directory if it doesn't exist
mkdir -p "$TARGET_DIR"

# Create Corefile in the target directory
cat <<EOF > "$TARGET_DIR/corefile"
example {
    file /etc/coredns/example.zone
    log
    errors
    health 0.0.0.0:8090
}
EOF

# Generate the zone file content into example.zone in the target directory
{
    # Zone header
    cat <<EOF
\$ORIGIN example.
\$TTL 1D
@ IN SOA ns.example. admin.example. (
    $(date +%Y%m%d)01 ; serial
    8H         ; refresh
    4H         ; retry
    4D         ; expire
    1D         ; minimum TTL
)
@ IN NS ns.example.
; Host A records
EOF

    # Generate A records from Docker Compose
    yq -r '
    .services
    | to_entries[]
    | .value as $svc
    | $svc | select(has("networks"))  # Filter out services without networks
    | $svc.hostname as $hostname
    | $svc.networks
    | to_entries[]
    | .value.ipv4_address as $ip
    | select($ip != null)
    | $hostname
    | capture("(?<name>[^\\.]+)\\.(?<domain>.*)") as $cap
    | $cap.name + "\tIN A\t" + $ip
    ,
    (if $svc.environment.TYPE == "relay" then
        "p" + $svc.environment.POOL_ID + "\tIN A\t" + $ip + "\n_cardano._tcp.p" + $svc.environment.POOL_ID + "\tIN SRV 10 10 3001 " + $cap.name
     else
        empty
     end)
    ' "$DOCKER_COMPOSE_FILE"

} > "$TARGET_DIR/example.zone"
