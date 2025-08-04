#!/usr/bin/env bash

set -o errexit
set -o pipefail

SHELL="/bin/bash"
PATH="/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin"

# Environment variables
DB_ADMIN_DATABASE="${DB_ADMIN_DATABASE:-postgres}"
DB_ADMIN_PASSWORD="${DB_ADMIN_PASSWORD:-admin}"
DB_ADMIN_USERNAME="${DB_ADMIN_USERNAME:-admin}"
DB_HERON_DATABASE="${DB_HERON_DATABASE:-heron_db}"
DB_HERON_PASSWORD="${DB_HERON_PASSWORD:-heron}"
DB_HERON_USERNAME="${DB_HERON_USERNAME:-heron}"
DB_HOST="${DB_HOST:-db.example}"
DB_PORT="${DB_PORT:-5432}"
PGPASS="$HOME/.pgpass"
REDIS_HOST="${REDIS_HOST:-redis.example}"
REDIS_PORT="${REDIS_PORT:-6379}"

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

wait_for_redis() {
    # Wait until 'redis' is available
    cmd="redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} info server"
    i=0
    wait=90
    sleep 1
    # shellcheck disable=SC2128,SC2143
    until [ "$(${cmd} | grep 'redis_version')" ]; do
        if [ ${i} -lt ${wait} ]; then
            echo "* Trying to connect to 'redis' on address '${REDIS_HOST}:${REDIS_PORT}'..."
        else
            echo "* Unable to connect to 'redis' on address '${REDIS_HOST}:${REDIS_PORT}', giving up..."
            exit 1
        fi
        i=$((i + 1))
        sleep 3
    done
    echo "* Connection to 'redis' on address '${REDIS_HOST}:${REDIS_PORT}' was successful."
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

# Establish run order
main() {
#    uv python install 3.11
#    uv venv

#    cd /usr/local/src/heron-cardano
#    uv pip install -r requirements.txt

#    (
#        cat <<EOF
#BLOCKFROST_PROJECT_ID=preprod_cardanoignite
#POSTGRES_USER=heron
#POSTGRES_PASSWORD=heron
#POSTGRES_DBNAME=heron
#WALLET_ENCRYPTION_KEY=IZIbslT33LzrLQ1gsk/ril3sYZ35aCnMqzKMQ97etjo=
#EOF
#    ) >"/usr/local/src/heron-cardano/.env"

#    source /usr/local/src/heron-cardano/.venv/bin/activate

#    export PYTHONPATH=/usr/local/src/heron-cardano
#    export WALLET_ENCRYPTION_KEY="$(openssl rand -base64 32)"

#    alembic upgrade head

#    uvicorn heron_app.main:app --host 0.0.0.0 --port 8000

#curl -X 'GET' 'http://localhost:8000/wallets/' -H 'accept: application/json'
#  
#curl -X 'POST' 'http://localhost:8000/wallets/' -H 'accept: application/json' -H 'Content-Type: application/json' -d '{"name": "test", "mnemonic": "pitch panel other order mosquito degree suggest conduct film attitude strategy rebel sick reflect property priority online syrup surprise place shiver innocent float promote"}'

    wait_for_postgresql
    wait_for_redis
    config_database_instance ${DB_HERON_DATABASE}
    config_database_user ${DB_HERON_USERNAME} ${DB_HERON_PASSWORD} ${DB_HERON_DATABASE}
    #/fundme.sh
    sleep 6000
}
    
main
