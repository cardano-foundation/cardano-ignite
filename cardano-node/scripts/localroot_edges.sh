#!/bin/bash

# Configuration
DB_SIDECAR_DATABASE="${DB_SIDECAR_DATABASE:-sidecar}"
DB_SIDECAR_USERNAME="${DB_SIDECAR_USERNAME:-sidecar}"
DB_HOST="${DB_HOST:-db.example}"
PSQL_CMD="/usr/bin/psql --host ${DB_HOST} --dbname ${DB_SIDECAR_DATABASE} --user ${DB_SIDECAR_USERNAME}"
SQL_FILE="${SQL_FILE:-/opt/cardano-node/data/localroot_edges.sql}"

do_inserts() {
    i=0
    wait=90
    sleep 1
    until ${PSQL_CMD} < "${SQL_FILE}"  >/dev/null 2>&1; do
        if [ ${i} -lt ${wait} ]; then
            echo "* Trying to connect to 'postgresql' on address '${DB_HOST}:${DB_PORT}'..."
        else
            echo "* Unable to connect to 'postgresql' on address '${DB_HOST}:${DB_PORT}', giving up..."
            exit 1
        fi
        i=$((i + 1))
        sleep 3
    done
}

do_inserts
