#!/usr/bin/env bash

set -o errexit
set -o pipefail

SHELL="/bin/bash"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

# Environment variables
BIND="${BIND:-0.0.0.0}"
LOGLEVEL="${LOGLEVEL:-notice}"
PORT="${PORT:-6379}"

# Configuration files
CONFIG_SRC="/etc/redis"
CONFIG_DST="/opt/redis/config"

# REDIS
DB_DIR="/opt/redis/db"

reset_configuration() {
    # Purge existing configuration files
    if [ -f "${CONFIG_DST}/redis.conf" ]; then
        rm --force "${CONFIG_DST}/redis.conf"
    fi

    # Copy redis configuration file
    if [ ! -f "${CONFIG_DST}/redis.conf" ]; then
        cp --force "${CONFIG_SRC}/redis.conf" "${CONFIG_DST}/redis.conf"
    fi
}

config_redis_conf() {
    sed -i "s@^bind .*@bind ${BIND}@g" "${CONFIG_DST}/redis.conf"
    sed -i 's@^daemonize .*@daemonize no@g' "${CONFIG_DST}/redis.conf"
    sed -i "s@^dir .*@dir ${DB_DIR}@g" "${CONFIG_DST}/redis.conf"
    sed -i "s@^loglevel .*@loglevel ${LOGLEVEL}@g" "${CONFIG_DST}/redis.conf"
    sed -i 's@^logfile .*@#&@' "${CONFIG_DST}/redis.conf"
    sed -i "s@^pidfile .*@pidfile ${DB_DIR}/redis-server.pid@g" "${CONFIG_DST}/redis.conf"
    sed -i "s@^port .*@port ${PORT}@g" "${CONFIG_DST}/redis.conf"
}

# shellcheck disable=SC2206
assemble_command() {
    cmd=(exec)
    cmd+=(/usr/bin/redis-server)
    cmd+=(${CONFIG_DST}/redis.conf)
    cmd+=(--daemonize no)
    cmd+=(--protected-mode no)
}

# Establish run order
main() {
    reset_configuration
    config_redis_conf
    assemble_command
    "${cmd[@]}"
}

main
