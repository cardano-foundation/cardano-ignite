#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: analyze_profiling.sh DIR

Summarize cardano-node profiling differences by node type and node version.
DIR should contain cardano-node-*.prof files and per-container JSON metadata.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

dir="${1:-}"
if [ -z "${dir}" ]; then
    usage
    exit 1
fi

if [ ! -d "${dir}" ]; then
    echo "Directory not found: ${dir}" >&2
    exit 1
fi

mapfile="$(mktemp)"
trap 'rm -f "${mapfile}"' EXIT

# Build container -> type/version map from JSON files
shopt -s nullglob
for json in "${dir}"/*.json; do
    container="$(awk -F'"' '/"container"/{print $4; exit}' "${json}")"
    type_val="$(awk -F'"' '/"type"/{print $4; exit}' "${json}")"
    ver_val="$(awk -F'"' '/"node_version"/{print $4; exit}' "${json}")"
    [ -z "${container}" ] && continue
    [ -z "${type_val}" ] && type_val="unknown"
    [ -z "${ver_val}" ] && ver_val="unknown"
    printf '%s\t%s\t%s\n' "${container}" "${type_val}" "${ver_val}" >> "${mapfile}"
done
shopt -u nullglob

awk -v mapfile="${mapfile}" '
BEGIN {
    FS="[[:space:]]+"
    while ((getline < mapfile) > 0) {
        type[$1]=$2
        ver[$1]=$3
    }
    close(mapfile)
}

function init_min(a, v) {
    return (a == "" || (v + 0) < (a + 0)) ? v : a
}

function init_max(a, v) {
    return (a == "" || (v + 0) > (a + 0)) ? v : a
}

function update_group(k, t, a,    kt, ka) {
    count[k]++
    sum_t[k] += t
    sum_a[k] += a
    min_t[k] = init_min(min_t[k], t)
    max_t[k] = init_max(max_t[k], t)
    min_a[k] = init_min(min_a[k], a)
    max_a[k] = init_max(max_a[k], a)
}

function is_core(t) {
    return (t != "txg" && t != "client")
}

function add_cc(g, cc, t, a) {
    cc_present[g, cc] = 1
    sum_cc_t[g, cc] += t
    sum_cc_a[g, cc] += a
}

function print_summary(prefix, title, label,    k, name, w) {
    w = length(label)
    for (k in count) {
        if (k !~ "^" prefix ":") continue
        name = substr(k, length(prefix) + 2)
        if (length(name) > w) w = length(name)
    }
    print ""
    print title
    printf "%-*s  %4s  %10s  %10s  %10s  %12s  %12s  %12s\n", w, label, "n", "avg_time_s", "min_time_s", "max_time_s", "avg_alloc_GB", "min_alloc_GB", "max_alloc_GB"
    for (k in count) {
        if (k !~ "^" prefix ":") continue
        name = substr(k, length(prefix) + 2)
        printf "%-*s  %4d  %10.2f  %10.2f  %10.2f  %12.2f  %12.2f  %12.2f\n", w, name, count[k], sum_t[k]/count[k], min_t[k], max_t[k], (sum_a[k]/count[k])/1e9, min_a[k]/1e9, max_a[k]/1e9
    }
}

function print_cc_group(prefix, title,    k, g, cc, max_cc, max_v, i, n, avg_t, avg_a, any, w_g, w_cc, cc_key, parts) {
    w_g = length("group")
    w_cc = length("cost_centre")
    for (k in count) {
        if (k !~ "^" prefix ":") continue
        g = substr(k, length(prefix) + 2)
        if (length(g) > w_g) w_g = length(g)
    }
    for (cc_key in cc_present) {
        split(cc_key, parts, SUBSEP)
        if (parts[1] !~ "^" prefix ":") continue
        cc = parts[2]
        if (length(cc) > w_cc) w_cc = length(cc)
    }
    print ""
    print title
    printf "%-*s  %4s  %-*s  %9s  %10s\n", w_g, "group", "rank", w_cc, "cost_centre", "avg_%time", "avg_%alloc"
    for (k in count) {
        if (k !~ "^" prefix ":") continue
        g = substr(k, length(prefix) + 2)
        n = count[k]
        if (n == 0) continue
        # Build a temp list of cost centres for this group
        delete tmp_t
        delete tmp_a
        any = 0
        for (cc_key in cc_present) {
            split(cc_key, parts, SUBSEP)
            if (parts[1] != k) continue
            cc = parts[2]
            avg_t = sum_cc_t[k, cc] / n
            avg_a = sum_cc_a[k, cc] / n
            tmp_t[cc] = avg_t
            tmp_a[cc] = avg_a
            any = 1
        }
        if (!any) continue
        for (i = 1; i <= 5; i++) {
            max_cc = ""
            max_v = -1
            for (cc in tmp_t) {
                if (tmp_t[cc] > max_v) {
                    max_v = tmp_t[cc]
                    max_cc = cc
                }
            }
            if (max_cc == "") break
            printf "%-*s  %4d  %-*s  %9.2f  %10.2f\n", w_g, g, i, w_cc, max_cc, tmp_t[max_cc], tmp_a[max_cc]
            delete tmp_t[max_cc]
            delete tmp_a[max_cc]
        }
    }
}

FNR == 1 {
    # finalize previous file
    if (in_file && total_time != "" && total_alloc != "") {
        update_group("type:" ttype, total_time, total_alloc)
        update_group("ver:" tver, total_time, total_alloc)
        if (is_core(ttype)) {
            update_group("ver_core:" tver, total_time, total_alloc)
        }
    }

    in_file = 1
    total_time = ""
    total_alloc = ""
    in_table = 0
    table_done = 0

    tag = FILENAME
    sub(/^.*cardano-node-/, "", tag)
    sub(/\.prof$/, "", tag)
    ttype = (tag in type) ? type[tag] : "unknown"
    tver = (tag in ver) ? ver[tag] : "unknown"
}

{
    if (total_time == "" && match($0, /total time[[:space:]]*=[[:space:]]*[0-9.]+/)) {
        total_time = substr($0, RSTART, RLENGTH)
        gsub(/[^0-9.]/, "", total_time)
    }
    if (total_alloc == "" && match($0, /total alloc[[:space:]]*=[[:space:]]*[0-9,]+/)) {
        total_alloc = substr($0, RSTART, RLENGTH)
        gsub(/[^0-9]/, "", total_alloc)
    }

    if ($0 ~ /^COST CENTRE/) {
        if (in_table && !table_done) {
            table_done = 1
            in_table = 0
        } else if (!table_done) {
            in_table = 1
        }
        next
    }
    if (in_table) {
        if ($0 ~ /^[[:space:]]*$/) next
        # last two fields are %time and %alloc
        if (NF < 3) next
        t = $(NF-1)
        a = $(NF)
        if (t !~ /^[0-9.]+$/ || a !~ /^[0-9.]+$/) next
        cc = $1
        add_cc("type:" ttype, cc, t, a)
        add_cc("ver:" tver, cc, t, a)
        if (is_core(ttype)) {
            add_cc("ver_core:" tver, cc, t, a)
        }
    }
}

END {
    if (in_file && total_time != "" && total_alloc != "") {
        update_group("type:" ttype, total_time, total_alloc)
        update_group("ver:" tver, total_time, total_alloc)
        if (is_core(ttype)) {
            update_group("ver_core:" tver, total_time, total_alloc)
        }
    }

    print "NOTE: Summaries below use .prof header totals: total time (secs) and total alloc (bytes)."
    print "      Cost centre sections use the first COST CENTRE table in each .prof file."
    print ""

    print_summary("type", "TYPE SUMMARY (Totals)", "type")
    print_summary("ver", "VERSION SUMMARY (Totals)", "version")
    print_summary("ver_core", "VERSION SUMMARY (CORE ONLY, Totals)", "version")

    print_cc_group("type", "COST CENTRES BY TYPE (Top 5 by avg %time)")
    print_cc_group("ver", "COST CENTRES BY VERSION (Top 5 by avg %time)")
    print_cc_group("ver_core", "COST CENTRES BY VERSION (CORE ONLY, Top 5 by avg %time)")
}
' "${dir}"/cardano-node-*.prof
