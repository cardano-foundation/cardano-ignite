# Description

Leios (Ouroboros Leios) testnet: hard-forks to the Dijkstra era at genesis and forges
endorser blocks. Built from source, mirroring the official ouroboros-leios testnet node
config. Endorser blocks only appear under transaction load, so start the tx-generator with
`make up-all`. Ships a Leios-aware cardano-db-sync (built from source) and a Leios Grafana
dashboard scoped to this testnet.

All components track the revisions pinned by the `prototype-2026w38a` tag of
[ouroboros-leios](https://github.com/input-output-hk/ouroboros-leios).

## Cardano-Node

- **Version**: 11.1.0.164 (Leios)
- **Branch**: leios-prototype (8c44d1454)
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

- **Pools**: 3
- **Load**: tx-generator (`c2`, `optional` profile) -> its local node
- **Voting**: each pool gets a BLS key registered as `blsKey` in the Shelley
  genesis; block producers run with `--shelley-bls-key`
