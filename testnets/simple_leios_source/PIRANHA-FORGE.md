# Piranha as a block producer in simple_leios_source

Run `net-node` (piranha) as `p3`, taking over pool 3's on-chain identity and
forging real Praos blocks that p1/p2 (Haskell cardano-node) fetch and adopt.
Stake and epoch nonce come from ignite's genesis; no Kleioscan.

Simpler than the global variant: default bridge network, no macvlan/regions, and
`p3` is already the forger hostname — p1/p2 dial `p3.example` as a local root by
construction, so no IP impersonation is needed.

## Quick start

1. **Once per host:** have `piranha:latest` in the local image store; on an
   arm host running amd64 node images, `docker run --privileged --rm tonistiigi/binfmt --install amd64`.
2. Bring up the pools + support **without p3** (it needs the forge dir first):
   ```bash
   cd testnets/simple_leios_source
   docker compose --profile core up -d p1 p2 c1 loki grafana prometheus blackbox
   ```
3. Populate the forge dir — run the **Setup** block below (extract genesis+keys,
   fix perms, derive `pool_id`/`genesis_time_unix`, write `forge-ignite.toml`).
4. Start p3: `docker compose --profile core up -d p3`.
5. Verify (see **Verify** below): `resolved stake distribution … our_stake` non-zero,
   `produced block`, then p1/p2 `AddedToCurrentChain` with your issuer hash.

Steps 1–2 are one-time-ish; step 3 is the only manual part each `make up` (until a
`forge-init` step automates it).

## Image

Expects a prebuilt **`piranha:latest`** in the local Docker image store
before `docker compose up`. Built from a **private** repo and documented there
(this repo is public); obtain/build it out-of-band and tag it `piranha:latest`.

## Setup

Bring the testnet up first (`p1`, `p2`, `c1` running), then populate the forge dir
that the `p3` service mounts. The mount defaults to `./forge` (repo-relative:
`testnets/simple_leios_source/forge`), overridable with `FORGE_DIR`.

```bash
SRC=p1                       # any running ignite node — all pools are baked in
FORGE=./forge                # p3 mount default; or export FORGE_DIR and match it

mkdir -p "$FORGE/keys"
# Genesis from the pool the container ACTUALLY RUNS (pool 1) — see gotcha below.
docker cp "$SRC":/opt/cardano-node/pools/1/configs/shelley-genesis.json "$FORGE/shelley-genesis.json"
# Pool 3's forging keys.
docker cp "$SRC":/opt/cardano-node/pools/3/keys/. "$FORGE/keys/"
chmod 700 "$FORGE/keys"; chmod a+rX "$FORGE"/keys/*      # net-node runs as uid 10001

# Derive the two per-run values.
POOL_ID=$(docker exec "$SRC" cardano-cli latest stake-pool id \
  --cold-verification-key-file /opt/cardano-node/pools/3/keys/cold.vkey --output-format hex)
GTU=$(date -u -d "$(jq -r .systemStart "$FORGE/shelley-genesis.json")" +%s)

echo "pool_id=$POOL_ID  genesis_time_unix=$GTU"
jq --arg p "$POOL_ID" '.staking.pools|has($p)' "$FORGE/shelley-genesis.json"   # must be true
```

Write `$FORGE/forge-ignite.toml` with `$POOL_ID` and `$GTU` filled in:

```toml
node_id = "p3"
listen_address = "0.0.0.0:3001"
network_magic = 42
slot_duration_ms = 1000
genesis_time_unix = <GTU>      # from setup
leios_enabled = true
scheduler = "priority-wfq"
security_param_k = 90          # ignite securityParam, not 2160
sync_method = "tip"
genesis_path = "/etc/forge/shelley-genesis.json"

[production]
total_stake = 1000             # overridden at boot from genesis SPDD
stake = 0                      # overridden at boot from genesis SPDD
rb_generation_probability = 0.05   # ignored under real VRF
vote_generation_probability = 0.8
stage_length_slots = 20
protocol_major = 12            # header ProtVer on real blocks, NOT the genesis value (10)

[production.committee_selection]
type = "StakeCentile"
top_centile_of_stake = 0.99

[transactions]
tx_rate = 0.0

[keys]
pool_id = "<POOL_ID>"          # from setup
vrf_skey_path = "/etc/forge/keys/vrf.skey"
kes_skey_path = "/etc/forge/keys/kes.skey"
op_cert_path = "/etc/forge/keys/opcert.cert"
cold_vkey_path = "/etc/forge/keys/cold.vkey"

[chain_data]
source = "genesis"

[telemetry]
stats_interval_secs = 10

[[telemetry.stats_sinks]]
type = "log"

[[peers]]
address = "p1.example:3001"

[[peers]]
address = "p2.example:3001"
```

- `epochLength`, `slotLength`, `activeSlotsCoeff` come from `genesis_path`; don't restate.
- Peers are duplex — p1/p2 dial back on 3001, so diffusion is bidirectional.
- No `bls.skey` in ignite: leave `bls_skey_path` unset (votes carry an empty BLS sig).

## p3 service

Already in `docker-compose.yaml` (profiles `core`, `pools`):

```yaml
  p3:
    <<: *base
    image: piranha:latest
    container_name: p3
    hostname: p3.example
    volumes:
      - ${FORGE_DIR:-./forge}:/etc/forge:ro
    entrypoint: ["/usr/local/bin/net-node"]      # bypass the baked relay entrypoint (stake=0)
    command: ["--config", "/etc/forge/forge-ignite.toml"]
    environment:
      RUST_LOG: "${RUST_LOG:-info}"
    profiles: [core, pools]
```

Only ONE process may ever hold these KES keys (two = equivocation + counter conflict).

Portability rough edges (pending a `forge-init` automation): the mount is an
absolute host path, and a `platform:` pin would fight host-native image builds —
build `piranha` for the host arch and don't pin `platform`.

## Verify

```bash
docker logs p3 2>&1 | grep 'resolved stake distribution'   # our_stake must be NON-ZERO
docker logs p3 2>&1 | grep 'produced block'                # block_no ~ network_tip+1
# adoption by the real Haskell nodes:
docker logs p1 2>&1 | grep -c 'AddedToCurrentChain'        # then filter by issuerHash below
```

Loki (issuer = your `$POOL_ID`):

```
{container_name=~"p1|p2"} |= "AddedToCurrentChain" |= "<POOL_ID>"
```

A steady stream of those = piranha's blocks are adopted (expect roughly the pool's
stake share of slots).

## Gotchas (each of these bit us)

- **Genesis must come from the *running* pool (pool 1), not `pools/3`.** `cmd.sh`
  patches `systemStart` only into the pool the container runs; the `pools/3` copy
  keeps a stale build-time `systemStart`, putting p3 on a different slot timeline →
  `FetchDeclineChainNotPlausible` → forged but never adopted.
- **Key perms.** `docker cp` copies keys as uid 10000/0600; net-node runs as uid
  10001 → `Permission denied` crash. `chmod a+rX`.
- **The `starting node … stake=0 total_stake=1000` banner is a pre-override default.**
  The real stake is on the `resolved stake distribution (SPDD) … our_stake=` line.
  Don't chase the banner.
- **Pool ids are deterministic** across genesis regens, so `pool_id` is stable — a
  genuine `our_stake=0` is almost always the systemStart or perms issue above.

## Debugging non-adoption (if it happens)

Symptom: p1/p2 ChainSync p3's headers but never BlockFetch the bodies. Raise the
decision tracers on p1 (new-tracing `TraceOptions` in `config.json`):

```bash
docker exec p1 sh -lc 'cfg=/opt/cardano-node/pools/1/configs/config.json;
  jq ".TraceOptions[\"BlockFetch.Decision\"].severity=\"Debug\"
    | .TraceOptions[\"ChainSync.Client\"].severity=\"Debug\"" "$cfg" > "$cfg.t" && mv "$cfg.t" "$cfg"'
docker restart p1                                   # restart, not recreate — jq edit survives
```

Then read the reason:

```
{container_name="p1"} |= "FetchDecline"
{container_name="p1"} |~ "DownloadedHeader|RollForward"
```

- `FetchDeclineChainNotPlausible` → timeline/preference (check the systemStart gotcha).
- a validation/candidate-rejection reason → a Haskell-specific header check.
- no `FetchDecline` at all → the header never became a candidate.

## Result

Praos forging and adoption **work** here: on a w30-matched node, p1 and p2 fetch
and adopt piranha's forged blocks (issuer = pool 3), roughly at the pool's stake
share. Leios vote certification is untested (no BLS key / registered committee).
