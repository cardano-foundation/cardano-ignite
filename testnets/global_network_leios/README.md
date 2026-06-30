# Description

Global multi-region (NA / EU / AS) testnet where **every** node runs the Leios
(Dijkstra-era) cardano-node, with tx load driven by **tx-centrifuge**. Same macvlan
topology, regional gateways and `ns`/monitoring as `global_network`, but all nodes use the
Leios source build and the legacy tx-generator is replaced by tx-centrifuge. The
era-sensitive indexers (blockfrost, yaci) are removed; cardano-db-sync is the Leios-aware
source build.

## Cardano-Node

- **Version**: 11.0.1 (Leios)
- **Branch**: leios-prototype (db5373ea6)
- **Binary/Source**: Source

## Testnet

- **Pools**: 6 (each: 1 block producer + 2 relays + 1 private relay)
- **Regions**: NA, EU, AS (macvlan VLANs + per-region gateways)
- **Load**: tx-centrifuge (`c2`, `optional` profile) -> each pool's private relay (`pNr3`)

Run with:

```
make build testnet=global_network_leios
make up-all testnet=global_network_leios
```
