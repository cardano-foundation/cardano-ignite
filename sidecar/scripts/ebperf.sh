#!/usr/bin/env bash
# ----------------------------------------------------------------------
# Endorser-block (Leios EB) performance collector - the EB analogue of
# blockperf.sh. Reads node traces from Loki
# (ns=Consensus.LeiosKernel.TraceLeiosKernel) and stores two metrics:
#
#   eb_adoption      per-node EB propagation delay.
#                    LeiosBlockForged on the producer, LeiosBlockAcquired on
#                    every other node; delay = seen_at - (SYSTEM_START + ebSlot).
#                    (An EB's slot IS its production slot, so forge time is
#                    deterministic from the slot - same trick as blockperf.)
#
#   eb_certification forge->quorum latency, from LeiosBlockCertified:
#                    latency_slots = atSlot - ebSlot. Self-contained (no join).
#
# On non-Leios testnets no LeiosBlock* traces exist, so this idles harmlessly.
# ----------------------------------------------------------------------

# Map a /24 network to a region (same scheme as blockperf.sh).
get_region() {
    local ip=$1
    local network_prefix
    network_prefix=$(echo "$ip" | cut -d'.' -f1-3)
    case "$network_prefix" in
        "172.16.1") echo "North America" ;;
        "172.16.3") echo "Europe" ;;
        "172.16.4") echo "Asia" ;;
        *)          echo "Unknown" ;;
    esac
}

# Resolve a short host name (e.g. p1bp) to an IP. getent exits 0 whenever
# the A lookup succeeds, unlike `host` (see blockperf.sh).
resolve_ip() {
    local short_host=$1
    getent hosts "${short_host}.example" 2>/dev/null | awk '{print $1; exit}' || true
}

# NOTE: deliberately no `errexit` - this is a long-running collector and a
# transient Loki/psql failure must not kill it.
set -uo pipefail

DB_HOST="${DB_HOST:-db.example}"
DB_SIDECAR_DATABASE="${DB_SIDECAR_DATABASE:-sidecar}"
DB_SIDECAR_USERNAME="${DB_SIDECAR_USERNAME:-sidecar}"

LOKI_URL="${LOKI_URL:-http://loki.example:3100/loki/api/v1/query_range}"
# bp + relays + clients. `| json` exposes nested data.kind as label data_kind
# (same mechanism blockperf.sh relies on).
# The `|= "LeiosBlock"` line filter lets Loki drop non-matching lines before
# the expensive `| json` parse stage.
LOKI_QUERY='{container_name=~"p[0-9]+(bp|r[0-9])?|(c[0-9]+)"} |= "LeiosBlock" | json | data_kind=~"LeiosBlock(Forged|Acquired|Certified)"'
LOKI_LIMIT=5000

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2; }

# Wait for the testnet to be initialized
while [ ! -f /opt/synth/start_time.unix_epoch ]; do
    log "Waiting for initialization to complete..."
    sleep 1
done
SYSTEM_START_UNIX=$(cat /opt/synth/start_time.unix_epoch)

# ISO-8601 (Loki) timestamp -> float unix epoch with ms precision.
ts_to_epoch() {
    local timestamp="${1%Z}+00"
    local seconds_part milliseconds_part
    if [[ "$timestamp" == *.* ]]; then
        seconds_part="${timestamp%%.*}"
        milliseconds_part="${timestamp#*.}"
        milliseconds_part="${milliseconds_part:0:3}"
    else
        seconds_part="$timestamp"
        milliseconds_part="000"
    fi
    local seconds_unix
    seconds_unix=$(date -d "$seconds_part" +%s 2>/dev/null) || { echo ""; return; }
    awk -v sec="$seconds_unix" -v ms="$milliseconds_part" 'BEGIN { printf "%.3f\n", sec + ms/1000 }'
}

# Cache host->region so we DNS-resolve each host only once. Returns via the
# REGION variable (a command substitution would run in a subshell and lose
# the cache writes). Failed lookups are not cached and retry on the next row.
declare -A REGION_CACHE
region_for() {
    local h="$1"
    if [[ -z "${REGION_CACHE[$h]:-}" ]]; then
        local ip
        ip=$(resolve_ip "$h")
        if [[ -z "$ip" ]]; then REGION="Unknown"; return; fi
        REGION_CACHE[$h]=$(get_region "$ip")
    fi
    REGION="${REGION_CACHE[$h]}"
}

# ----------------------------------------------------------------------
# Tables
# ----------------------------------------------------------------------
until psql -h "$DB_HOST" -U "$DB_SIDECAR_USERNAME" -d "$DB_SIDECAR_DATABASE" -c "
    CREATE TABLE IF NOT EXISTS eb_adoption (
        host        TEXT NOT NULL,
        region      TEXT NOT NULL,
        ts          TIMESTAMP NOT NULL,
        eb_slot     BIGINT NOT NULL,
        eb_hash     TEXT NOT NULL,
        kind        TEXT NOT NULL,
        forged_time TIMESTAMP NOT NULL,
        delay       DOUBLE PRECISION NOT NULL,
        PRIMARY KEY (host, eb_hash)
    );
    CREATE TABLE IF NOT EXISTS eb_certification (
        host          TEXT NOT NULL,
        region        TEXT NOT NULL,
        ts            TIMESTAMP NOT NULL,
        eb_slot       BIGINT NOT NULL,
        at_slot       BIGINT NOT NULL,
        eb_hash       TEXT NOT NULL,
        latency_slots BIGINT NOT NULL,
        PRIMARY KEY (host, eb_hash)
    );
" >/dev/null 2>&1; do
    log "Waiting for postgres to create EB tables..."
    sleep 5
done

# ----------------------------------------------------------------------
# Main collection loop. Each window starts where the previous one left off
# (with a 30s lap for late log shipping) instead of a fixed 2 minutes back.
# Results are fetched oldest-first; when a burst saturates LOKI_LIMIT the
# window is advanced only to the last fetched event, so the remainder is
# drained on following cycles instead of silently dropped.
# ----------------------------------------------------------------------
WINDOW_START=$(( $(date +%s) - 120 ))
while true; do
    log "Starting EB perf cycle..."
    NOW=$(date +%s)
    START="${WINDOW_START}000000000"
    END="${NOW}000000000"

    RAW=$(mktemp)
    if ! curl -s -G "$LOKI_URL" \
        --data-urlencode "query=$LOKI_QUERY" \
        --data-urlencode "start=$START" \
        --data-urlencode "end=$END" \
        --data-urlencode "direction=forward" \
        --data-urlencode "limit=$LOKI_LIMIT" > "$RAW"; then
        log "WARN: Loki query failed; retrying next cycle"
        rm -f "$RAW"; sleep 60; continue
    fi

    FETCHED=$(jq '[.data.result[]?.values[]?] | length' "$RAW" 2>/dev/null) || FETCHED=0
    if [[ "$FETCHED" -ge "$LOKI_LIMIT" ]]; then
        LAST_SEC=$(jq -r '[.data.result[]?.values[]?[0]] | max | .[0:10]' "$RAW" 2>/dev/null)
        [[ "$LAST_SEC" =~ ^[0-9]+$ ]] && WINDOW_START="$LAST_SEC"
        log "WARN: Loki result hit limit=$LOKI_LIMIT; draining backlog from $WINDOW_START"
    else
        WINDOW_START=$(( NOW - 30 ))
    fi

    # ---- eb_adoption : LeiosBlockForged (producer) + LeiosBlockAcquired (others) ----
    ADOPT=$(mktemp)
    jq -r '
        .data.result[]?.values[]? | .[1] | fromjson as $log |
        ($log.data.kind)                      as $kind   |
        ($log.data.ebHash // $log.data.hash)  as $ebHash |
        ($log.data.ebSlot // $log.data.slot)  as $ebSlot |
        select(
            ($kind == "LeiosBlockForged" or $kind == "LeiosBlockAcquired") and
            ($log.host != null) and ($log.at != null) and
            ($ebHash != null) and ($ebSlot != null)
        ) |
        [ $log.host, $log.at, ($ebSlot|tostring), $ebHash, $kind ] | @tsv
    ' "$RAW" 2>/dev/null > "$ADOPT" || true

    ADOPT_ROWS=()
    while IFS=$'\t' read -r host at eb_slot eb_hash kind; do
        [[ -z "${host:-}" || -z "${eb_hash:-}" || -z "${eb_slot:-}" ]] && continue
        region_for "$host"
        seen=$(ts_to_epoch "$at"); [[ -z "$seen" ]] && continue
        forged=$(( SYSTEM_START_UNIX + eb_slot ))
        delay=$(awk -v a="$seen" -v f="$forged" 'BEGIN { printf "%.3f\n", a - f }')
        ts_norm="${at%Z}+00"
        ADOPT_ROWS+=("('$host', '$REGION', '$ts_norm', $eb_slot, '$eb_hash', '$kind', to_timestamp($forged), $delay)")
    done < "$ADOPT"

    if [[ ${#ADOPT_ROWS[@]} -gt 0 ]]; then
        printf -v ADOPT_SQL '%s,' "${ADOPT_ROWS[@]}"
        psql -h "$DB_HOST" -U "$DB_SIDECAR_USERNAME" -d "$DB_SIDECAR_DATABASE" -c "
            INSERT INTO eb_adoption (host, region, ts, eb_slot, eb_hash, kind, forged_time, delay)
            VALUES ${ADOPT_SQL%,}
            ON CONFLICT (host, eb_hash) DO NOTHING;
        " >/dev/null 2>&1 || log "WARN: eb_adoption batch insert failed (${#ADOPT_ROWS[@]} rows)"
    fi

    # ---- eb_certification : LeiosBlockCertified (atSlot - ebSlot) ----
    CERT=$(mktemp)
    jq -r '
        .data.result[]?.values[]? | .[1] | fromjson as $log |
        select(
            ($log.data.kind) == "LeiosBlockCertified" and
            ($log.host != null) and ($log.at != null) and
            ($log.data.ebHash != null) and ($log.data.ebSlot != null) and ($log.data.atSlot != null)
        ) |
        [ $log.host, $log.at, ($log.data.ebSlot|tostring), ($log.data.atSlot|tostring), $log.data.ebHash ] | @tsv
    ' "$RAW" 2>/dev/null > "$CERT" || true

    CERT_ROWS=()
    while IFS=$'\t' read -r host at eb_slot at_slot eb_hash; do
        [[ -z "${host:-}" || -z "${eb_hash:-}" || -z "${eb_slot:-}" || -z "${at_slot:-}" ]] && continue
        region_for "$host"
        ts_norm="${at%Z}+00"
        latency=$(( at_slot - eb_slot ))
        CERT_ROWS+=("('$host', '$REGION', '$ts_norm', $eb_slot, $at_slot, '$eb_hash', $latency)")
    done < "$CERT"

    if [[ ${#CERT_ROWS[@]} -gt 0 ]]; then
        printf -v CERT_SQL '%s,' "${CERT_ROWS[@]}"
        psql -h "$DB_HOST" -U "$DB_SIDECAR_USERNAME" -d "$DB_SIDECAR_DATABASE" -c "
            INSERT INTO eb_certification (host, region, ts, eb_slot, at_slot, eb_hash, latency_slots)
            VALUES ${CERT_SQL%,}
            ON CONFLICT (host, eb_hash) DO NOTHING;
        " >/dev/null 2>&1 || log "WARN: eb_certification batch insert failed (${#CERT_ROWS[@]} rows)"
    fi

    rm -f "$RAW" "$ADOPT" "$CERT"
    log "EB perf cycle done; sleeping 60s..."
    sleep 60
done
