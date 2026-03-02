#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: download_profiling.sh [DEST_DIR]

Downloads cardano-node profiling files from running containers into DEST_DIR.
If DEST_DIR is not provided, a new temp dir under /tmp is created.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "docker not found in PATH" >&2
    exit 1
fi

dest_dir="${1:-}"
if [ -z "${dest_dir}" ]; then
    dest_dir="$(mktemp -d /tmp/cardano-profiling-XXXXXX)"
else
    mkdir -p "${dest_dir}"
fi

json_escape() {
    local s="${1}"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    printf '%s' "${s}"
}

mapfile -t containers < <(docker ps --format '{{.Names}}')

copied=0
for c in "${containers[@]:-}"; do
    files="$(docker exec "${c}" sh -c 'for f in /opt/cardano-node/log/cardano-node-*.prof; do [ -e "$f" ] && echo "$f"; done' 2>&1)" || {
        if printf '%s' "${files}" | grep -qi 'exec: "sh": executable file not found'; then
            echo "Skipping ${c}: no sh in container."
        else
            echo "Skipping ${c}: docker exec failed."
        fi
        continue
    }
    if [ -z "${files}" ]; then
        continue
    fi

    while IFS= read -r f; do
        [ -z "${f}" ] && continue
        docker cp "${c}:${f}" "${dest_dir}/"
        copied=$((copied + 1))
    done <<< "${files}"

    type_val="$(docker exec "${c}" /usr/bin/env 2>/dev/null | awk -F= '$1=="TYPE"{print $2; exit}' || true)"
    if [ -z "${type_val}" ]; then
        type_val="unknown"
    fi

    version_out="$(docker exec "${c}" /usr/local/bin/cardano-node --version 2>/dev/null || docker exec "${c}" cardano-node --version 2>/dev/null || true)"
    node_version="$(printf '%s' "${version_out}" | awk 'NR==1 {print $2}')"
    if [ -z "${node_version}" ]; then
        node_version="unknown"
    fi

    json_path="${dest_dir}/${c}.json"
    printf '{\n  "container": "%s",\n  "type": "%s",\n  "node_version": "%s"\n}\n' \
        "$(json_escape "${c}")" \
        "$(json_escape "${type_val}")" \
        "$(json_escape "${node_version}")" \
        > "${json_path}"
done

if [ "${copied}" -eq 0 ]; then
    echo "No profiling files found in running containers."
else
    echo "Downloaded ${copied} profiling file(s)."
fi
echo "Destination: ${dest_dir}"
