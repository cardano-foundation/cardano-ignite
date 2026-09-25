# Description

Global multi-region (NA / EU / AS) testnet where **every** node runs the Leios
(Dijkstra-era) cardano-node, with tx load driven by the legacy **tx-generator**. Same
macvlan topology, regional gateways and `ns`/monitoring as `global_network`, but all nodes
use the Leios source build. The era-sensitive indexers (blockfrost, yaci) are removed;
cardano-db-sync is the Leios-aware source build.

All components track the revisions pinned by the `prototype-2026w38a` tag of
[ouroboros-leios](https://github.com/input-output-hk/ouroboros-leios).

## Cardano-Node

- **Version**: 11.1.0.164 (Leios)
- **Branch**: karknu/cdf_leios (325d075a6): leios-prototype 8c44d1454 plus the block fetch CDF fix
- **Binary/Source**: Source

## Cardano-CLI

- **Branch**: leios-prototype (b8c7166c1)
- **Binary/Source**: Source

## Cardano-DB-Sync

- **Branch**: leios-w36 (e48dcb6be)
- **Binary/Source**: Source

## Testnet Generation Tool

- **Branch**: karknu/leios
- **Genesis cardano-cli**: prototype-2026w38a release archive (see the
  `x-testnet_builder` args in `docker-compose.yaml`)

## Testnet

- **Pools**: 6 (each: 1 block producer + 2 relays + 1 private relay)
- **Regions**: NA, EU, AS (macvlan VLANs + per-region gateways)
- **Load**: one tx generator per region (`c2` NA, `c3` EU, `c4` AS, `optional` profile),
  each sending a third of the load. In `plain` mode each submits directly to its
  region's private relays (`pNr3`); in `firehose` mode it submits to its own node
  and reaches the relays via `EXTRA_LOCALROOTS`.
- **Voting**: each pool gets a BLS key registered as `blsKey` in the Shelley
  genesis; block producers run with `--shelley-bls-key`

Run with:

```
make build testnet=global_network_leios
make up-all testnet=global_network_leios
```

## Benchmarking Knobs

`TX_GEN_MODE` picks the load generator for `c2`–`c4`: `plain` (default, legacy
tx-generator at a fixed rate) or `firehose` (tx-firehose cycling through
`FIREHOSE_PHASES`: three 20 min phases at 3/10/20 tps per generator, the last sized
to overload the EBs with half of them discarded, so the mempools fill). EBs are capped at 256 KiB by
`maxEndorserBlockTxsSize` in `testnet.yaml` (the tool's 1 MB default is too large
to handle). tx-firehose tags each generator's txs with a metadata colour:
`c2` `ff0000`, `c3` `00c000`, `c4` `0060ff`:

```
TX_GEN_MODE=firehose make up-all testnet=global_network_leios
```

`TX_SUBMISSION_LOGIC_VERSION` picks the tx-submission logic (`1` or `2`,
default `1`) for every node, via `env_{na,eu,as}.base`:

```
TX_SUBMISSION_LOGIC_VERSION=2 make up-all testnet=global_network_leios
```

Like `PROFILING` and `SHUTDOWN_ON_BLOCK`, it is recorded in `.env.tmp` when set,
so the whole run keeps the same version even if containers are recreated.

## Mempool Composition

Every node runs `mempool-monitor` (`MEMPOOL_MONITOR_INTERVAL`, default 15s, `0` disables),
draining its mempool and recording tx counts per tx-firehose colour in the
sidecar database. With `TX_GEN_MODE=firehose` this makes the origin mix visible:
each region's load is tagged `ff0000` (NA), `00c000` (EU) or `0060ff` (AS).

```
make mempool
```

renders the latest snapshot per node: a region rollup bar at the top, then one
composition bar per node. Bars are scaled to mempool capacity: the coloured part
shows how full the mempool is and whose txs it holds. It reads the sidecar
database, so the testnet must be running. `MEMPOOL_REFRESH=2` repaints every 2 seconds; `NO_COLOR=1` (or piping)
prints a plain table; `MEMPOOL_WINDOW` (default twice the snapshot interval) sets
how far back to look. The same data backs the "Mempool composition (tx-firehose
colours)" Grafana row.

The "EB transaction availability (fragmentation)" row shows how much of each EB
pool nodes already held in their mempools (`LeiosBodyHits` traces, collected by
the sidecar into `eb_body_hits`) and how many EB tx bytes nodes had to fetch (the
`leiosFetchTxs*Bytes` node counters). `c1`–`c4` are kept out of the pool-node
panels: they receive no txs into their mempools, so they fetch every EB's txs.
