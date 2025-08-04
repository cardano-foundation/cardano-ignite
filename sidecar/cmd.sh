#!/usr/bin/env bash

set -o errexit
set -o pipefail

SHELL="/bin/bash"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

# Environment variables
POOLS="${POOLS:-}"
DB_ADMIN_DATABASE="${DB_ADMIN_DATABASE:-postgres}"
DB_ADMIN_PASSWORD="${DB_ADMIN_PASSWORD:-admin}"
DB_ADMIN_USERNAME="${DB_ADMIN_USERNAME:-admin}"
DB_SIDECAR_DATABASE="${DB_SIDECAR_DATABASE:-sidecar}"
DB_SIDECAR_PASSWORD="${DB_SIDECAR_PASSWORD:-sidecar}"
DB_SIDECAR_USERNAME="${DB_SIDECAR_USERNAME:-sidecar}"
DB_YACI_DATABASE="${DB_YACI_DATABASE:-yaci}"
DB_YACI_PASSWORD="${DB_YACI_PASSWORD:-yaci}"
DB_YACI_USERNAME="${DB_YACI_USERNAME:-yaci}"
DB_DBSYNC_DATABASE="${DB_DBSYNC_DATABASE:-dbsync}"
DB_DBSYNC_PASSWORD="${DB_DBSYNC_PASSWORD:-dbsync}"
DB_DBSYNC_USERNAME="${DB_DBSYNC_USERNAME:-dbsync}"
DB_HOST="${DB_HOST:-db.example}"
DB_PORT="${DB_PORT:-5432}"
PGPASS="$HOME/.pgpass"

DB_OPTIONS="postgres://${DB_ADMIN_USERNAME}:${DB_ADMIN_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_ADMIN_DATABASE} --quiet"

wait_for_postgresql() {
    # Wait until 'postgresql' is available
    cmd="psql ${DB_OPTIONS} --list"
    i=0
    wait=90
    sleep 1
    until ${cmd} >/dev/null 2>&1; do
        if [ ${i} -lt ${wait} ]; then
            echo "* Trying to connect to 'postgresql' on address '${DB_HOST}:${DB_PORT}'..."
        else
            echo "* Unable to connect to 'postgresql' on address '${DB_HOST}:${DB_PORT}', giving up..."
            exit 1
        fi
        i=$((i + 1))
        sleep 3
    done
    echo "* Connection to 'postgresql' on address '${DB_HOST}:${DB_PORT}' was successful."
}

config_database_instance() {
    local DATABASE="$1"

    if [ $(psql ${DB_OPTIONS} --no-align --tuples-only --command="SELECT COUNT(*) FROM pg_database WHERE datname = '${DATABASE}';") -ne 1 ]; then
        psql ${DB_OPTIONS} --command="CREATE DATABASE ${DATABASE};"
    fi
}

config_database_user() {
    local USERNAME="$1"
    local PASSWORD="$2"
    local DATABASE="$3"

    if [ $(psql ${DB_OPTIONS} --no-align --tuples-only --command="SELECT COUNT(*) FROM pg_roles WHERE rolname = '${USER_NAME}';") -ne 1 ]; then
        psql ${DB_OPTIONS} --command="CREATE USER ${USERNAME} WITH PASSWORD '${PASSWORD}';"
        psql ${DB_OPTIONS} --command="ALTER ROLE ${USERNAME} WITH SUPERUSER;"
        psql ${DB_OPTIONS} --command="GRANT ALL PRIVILEGES ON DATABASE ${DATABASE} TO ${USERNAME};"
    fi
}

config_pgpass() {
    # hostname:port:database:username:password
    (
        cat <<EOF
${DB_HOST}:${DB_PORT}:${DB_SIDECAR_DATABASE}:${DB_SIDECAR_USERNAME}:${DB_SIDECAR_PASSWORD}
${DB_HOST}:${DB_PORT}:${DB_YACI_DATABASE}:${DB_YACI_USERNAME}:${DB_YACI_PASSWORD}
${DB_HOST}:${DB_PORT}:${DB_DBSYNC_DATABASE}:${DB_DBSYNC_USERNAME}:${DB_DBSYNC_PASSWORD}
EOF
    ) >"${PGPASS}"

    chmod 0600 "${PGPASS}"
}

create_tables() {
    psql -h ${DB_HOST} -U ${DB_SIDECAR_USERNAME} --dbname ${DB_SIDECAR_DATABASE} < graph_nodes.sql
}

verify_environment_variables() {
    if [ -z "${POOLS}" ]; then
        echo "POOLS not defined, exiting..."
        sleep 60
        exit 1
    fi
}

add_routes() {
    doas ip route add 172.16.1.0/24 via 172.16.7.14 dev eth0
    doas ip route add 172.16.2.0/24 via 172.16.7.14 dev eth0
    doas ip route add 172.16.3.0/24 via 172.16.7.14 dev eth0
    doas ip route add 172.16.4.0/24 via 172.16.7.14 dev eth0
}

start_process_exporter() {

cat << EOF > /tmp/process_exporter.yml
process_names:
  - name: 'grafana_consensus'
    cmdline:
    - '/opt/scripts/grafana_consensus.sh'
EOF

    process_exporter -config.path /tmp/process_exporter.yml
}

# Establish run order
main() {
    verify_environment_variables
    if [[ "${TOPOLOGY}" == "fancy" ]]; then
        add_routes
    fi
    wait_for_postgresql
    config_database_instance ${DB_SIDECAR_DATABASE}
    config_database_user ${DB_SIDECAR_USERNAME} ${DB_SIDECAR_PASSWORD} ${DB_SIDECAR_DATABASE}
    config_database_instance ${DB_YACI_DATABASE}
    config_database_user ${DB_YACI_USERNAME} ${DB_YACI_PASSWORD} ${DB_YACI_DATABASE}
    config_pgpass
    create_tables
    start_process_exporter &
    /opt/scripts/grafana_graph_nodes.sh >/dev/null 2>&1 &
    /opt/scripts/grafana_consensus.sh >/dev/null 2>&1 &
    /opt/scripts/pots.sh >/dev/null 2>&1
}

main
