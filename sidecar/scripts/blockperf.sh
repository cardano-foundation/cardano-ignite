#!/usr/bin/env bash
# ----------------------------------------------------------------------
# block‑adoption collector – resolves short host names to IPs,
# determines the region and stores it in the DB.
# ----------------------------------------------------------------------

# ----------------------------------------------------------------------
# Helper: map a /24 network to a human‑readable region (you supplied)
# ----------------------------------------------------------------------
get_region() {
    local ip=$1
    # Extract first 3 octets (for /24 network)
    local network_prefix=$(echo "$ip" | cut -d'.' -f1-3)
    case "$network_prefix" in
        "172.16.1")
            echo "North America"
            ;;
        "172.16.3")
            echo "Europe"
            ;;
        "172.16.4")
            echo "Asia"
            ;;
        *)
            echo "Unknown"
            ;;
    esac
}

# ----------------------------------------------------------------------
# Resolve a short host name (e.g. p1r1) to an IP address.
# Returns the IP on success, empty string on failure.
# ----------------------------------------------------------------------
resolve_ip() {
    local short_host=$1
    # Append the domain you use for DNS resolution
    local fqdn="${short_host}.example"

    # `host` may emit multiple lines – we only need the first "has address"
    # Suppress errors (e.g. NXDOMAIN) and fall back to empty string.
    host "$fqdn" 2>/dev/null |
        awk '/has address/ {print $4; exit}'
}

# ----------------------------------------------------------------------
# Global configuration
# ----------------------------------------------------------------------
SYSTEM_START_UNIX=$(cat /opt/synth/start_time.unix_epoch)

set -euo pipefail
set -x

# PostgreSQL config
DB_HOST="${DB_HOST:-db.example}"
DB_SIDECAR_DATABASE="${DB_SIDECAR_DATABASE:-sidecar}"
DB_SIDECAR_USERNAME="${DB_SIDECAR_USERNAME:-sidecar}"

# Loki config
LOKI_URL="${LOKI_URL:-http://loki.example:3100/loki/api/v1/query_range}"
LOKI_QUERY='{container_name=~"p[0-9]+(bp|r[0-9])?|(c[0-9]+)"} | json | data_kind=~"TraceAddBlockEvent\\.(AddedToCurrentChain|SwitchedToAFork)"'

# Simple logger
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2; }

# ----------------------------------------------------------------------
# Ensure the target table exists (now with a `region` column)
# ----------------------------------------------------------------------
psql -h "$DB_HOST" -U "$DB_SIDECAR_USERNAME" -d "$DB_SIDECAR_DATABASE" -c "
    CREATE TABLE IF NOT EXISTS block_adoption (
        host        TEXT    NOT NULL,
        region      TEXT    NOT NULL,
        timestamp   TIMESTAMP NOT NULL,
        blockNo     INTEGER NOT NULL,
        slotNo      INTEGER NOT NULL,
        forgedTime  TIMESTAMP NOT NULL,
        hash        TEXT    NOT NULL,
        delay       DOUBLE PRECISION NOT NULL,
        PRIMARY KEY (host, timestamp, hash)
    );
" >/dev/null

# ----------------------------------------------------------------------
# Main collection loop
# ----------------------------------------------------------------------
while true; do
    log "Starting data extraction cycle..."

    # ------------------------------------------------------------------
    # Time window (2 minutes back → now) in nanoseconds
    # ------------------------------------------------------------------
    END=$(date +%s)000000000
    START=$(date -d '2 minutes ago' +%s)000000000

    # ------------------------------------------------------------------
    # Pull matching logs from Loki
    # ------------------------------------------------------------------
    log "Querying Loki..."
    LOGS=$(mktemp)
    curl -s -G \
        "$LOKI_URL" \
        --data-urlencode "query=$LOKI_QUERY" \
        --data-urlencode "start=$START" \
        --data-urlencode "end=$END" \
        --data-urlencode "limit=1000" |
        jq -r '
            .data.result[].values[] | .[1] | fromjson |
            [
                .host,                       # short host name (e.g. p1r1)
                .at,                         # timestamp string
                (."data"."newTipSelectView"."chainLength" | tostring),
                (."data"."newtip" | split("@")[0]),
                (."data"."newtip" | split("@")[1])
            ] | @csv
        ' > "$LOGS"

    # ------------------------------------------------------------------
    # Process each CSV line and insert into PostgreSQL
    # ------------------------------------------------------------------
    log "Processing $(wc -l < "$LOGS") records..."
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue   # skip empty lines

        # ------------------------------------------------------------------
        # Parse the CSV line produced by jq
        # ------------------------------------------------------------------
        # shellcheck disable=SC2086   # intentional word‑splitting inside eval
        eval "IFS=',' read -r host timestamp blockNo hash slotNo <<< $line"

        # ------------------------------------------------------------------
        # Resolve short host name to an IP address
        # ------------------------------------------------------------------
        ip=$(resolve_ip "$host")
        if [[ -z "$ip" ]]; then
            log "WARN: Could not resolve IP for host '$host' – region set to 'Unknown'"
            region="Unknown"
        else
            region=$(get_region "$ip")
        fi

        # ------------------------------------------------------------------
        # Normalise the timestamp (Loki returns ISO‑8601)
        # ------------------------------------------------------------------
        timestamp="${timestamp%Z}+00"   # ensure UTC offset

        if [[ "$timestamp" == *.* ]]; then
            seconds_part="${timestamp%%.*}"
            milliseconds_part="${timestamp#*.}"
            milliseconds_part="${milliseconds_part:0:3}"   # keep ms precision
        else
            seconds_part="$timestamp"
            milliseconds_part="000"
        fi

        seconds_unix=$(date -d "$seconds_part" +%s)
        added_time_float=$(awk -v sec="$seconds_unix" -v ms="$milliseconds_part" '
            BEGIN { printf "%.3f\n", sec + ms/1000 }
        ')

        # ------------------------------------------------------------------
        # Compute forged time and delay (unchanged from original script)
        # ------------------------------------------------------------------
        forged_time=$(( SYSTEM_START_UNIX + slotNo ))   # seconds since epoch
        delay_float=$(awk -v added="$added_time_float" -v forged="$forged_time" '
            BEGIN { printf "%.3f\n", added - forged }
        ')

        # ------------------------------------------------------------------
        # Insert (or ignore on conflict)
        # ------------------------------------------------------------------
        psql -h "$DB_HOST" -U "$DB_SIDECAR_USERNAME" -d "$DB_SIDECAR_DATABASE" -c "
            INSERT INTO block_adoption
                (host, region, timestamp, blockNo, slotNo, forgedTime, hash, delay)
            VALUES
                ('$host', '$region', '$timestamp', $blockNo, $slotNo,
                 to_timestamp($forged_time), '$hash', $delay_float)
            ON CONFLICT (host, timestamp, hash) DO NOTHING;
        " >/dev/null
    done < "$LOGS"

    # ------------------------------------------------------------------
    # Clean up
    # ------------------------------------------------------------------
    rm -f "$LOGS"

    log "Sleeping for 60 seconds..."
    sleep 60
done

