# Description

Global multi-region (NA / EU / AS) testnet where **every** node runs the Leios
(Dijkstra-era) cardano-node, with tx load driven by the legacy **tx-generator**. Same
macvlan topology, regional gateways and `ns`/monitoring as `global_network`, but all nodes
use the Leios source build. The era-sensitive indexers (blockfrost, yaci) are removed;
cardano-db-sync is the Leios-aware source build.

All components track the revisions pinned by the `prototype-2026w32` tag of
[ouroboros-leios](https://github.com/input-output-hk/ouroboros-leios).

## Cardano-Node

- **Version**: 11.1.0.164 (Leios)
- **Branch**: leios-prototype (c5f7d9121)
- **Binary/Source**: Source

## Cardano-CLI

- **Branch**: leios-prototype (de7865577)
- **Binary/Source**: Source

## Cardano-DB-Sync

- **Branch**: jl/leios-prototype (6d7f61347)
- **Binary/Source**: Source

## Testnet Generation Tool

- **Branch**: karknu/leios
- **Genesis cardano-cli**: prototype-2026w32 release archive (see the
  `x-testnet_builder` args in `docker-compose.yaml`)

## Testnet

- **Pools**: 6 (each: 1 block producer + 2 relays + 1 private relay)
- **Regions**: NA, EU, AS (macvlan VLANs + per-region gateways)
- **Load**: tx-generator (`c2`, `optional` profile) -> each pool's private relay (`pNr3`)
- **Voting**: each pool gets a BLS key registered as `leiosKey` in the Shelley
  genesis; block producers run with `--shelley-bls-key`

Run with:

```
make build testnet=global_network_leios
make up-all testnet=global_network_leios
```
