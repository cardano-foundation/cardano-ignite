#!/bin/bash

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

# Generate the forward zone file (example.zone)
{
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

    yq -r '
    .services
    | to_entries[]
    | .value as $svc
    | $svc | select(has("networks"))
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

# Generate reverse zone files
yq -r '
    .services
    | to_entries[]
    | .value as $svc
    | $svc | select(has("networks"))
    | $svc.hostname as $hostname
    | $svc.networks
    | to_entries[]
    | .value.ipv4_address as $ip
    | select($ip != null)
    | $hostname + " " + $ip
' "$DOCKER_COMPOSE_FILE" | while read -r hostname ip; do
    IFS='.' read -r oct1 oct2 oct3 oct4 <<< "$ip"
    reverse_zone="$oct3.$oct2.$oct1.in-addr.arpa"
    zone_file="$TARGET_DIR/$reverse_zone.zone"

    if [ ! -f "$zone_file" ]; then
        cat <<EOF > "$zone_file"
\$ORIGIN $reverse_zone.
\$TTL 1D
@	IN	SOA	ns.example. admin.example. (
                $(date +%Y%m%d)01 ; serial
                8H ; refresh
                4H ; retry
                4D ; expire
                1D ) ; minimum TTL
    IN	NS	ns.example.
EOF
    fi

    echo "$oct4	IN PTR	$hostname." >> "$zone_file"
done

# Create or update the corefile to include reverse zones
{
    cat <<EOF
example {
    file /etc/coredns/example.zone
    log
    errors
    health 0.0.0.0:8090
}
EOF

    for zone_file in "$TARGET_DIR"/*.zone; do
        zone=$(basename "$zone_file" .zone)
        if [[ "$zone" == *in-addr.arpa ]]; then
            cat <<EOF

$zone {
    file /etc/coredns/$(basename "$zone_file")
    log
    errors
    health 0.0.0.0:8090
}
EOF
        fi
    done

} > "$TARGET_DIR/corefile"
