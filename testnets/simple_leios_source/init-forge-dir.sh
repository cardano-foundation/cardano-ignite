function wait_first_block() {
    until docker logs ${SRC} 2> /dev/null | grep ChainDB.AddBlockEvent.AddedToCurrentChain > /dev/null
    do
        echo "Waiting for first adopted block ..."
        sleep 5
    done
}

SRC=p1                       # any running ignite node — all pools are baked in
FORGE=./forge                # p3 mount default; or export FORGE_DIR and match it

mkdir -p "$FORGE/keys"
# Genesis from the pool the container ACTUALLY RUNS (pool 1) — see gotcha below.
wait_first_block
docker cp "$SRC":/opt/cardano-node/pools/1/configs/shelley-genesis.json "$FORGE/shelley-genesis.json"
# Pool 3's forging keys.
docker cp "$SRC":/opt/cardano-node/pools/3/keys/. "$FORGE/keys/"
chmod 755 "$FORGE/keys";        # TODO: original was 700; what's correct?
chmod a+rX "$FORGE"/keys/*      # net-node runs as uid 10001

# Derive the two per-run values.
POOL_ID=$(docker exec "$SRC" cardano-cli latest stake-pool id \
  --cold-verification-key-file /opt/cardano-node/pools/3/keys/cold.vkey --output-format hex)
GTU=$(date -u -d "$(jq -r .systemStart "$FORGE/shelley-genesis.json")" +%s)

echo "pool_id=$POOL_ID  genesis_time_unix=$GTU"
POOL_ID_VALID=`jq --arg p "$POOL_ID" '.staking.pools|has($p)' "$FORGE/shelley-genesis.json"`   # must be true

if "$POOL_ID_VALID" == "true"; then
    sed "s/<PoolId>/${POOL_ID}/g; s/<GTU>/${GTU}/g" < forge-ignite-template.toml > ${FORGE}/forge-ignite.toml
    exit 0
else
    echo "Pools are not correctly configured."
    exit 1
fi
