#!/usr/bin/env bash

# Validate exactly two arguments are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <docker-compose.yaml> <output.zone>" >&2
    exit 1
fi

COMPOSE_FILE="$1"
TARGET_DIR="$2"

if [ ! -f "$COMPOSE_FILE" ]; then
    echo "Error: Docker compose file not found at '$COMPOSE_FILE'" >&2
    exit 1
fi

# Create Corefile in the target directory
cat <<EOF > "$TARGET_DIR/corefile"
example {
    file /etc/coredns/example.zone
    log
    errors
    health 0.0.0.0:8090
}
EOF

SERIAL=$(date +%Y%m%d)01

cat <<EOF > "$TARGET_DIR/example.zone"
\$ORIGIN example.
\$TTL 1D
@ IN SOA ns.example. admin.example. (
    $SERIAL ; serial
    8H      ; refresh
    4H      ; retry
    4D      ; expire
    1D      ; minimum TTL
)
@ IN NS ns.example.
; Host A records
EOF

yq '.services[] | 
    select(.hostname) | 
    .hostname + "|" + 
    (.networks | to_entries[] | .value.ipv4_address)
' "$COMPOSE_FILE" 2>/dev/null | \
grep -v 'null' | \
sort | \
while IFS='|' read -r HOSTNAME_FULL IP; do
    HOST=$(echo "$HOSTNAME_FULL" | sed 's/\.example$//')
    printf "%s\tIN A\t%s\n" "$HOST" "$IP" >> "$TARGET_DIR/example.zone"
done

echo "; Relay-specific A and SRV records" >> "$TARGET_DIR/example.zone"

yq '.services[] | 
    select(.environment.RELAY_ID | test("^[12]$")) | 
    (.environment.POOL_ID | "p" + .) as $pool |
    (.hostname | sub("\\.example$"; "")) as $hostname |
    .networks | to_entries[] | 
    select(.value.ipv4_address) |
    "\($pool)|\($hostname)|\(.value.ipv4_address)"
' "$COMPOSE_FILE" 2>/dev/null | \
sort -u | \
while IFS='|' read -r POOL HOST IP; do
    printf "%s\tIN A\t%s\n" "$POOL" "$IP" >> "$TARGET_DIR/example.zone"
    printf "_cardano._tcp.%s\tIN SRV\t%d %d %d %s\n" "$POOL" "10" "10" "3001" "$HOST" >> "$TARGET_DIR/example.zone"
done
