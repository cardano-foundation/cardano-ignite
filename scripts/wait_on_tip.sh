#!/usr/bin/env bash

#
# Wait until the specific peer's tip is at least the specified
# block number.
#
 
if [ $# -ne 3 ]; then
    echo "Usage: $0 <host> <port> <target_block_number>" >&2
    exit 1
fi

HOST="$1"
PORT="$2"
TARGET_BLOCK="$3"

echo -n "Waiting for tip >= ${TARGET_BLOCK} on ${HOST}:${PORT}..."

while true; do
    output=$(cardano-cli ping -h "${HOST}" -p "${PORT}" -m 42 -j -q -t 2>&1)
    ping_status=$?

    if [ ${ping_status} -eq 0 ]; then
        blockNo=$(echo "$output" | jq -r '.tip[0].blockNo' 2>/dev/null)
        jq_status=$?

        if [ ${jq_status} -eq 0 ] && [ -n "${blockNo}" ] && [[ "${blockNo}" =~ ^[0-9]+$ ]]; then
            if [ "${blockNo}" -ge "${TARGET_BLOCK}" ]; then
                echo " tip at ${blockNo}."
                exit 0
            fi
        fi
    fi
    echo -n "."
    sleep 5
done
