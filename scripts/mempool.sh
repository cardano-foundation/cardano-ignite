#!/usr/bin/env bash
# ----------------------------------------------------------------------
# mempool - render the current mempool colour composition per node.
#
# Reads the sidecar tables written by mempool-monitor (global_network_leios):
#   mempool_snapshots  one row per node and snapshot
#   mempool_colors     txs per tx-firehose colour in that snapshot
#
# The colours are the tx-firehose origin tags (metadata label 1022). The top
# bar rolls them up per region; each node then gets its own stacked bar painted
# in the real colours. Bars are scaled to mempool capacity: the coloured part is
# how full the mempool is, the blank rest is free. MEMPOOL_REFRESH=2 repaints
# every 2 seconds.
# ----------------------------------------------------------------------

set -euo pipefail

SIDECAR_CONTAINER="${SIDECAR_CONTAINER:-sidecar}"

# Seconds of snapshots to consider (latest per node within the window). Unset:
# twice the snapshot interval seen over the last hour, plus 10s.
MEMPOOL_WINDOW="${MEMPOOL_WINDOW:-}"
MEMPOOL_BAR_WIDTH="${MEMPOOL_BAR_WIDTH:-40}"
# Seconds between repaints. Unset: draw once and exit.
MEMPOOL_REFRESH="${MEMPOOL_REFRESH:-}"
# tx-firehose colour -> origin region, space separated "hex=label" pairs.
# Unset: taken from the running tx generators' FIREHOSE_COLOR and REGION.
MEMPOOL_COLOR_LABELS="${MEMPOOL_COLOR_LABELS:-}"

require_positive_int() {
    case "$2" in
        '' | *[!0-9]* | 0*)
            echo "$1 must be a positive integer" >&2
            exit 1
            ;;
    esac
}
require_positive_int MEMPOOL_BAR_WIDTH "${MEMPOOL_BAR_WIDTH}"
[ -z "${MEMPOOL_WINDOW}" ] || require_positive_int MEMPOOL_WINDOW "${MEMPOOL_WINDOW}"
[ -z "${MEMPOOL_REFRESH}" ] || require_positive_int MEMPOOL_REFRESH "${MEMPOOL_REFRESH}"

# Bars need a terminal: 24-bit colour where the terminal advertises it,
# otherwise the nearest xterm-256 colour.
colour=none
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    case "${COLORTERM:-}" in
        truecolor | 24bit) colour=truecolor ;;
        *) colour=256 ;;
    esac
fi
clear=false
if [ -n "${MEMPOOL_REFRESH}" ] && [ -t 1 ]; then
    clear=true
fi

state="$(docker inspect --format '{{.State.Running}}' "${SIDECAR_CONTAINER}" 2>&1)" || {
    case "${state}" in
        *[Nn]"o such"*) state=false ;;
        *)
            echo "Cannot inspect container '${SIDECAR_CONTAINER}': ${state}" >&2
            exit 1
            ;;
    esac
}
if [ "${state}" != "true" ]; then
    echo "Container '${SIDECAR_CONTAINER}' is not running." >&2
    echo "Start the testnet first (make up-all testnet=global_network_leios)." >&2
    exit 1
fi

if [ -z "${MEMPOOL_COLOR_LABELS}" ]; then
    ids="$(docker ps --quiet)"
    # shellcheck disable=SC2086 # one container id per word
    MEMPOOL_COLOR_LABELS="$(docker inspect --format '{{range .Config.Env}}{{.}} {{end}}' ${ids} 2>/dev/null |
        awk '{
            colour = region = ""
            for (i = 1; i <= NF; i++) {
                if ($i ~ /^FIREHOSE_COLOR=/) colour = substr($i, 16)
                if ($i ~ /^REGION=/) region = substr($i, 8)
            }
            if (colour != "" && region != "") printf "%s=%s ", colour, region
        }' || true)"
fi

# Data rows (0, node, slot, txs, drain secs, age secs, bytes, capacity, colour,
# count, rgb) are followed by one marker row (1, ..., window secs) that ends
# each frame. bytes and capacity are NULL where the table predates them.
SQL="
WITH gaps AS (
    SELECT extract(epoch FROM ts - lag(ts) OVER (PARTITION BY node ORDER BY ts)) AS gap
    FROM mempool_snapshots
    WHERE ts > now() - interval '1 hour'
), win AS (
    SELECT coalesce(${MEMPOOL_WINDOW:-NULL},
                    2 * percentile_cont(0.5) WITHIN GROUP (ORDER BY gap) + 10,
                    120)::int AS secs
    FROM gaps
    WHERE gap IS NOT NULL
), latest AS (
    SELECT node, max(ts) AS ts
    FROM mempool_snapshots, win
    WHERE ts > now() - make_interval(secs => win.secs)
    GROUP BY node
)
SELECT 0, s.node, s.slot, s.txs, round(s.drain_secs::numeric, 2),
       extract(epoch FROM now() - s.ts)::int,
       (to_jsonb(s) ->> 'bytes')::bigint, (to_jsonb(s) ->> 'capacity')::bigint,
       coalesce(c.color, ''), coalesce(c.txs, 0),
       CASE WHEN c.color ~ '^[0-9a-f]{6}\$' THEN ('x' || c.color)::bit(24)::int END
FROM latest l
JOIN mempool_snapshots s USING (node, ts)
LEFT JOIN mempool_colors c USING (node, ts)
UNION ALL
SELECT 1, '', 0, 0, 0, 0, NULL, NULL, '', 0, secs FROM win
ORDER BY 1, 2, 10 DESC, 9"

AWK_PROGRAM="$(
    cat <<'AWK'
function commify(n,    s, r) {
    s = sprintf("%d", n)
    r = ""
    while (length(s) > 3) {
        r = "," substr(s, length(s) - 2) r
        s = substr(s, 1, length(s) - 3)
    }
    return s r
}
function cube(v) { return v < 48 ? 0 : v < 115 ? 1 : int((v - 35) / 40) }
# `n` bar cells in colour `rgb` (a 24-bit integer; empty for untagged txs).
function cells(rgb, n,    r, g, b, code) {
    if (rgb == "") {
        code = "48;5;238"
    } else {
        r = int(rgb / 65536); g = int(rgb / 256) % 256; b = rgb % 256
        if (colour == "truecolor") code = "48;2;" r ";" g ";" b
        else code = "48;5;" (16 + 36 * cube(r) + 6 * cube(g) + cube(b))
    }
    return "\033[" code "m" sprintf("%" n "s", "") "\033[0m"
}
# Bar of `width` cells: the share `fill` of it (1 if unknown) stacked over
# counts[1..k] with largest-remainder rounding, the rest left blank as free space.
function bar(counts, rgbs, k, total, fill,    i, n, rem, used, got, bi, s) {
    used = int(width * fill + 0.5)
    if (used < 1) used = 1
    got = 0
    for (i = 1; i <= k; i++) {
        n[i] = int(used * counts[i] / total)
        rem[i] = used * counts[i] / total - n[i]
        got += n[i]
    }
    while (got < used) {
        bi = 1
        for (i = 2; i <= k; i++) if (rem[i] > rem[bi]) bi = i
        n[bi]++; got++; rem[bi] = -1
    }
    s = ""
    for (i = 1; i <= k; i++) if (n[i] > 0) s = s cells(rgbs[i], n[i])
    return s sprintf("%" (width - used) "s", "")
}
function full(b, c) { return (c > 0) ? sprintf("  %.1f%% full", 100 * b / c) : "" }
function reset_frame() {
    nnode = 0; ng = 0
    split("", seen); split("", gcount); split("", grgb)
}
function render(    i, j, k, c, key, node, total, gtotal, tb, tc, line, ord) {
    if (clear == "true") printf "\033[H\033[2J"
    if (nnode == 0) {
        printf "No mempool snapshots in the last %ss.\n", window
        print "mempool-monitor runs on global_network_leios nodes (MEMPOOL_MONITOR_INTERVAL)."
        fflush()
        return
    }
    printf "Mempool composition  (%d nodes, window %ss)\n\n", nnode, window

    # Network-wide bar: colours rolled up by label, largest first.
    gtotal = 0
    for (i = 1; i <= ng; i++) {
        key = gkey[i]; gtotal += gcount[key]
        j = i - 1
        while (j > 0 && (gcount[ord[j]] < gcount[key] || (gcount[ord[j]] == gcount[key] && ord[j] > key))) {
            ord[j + 1] = ord[j]; j--
        }
        ord[j + 1] = key
    }
    for (i = 1; i <= ng; i++) { counts[i] = gcount[ord[i]]; rgbs[i] = grgb[ord[i]] }
    tb = tc = 0
    for (i = 1; i <= nnode; i++) if (cap[nodes[i]] > 0) { tb += bytes[nodes[i]]; tc += cap[nodes[i]] }
    print ((colour == "none" || gtotal == 0) ? "ALL" : "ALL   [" bar(counts, rgbs, ng, gtotal, (tc > 0) ? tb / tc : 1) "]")
    printf "      total %s txs across %d mempools%s\n", commify(gtotal), nnode, full(tb, tc)
    line = "     "
    for (i = 1; i <= ng; i++)
        if (counts[i] > 0) line = line sprintf("  %s %.1f%%", ord[i], 100 * counts[i] / gtotal)
    print line "\n"

    for (i = 1; i <= nnode; i++) {
        node = nodes[i]; k = nseg[node]; total = 0
        for (j = 1; j <= k; j++) { counts[j] = scount[node, j]; rgbs[j] = srgb[node, j]; total += counts[j] }
        printf "%-5s slot %s  txs %s%s  %ss  %ss ago\n", node, slot[node], commify(txs[node]),
            full(bytes[node], cap[node]), drain[node], age[node]
        if (total == 0) { print "      (empty)"; continue }
        if (colour != "none") print "      [" bar(counts, rgbs, k, total, (cap[node] > 0) ? bytes[node] / cap[node] : 1) "]"
        line = "     "
        for (j = 1; j <= k; j++) {
            c = scolour[node, j]
            if (counts[j] > 0) line = line sprintf("  %s%s %.1f%%", c, ((c in lab) ? " (" lab[c] ")" : ""), 100 * counts[j] / total)
        }
        print line
    }
    fflush()
}
BEGIN {
    FS = "\t"
    width = bar_width + 0
    n = split(labels, parts, " ")
    for (i = 1; i <= n; i++) {
        eq = index(parts[i], "=")
        if (eq == 0) continue
        key = tolower(substr(parts[i], 1, eq - 1))
        sub(/^#/, "", key)
        lab[key] = substr(parts[i], eq + 1)
    }
    reset_frame()
}
$1 == "1" { window = $11; render(); reset_frame(); next }
$1 == "0" {
    node = $2
    if (!(node in seen)) {
        seen[node] = 1; nodes[++nnode] = node; nseg[node] = 0
        slot[node] = $3; txs[node] = $4; drain[node] = $5; age[node] = $6
        bytes[node] = $7 + 0; cap[node] = $8 + 0
    }
    if ($9 == "") next
    j = ++nseg[node]
    scolour[node, j] = $9; scount[node, j] = $10 + 0; srgb[node, j] = $11
    key = ($9 in lab) ? lab[$9] : $9
    if (!(key in gcount)) { gkey[++ng] = key; grgb[key] = $11 }
    gcount[key] += $10
}
AWK
)"

err_file="$(mktemp)"
trap 'rm -f "${err_file}"' EXIT

# One short query per frame: a long-lived psql (e.g. \watch) would outlive an
# interrupted view, since docker exec keeps draining its output.
while true; do
    set +e
    printf '%s;\n' "${SQL}" |
        docker exec -i -e PGCONNECT_TIMEOUT=5 "${SIDECAR_CONTAINER}" \
            psql --host db.example --dbname sidecar --user sidecar --no-psqlrc --quiet \
            --tuples-only --no-align --field-separator=$'\t' -v ON_ERROR_STOP=1 2>"${err_file}" |
        awk -v colour="${colour}" -v clear="${clear}" -v bar_width="${MEMPOOL_BAR_WIDTH}" \
            -v labels="${MEMPOOL_COLOR_LABELS}" "${AWK_PROGRAM}"
    status=("${PIPESTATUS[@]}")
    set -e

    if [ "${status[1]}" -ne 0 ]; then
        if grep -qE 'relation "mempool_(snapshots|colors)" does not exist' "${err_file}"; then
            echo "The mempool tables don't exist yet: mempool-monitor creates them with its first" >&2
            echo "snapshot. It runs on global_network_leios nodes (MEMPOOL_MONITOR_INTERVAL)." >&2
        else
            echo "Failed to query the sidecar database:" >&2
        fi
        cat "${err_file}" >&2
        exit 1
    fi
    [ -n "${MEMPOOL_REFRESH}" ] || exit "${status[2]}"
    sleep "${MEMPOOL_REFRESH}"
done
