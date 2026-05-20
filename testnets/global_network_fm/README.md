# Description

Fancy single-pool global testnet. A `tx-centrifuge` generator in EU feeds
transactions through a single relay into the block producer, while passive
observer clients in North America and Asia sync from the EU relay. Useful for
measuring tx propagation and block diffusion across continents, and for
exercising the new pull-based tx generator in isolation.

## Cardano-Node

Two cardano-node images are built:

| Anchor                 | `CARDANO_NODE_REF`                           | Used by                          |
|------------------------|----------------------------------------------|----------------------------------|
| `*cardano_node`        | `a93ad9776c0f28144386067e5406f3fad3bd133a`   | `p1bp`, `p1r1`, `c1`, `c3`, `c4` |
| `*cardano_node_txg`    | `3ea9fb36e6d69faaaa1b5f00c2407eb24d3f868e`   | `c2` only (ships `tx-centrifuge`) |

- **Binary/Source**: Source (built via `cardano-node/Dockerfile.source`).

## Testnet

- **Pools**: 1

## Logical Topology

```
                  net_na                              net_as
                    |                                  |
                    c1 (client, v2)         c3 (client, v2)
                                            c4 (client, v1)
                    |                                  |
                  nagw <-- net_eu_na -- eugw -- net_as_eu --> asgw
                                          |
                                        net_eu
                                          |
       c2 (txg, tx-centrifuge) ---> p1r1 (privaterelay) ---> p1bp (bp)
```

### Nodes

- `p1bp` (EU, `TYPE=bp`) — block producer.
- `p1r1` (EU, `TYPE=privaterelay`) — connected to `p1bp`; carries
  `EXTRA_LOCALROOTS=c1.example:3001,c2.example:3001,c3.example:3001,c4.example:3001`
  so the relay actively peers with every client.
- `c1` (NA, `TYPE=client`) — passive observer; also the node `cardano-db-sync`
  follows.
- `c2` (EU, `TYPE=txg`) — runs `tx-centrifuge` against `p1r1` (see below).
- `c3` (AS, `TYPE=client`) — passive observer.
- `c4` (AS, `TYPE=client`) — passive observer, pinned to **tx-submission v1**
  (everyone else uses v2).

Every client also has `EXTRA_LOCALROOTS=p1r1.example:3001` so the
client↔relay edge is established from both sides; the connection manager
dedupes to a single TCP session.

## Tx generator (`c2`)

`c2` runs `tx-centrifuge` (pull-based load generator) via `TX_GEN_MODE=centrifuge`.
The launcher (`cardano-node/scripts/tx-centrifuge.sh`) generates a `funds.json`
from `genesis.${POOL_ID}.skey` and a centrifuge config from these env vars:

| Var                          | Default        | Meaning                              |
|------------------------------|----------------|--------------------------------------|
| `TPS`                        | `10`           | Token-bucket rate (shared scope).    |
| `TX_GENERATOR_TARGETS`       | `p1r1.example` | CSV of target hosts (port 3001).     |
| `CENTRIFUGE_INPUTS_PER_TX`   | `1`            | UTxO inputs per built tx.            |
| `CENTRIFUGE_OUTPUTS_PER_TX`  | `1`            | Outputs per built tx.                |
| `CENTRIFUGE_FEE`             | `1000000`      | Lovelace fee per tx.                 |
| `CENTRIFUGE_RECYCLE`         | `on_pull`      | `on_build` / `on_pull` / `on_confirm`. |
| `CENTRIFUGE_MAX_BATCH_SIZE`  | `500`          | Cap on items announced per request.  |
| `CENTRIFUGE_FUND_VALUE`      | `600000000000000` | Believed value of the genesis UTxO. |

Dispatch lives in `cardano-node/cmd.sh:tx_generator()` — `TX_GEN_MODE=centrifuge`
runs `/tx-centrifuge.sh`; any other value runs the legacy `/tx-generator.sh`.

## Per-node overrides

| Setting                       | Where                          |
|-------------------------------|--------------------------------|
| `PEER_SHARING=false`          | `env_{eu,na,as}.base` (all nodes) |
| `TX_SUBMISSION_LOGIC_VERSION=2` | `env_{eu,na,as}.base` (all nodes by default) |
| `TX_SUBMISSION_LOGIC_VERSION=1` | inline on `c4` (overrides default) |
| `MempoolCapacityBytesOverride: 25000000`<br>`MempoolTimeoutCapacity: 20.0`<br>`MempoolTimeoutSoft: 1.0`<br>`MempoolTimeoutHard: 1.5` | `testnet.yaml` |

## Notes

- `p1r1` is configured as `privaterelay` rather than `relay` because the
  default `relay` topology in `cardano-node/cmd.sh` assumes >= 2 pools and
  builds a pool ring; with `poolCount: 1` it would self-loop.
- `p1bp`'s default BP topology hard-codes three relay entries
  (`p1r1/p1r2/p1r3`). Only `p1r1` exists, so the node will log DNS errors
  for `p1r2` and `p1r3` — these are benign.
- The `cardano_node_txg` image installs `tx-centrifuge` from
  `bench/tx-centrifuge` in the cardano-node tree. The install is guarded by a
  directory check in `Dockerfile.source`, so other testnets that pin to a
  commit without `tx-centrifuge` continue to build (they get a stub binary).

## Usage

```
make build testnet=global_network_fm
make up testnet=global_network_fm            # core services
make up-all testnet=global_network_fm        # incl. c2 (txg) and blockfrost
make down testnet=global_network_fm
```
