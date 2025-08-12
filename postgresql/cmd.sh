#!/usr/bin/env bash

set -o errexit
set -o pipefail

SHELL="/bin/bash"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

# Environment variables
ADMIN_DATABASE="${ADMIN_DATABASE:-postgres}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
CHECKPOINT_COMPLETION_TARGET="${CHECKPOINT_COMPLETION_TARGET:-0.9}"
CHECKPOINT_TIMEOUT="${CHECKPOINT_TIMEOUT:-20min}"
DEFAULT_STATISTICS_TARGET="${DEFAULT_STATISTICS_TARGET:-100}"
EFFECTIVE_CACHE_SIZE="${EFFECTIVE_CACHE_SIZE:-8GB}"
EFFECTIVE_IO_CONCURRENCY="${EFFECTIVE_IO_CONCURRENCY:-1}"
HOST="${HOST:-127.0.0.1}"
MAINTENANCE_WORK_MEM="${MAINTENANCE_WORK_MEM:-256MB}"
MAX_LOCKS_PER_TRANSACTION="${MAX_LOCKS_PER_TRANSACTION:-64}"
MAX_PARALLEL_MAINTENANCE_WORKERS="${MAX_PARALLEL_MAINTENANCE_WORKERS:-4}"
MAX_PARALLEL_WORKERS_PER_GATHER="${MAX_PARALLEL_WORKERS_PER_GATHER:-4}"
MAX_WAL_SIZE="${MAX_WAL_SIZE:-4GB}"
MIN_WAL_SIZE="${MIN_WAL_SIZE:-512MB}"
PORT="${PORT:-5432}"
RANDOM_PAGE_COST="${RANDOM_PAGE_COST:-4}"
SHARED_BUFFERS="${SHARED_BUFFERS:-512MB}"
TEMP_BUFFERS="${TEMP_BUFFERS:-32MB}"
WAL_BUFFERS="${WAL_BUFFERS:-64MB}"
WORK_MEM="${WORK_MEM:-16MB}"

# Configuration files
CONFIG_DST="/opt/postgresql/db"

# PGSQL
PGSQL_BIN="/usr/lib/postgresql/17/bin"
PGSQL_DB="/opt/postgresql/db"

initialize_database() {
    if [ ! -d "${PGSQL_DB}/base" ]; then
        # NOTE: Do not accept incoming connections on default port while initializing admin account; listen on port 5433/tcp instead

        # Create database
        "${PGSQL_BIN}/initdb" --pgdata="${PGSQL_DB}" --locale="en_US.utf8"
        sleep 2

        # Start PostgreSQL
        "${PGSQL_BIN}/pg_ctl" start --pgdata="${PGSQL_DB}" --options="--port=5433"

        # Wait before configuring PostgreSQL
        sleep 2

        # Create admin user
        createuser --login --superuser "${ADMIN_USERNAME}" --host="${PGSQL_DB}" --port=5433

        # Set password for user admin
        "${PGSQL_BIN}/psql" --host="${PGSQL_DB}" --port=5433 -c "ALTER USER ${ADMIN_USERNAME} WITH PASSWORD '${ADMIN_PASSWORD}'"

        # Wait before stopping PostgreSQL
        sleep 2

        # Stop PostgreSQL
        "${PGSQL_BIN}/pg_ctl" stop --pgdata="${PGSQL_DB}" --options="--port=5433"
    fi
}

reset_configuration() {
    # Purge existing configuration files
    for file in "${CONFIG_DST}"/{pg_hba.conf,postgresql.conf}; do
        if [ -f "${file}" ]; then
            rm --force "${file}"
        fi
    done
}

config_pg_hba_conf() {
    (
        cat <<EOF
# TYPE  DATABASE        USER            ADDRESS                 METHOD

host    all             all             0.0.0.0/0               scram-sha-256
EOF
    ) >"${CONFIG_DST}/pg_hba.conf"
}

config_postgresql_conf() {
    (
        cat <<EOF
# FILE LOCATIONS
data_directory = '${PGSQL_DB}'
hba_file = '${PGSQL_DB}/pg_hba.conf'
ident_file = '${PGSQL_DB}/pg_ident.conf'

# CONNECTIONS AND AUTHENTICATION
listen_addresses = '*'
port = 5432
max_locks_per_transaction = ${MAX_LOCKS_PER_TRANSACTION}
unix_socket_directories = '${PGSQL_DB}'

# RESOURCE USAGE (except WAL)
maintenance_work_mem = ${MAINTENANCE_WORK_MEM}
max_parallel_maintenance_workers = ${MAX_PARALLEL_MAINTENANCE_WORKERS}
max_parallel_workers_per_gather = ${MAX_PARALLEL_WORKERS_PER_GATHER}
shared_buffers = ${SHARED_BUFFERS}
temp_buffers = ${TEMP_BUFFERS}
work_mem = ${WORK_MEM}

# WRITE-AHEAD LOG
checkpoint_completion_target = ${CHECKPOINT_COMPLETION_TARGET}
checkpoint_timeout = ${CHECKPOINT_TIMEOUT}
max_wal_size = ${MAX_WAL_SIZE}
min_wal_size = ${MIN_WAL_SIZE}
synchronous_commit = off
wal_buffers = ${WAL_BUFFERS}

# QUERY TUNING
default_statistics_target = ${DEFAULT_STATISTICS_TARGET}
effective_cache_size = ${EFFECTIVE_CACHE_SIZE}
random_page_cost = ${RANDOM_PAGE_COST}

# REPORTING AND LOGGING
log_destination = 'stderr'
log_timezone = 'UTC'

# CLIENT CONNECTION DEFAULTS
datestyle = 'iso, mdy'
timezone = 'UTC'
lc_messages = 'en_US.UTF-8'
lc_monetary = 'en_US.UTF-8'
lc_numeric = 'en_US.UTF-8'
lc_time = 'en_US.UTF-8'
EOF
    ) >"${CONFIG_DST}/postgresql.conf"
}

start_process_exporter() {
    process_exporter -procnames postgres,node_exporter,process_exporte
}

assemble_command() {
    cmd=(exec)
    cmd+=("${PGSQL_BIN}/postgres")
    cmd+=(-D "${PGSQL_DB}")
}

# Establish run order
main() {
    initialize_database
    reset_configuration
    config_pg_hba_conf
    config_postgresql_conf
    start_process_exporter &
    assemble_command
    "${cmd[@]}"
}

main
